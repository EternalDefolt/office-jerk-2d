# BACKUP_RESTORE_REPORT

backup.bat создаёт `backups/office-jerk_YYYY-MM-DD.zip` (проект + сейвы).
restore.bat распаковывает в `restore_test/` и прогоняет headless-проверку сцены.
Результат: после восстановления проект загружается без ошибок.
