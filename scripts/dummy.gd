extends StaticBody2D
## Dummy — point-based ragdoll. Each body part is a physics point.

const OL := Color(0.05, 0.05, 0.05)
const FL := Color(1.0, 1.0, 1.0)
const SUIT := Color(0.55, 0.58, 0.62)   # серый деловой костюм
const TIE := Color(0.18, 0.15, 0.28)    # тёмный галстук
const BOOT := Color(0.08, 0.08, 0.1)    # чёрные ботинки
const SHIRT := Color(0.92, 0.92, 0.95)  # полоска воротничка
const SW := 3.0
const SZ_HEAD := Vector2(68, 64)
const SZ_BODY := Vector2(46, 82)
const SZ_FOOT := Vector2(44, 16)
const HAND_SZ := Vector2(48, 48)
const GND := 113.0
const BLD_DARK := Color(0.25, 0.0, 0.0)
const BLD_MID := Color(0.5, 0.02, 0.02)

var _ti: Texture2D
var _to: Texture2D
var _thead: Texture2D

# RAGDOLL: 6 points  0=head 1=body 2=lhand 3=rhand 4=lfoot 5=rfoot
var _pos: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _grav := 0.0
var _constraints: Array = []
var _ragdoll := false
var _rest: Array[Vector2] = []

var _bt := 0.0
var _hit_count := 0
var _flash := 0.0
var _hit_in := [false, false]
var _shake := 0.0
var _tremor := 0.0

var _wounds: Array = []
var _blood: Array = []
var _stains: Array = []

var finisher_active := false
var is_downed := false
var _fin_override := {}
var _player: Node2D = null
var _ai = preload("res://scripts/body_ai.gd").new()
var _hurt: Array = []  # 6 Area2D hurtboxes following ragdoll points


func _ready() -> void:
	_ti = load("res://assets/img/hand_inner.png")
	_to = load("res://assets/img/hand_outer.png")
	_thead = load("res://assets/img/head.png")

	var bt := GND - SZ_FOOT.y - 36.0 - SZ_BODY.y
	var head_y := bt - 10.0 - SZ_HEAD.y / 2.0
	var body_y := bt + SZ_BODY.y / 2.0
	var sh_y := bt + SZ_BODY.y * 0.25
	var foot_y := GND - SZ_FOOT.y / 2.0

	_rest = [
		Vector2(0, head_y),
		Vector2(0, body_y),
		Vector2(-SZ_BODY.x / 2.0 - 8, sh_y + 50),
		Vector2(SZ_BODY.x / 2.0 + 8, sh_y + 50),
		Vector2(-8, foot_y),
		Vector2(8, foot_y),
	]
	_pos.resize(6)
	_vel.resize(6)
	for i in 6:
		_pos[i] = _rest[i]
		_vel[i] = Vector2.ZERO

	_constraints = [
		[0, 1, 60.0],
		[1, 2, 70.0],
		[1, 3, 70.0],
		[1, 4, 90.0],
		[1, 5, 90.0],
		[4, 5, 30.0],
		[2, 3, 100.0],
	]
	# Init body AI with rest positions
	_ai.setup_rest_positions(_rest)
	# 6 hurtboxes: head, body, lhand, rhand, lfoot, rfoot
	_hurt = [
		get_node_or_null("HeadHurt"),
		get_node_or_null("BodyHurt"),
		get_node_or_null("LHandHurt"),
		get_node_or_null("RHandHurt"),
		get_node_or_null("LFootHurt"),
		get_node_or_null("RFootHurt"),
	]

	await get_tree().process_frame
	_player = get_parent().get_node_or_null("Player")


func _physics_process(delta: float) -> void:
	_bt += delta
	_flash = maxf(_flash - delta, 0.0)
	_tremor = lerpf(_tremor, 0.0, delta * 4.0)
	_shake = lerpf(_shake, 0.0, delta * 5.0)

	if finisher_active and not _fin_override.is_empty():
		queue_redraw()
		return

	if _ragdoll:
		_sim_ragdoll(delta)
	else:
		_sim_standing(delta)
		if _player and not _ragdoll:
			var punching := false
			for hi in 2:
				if _player._ph_on[hi]:
					punching = true
					_check_hit(hi)
			if not punching:
				_hit_in[0] = false
				_hit_in[1] = false

	# Sync ALL 6 hurtboxes to ragdoll positions
	for i in mini(_hurt.size(), _pos.size()):
		if _hurt[i]:
			_hurt[i].position = _pos[i]

	if _shake > 0.3:
		var cam := get_viewport().get_camera_2d()
		if cam:
			cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	queue_redraw()


func _sim_standing(delta: float) -> void:
	# Use BodyAI for standing behavior (includes schizo twitches)
	_ai.update(delta)
	var ai_pos = _ai.get_positions()
	# Spring toward AI-computed positions
	for i in 6:
		var target: Vector2 = ai_pos[i]
		_vel[i] += (100.0 * (target - _pos[i]) - 10.0 * _vel[i]) * delta
		_pos[i] += _vel[i] * delta


func _sim_ragdoll(delta: float) -> void:
	for i in 6:
		_vel[i].y += _grav * delta
		_vel[i] *= 0.99
		_pos[i] += _vel[i] * delta
		if _pos[i].y > GND:
			_pos[i].y = GND
			_vel[i].y *= -0.2
			_vel[i].x *= 0.7
	for _iter in 4:
		for c in _constraints:
			var ia: int = c[0]
			var ib: int = c[1]
			var mx: float = c[2]
			var diff := _pos[ib] - _pos[ia]
			var dist := diff.length()
			if dist > mx and dist > 0.01:
				var fix := diff.normalized() * (dist - mx) * 0.5
				_pos[ia] += fix
				_pos[ib] -= fix
				_vel[ia] += fix * 2.0
				_vel[ib] -= fix * 2.0
		for i in 6:
			if _pos[i].y > GND:
				_pos[i].y = GND
				if _vel[i].y > 0: _vel[i].y *= -0.15


func go_ragdoll(impulse: Vector2 = Vector2.ZERO, gravity: float = 1800.0) -> void:
	_ragdoll = true
	_grav = gravity
	_vel[1] += impulse
	_vel[0] += impulse * 0.8 + Vector2(randf_range(-30, 30), randf_range(-20, 0))
	_vel[2] += impulse * 0.5 + Vector2(randf_range(-50, 50), randf_range(-30, 10))
	_vel[3] += impulse * 0.5 + Vector2(randf_range(-50, 50), randf_range(-30, 10))
	_vel[4] += impulse * 0.3 + Vector2(randf_range(-20, 20), randf_range(-10, 10))
	_vel[5] += impulse * 0.3 + Vector2(randf_range(-20, 20), randf_range(-10, 10))


func reset_standing() -> void:
	_ragdoll = false
	_grav = 0.0
	for i in 6:
		_pos[i] = _rest[i]
		_vel[i] = Vector2.ZERO


func _check_hit(hand_idx: int) -> void:
	if _player == null: return
	if not _player._ph_on[hand_idx]:
		_hit_in[hand_idx] = false
		return
	# Only check during STRIKE phase (not windup)
	var pt: float = _player._ph_t[hand_idx]
	var wf = _player.PUNCH_WINDUP / (_player.PUNCH_WINDUP + _player.PUNCH_STRIKE)
	if pt < wf:
		_hit_in[hand_idx] = false  # RESET for each new punch windup
		return
	var hp: Vector2 = _player._lh_pos if hand_idx == 0 else _player._rh_pos
	var local := hp + _player.global_position - global_position
	# Bigger hitboxes for reliable detection
	var in_head := local.distance_to(_pos[0]) < 50
	var in_body := local.distance_to(_pos[1]) < 55
	var hit := -1
	if in_head: hit = 0
	elif in_body: hit = 1
	if hit >= 0 and not _hit_in[hand_idx]:
		_hit_in[hand_idx] = true
		var pd: Vector2 = _player._ph_dir[hand_idx]
		_register_hit(local, hit, pd)


func _register_hit(_hit_pos: Vector2, part: int, dir: Vector2) -> void:
	_hit_count += 1
	_flash = 0.08
	var d := dir.normalized()
	var force := 70.0 + float(_hit_count) * 1.5

	# === HIT PHYSICS ===
	# Direct hit: hit part takes full force
	_vel[part] += d * force * 2.0

	# HEAD HIT: head snaps back, body follows less, hands jolt
	if part == 0:
		_vel[0] += d * force * 1.5 + Vector2(0, -force * 0.3)  # head snaps UP from impact
		_vel[1] += d * force * 0.5  # body follows
		_vel[2] += Vector2(randf_range(-20, 20), randf_range(-15, 5))  # hands jolt
		_vel[3] += Vector2(randf_range(-20, 20), randf_range(-15, 5))
		_vel[4] += d * force * 0.15  # feet barely
		_vel[5] += d * force * 0.15

	# BODY HIT: body crunches, head whips forward, hands flail
	elif part == 1:
		_vel[1] += d * force * 1.0
		_vel[0] += d * force * 0.7 + Vector2(d.x * 20.0, 10.0)  # head whips
		_vel[2] += d * force * 0.6 + Vector2(randf_range(-30, 30), randf_range(-10, 10))
		_vel[3] += d * force * 0.6 + Vector2(randf_range(-30, 30), randf_range(-10, 10))
		_vel[4] += d * force * 0.25
		_vel[5] += d * force * 0.25

	# Feed AI
	_ai.receive_hit(d, force)
	_ai.panic = minf(_ai.panic + 0.15, 1.0)

	# Screen shake proportional to force
	_shake = clampf(force * 0.04, 1.0, 6.0)

	# Pushback (whole dummy slides)
	global_position.x += d.x * force * 0.2


func _upd_blood(delta: float) -> void:
	var i := 0
	while i < _blood.size():
		var b: Array = _blood[i]
		var p: Vector2 = b[0]; var v: Vector2 = b[1]; var l: float = b[2]
		v.y += 400.0 * delta; p += v * delta; l -= delta
		if l <= 0.0 or p.y > GND:
			if p.y > GND and _stains.size() < 200:
				_stains.append([p, randf_range(2, 5)])
			_blood.remove_at(i); continue
		_blood[i] = [p, v, l]; i += 1


func _draw() -> void:
	if finisher_active and not _fin_override.is_empty():
		_draw_override(); return
	var flash_col := Color(1.0, 0.35, 0.25)
	var body_fill := flash_col if _flash > 0.0 else SUIT
	var foot_fill := flash_col if _flash > 0.0 else BOOT

	var hr := clampf(_vel[0].x * 0.003, -0.3, 0.3)
	var br := clampf(_vel[1].x * 0.002, -0.2, 0.2)
	_draw_hand(_pos[2], true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_box(_pos[4], SZ_FOOT, foot_fill)
	_draw_box(_pos[5], SZ_FOOT, foot_fill)
	draw_set_transform(_pos[1], br, Vector2.ONE)
	# Корпус (пиджак)
	draw_rect(Rect2(-SZ_BODY.x / 2.0 - SW, -SZ_BODY.y / 2.0 + 4, SZ_BODY.x + SW * 2, SZ_BODY.y - 4 + SW), OL)
	draw_rect(Rect2(-SZ_BODY.x / 2.0, -SZ_BODY.y / 2.0 + 4, SZ_BODY.x, SZ_BODY.y - 4), body_fill)
	# Белая полоска воротничка у шеи
	if _flash <= 0.0:
		draw_rect(Rect2(-14.0, -SZ_BODY.y / 2.0 + 4, 28.0, 4.0), SHIRT)
		# Галстук
		var tie_w := 9.0
		var tie_top := -SZ_BODY.y / 2.0 + 8
		var tie_bot := SZ_BODY.y / 2.0 - 6
		draw_rect(Rect2(-tie_w / 2.0, tie_top, tie_w, tie_bot - tie_top), TIE)
		# Треугольный «узел» галстука сверху
		var knot := PackedVector2Array([
			Vector2(-tie_w / 2.0 - 2, tie_top),
			Vector2(tie_w / 2.0 + 2, tie_top),
			Vector2(0, tie_top + 6),
		])
		draw_polygon(knot, PackedColorArray([TIE]))
	draw_set_transform(_pos[0], hr, Vector2.ONE)
	if _thead:
		draw_texture_rect(_thead, Rect2(-SZ_HEAD.x / 2.0, -SZ_HEAD.y / 2.0, SZ_HEAD.x, SZ_HEAD.y), false)
	else:
		draw_rect(Rect2(-SZ_HEAD.x / 2.0 - SW, -SZ_HEAD.y / 2.0 - SW, SZ_HEAD.x + SW * 2, SZ_HEAD.y + SW * 2), OL)
		draw_rect(Rect2(-SZ_HEAD.x / 2.0, -SZ_HEAD.y / 2.0, SZ_HEAD.x, SZ_HEAD.y), body_fill)
	_draw_eyes()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hand(_pos[3], false)
	if _hit_count > 0:
		var cp := _pos[0] + Vector2(0, -SZ_HEAD.y / 2.0 - 16)
		draw_set_transform(cp, 0.0, Vector2.ONE)
		var font := ThemeDB.fallback_font; var txt := str(_hit_count)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		draw_rect(Rect2(-tw / 2.0 - 4, -9, tw + 8, 16), Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(-tw / 2.0, 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FL)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_override() -> void:
	var fill := Color(1.0, 0.35, 0.25) if _flash > 0.0 else FL
	var hc: Vector2 = _fin_override.get("head_ctr", _pos[0])
	var bc: Vector2 = _fin_override.get("body_ctr", _pos[1])
	var ra = _fin_override.get("rot", [0.0, 0.0])
	var off_arr = _fin_override.get("off", [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

	# Compute part positions from offsets
	var bt := GND - SZ_FOOT.y - 36.0 - SZ_BODY.y
	var sh_y := bt + SZ_BODY.y * 0.25
	var foot_y := GND - SZ_FOOT.y / 2.0
	var lh_p := Vector2(-SZ_BODY.x / 2.0 - 8, sh_y + 50) + Vector2(off_arr[2])
	var rh_p := Vector2(SZ_BODY.x / 2.0 + 8, sh_y + 50) + Vector2(off_arr[3])
	var lf_p := Vector2(-8, foot_y) + Vector2(off_arr[4])
	var rf_p := Vector2(8, foot_y) + Vector2(off_arr[5])

	# Hand rotations from AI (or default PI/2)
	var hr = _fin_override.get("hand_rot", [PI / 2.0, PI / 2.0])
	var lr: float = hr[0]
	var rr: float = hr[1]

	# Back hand
	_draw_hand_r(lh_p, true, lr)
	# Feet
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_box(lf_p, SZ_FOOT, fill)
	_draw_box(rf_p, SZ_FOOT, fill)
	# Body
	draw_set_transform(bc, float(ra[1]), Vector2.ONE)
	draw_rect(Rect2(-SZ_BODY.x / 2.0 - SW, -SZ_BODY.y / 2.0 + 4, SZ_BODY.x + SW * 2, SZ_BODY.y - 4 + SW), OL)
	draw_rect(Rect2(-SZ_BODY.x / 2.0, -SZ_BODY.y / 2.0 + 4, SZ_BODY.x, SZ_BODY.y - 4), fill)
	# Head
	draw_set_transform(hc, float(ra[0]), Vector2.ONE)
	if _thead:
		draw_texture_rect(_thead, Rect2(-SZ_HEAD.x / 2.0, -SZ_HEAD.y / 2.0, SZ_HEAD.x, SZ_HEAD.y), false)
	_draw_eyes()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Front hand
	_draw_hand_r(rh_p, false, rr)


func _draw_eyes() -> void:
	# Глаза в стиле Player'а: вытянутые чёрные сокеты («глазные яблоки» в тени)
	# + белые зрачки внутри. Разница только в том, что взгляд Dummy
	# ФИКСИРОВАН — не следит за Player'ом.
	var ey := 14.0
	var ew := 12.0
	var eh := 28.0
	var eg := 6.0
	var lx := -eg / 2.0 - ew
	var rx := eg / 2.0
	if _hit_count > 10:
		# X-eyes после множества попаданий (в отключке)
		for ex in [lx + ew / 2.0, rx + ew / 2.0]:
			draw_line(Vector2(ex - 5, ey - 5), Vector2(ex + 5, ey + 5), OL, 2.5)
			draw_line(Vector2(ex + 5, ey - 5), Vector2(ex - 5, ey + 5), OL, 2.5)
	else:
		# Глазные яблоки — чёрные вытянутые прямоугольники (как у Player).
		draw_rect(Rect2(lx, ey - eh / 2.0, ew, eh), OL)
		draw_rect(Rect2(rx, ey - eh / 2.0, ew, eh), OL)
		# Белые зрачки 6×8 (того же размера как у Player).
		# Статично смещены: чуть вправо (смотрит мимо Player'а)
		# и слегка вниз (пустой усталый взгляд).
		var pup_w := 6.0
		var pup_h := 8.0
		var pup_dx := 1.0
		var pup_dy := 4.0
		var le_cx := lx + ew / 2.0
		var re_cx := rx + ew / 2.0
		draw_rect(Rect2(le_cx - pup_w / 2.0 + pup_dx, ey - pup_h / 2.0 + pup_dy, pup_w, pup_h), FL)
		draw_rect(Rect2(re_cx - pup_w / 2.0 + pup_dx, ey - pup_h / 2.0 + pup_dy, pup_w, pup_h), FL)


func _draw_wounds(part: int, sz: Vector2) -> void:
	var half := sz / 2.0
	for w in _wounds:
		if int(w[0]) != part: continue
		var off: Vector2 = w[1]; var dir: Vector2 = w[2]
		off.x = clampf(off.x, -half.x + 5, half.x - 5)
		off.y = clampf(off.y, -half.y + 5, half.y - 5)
		var perp := Vector2(-dir.y, dir.x)
		draw_line(off - perp * 6, off + perp * 6, BLD_MID, 3.0)
		draw_line(off - perp * 4, off + perp * 4, BLD_DARK, 2.0)


func _draw_hand_r(pos: Vector2, is_left: bool, rot: float) -> void:
	var tex := _to if is_left else _ti
	if tex:
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-HAND_SZ / 2.0, HAND_SZ), false)
	else:
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_rect(Rect2(-HAND_SZ.x / 2.0 - SW, -HAND_SZ.y / 2.0 - SW, HAND_SZ.x + SW * 2, HAND_SZ.y + SW * 2), OL)
		draw_rect(Rect2(-HAND_SZ.x / 2.0, -HAND_SZ.y / 2.0, HAND_SZ.x, HAND_SZ.y), FL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hand(pos: Vector2, is_left: bool) -> void:
	var tex := _to if is_left else _ti
	if tex:
		draw_set_transform(pos, PI / 2.0, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-HAND_SZ / 2.0, HAND_SZ), false)
	else:
		draw_set_transform(pos, 0.0, Vector2.ONE)
		draw_rect(Rect2(-HAND_SZ.x / 2.0 - SW, -HAND_SZ.y / 2.0 - SW, HAND_SZ.x + SW * 2, HAND_SZ.y + SW * 2), OL)
		draw_rect(Rect2(-HAND_SZ.x / 2.0, -HAND_SZ.y / 2.0, HAND_SZ.x, HAND_SZ.y), FL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_box(ctr: Vector2, sz: Vector2, fill: Color) -> void:
	draw_rect(Rect2(ctr.x - sz.x / 2.0 - SW, ctr.y - sz.y / 2.0 - SW, sz.x + SW * 2, sz.y + SW * 2), OL)
	draw_rect(Rect2(ctr.x - sz.x / 2.0, ctr.y - sz.y / 2.0, sz.x, sz.y), fill)
