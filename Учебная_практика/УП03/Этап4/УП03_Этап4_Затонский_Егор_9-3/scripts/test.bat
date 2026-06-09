@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if "%GODOT%"=="" set "GODOT=godot"
gdlint scripts || exit /b 1
"%GODOT%" --headless --path . --quit-after 120 res://scenes/main.tscn || exit /b 1
echo [OK] тесты пройдены
