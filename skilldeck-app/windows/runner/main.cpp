#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

// Must match the class Win32Window registers and the title passed to Create();
// together they let a second launch find an already running, possibly hidden,
// SkillDeck window.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"SkillDeck";

// FlutterWindow shows its first frame natively. Suppress that one show before
// it reaches Win32; later tray requests must be able to show the same window.
class LaunchWindow : public FlutterWindow {
 public:
  LaunchWindow(const flutter::DartProject& project, bool background)
      : FlutterWindow(project), suppress_initial_show_(background) {}

 protected:
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept override {
    if (suppress_initial_show_ && message == WM_WINDOWPOSCHANGING) {
      auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
      if ((position->flags & SWP_SHOWWINDOW) != 0) {
        position->flags = (position->flags & ~SWP_SHOWWINDOW) | SWP_NOACTIVATE;
        suppress_initial_show_ = false;
      }
    }
    return FlutterWindow::MessageHandler(hwnd, message, wparam, lparam);
  }

 private:
  bool suppress_initial_show_;
};

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool background =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--skilldeck-background") != command_line_arguments.end();

  // Admit a single instance per session.
  //
  // The window can now be hidden rather than closed, so "the user launches
  // SkillDeck again" is ordinary, not an edge case. A second process would
  // fail to acquire the Workspace writer lock the first one holds for its
  // whole lifetime, so hand off to the running instance instead of starting.
  ::HANDLE instance_mutex =
      ::CreateMutex(nullptr, FALSE, L"Local\\SkillDeck.SingleInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindow(kWindowClassName, kWindowTitle);
    // A CLI launch may race the first instance's Command Host startup.
    if (existing != nullptr && !background) {
      ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  LaunchWindow window(project, background);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  // Closing the window puts SkillDeck away instead of ending it, so background
  // update checks keep running. The Dart side intercepts the close signal and
  // hides the window; the tray icon is the way back in.
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
