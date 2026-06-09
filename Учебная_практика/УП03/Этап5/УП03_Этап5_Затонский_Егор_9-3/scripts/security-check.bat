@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
echo [1] поиск секретов...
git grep -nE "AIza|secret|password|token" -- "*.gd" "*.py" .env.example
echo [2] проверка .gitignore...
findstr /C:".env" .gitignore
