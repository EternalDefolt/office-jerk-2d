@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
python scripts\asset_gen.py --selftest
echo [OK] проверка API-обвязки asset_gen завершена
