@echo off
cd /d "%~dp0"
if not exist "downloads\relinker.exe" goto setup
if not exist "downloads\runtime-windows\libs\libkernel.prx" goto setup
goto launch
:setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup_gui.ps1"
if errorlevel 1 (
  pause
  exit /b 1
)
:launch
if exist "gui\build\windows\x64\runner\Release\anyps5_gui.exe" (
  start "" "gui\build\windows\x64\runner\Release\anyps5_gui.exe"
  exit /b
)
cd gui
set "PUB_CACHE=%~dp0downloads\pub-cache"
call flutter run -d windows --release
