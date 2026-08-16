#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  constexpr wchar_t kSingleInstanceMutex[] =
      L"Local\\Vibekits.SingleInstance.1";
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  const bool another_instance =
      instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (another_instance) {
    HWND existing_window = nullptr;
    for (int attempt = 0; attempt < 50 && existing_window == nullptr;
         ++attempt) {
      existing_window = ::FindWindowW(nullptr, L"Vibekits");
      if (existing_window == nullptr) ::Sleep(100);
    }
    if (existing_window != nullptr) {
      std::vector<wchar_t> payload;
      for (const std::wstring& argument : GetCommandLineArgumentsUtf16()) {
        payload.insert(payload.end(), argument.begin(), argument.end());
        payload.push_back(L'\0');
      }
      payload.push_back(L'\0');
      COPYDATASTRUCT data{};
      data.dwData = 0x564B464C;  // VKFL
      data.cbData = static_cast<DWORD>(payload.size() * sizeof(wchar_t));
      data.lpData = payload.data();
      DWORD_PTR ignored_result = 0;
      ::SendMessageTimeoutW(existing_window, WM_COPYDATA, 0,
                            reinterpret_cast<LPARAM>(&data),
                            SMTO_ABORTIFHUNG, 2000, &ignored_result);
      ::ShowWindow(existing_window, SW_RESTORE);
      ::SetForegroundWindow(existing_window);
      ::CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"Vibekits", origin, size)) {
    if (instance_mutex != nullptr) ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
