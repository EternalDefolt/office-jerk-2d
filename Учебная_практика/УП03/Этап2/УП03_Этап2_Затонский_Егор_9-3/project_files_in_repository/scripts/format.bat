@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  FORMAT - форматирование GDScript
echo ========================================

echo gdformat - приведение scripts\ к единому стилю...
gdformat scripts
if errorlevel 1 (
    echo ОШИБКА форматирования.
    exit /b 1
)

echo.
echo Готово. Код отформатирован.
