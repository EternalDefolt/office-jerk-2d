# INSTALL — Office Jerk 2D

Короткие команды для запуска и проверки проекта. Все BAT-файлы лежат в `scripts/`
и сами переходят в корень проекта.

## Требования

- **Godot 4.6.x** — один исполняемый файл, https://godotengine.org/download
  Путь можно задать: `set GODOT=C:\path\to\Godot.exe` (или `make ... GODOT=...`).
- **Python 3.10+** — для линтера/форматтера GDScript.
- **Docker** *(опционально)* — для сборки в контейнере.
- **Git**.

## Запуск локально (Windows, BAT)

```bat
scripts\setup.bat      :: установить gdtoolkit + импортировать ассеты
scripts\run.bat        :: запустить игру (окно 1280x720)
scripts\check.bat      :: gdlint + юнит-тесты gdUnit4
scripts\format.bat     :: gdformat — форматирование scripts\
```

## Запуск локально (Makefile)

```bash
make setup
make run
make check
make format
```

## Запуск через Docker

```bash
scripts\docker-up.bat        :: или: docker compose up --build
scripts\docker-down.bat      :: или: docker compose down
scripts\logs.bat             :: или: docker compose logs -f
```

Образ скачивает Linux-бинарник Godot 4.6.1, импортирует ассеты и прогоняет
headless smoke-test главной сцены. GUI в контейнере не открывается — игра
десктопная; для реальной игры используйте `scripts\run.bat`.

## Переменные окружения

Игре `.env` не нужен. Для dev-скриптов генерации спрайтов скопируйте
`.env.example` → `.env` и впишите `GEMINI_API_KEY` (см. `.env.example`).

## Карта команд

| Действие | BAT | Makefile | Docker |
|----------|-----|----------|--------|
| Установка | `scripts\setup.bat` | `make setup` | `docker compose build` |
| Запуск | `scripts\run.bat` | `make run` | `docker compose up --build` |
| Проверка | `scripts\check.bat` | `make check` | — |
| Формат | `scripts\format.bat` | `make format` | — |
| Логи | `scripts\logs.bat` | `make logs` | `docker compose logs -f` |
| Стоп | `scripts\docker-down.bat` | `make docker-down` | `docker compose down` |
