# Office Jerk 2D

Авторская десктопная инди-игра в жанре *stress-reliever* на движке **Godot 4.6**
(GDScript) под Windows 10/11. Игрок управляет персонажем в офисе и взаимодействует
с физическим манекеном: движение (WASD) с инерцией, прицел мышью, удары ЛКМ с
чередованием рук, блок ПКМ и многофазный финишер (X). У манекена — точечный рэгдолл
(6 узлов) и поведенческая AI-система реакций (BodyAI, 8 намерений).

## Стек

| Слой | Технология |
|------|------------|
| Движок | Godot Engine 4.6.x (`gl_compatibility`) |
| Язык | GDScript |
| Тесты | gdUnit4 |
| Качество | gdlint + gdformat (gdtoolkit) |
| Контейнер | Docker (headless-сборка/smoke-test) |
| Dev-тулинг | Python 3 (генерация спрайтов, опционально) |

## Быстрый старт

```bat
scripts\setup.bat      :: установка зависимостей + импорт ассетов
scripts\run.bat        :: запуск игры
scripts\check.bat      :: линтер + тесты
scripts\format.bat     :: форматирование
```

Полные команды (BAT / Makefile / Docker) — в [INSTALL.md](INSTALL.md).

## Управление

| Действие | Клавиша |
|----------|---------|
| Движение | W A S D |
| Прицел | Мышь |
| Удар | ЛКМ |
| Блок | ПКМ |
| Финишер | X |

## Структура

```
office-jerk-2d/
├── project.godot           конфигурация движка
├── scenes/                 сцены (.tscn)
├── scripts/                GDScript + BAT-команды (setup/run/check/format/...)
├── assets/img/             спрайты
├── tests/unit/             юнит-тесты gdUnit4
├── addons/gdUnit4/         фреймворк тестов
├── Dockerfile, docker-compose.yml, .dockerignore
├── Makefile, .env.example, requirements-dev.txt, .gdlintrc
└── docs/                   документация и практика
```

## Репозиторий

https://github.com/EternalDefolt/office-jerk-2d
