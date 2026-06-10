@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  RUN - запуск игры Office Jerk 2D
echo ========================================

if "%GODOT%"=="" set "GODOT=godot"

"%GODOT%" --path . res://scenes/main.tscn
