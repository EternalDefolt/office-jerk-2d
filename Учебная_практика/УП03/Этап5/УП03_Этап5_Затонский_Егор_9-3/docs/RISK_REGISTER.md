# RISK_REGISTER

| Риск | Уровень | Меры |
|---|---|---|
| Дефолтный GEMINI_API_KEY в asset_gen.py | Средний | Вынести в .env, ротация ключа (рекомендация) |
| Потеря сейвов | Низкий | scripts\backup.bat / restore.bat |
| Пик аудио-шины | Низкий | ограничитель на SFX bus |
