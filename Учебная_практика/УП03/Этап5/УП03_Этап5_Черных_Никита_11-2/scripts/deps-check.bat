@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
python -m pip install --user pip-audit >nul 2>&1
pip-audit -r requirements-dev.txt
