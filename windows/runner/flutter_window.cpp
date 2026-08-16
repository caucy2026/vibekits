#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
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
  DragAcceptFiles(GetHandle(), TRUE);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
