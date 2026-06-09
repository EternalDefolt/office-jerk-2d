@echo off
chcp 65001 > nul
cd /d "%~dp0\.."

echo ========================================
echo  SETUP - установка зависимостей проекта
echo ========================================

REM Godot можно переопределить: set GODOT=C:\path\to\Godot.exe
if "%GODOT%"=="" set "GODOT=godot"

echo [1/2] Установка инструментов качества GDScript (gdtoolkit)...
python -m pip install --user -r requirements-dev.txt
if errorlevel 1 (
    echo ОШИБКА: не удалось установить gdtoolkit. Проверьте Python и pip.
    exit /b 1
)

echo [2/2] Импорт ассетов Godot (аналог установки зависимостей)...
"%GODOT%" --headless --path . --import
if errorlevel 1 (
    echo ОШИБКА: импорт не удался. Проверьте путь к Godot (set GODOT=...).
    exit /b 1
)

echo.
echo Готово. Зависимости установлены, ассеты импортированы.
