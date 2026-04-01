extends Node2D
## Finisher — keyframed grab + physics throw. Heavy, impactful.
## Principles: 3:1 windup/snap ratio, hitstop, dummy locked to player during grab

enum Phase { INACTIVE, LUNGE, GRAB, WINDUP, RELEASE }

const GND := 113.0
const SZ_HEAD := Vector2(68, 64)
const SZ_BODY := Vector2(46, 82)
const SZ_FOOT := Vector2(44, 16)
const GAP_HB := 10.0
const GAP_BF := 36.0

var _player: CharacterBody2D
var _dummy: StaticBody2D
var _camera: Camera2D

var _phase := Phase.INACTIVE
var _t := 0.0
var _dir := 1.0  # throw direction
var _grab_hand := 1

# Positions
var _d_offset := Vector2.ZERO
var _d_start := Vector2.ZERO
var _p_start_x := 0.0
var _p_target_x := 0.0
var _neck_local := Vector2.ZERO

# Hitstop
var _hitstop_left := 0.0
var _hitstop_vib := 0.0

# Particles
var _dust: Array = []
var _blood: Array = []

var _cam_zoom := Vector2.ONE


func _ready() -> void:
	await get_tree().process_frame
	_player = get_parent().get_node_or_null("Player")
	_dummy = get_parent().get_node_or_null("Dummy")
	if _player:
		_camera = _player.get_node_or_null("Camera")
		if not _camera:
			_camera = get_viewport().get_camera_2d()


func _physics_process(delta: float) -> void:
	# Hitstop: freeze everything
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		_hitstop_vib = sin(_hitstop_left * 120.0) * 4.0 * (_hitstop_left / 0.1)
		if _camera:
			_camera.offset = Vector2(_hitstop_vib, 0)
		queue_redraw()
		return

	if _phase == Phase.INACTIVE:
		if Input.is_action_just_pressed("finisher") and _player and _dummy:
			if not _dummy.is_downed:
				var dist := absf(_player.global_position.x - _dummy.global_position.x)
				if dist < 250.0 and _dummy._hit_count >= 5:
					_start()
		_upd_fx(delta)
		queue_redraw()
		return

	_t += delta
	match _phase:
		Phase.LUNGE: _do_lunge(delta)
		Phase.GRAB: _do_grab(delta)
		Phase.WINDUP: _do_windup(delta)
		Phase.RELEASE: _do_release(delta)

	_upd_fx(delta)
	queue_redraw()


func _start() -> void:
	_player.finisher_active = true
	_dummy.finisher_active = true
	_dir = signf(_dummy.global_position.x - _player.global_position.x)
	_grab_hand = 1 if _dir > 0 else 0
	_d_start = _dummy.global_position
	_player._vdir = _dir
	_player._dir = _dir
	if _camera:
		_cam_zoom = _camera.zoom
	_phase = Phase.LUNGE
	_t = 0.0


# ═══════════════════════════
#  LUNGE (0.25s) — player walks to dummy
# ═══════════════════════════
func _do_lunge(delta: float) -> void:
	var dur := 0.25
	var t := clampf(_t / dur, 0.0, 1.0)
	var et := t * t  # ease-in (accelerating)

	var target_x := _dummy.global_position.x - _dir * 70.0
	_player.global_position.x = lerpf(_player.global_position.x, target_x, et)

	# Body leans forward
	_player._t_rot = _dir * et * 0.12
	_player._h_rot = _dir * et * 0.06
	_recomp()

	# Grab hand reaches toward dummy neck
	var neck_world := _dummy.global_position + Vector2(0, -GND + SZ_FOOT.y + GAP_BF + SZ_BODY.y + GAP_HB * 0.5)
	var hand_local = neck_world - _player.global_position
	if _grab_hand == 1:
		_player._rh_pos = _player._rh_pos.lerp(hand_local, delta * 12.0)
	else:
		_player._lh_pos = _player._lh_pos.lerp(hand_local, delta * 12.0)

	_dummy._fin_override = _stand_pose(sin(_t * 15.0) * 2.0 * (1.0 - t))

	if _t >= dur:
		# SNAP dummy to player offset (locked)
		_d_offset = _dummy.global_position - _player.global_position
		_phase = Phase.GRAB
		_t = 0.0

	_player.queue_redraw()
	_dummy.queue_redraw()


# ═══════════════════════════
#  GRAB (0.8s) — choke. Dummy LOCKED to player. Struggles.
# ═══════════════════════════
func _do_grab(delta: float) -> void:
	var dur := 0.8
	var t := clampf(_t / dur, 0.0, 1.0)
	var alive := 1.0 - t * 0.6

	# Dummy LOCKED to player (moves with player)
	_dummy.global_position = _player.global_position + _d_offset
	# Slowly lift
	_d_offset.y -= delta * 30.0 * (1.0 - t)

	# Hand locked to neck — SHAKES from weight of holding dummy up
	var strain := sin(_t * 7.0) * 3.0 * alive + randf_range(-1.5, 1.5) * alive
	var neck = _d_offset + Vector2(strain, -GND + SZ_FOOT.y + GAP_BF + SZ_BODY.y + GAP_HB * 0.5 + sin(_t * 4.0) * 2.0)
	if _grab_hand == 1:
		_player._rh_pos = neck
		_player._rh_rot = atan2(0.5 + sin(_t * 5.0) * 0.1, _dir)
	else:
		_player._lh_pos = neck
		_player._lh_rot = atan2(0.5 + sin(_t * 5.0) * 0.1, _dir)

	# Player: straining to hold, arm shakes, body sways from effort
	var sway := sin(_t * 2.5) * 0.02 + sin(_t * 6.0) * 0.01 * alive
	_player._t_rot = _dir * (0.08 + sway + strain * 0.003)
	_player._h_rot = _dir * 0.04 + sway
	_recomp()
	_set_free_hand(delta)

	# Dummy STRUGGLES with WEIGHT (not vibration — actual movement)
	var bt := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y
	var hy := bt - GAP_HB - SZ_HEAD.y / 2.0
	var by := bt + SZ_BODY.y / 2.0
	var kick_l := sin(_t * 3.5) * 18.0 * alive  # slow heavy kicks
	var kick_r := sin(_t * 4.2 + 1.0) * 18.0 * alive
	var grab_at_neck := sin(_t * 5.0) * 3.0 * alive
	var head_jerk := sin(_t * 6.0) * 4.0 * alive + randf_range(-1, 1) * alive

	_dummy._fin_override = {
		"head_ctr": Vector2(head_jerk, hy),
		"body_ctr": Vector2(sin(_t * 3.0) * 2.0 * alive, by),
		"rot": [head_jerk * 0.02, sin(_t * 2.5) * 0.03 * alive],
		"squash": [Vector2.ONE, Vector2.ONE],
		"tremor": alive * 3.0,
		"off": [
			Vector2(head_jerk, 0),
			Vector2(sin(_t * 3.0) * 2.0 * alive, 0),
			# Hands at own neck, prying
			Vector2(grab_at_neck, -SZ_BODY.y * 0.3 + sin(_t * 7.0) * 4.0 * alive),
			Vector2(-grab_at_neck, -SZ_BODY.y * 0.3 + sin(_t * 8.0) * 4.0 * alive),
			# Feet: heavy pendulum kicks (not vibration)
			Vector2(kick_l, sin(_t * 2.0) * 8.0 * alive),
			Vector2(kick_r, sin(_t * 2.5) * 8.0 * alive),
		],
	}

	if _camera:
		_camera.zoom = _cam_zoom * (1.0 + t * 0.1)

	if _t >= dur:
		_phase = Phase.WINDUP
		_t = 0.0

	_player.queue_redraw()
	_dummy.queue_redraw()


# ═══════════════════════════
#  WINDUP (0.2s) — SLOW pullback. 3:1 ratio.
# ═══════════════════════════
func _do_windup(delta: float) -> void:
	var dur := 0.2  # wind-up is 3x longer than snap (snap = ~0.06s via hitstop)
	var t := clampf(_t / dur, 0.0, 1.0)
	var et := 1.0 - (1.0 - t) * (1.0 - t)  # ease-out (decelerates into coil)

	# Player coils BACK (opposite throw direction)
	_player._t_rot = _dir * lerpf(0.1, -0.15, et)
	_player._h_rot = _dir * lerpf(0.05, -0.08, et)
	_recomp()

	# Dummy pulled back with player
	_dummy.global_position = _player.global_position + _d_offset

	# Hand still on neck
	var neck = _d_offset + Vector2(0, -GND + SZ_FOOT.y + GAP_BF + SZ_BODY.y + GAP_HB * 0.5)
	if _grab_hand == 1:
		_player._rh_pos = neck
	else:
		_player._lh_pos = neck
	_set_free_hand(delta)

	# Dummy: frozen in fear (stopped struggling, going limp)
	var bt := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y
	_dummy._fin_override = _stand_pose(sin(_t * 30.0) * 1.0 * (1.0 - t))

	if _t >= dur:
		_hitstop_left = 0.1
		# RAGDOLL THROW: use dummy's point-based physics
		_dummy.finisher_active = false
		_dummy._fin_override = {}
		_dummy.go_ragdoll(Vector2(_dir * 350.0, -200.0), 2000.0)
		_phase = Phase.RELEASE
		_t = 0.0
		_player._t_rot = _dir * 0.2
		_player._h_rot = _dir * 0.1

	_player.queue_redraw()
	_dummy.queue_redraw()


# ═══════════════════════════
#  RELEASE — player recovers, dummy ragdoll handles itself
# ═══════════════════════════
func _do_release(delta: float) -> void:
	var dur := 0.5
	var t := clampf(_t / dur, 0.0, 1.0)
	var et := 1.0 - (1.0 - t) * (1.0 - t)

	# Player steps back and relaxes
	_player.global_position.x = lerpf(_player.global_position.x, _p_target_x - _dir * 50.0, delta * 4.0)
	_player._t_rot = lerpf(_player._t_rot, 0.0, delta * 4.0)
	_player._h_rot = lerpf(_player._h_rot, 0.0, delta * 4.0)
	_recomp()
	_set_free_hand(delta)
	_return_grab_hand(delta)

	if _camera:
		_camera.zoom = _camera.zoom.lerp(_cam_zoom, delta * 3.0)
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, delta * 5.0)

	Engine.time_scale = lerpf(Engine.time_scale, 1.0, delta * 5.0)

	if _t >= dur:
		_phase = Phase.INACTIVE
		_player.finisher_active = false
		Engine.time_scale = 1.0
		if _camera:
			_camera.offset = Vector2.ZERO
			_camera.zoom = _cam_zoom

	_player.queue_redraw()


# ═══════════════════════════
#  HELPERS
# ═══════════════════════════
func _recomp() -> void:
	var bt := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y
	_player._t_pos = Vector2(-SZ_BODY.x / 2.0, bt)
	_player._t_ctr = _player._t_pos + SZ_BODY / 2.0
	_player._t_scl = Vector2.ONE
	_player._h_pos = Vector2(-SZ_HEAD.x / 2.0, bt - GAP_HB - SZ_HEAD.y)
	_player._h_ctr = _player._h_pos + SZ_HEAD / 2.0
	_player._fp[0] = Vector2(-8, GND - SZ_FOOT.y / 2.0)
	_player._fp[1] = Vector2(8, GND - SZ_FOOT.y / 2.0)
	_player._fa[0] = 0.0
	_player._fa[1] = 0.0


func _set_free_hand(delta: float) -> void:
	var sh_y := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y + SZ_BODY.y * 0.25
	var idle := Vector2((-8.0 if _grab_hand == 1 else 8.0), sh_y + 50.0)
	if _grab_hand == 1:
		_player._lh_pos = _player._lh_pos.lerp(idle, delta * 5.0)
		_player._lh_rot = lerpf(_player._lh_rot, PI / 2.0 * _dir, delta * 5.0)
	else:
		_player._rh_pos = _player._rh_pos.lerp(idle, delta * 5.0)
		_player._rh_rot = lerpf(_player._rh_rot, PI / 2.0 * _dir, delta * 5.0)


func _return_grab_hand(delta: float) -> void:
	var sh_y := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y + SZ_BODY.y * 0.25
	var idle := Vector2((8.0 if _grab_hand == 1 else -8.0), sh_y + 50.0)
	if _grab_hand == 1:
		_player._rh_pos = _player._rh_pos.lerp(idle, delta * 4.0)
		_player._rh_rot = lerpf(_player._rh_rot, PI / 2.0 * _dir, delta * 4.0)
	else:
		_player._lh_pos = _player._lh_pos.lerp(idle, delta * 4.0)
		_player._lh_rot = lerpf(_player._lh_rot, PI / 2.0 * _dir, delta * 4.0)


func _stand_pose(shake: float) -> Dictionary:
	var bt := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y
	return {
		"head_ctr": Vector2(shake, bt - GAP_HB - SZ_HEAD.y / 2.0),
		"body_ctr": Vector2(shake * 0.5, bt + SZ_BODY.y / 2.0),
		"rot": [shake * 0.01, 0.0],
		"squash": [Vector2.ONE, Vector2.ONE],
		"tremor": 0.0,
		"off": [Vector2(shake, 0), Vector2(shake * 0.5, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO],
	}


func _spawn_impact() -> void:
	for _i in 10:
		var bdir := Vector2(randf_range(-1, 1), randf_range(-1.5, -0.3)).normalized() * randf_range(40, 150)
		_blood.append([_dummy.global_position + Vector2(0, GND), bdir, randf_range(0.3, 0.7)])
	for _i in 8:
		var ddir := Vector2(randf_range(-1, 1), randf_range(-1, -0.2)).normalized() * randf_range(20, 80)
		_dust.append([_dummy.global_position + Vector2(randf_range(-10, 10), GND), ddir, randf_range(0.3, 0.6)])


func _upd_fx(delta: float) -> void:
	var i := 0
	while i < _blood.size():
		var b: Array = _blood[i]
		var p: Vector2 = b[0]; var v: Vector2 = b[1]; var l: float = b[2]
		v.y += 400.0 * delta; p += v * delta; l -= delta
		if l <= 0: _blood.remove_at(i)
		else: _blood[i] = [p, v, l]; i += 1
	i = 0
	while i < _dust.size():
		var d: Array = _dust[i]
		var p: Vector2 = d[0]; var v: Vector2 = d[1]; var l: float = d[2]
		v.y += 100.0 * delta; v *= 0.95; p += v * delta; l -= delta
		if l <= 0: _dust.remove_at(i)
		else: _dust[i] = [p, v, l]; i += 1


func _draw() -> void:
	if _player == null: return
	var off := -_player.global_position
	for b in _blood:
		var p: Vector2 = b[0]; var l: float = b[2]
		var sz := lerpf(2.0, 4.0, l)
		draw_rect(Rect2(p.x + off.x - sz / 2, p.y + off.y - sz / 2, sz, sz), Color(0.5, 0.02, 0.02, l))
	for d in _dust:
		var p: Vector2 = d[0]; var l: float = d[2]
		var sz := lerpf(1.0, 3.0, l)
		draw_rect(Rect2(p.x + off.x - sz / 2, p.y + off.y - sz / 2, sz, sz), Color(0.4, 0.35, 0.3, l * 0.5))
