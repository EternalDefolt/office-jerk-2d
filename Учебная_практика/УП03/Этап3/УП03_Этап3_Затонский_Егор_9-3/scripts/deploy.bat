@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
echo [DEPLOY] сборка release-билда (без Docker)...
call scripts\build_release.bat
echo [DEPLOY] готово: release\
