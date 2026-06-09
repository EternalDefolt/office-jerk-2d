@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if "%GODOT%"=="" set "GODOT=godot"
"%GODOT%" --headless --path . --quit-after 120 res://scenes/main.tscn
if errorlevel 1 (echo [FAIL] сцена не загрузилась & exit /b 1)
echo [OK] билд загружается вне IDE
