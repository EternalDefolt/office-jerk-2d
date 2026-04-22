@tool
extends Node2D
## Цветной тайл-заглушка. Рисует плоский прямоугольник заданного цвета и размера.
## Работает как на Node2D (пол, без физики), так и на StaticBody2D (стена, с коллизией) —
## любой Node2D-наследник унаследует это поведение.

@export var color: Color = Color(1, 1, 1, 1):
	set(value):
		color = value
		queue_redraw()

@export var size: Vector2 = Vector2(32, 32):
	set(value):
		size = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
