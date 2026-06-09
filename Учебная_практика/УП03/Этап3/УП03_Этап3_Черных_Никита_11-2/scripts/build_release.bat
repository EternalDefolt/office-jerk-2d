@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if "%GODOT%"=="" set "GODOT=godot"
if not exist build mkdir build
if not exist release mkdir release
"%GODOT%" --headless --path . --export-release "Windows Desktop" build\OfficeJerk2D.exe
powershell -Command "Compress-Archive -Force build\* release\OfficeJerk2D_v1.0.0_win64.zip"
echo [OK] release\OfficeJerk2D_v1.0.0_win64.zip
