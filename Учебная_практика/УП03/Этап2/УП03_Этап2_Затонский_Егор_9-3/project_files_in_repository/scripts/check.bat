@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  CHECK - линтер GDScript + smoke-test
echo ========================================

if "%GODOT%"=="" set "GODOT=godot"
set EXITCODE=0

echo [1/2] gdlint - проверка стиля скриптов...
gdlint scripts
if errorlevel 1 set EXITCODE=1

echo.
echo [2/2] smoke-test - headless-загрузка главной сцены...
REM gdUnit4-тесты запускаются в редакторе (F5 в gdUnit панели):
REM их CLI-раннер несовместим с Godot 4.6 в headless-режиме.
REM Поэтому в CI используется headless smoke-test сборки сцены.
"%GODOT%" --headless --path . --quit-after 120 res://scenes/main.tscn
if errorlevel 1 set EXITCODE=1

echo.
if "%EXITCODE%"=="0" (
    echo Проверка пройдена без ошибок.
) else (
    echo Проверка нашла проблемы - см. вывод выше.
)
exit /b %EXITCODE%
