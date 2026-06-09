@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if "%~1"=="" (echo укажи zip & exit /b 1)
powershell -Command "Expand-Archive -Force '%~1' restore_test"
if "%GODOT%"=="" set "GODOT=godot"
"%GODOT%" --headless --path restore_test --quit-after 60 res://scenes/main.tscn
