@echo off
chcp 65001 >nul
taskkill /IM OfficeJerk2D.exe /F >nul 2>&1
start "" "%~dp0\..\release\OfficeJerk2D.exe"
echo [OK] перезапущено
