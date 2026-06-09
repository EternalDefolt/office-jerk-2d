@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
findstr /R "ERROR CRITICAL" logs\game.log || echo [OK] критических ошибок нет
