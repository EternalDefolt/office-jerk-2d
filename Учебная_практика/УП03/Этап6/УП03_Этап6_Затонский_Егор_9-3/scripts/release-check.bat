@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
call scripts\test.bat || exit /b 1
if not exist release\*.zip (echo [FAIL] нет release-архива & exit /b 1)
echo [OK] готово к релизу
