@echo off
chcp 65001 >nul
netstat -ano | findstr OfficeJerk || echo [OK] портов не слушает
