@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  DOCKER-DOWN - остановка контейнеров
echo ========================================

docker compose down
