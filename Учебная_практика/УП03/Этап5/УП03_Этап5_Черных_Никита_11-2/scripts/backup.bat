@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
if not exist backups mkdir backups
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DT=%%d
powershell -Command "Compress-Archive -Force scripts,scenes,assets,saves backups\office-jerk_%DT%.zip"
echo [OK] backups\office-jerk_%DT%.zip
