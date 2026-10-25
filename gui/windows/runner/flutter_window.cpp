#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  BOOL dark = TRUE;
  DwmSetWindowAttribute(GetHandle(), 20, &dark, sizeof(dark));
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "anyps5/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "openFolder") {
      const auto* path = std::get_if<std::string>(call.arguments());
      if (!path) { result->Error("arguments", "Invalid folder"); return; }
      int size = MultiByteToWideChar(CP_UTF8, 0, path->c_str(), -1, nullptr, 0);
      std::wstring wide(size, L'\0');
      MultiByteToWideChar(CP_UTF8, 0, path->c_str(), -1, wide.data(), size);
      auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(GetHandle(), L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      if (opened <= 32) result->Error("folder", "Could not open folder");
      else result->Success();
      return;
    }
    if (call.method_name() != "pick") { result->NotImplemented(); return; }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("arguments", "Invalid dialog arguments"); return; }
    auto get = [args](const char* key) -> std::string {
      const auto it = args->find(flutter::EncodableValue(key));
      if (it == args->end()) return {};
      const auto* text = std::get_if<std::string>(&it->second);
      return text ? *text : std::string();
    };
    const auto kind = get("kind");
    IFileDialog* dialog = nullptr;
    HRESULT hr = CoCreateInstance(kind == "save" ? CLSID_FileSaveDialog : CLSID_FileOpenDialog,
        nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) { result->Error("dialog", "Could not create file dialog"); return; }
    DWORD options = 0;
    dialog->GetOptions(&options);
    options |= FOS_FORCEFILESYSTEM;
    if (kind == "folder") options |= FOS_PICKFOLDERS;
    if (kind == "open") options |= FOS_FILEMUSTEXIST;
    if (kind == "save") options |= FOS_OVERWRITEPROMPT;
    dialog->SetOptions(options);
    const auto title = get("title");
    int size = MultiByteToWideChar(CP_UTF8, 0, title.c_str(), -1, nullptr, 0);
    std::wstring wide(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, title.c_str(), -1, wide.data(), size);
    dialog->SetTitle(wide.c_str());
    hr = dialog->Show(GetHandle());
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      dialog->Release(); result->Success(); return;
    }
    IShellItem* item = nullptr;
    if (SUCCEEDED(hr)) hr = dialog->GetResult(&item);
    PWSTR path = nullptr;
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (SUCCEEDED(hr)) result->Success(flutter::EncodableValue(Utf8FromUtf16(path)));
    else result->Error("dialog", "Could not select path");
    if (path) CoTaskMemFree(path);
    if (item) item->Release();
    dialog->Release();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 1050;
      info->ptMinTrackSize.y = 780;
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
