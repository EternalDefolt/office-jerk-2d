extends Node
## DEV EYE — автоматические скриншоты сцены для анализа Claude Code
## Добавь как AutoLoad: Project → Settings → AutoLoad → dev_eye.gd
## Скриншоты сохраняются в res://dev_screenshots/
## Claude Code читает их для визуального анализа и корректировки

const SCREENSHOT_DIR := "res://dev_screenshots/"
const SCREENSHOT_INTERVAL := 3.0  # секунды между авто-скриншотами
const MAX_SCREENSHOTS := 20  # макс файлов (кольцевой буфер)

var _timer := 0.0
var _shot_index := 0
var _enabled := false  # дисебля отключалочка
var _scene_info := {}


func _ready() -> void:
	# Создаём папку
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	if OS.is_debug_build():
		print("[DEV_EYE] Auto OFF. F9 = manual screenshot, F10 = toggle auto")


func _process(delta: float) -> void:
	# Горячие клавиши
	if Input.is_physical_key_pressed(KEY_F9) and not _was_f9:
		_take_screenshot("manual")
	_was_f9 = Input.is_physical_key_pressed(KEY_F9)

	if Input.is_physical_key_pressed(KEY_F10) and not _was_f10:
		_enabled = not _enabled
		if OS.is_debug_build():
			print("[DEV_EYE] Auto: %s" % ("ON" if _enabled else "OFF"))
	_was_f10 = Input.is_physical_key_pressed(KEY_F10)

	if not _enabled:
		return

	_timer += delta
	if _timer >= SCREENSHOT_INTERVAL:
		_timer = 0.0
		_take_screenshot("auto")


var _was_f9 := false
var _was_f10 := false


func _take_screenshot(tag: String) -> void:
	# Ждём конец кадра для чистого скриншота
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	if img == null:
		return

	# Собираем инфо о сцене
	_gather_scene_info()

	# Сохраняем скриншот (кольцевой буфер)
	var idx := _shot_index % MAX_SCREENSHOTS
	var filename := "shot_%02d_%s.png" % [idx, tag]
	var path := SCREENSHOT_DIR + filename
	var global_path := ProjectSettings.globalize_path(path)
	img.save_png(global_path)

	# Сохраняем метаданные рядом
	var meta_path := global_path.replace(".png", ".json")
	var meta := {
		"index": _shot_index,
		"tag": tag,
		"timestamp": Time.get_datetime_string_from_system(),
		"viewport_size": [get_viewport().size.x, get_viewport().size.y],
	}
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()

	_shot_index += 1
	if OS.is_debug_build():
		print("[DEV_EYE] Saved: %s" % filename)


func _gather_scene_info() -> void:
	_scene_info = {}
	var root := get_tree().current_scene
	if root == null:
		return

	# Позиции всех ключевых нод
	var player := root.get_node_or_null("Player")
	var dummy := root.get_node_or_null("Dummy")
	var camera := get_viewport().get_camera_2d()

	if player:
		_scene_info["player"] = {
			"pos": [player.global_position.x, player.global_position.y],
			"vel": [player.velocity.x, player.velocity.y],
			"state": player._js,
			"combat": player._cs,
			"dir": player._dir,
		}

	if dummy:
		_scene_info["dummy"] = {
			"pos": [dummy.global_position.x, dummy.global_position.y],
			"hits": dummy._hit_count,
			"ragdoll": dummy._ragdoll,
		}

	if camera:
		_scene_info["camera"] = {
			"pos": [camera.global_position.x, camera.global_position.y],
			"zoom": [camera.zoom.x, camera.zoom.y],
			"offset": [camera.offset.x, camera.offset.y],
		}
