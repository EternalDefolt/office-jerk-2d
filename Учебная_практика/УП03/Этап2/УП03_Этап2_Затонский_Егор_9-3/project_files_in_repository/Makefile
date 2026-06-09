# Office Jerk 2D — единая карта команд проекта.
# Godot можно переопределить:  make run GODOT=/path/to/godot
GODOT ?= godot

.PHONY: setup run check format docker-build docker-up docker-down logs clean

setup:          ## Установить gdtoolkit и импортировать ассеты
	python -m pip install --user -r requirements-dev.txt
	$(GODOT) --headless --path . --import

run:            ## Запустить игру
	$(GODOT) --path . res://scenes/main.tscn

check:          ## Линтер GDScript + headless smoke-test главной сцены
	gdlint scripts
	$(GODOT) --headless --path . --quit-after 120 res://scenes/main.tscn

format:         ## Отформатировать scripts/ через gdformat
	gdformat scripts

docker-build:   ## Собрать Docker-образ
	docker compose build

docker-up:      ## Поднять проект через Docker Compose
	docker compose up --build

docker-down:    ## Остановить контейнеры
	docker compose down

logs:           ## Логи контейнеров
	docker compose logs -f

clean:          ## Удалить кэш импорта Godot
	rm -rf .godot
