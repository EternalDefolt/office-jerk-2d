@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  DOCKER-UP - запуск проекта в контейнере
echo ========================================
echo  (десктопная игра: контейнер прогоняет headless smoke-test
echo   главной сцены и завершает работу)

docker compose up --build
