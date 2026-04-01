extends StaticBody2D

const TILE := 24.0
const C1 := Color(0.18, 0.18, 0.2)
const C2 := Color(0.25, 0.25, 0.27)
const COLS := 200
const ROWS := 12


func _draw() -> void:
	for x in range(-COLS / 2, COLS / 2):
		for y in range(ROWS):
			var c := C1 if (x + y) % 2 == 0 else C2
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), c)
	# Surface edge
	draw_line(Vector2(-COLS / 2 * TILE, 0), Vector2(COLS / 2 * TILE, 0), Color(0.35, 0.35, 0.38), 1.5)
