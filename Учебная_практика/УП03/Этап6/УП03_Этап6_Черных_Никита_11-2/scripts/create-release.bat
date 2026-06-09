@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if "%~1"=="" (echo укажи версию, напр. v1.0.1 & exit /b 1)
git tag %~1
gh release create %~1 release\*.zip --notes-file docs\RELEASE_NOTES.md
