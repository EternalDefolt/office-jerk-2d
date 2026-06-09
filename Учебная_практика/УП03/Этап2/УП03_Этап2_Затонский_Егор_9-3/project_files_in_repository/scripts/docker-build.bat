@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  DOCKER-BUILD - сборка образа Godot
echo ========================================

docker build -t office-jerk-2d:latest .
if errorlevel 1 (
    echo ОШИБКА сборки образа.
    exit /b 1
)

echo.
echo Образ office-jerk-2d:latest собран.
