# DEPLOYMENT — Office Jerk 2D

Docker НЕ используется. Развёртывание = экспорт десктоп-билда Godot.

## Сборка
```
scripts\build_release.bat
```
Создаёт `build/OfficeJerk2D.exe` и `release/OfficeJerk2D_v1.0.0_win64.zip`.

## Запуск вне IDE
```
cd release && OfficeJerk2D.exe
```

## Перезапуск
```
scripts\restart.bat
```

## Проверка
```
scripts\check_deploy.bat   :: запускает билд headless и проверяет загрузку сцены
```

## Логи
`logs/game.log` — ищем ERROR/CRITICAL, их быть не должно.
