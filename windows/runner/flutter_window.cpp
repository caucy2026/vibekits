#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  app_process_job_ = ::CreateJobObjectW(nullptr, nullptr);
  if (app_process_job_ != nullptr) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    const bool configured = ::SetInformationJobObject(
        app_process_job_, JobObjectExtendedLimitInformation, &limits,
        sizeof(limits));
    const bool assigned =
        configured && ::AssignProcessToJobObject(app_process_job_,
                                                 ::GetCurrentProcess());
    if (!assigned) {
      // Some launchers already put the runner in a restrictive job. Keep the
      // existing per-child fallback in that case.
      ::CloseHandle(app_process_job_);
      app_process_job_ = nullptr;
    }
  }

  // Give immediate click feedback while the Flutter engine and plugins are
  // still starting. The first Flutter frame replaces this lightweight native
  // surface; no disk, network or Harness work is allowed to block it.
  Show();
  ::UpdateWindow(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  file_drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "vibekits/file_drop",
          &flutter::StandardMethodCodec::GetInstance());
  process_lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "vibekits/process_lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  process_lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_arguments", "Expected a map argument");
          return;
        }
        const auto pid_entry =
            arguments->find(flutter::EncodableValue("pid"));
        if (pid_entry == arguments->end()) {
          result->Error("invalid_pid", "Missing child process id");
          return;
        }
        DWORD process_id = 0;
        if (const auto* int32_value =
                std::get_if<int32_t>(&pid_entry->second)) {
          process_id = static_cast<DWORD>(*int32_value);
        } else if (const auto* int64_value =
                       std::get_if<int64_t>(&pid_entry->second)) {
          process_id = static_cast<DWORD>(*int64_value);
        }
        if (process_id == 0) {
          result->Error("invalid_pid", "Invalid child process id");
          return;
        }

        if (call.method_name() == "releaseProcessTree") {
          const auto existing = child_process_jobs_.find(process_id);
          if (existing != child_process_jobs_.end()) {
            ::CloseHandle(existing->second);
            child_process_jobs_.erase(existing);
          }
          result->Success();
          return;
        }
        if (call.method_name() != "bindProcessTree") {
          result->NotImplemented();
          return;
        }

        HANDLE process = ::OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE |
                                           PROCESS_QUERY_LIMITED_INFORMATION,
                                       FALSE, process_id);
        if (process == nullptr) {
          result->Error("open_process_failed", "Cannot open child process",
                        flutter::EncodableValue(
                            static_cast<int64_t>(::GetLastError())));
          return;
        }
        BOOL already_in_app_job = FALSE;
        if (app_process_job_ != nullptr &&
            ::IsProcessInJob(process, app_process_job_, &already_in_app_job) &&
            already_in_app_job) {
          ::CloseHandle(process);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags =
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        const bool configured =
            job != nullptr &&
            ::SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                      &limits, sizeof(limits));
        const bool assigned =
            configured && ::AssignProcessToJobObject(job, process);
        const DWORD error = assigned ? ERROR_SUCCESS : ::GetLastError();
        ::CloseHandle(process);
        if (!assigned) {
          if (job != nullptr) ::CloseHandle(job);
          result->Error("assign_job_failed",
                        "Cannot bind child process tree to App lifetime",
                        flutter::EncodableValue(static_cast<int64_t>(error)));
          return;
        }
        const auto existing = child_process_jobs_.find(process_id);
        if (existing != child_process_jobs_.end()) {
          ::CloseHandle(existing->second);
          child_process_jobs_.erase(existing);
        }
        child_process_jobs_.emplace(process_id, job);
        result->Success(flutter::EncodableValue(true));
      });
  DragAcceptFiles(GetHandle(), TRUE);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  startup_surface_visible_ = false;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  DragAcceptFiles(GetHandle(), FALSE);
  file_drop_channel_.reset();
  process_lifecycle_channel_.reset();
  for (const auto& entry : child_process_jobs_) {
    ::CloseHandle(entry.second);
  }
  child_process_jobs_.clear();
  // Do not close app_process_job_ here: the runner itself belongs to this job,
  // so closing the last handle would terminate the process before Flutter and
  // COM finish their normal shutdown. Windows closes the handle at process
  // exit, which then terminates every remaining child in the job.
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_ERASEBKGND:
      if (startup_surface_visible_) return 1;
      break;
    case WM_PAINT:
      if (startup_surface_visible_) {
        PAINTSTRUCT paint{};
        HDC device = ::BeginPaint(hwnd, &paint);
        RECT client{};
        ::GetClientRect(hwnd, &client);
        HBRUSH background = ::CreateSolidBrush(RGB(248, 248, 246));
        ::FillRect(device, &client, background);
        ::DeleteObject(background);
        ::SetBkMode(device, TRANSPARENT);
        ::SetTextColor(device, RGB(35, 35, 33));
        HFONT font = ::CreateFontW(
            -28, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        HGDIOBJ previous_font = ::SelectObject(device, font);
        RECT text_area = client;
        text_area.left += 48;
        ::DrawTextW(device,
                    L"Vibekits  \u6b63\u5728\u542f\u52a8\u2026", -1,
                    &text_area,
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE);
        ::SelectObject(device, previous_font);
        ::DeleteObject(font);
        ::EndPaint(hwnd, &paint);
        return 0;
      }
      break;
    case WM_COPYDATA: {
      const COPYDATASTRUCT* data =
          reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data == nullptr || data->dwData != 0x564B464C ||
          data->lpData == nullptr || data->cbData < sizeof(wchar_t)) {
        return 0;
      }
      const wchar_t* current = static_cast<const wchar_t*>(data->lpData);
      const size_t length = data->cbData / sizeof(wchar_t);
      const wchar_t* end = current + length;
      flutter::EncodableList paths;
      while (current < end && *current != L'\0') {
        const size_t remaining = static_cast<size_t>(end - current);
        const size_t item_length = wcsnlen(current, remaining);
        if (item_length == remaining) break;
        paths.emplace_back(Utf8FromUtf16(current));
        current += item_length + 1;
      }
      if (file_drop_channel_ && !paths.empty()) {
        file_drop_channel_->InvokeMethod(
            "filesDropped",
            std::make_unique<flutter::EncodableValue>(paths));
      }
      return 1;
    }
    case WM_DROPFILES: {
      const HDROP drop = reinterpret_cast<HDROP>(wparam);
      const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
      flutter::EncodableList paths;
      paths.reserve(count);
      for (UINT index = 0; index < count; ++index) {
        const UINT length = DragQueryFileW(drop, index, nullptr, 0);
        std::vector<wchar_t> buffer(length + 1);
        if (DragQueryFileW(drop, index, buffer.data(), length + 1) > 0) {
          paths.emplace_back(Utf8FromUtf16(buffer.data()));
        }
      }
      DragFinish(drop);
      if (file_drop_channel_ && !paths.empty()) {
        file_drop_channel_->InvokeMethod(
            "filesDropped",
            std::make_unique<flutter::EncodableValue>(paths));
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
