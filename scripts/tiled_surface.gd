@tool
extends Node2D
## Поверхность, заполняемая повторяющейся текстурой (тайлом).
## Origin в (0,0) — левый верхний угол зоны.
##
## Тайлинг 100% прямой: текстура не растягивается и не искажается.
## Для «ощущения пола под углом» используется perspective_y_squish —
## плитки сжимаются по вертикали, становятся шире чем выше. Форма зоны
## остаётся прямоугольной, плитки — прямые, просто аспект изменён.
##
## Если текстура не задана — зона заливается fallback_color.
## Если в дочках есть CollisionShape2D с RectangleShape2D — он автоматически
## подгоняется под size (удобно для стен).

@export var tile_texture: Texture2D:
	set(value):
		tile_texture = value
		queue_redraw()

@export var size: Vector2 = Vector2(640, 256):
	set(value):
		size = value
		queue_redraw()
		_refresh_collision()

## Общий масштаб одной плитки на экране.
## 1.0 — 64x64 текстура рисуется как 64x64 px.
## 2.0 — 64x64 текстура рисуется как 128x128 px.
@export_range(0.25, 8.0, 0.25) var tile_scale: float = 1.0:
	set(value):
		tile_scale = value
		queue_redraw()

## Дополнительный сжим плитки по Y — создаёт ощущение пола «под углом».
## 1.0 — плитка остаётся квадратной (взгляд сверху).
## 0.7 — лёгкий наклон, плитка становится чуть шире чем выше.
## 0.5 — выраженная псевдо-перспектива, плитка в 2 раза ниже чем шире.
## 0.3 — сильный «полёт» пола, как в очень пологом 2.5D.
@export_range(0.2, 1.0, 0.05) var perspective_y_squish: float = 1.0:
	set(value):
		perspective_y_squish = value
		queue_redraw()

## Используется, если tile_texture не задана.
@export var fallback_color: Color = Color(1, 1, 1, 0):
	set(value):
		fallback_color = value
		queue_redraw()

## Сколько пикселей С НИЗА текстуры считать «плинтусом» (отбойником).
## Эта полоса будет нарисована ОДИН раз вдоль нижней кромки зоны,
## а основное тело текстуры (верхние tex_h - baseboard_px) тайлится выше.
## 0 — тайлинг всей текстуры как есть (плинтуса нет).
@export var baseboard_px: int = 0:
	set(value):
		baseboard_px = value
		queue_redraw()

## Дополнительный вертикальный масштаб плинтуса на экране.
## 1.0 — 1:1 с текстурой (для baseboard_px=5 даёт 5 px на экране — очень тонко).
## 3.0 — плинтус в 3 раза выше (15 px), хорошо видно.
## 5.0 — жирный плинтус (25 px), выглядит как полноценная дверная коробка.
@export_range(1.0, 10.0, 0.5) var baseboard_scale: float = 1.0:
	set(value):
		baseboard_scale = value
		queue_redraw()


func _ready() -> void:
	_apply_canvas_settings()
	_refresh_collision()
	queue_redraw()


func _enter_tree() -> void:
	# В @tool режиме _ready срабатывает не всегда когда надо — _enter_tree гарантирует,
	# что настройки канвас-айтема применятся как только узел появился в сцене.
	_apply_canvas_settings()
	queue_redraw()


func _apply_canvas_settings() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _refresh_collision() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			(child.shape as RectangleShape2D).size = size
			child.position = size / 2.0


func _draw() -> void:
	# Страховка: выставляем фильтр/репит каждый раз при отрисовке, чтобы в редакторе
	# не было ситуации, когда _ready ещё не отработал, а _draw уже вызывается.
	_apply_canvas_settings()
	if tile_texture == null:
		if fallback_color.a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), fallback_color)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.5, 0.5, 0.3), true)
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.3, 0.3, 1), false, 2.0)
		return

	var tex_sz := tile_texture.get_size()
	if tex_sz.x <= 0.0 or tex_sz.y <= 0.0:
		return

	# Разделяем текстуру: верх — тело для тайлинга, низ — плинтус (рисуется один раз).
	var bb_tex: float = float(clampi(baseboard_px, 0, int(tex_sz.y) - 1))
	var body_tex_h: float = tex_sz.y - bb_tex
	if body_tex_h <= 0.0:
		return

	# Размеры на экране.
	var tile_w: float = tex_sz.x * tile_scale
	var body_tile_h: float = body_tex_h * tile_scale * perspective_y_squish
	# Плинтус может иметь свой вертикальный масштаб — управляется baseboard_scale.
	var bb_screen_h: float = bb_tex * tile_scale * perspective_y_squish * baseboard_scale
	if tile_w <= 0.0 or body_tile_h <= 0.0:
		return

	# Граница между телом и плинтусом на экране.
	var body_zone_h: float = size.y - bb_screen_h
	if body_zone_h < 0.0:
		body_zone_h = 0.0

	var cols: int = int(ceil(size.x / tile_w))

	# --- ТЕЛО СТЕНЫ: тайлим СНИЗУ ВВЕРХ, чтобы нижний ряд был ПОЛНЫМ и прилегал
	# к плинтусу без смещения. Если зона не кратна высоте тайла — обрезается
	# верхний ряд (у потолка), где это не бросается в глаза.
	var remaining: float = body_zone_h
	var current_bottom: float = body_zone_h
	while remaining > 0.01:
		var h: float = minf(body_tile_h, remaining)
		var dst_y: float = current_bottom - h
		# Для обрезанного верхнего ряда показываем НИЖНЮЮ часть тела текстуры,
		# чтобы бордюр/градиент снизу тела корректно прилегал к ряду ниже.
		var src_y_off: float = body_tex_h - body_tex_h * (h / body_tile_h)
		var src_h: float = body_tex_h * (h / body_tile_h)
		for cx in cols:
			var px := float(cx) * tile_w
			var w: float = minf(tile_w, size.x - px)
			if w <= 0.0:
				continue
			var src_w: float = tex_sz.x * (w / tile_w)
			draw_texture_rect_region(
				tile_texture,
				Rect2(round(px), round(dst_y), round(w), round(h)),
				Rect2(Vector2(0, src_y_off), Vector2(src_w, src_h))
			)
		remaining -= h
		current_bottom -= h

	# --- ПЛИНТУС: рисуется ровно один раз по всей нижней кромке зоны,
	# тайлится только по горизонтали (по вертикали — всего один раз).
	if bb_tex > 0.0 and bb_screen_h > 0.0:
		var bb_y: float = size.y - bb_screen_h
		for cx in cols:
			var px := float(cx) * tile_w
			var w: float = minf(tile_w, size.x - px)
			if w <= 0.0:
				continue
			var src_w: float = tex_sz.x * (w / tile_w)
			draw_texture_rect_region(
				tile_texture,
				Rect2(round(px), round(bb_y), round(w), round(bb_screen_h)),
				Rect2(Vector2(0, body_tex_h), Vector2(src_w, bb_tex))
			)
