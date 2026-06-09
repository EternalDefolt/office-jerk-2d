@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if "%GODOT%"=="" set "GODOT=godot"
"%GODOT%" --path . --debug res://scenes/main.tscn
echo [INFO] смотри Debugger ^> Monitors для FPS/памяти
