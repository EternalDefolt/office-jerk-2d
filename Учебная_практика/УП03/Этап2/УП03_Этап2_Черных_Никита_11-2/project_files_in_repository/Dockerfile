# Office Jerk 2D — образ для headless-сборки/валидации проекта.
# Десктопная игра на Godot: GUI в контейнере не запускается, но образ
# импортирует ассеты и прогоняет smoke-test главной сцены в режиме --headless.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.6.1
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends wget unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Официальный Linux-бинарник Godot (он же работает с флагом --headless).
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /usr/local/bin \
 && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm /tmp/godot.zip

WORKDIR /app
COPY . .

# Импорт ассетов на этапе сборки — образ готов к запуску сразу.
RUN godot --headless --path . --import || true

# Smoke-test: открыть главную сцену headless на ~3 секунды и выйти.
CMD ["godot", "--headless", "--path", ".", "--quit-after", "180", "res://scenes/main.tscn"]
