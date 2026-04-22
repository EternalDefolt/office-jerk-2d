@tool
extends Node2D
## Фон больше ничего не рисует — пол и стены теперь расставляются как отдельные
## физические сцены (floor_tile.tscn / wall_tile.tscn). Оставлено пустым,
## чтобы не ломать узел OfficeBG в main.tscn, если он там ещё присутствует.


func _ready() -> void:
	pass
