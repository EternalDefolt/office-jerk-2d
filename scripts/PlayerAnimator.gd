class_name PlayerAnimator extends RefCounted
## Player animation + draw module.
## Объединяет: walk cycle, дыхание, тело-sway, lean spring, pendulum hands,
## head bob, squash/stretch, blink, step curve, compose всех per-part
## трансформов и финальную отрисовку (_draw делегируется сюда из player.gd).

# ════════════════════════════════════════════════════════════════
#  WALK CYCLE  (time-based cadence, NOT distance-based)
# ════════════════════════════════════════════════════════════════
const WALK_CADENCE := 1.55
const SPRINT_CADENCE := 2.5
const STRIDE_MAX := 48.0
const SPRINT_STRIDE := 72.0
const STEP_HEIGHT := 15.0
const SPRINT_STEP_H := 13.0
const WALK_BLEND_IN := 10.0
const WALK_BLEND_OUT := 7.0
## В Godot 2D Y направлен вниз, положительный угол = clockwise в экране.
## Для правой стопы (toe-pivot = правый край), чтобы пятка поднялась ВВЕРХ
## относительно пивота — нужен ПОЛОЖИТЕЛЬНЫЙ угол.
const FOOT_TOE_OFF := 0.18
const FOOT_HEEL_STRIKE := -0.14
const FOOT_SWING_LIFT := -0.25
const WALK_HIP_DROP := 3.2
const SPRINT_HIP_DROP := 5.5
const SPRINT_LEAN := 0.10
const SPRINT_FLIGHT := 2.2

# Arm swing амплитуды
const ARM_SWING_WALK := 14.0
const ARM_SWING_SPRINT_BONUS := 8.0
const ARM_DIP_WALK := 3.0
const ARM_DIP_SPRINT_BONUS := 2.0

# ════════════════════════════════════════════════════════════════
#  BREATHING  (3-layer sine для органичного ритма)
# ════════════════════════════════════════════════════════════════
const BR_FREQ := 2.8
const BR_AMP_Y := 1.5
const BR_AMP_X := 0.15
const BR_SCALE := 0.005

# ════════════════════════════════════════════════════════════════
#  BODY SWAY  (двухслойное idle-rocking)
# ════════════════════════════════════════════════════════════════
const SWAY_F1 := 1.3
const SWAY_A1 := 0.005
const SWAY_F2 := 2.1
const SWAY_A2 := 0.002
const WALK_SWAY := 0.015

# ════════════════════════════════════════════════════════════════
#  BODY LEAN  (spring-damper по горизонтальному ускорению)
# ════════════════════════════════════════════════════════════════
const LEAN_MAX := 0.09
const LEAN_RUN := 0.03
const LEAN_K := 120.0
const LEAN_DAMP := 5.0

# ════════════════════════════════════════════════════════════════
#  PENDULUM HANDS  (damped pendulums от плечевых якорей)
# ════════════════════════════════════════════════════════════════
const HAND_K := 50.0
const HAND_D := 12.0
const HAND_REST_ANG := 0.10
const HAND_GRAV_PULL := 180.0

# ════════════════════════════════════════════════════════════════
#  HEAD BOB  (spring-tracked + walk bob + counter-tilt)
# ════════════════════════════════════════════════════════════════
const HEAD_K := 160.0
const HEAD_DAMP := 5.0
const HEAD_BOB_Y := 3.5
const HEAD_SWAY_X := 2.5
const HEAD_LAG := 0.02
const HEAD_LOOK := 0.03

# ════════════════════════════════════════════════════════════════
#  AIR / FEET
# ════════════════════════════════════════════════════════════════
const AIR_TUCK := 16.0

var p: Player


func _init(player: Player) -> void:
	p = player


# ════════════════════════════════════════════════════════════════
#  UPDATE  (пробегает все sub-системы)
# ════════════════════════════════════════════════════════════════
func update(delta: float) -> void:
	_upd_walk(delta)
	_upd_breath(delta)
	_upd_sway(delta)
	_upd_lean(delta)
	_upd_head(delta)
	_upd_squash(delta)
	_upd_face(delta)


# ════════════════════════════════════════════════════════════════
#  WALK CYCLE
# ════════════════════════════════════════════════════════════════
func _upd_walk(delta: float) -> void:
	var cur_max: float = p.SPRINT_SPEED if p._sprinting else p.MAX_SPEED
	# Включаем walk cycle при движении в ЛЮБОМ направлении.
	p._spd_r = clampf(p.velocity.length() / cur_max, 0.0, 1.0)
	var walking := p._spd_r > 0.05

	if walking:
		p._wblend = minf(p._wblend + WALK_BLEND_IN * delta, 1.0)
		var cadence := SPRINT_CADENCE if p._sprinting else WALK_CADENCE
		p._wphase += cadence * p._spd_r * delta * TAU
	else:
		p._wblend = maxf(p._wblend - WALK_BLEND_OUT * delta, 0.0)
		if p._wblend < 0.01:
			p._wblend = 0.0
			p._wphase = 0.0


# ════════════════════════════════════════════════════════════════
#  BREATHING
# ════════════════════════════════════════════════════════════════
func _upd_breath(delta: float) -> void:
	p._bt += delta


func _breath_val() -> float:
	# 3 пересекающихся синуса для не-механичного дыхания
	return (
		sin(p._bt * BR_FREQ) + sin(p._bt * BR_FREQ * 0.37) * 0.3 + sin(p._bt * BR_FREQ * 1.7) * 0.15
	)


# ════════════════════════════════════════════════════════════════
#  BODY SWAY
# ════════════════════════════════════════════════════════════════
func _upd_sway(_delta: float) -> void:
	var idle := sin(p._bt * SWAY_F1) * SWAY_A1 + sin(p._bt * SWAY_F2) * SWAY_A2
	var walk := sin(p._wphase) * WALK_SWAY * p._wblend
	p._sway = idle * (1.0 - p._wblend) + walk


# ════════════════════════════════════════════════════════════════
#  BODY LEAN  (spring-damper)
# ════════════════════════════════════════════════════════════════
func _upd_lean(delta: float) -> void:
	var target := clampf(-p._accel_x / p.ACCEL, -1.0, 1.0) * LEAN_MAX
	p._lean_v += (LEAN_K * (target - p._lean) - LEAN_DAMP * p._lean_v) * delta
	p._lean += p._lean_v * delta
	p._lean = clampf(p._lean, -0.15, 0.15)


# ════════════════════════════════════════════════════════════════
#  HEAD BOB
# ════════════════════════════════════════════════════════════════
func _upd_head(delta: float) -> void:
	var idle_f := 1.0 - p._wblend
	var wb_y := sin(p._wphase * 2.0) * HEAD_BOB_Y * p._wblend * p._spd_r
	var wb_x := sin(p._wphase) * HEAD_SWAY_X * p._wblend * p._spd_r
	var br_y := sin(p._bt * BR_FREQ + 0.3) * BR_AMP_Y * 1.2 * idle_f
	var mouse_w := p.get_global_mouse_position()
	var to_mouse := mouse_w - p.global_position
	var mouse_x := clampf(to_mouse.x / 250.0, -1.0, 1.0) * 6.0
	var mouse_y := clampf(to_mouse.y / 350.0, -1.0, 1.0) * 4.0
	var look := p.velocity.x * HEAD_LOOK + mouse_x
	var tgt := Vector2(look + wb_x, wb_y + br_y + mouse_y)
	p._hvel += (HEAD_K * (tgt - p._hoff) - HEAD_DAMP * p._hvel) * delta
	p._hoff += p._hvel * delta
	var mouse_tilt := clampf(to_mouse.x / 400.0, -1.0, 1.0) * 0.04
	var tilt_tgt := -(p._lean + p._sway) * 0.3 + p._mouse_lean * 0.8 + mouse_tilt
	p._htilt = lerpf(p._htilt, tilt_tgt, delta * 6.0)


# ════════════════════════════════════════════════════════════════
#  SQUASH / STRETCH
# ════════════════════════════════════════════════════════════════
func _upd_squash(delta: float) -> void:
	match p._js:
		Player.JS.SQUAT:
			var t := 1.0 - p._squat_tmr / maxf(p.JUMP_SQUAT_T, 0.001)
			p._squash = t * 0.15
		Player.JS.RISING:
			var rise_t := clampf(-p.velocity.y / 500.0, 0.0, 1.0)
			p._squash = lerpf(p._squash, -rise_t * 0.10, delta * 15.0)
		Player.JS.FALLING:
			var fall_t := clampf(p.velocity.y / 400.0, 0.0, 1.0)
			p._squash = lerpf(p._squash, fall_t * 0.04, delta * 6.0)
		Player.JS.LANDING:
			p._squash = lerpf(p._squash, -0.03, delta * 10.0)
			if absf(p._squash) < 0.01:
				p._squash = 0.0
		Player.JS.GROUND:
			p._squash = lerpf(p._squash, 0.0, delta * 12.0)


# ════════════════════════════════════════════════════════════════
#  FACE (blink — реакции бровей делает PlayerCombat)
# ════════════════════════════════════════════════════════════════
func _upd_face(delta: float) -> void:
	# Blink: рандомный интервал 2-5s, моргание длится 0.12s
	p._blink_tmr -= delta
	if p._blink_tmr <= 0.0 and p._blink_phase <= 0.0:
		p._blink_phase = 0.12
		p._blink_tmr = randf_range(2.0, 5.0)
	if p._blink_phase > 0.0:
		p._blink_phase -= delta
	# Делегируем брови боевому модулю (он знает контекст PUNCH/BLOCK)
	p._combat.update_brows(delta)


# ════════════════════════════════════════════════════════════════
#  WALK STEP CURVE  (5-фазная раскадровка по скетчу LO)
# ════════════════════════════════════════════════════════════════
func _step(ph: float, stride: float, step_h: float = STEP_HEIGHT) -> Array:
	var n := fposmod(ph, TAU) / TAU
	var x := 0.0
	var y := 0.0
	var ang := 0.0
	var pv := 0.0

	if n < 0.5:
		# STANCE
		var t := n / 0.5
		x = lerpf(stride * 0.5, -stride * 0.5, t)
		y = 0.0
		if t < 0.10:
			var u := t / 0.10
			ang = lerpf(FOOT_HEEL_STRIKE, 0.0, _ss(u))
			pv = lerpf(-1.0, 0.0, u)
		elif t > 0.80:
			var u := (t - 0.80) / 0.20
			ang = _ss(u) * FOOT_TOE_OFF
			pv = 1.0
	else:
		# SWING
		var t := (n - 0.5) / 0.5
		var et := _ss(t)
		x = lerpf(-stride * 0.5, stride * 0.5, et)
		y = -step_h * sin(t * PI)

		if t < 0.25:
			var u := t / 0.25
			ang = lerpf(FOOT_TOE_OFF, 0.0, _ss(u))
			pv = lerpf(1.0, 0.0, u)
		elif t < 0.75:
			var u := (t - 0.25) / 0.50
			ang = FOOT_SWING_LIFT * sin(u * PI)
			pv = 0.0
		else:
			var u := (t - 0.75) / 0.25
			ang = lerpf(0.0, FOOT_HEEL_STRIKE, _ss(u))
			pv = lerpf(0.0, -1.0, u)

	return [x, y, ang, pv]


# ════════════════════════════════════════════════════════════════
#  COMPOSE  (все системы → per-part трансформы)
# ════════════════════════════════════════════════════════════════
func compose() -> void:
	var idle_f := 1.0 - p._wblend
	var arm_spd_raw := clampf(absf(p.velocity.x) / p.MAX_SPEED, 0.0, 2.0)

	# Breathing
	var bv := _breath_val()
	var br_y := bv * BR_AMP_Y * idle_f
	var br_x := sin(p._bt * BR_FREQ * 0.5) * BR_AMP_X * idle_f
	var br_sx := bv * BR_SCALE * idle_f
	var br_sy := -bv * BR_SCALE * idle_f

	# Walk bob
	var sprint_f := (1.0 if p._sprinting else 0.0) * p._spd_r
	var hip_drop := lerpf(WALK_HIP_DROP, SPRINT_HIP_DROP, sprint_f)
	var footfall := absf(sin(p._wphase))
	var wbob := footfall * hip_drop * p._wblend * p._spd_r
	if p._sprinting:
		var flight := (1.0 - footfall) * SPRINT_FLIGHT * p._wblend * p._spd_r * sprint_f
		wbob -= flight

	var shift_amp := lerpf(3.5, 5.5, sprint_f)
	var wshift := sin(p._wphase) * shift_amp * p._wblend * p._spd_r

	var hip_amp := lerpf(0.012, 0.028, sprint_f)
	var whip := sin(p._wphase) * hip_amp * p._wblend * p._spd_r

	var sprint_lean := 0.0
	if p._sprinting:
		sprint_lean = SPRINT_LEAN * p._spd_r * sprint_f * p._vdir

	var air_lean := 0.0
	if p._js == Player.JS.RISING or p._js == Player.JS.FALLING:
		air_lean = clampf(p.velocity.x / p.MAX_SPEED, -1.0, 1.0) * 0.08
		if p.velocity.y < 0:
			air_lean += p._dir * 0.03
		else:
			air_lean -= p._dir * 0.02

	var cur_max: float = p.SPRINT_SPEED if p._sprinting else p.MAX_SPEED
	var run_lean := p.velocity.x / cur_max * LEAN_RUN
	var total_rot := (
		p._lean
		+ run_lean
		+ p._sway
		+ whip
		+ p._mouse_lean
		+ air_lean
		+ p._punch_body_lean
		+ sprint_lean
	)

	# TORSO
	var base_top := p.GND - p.SZ_FOOT.y - p.GAP_BF - p.SZ_BODY.y
	p._t_pos = Vector2(-p.SZ_BODY.x / 2.0 + br_x + wshift, base_top + br_y + wbob)
	p._t_ctr = p._t_pos + p.SZ_BODY / 2.0
	p._t_rot = total_rot
	var turn_squish := (1.0 - absf(p._vdir)) * 0.3
	p._t_scl = Vector2(1.0 + p._squash + br_sx - turn_squish, 1.0 - p._squash + br_sy)

	var step_impact := maxf(-sin(p._wphase * 2.0), 0.0)
	var ws := step_impact * 0.015 * p._wblend * p._spd_r
	p._t_scl.x += ws
	p._t_scl.y -= ws * 1.5

	# HEAD
	var head_gap: float = p.GAP_HB
	if p._js == Player.JS.RISING:
		head_gap += clampf(-p.velocity.y / 400.0, 0.0, 1.0) * 8.0
	elif p._js == Player.JS.SQUAT:
		head_gap -= p._squash * 40.0
	elif p._js == Player.JS.LANDING:
		head_gap -= p._squash * 30.0

	var head_base_y := p._t_pos.y - head_gap - p.SZ_HEAD.y
	p._h_pos = Vector2(
		-p.SZ_HEAD.x / 2.0 + p._hoff.x + br_x * 0.8 + wshift * 0.7, head_base_y + p._hoff.y
	)
	p._h_ctr = p._h_pos + p.SZ_HEAD / 2.0
	p._h_rot = p._htilt + whip * 0.5

	# HANDS
	var shoulder_lift := arm_spd_raw * arm_spd_raw * 4.0
	var sh_y := p._t_pos.y + p.SZ_BODY.y * 0.25 + br_y * 0.5 - shoulder_lift
	var l_sh := Vector2(p._t_ctr.x - p.SZ_BODY.x / 2.0 - p.SHOULDER_OFF, sh_y)
	var r_sh := Vector2(p._t_ctr.x + p.SZ_BODY.x / 2.0 + p.SHOULDER_OFF, sh_y)
	var l_tgt := l_sh + Vector2(0, p.HAND_LEN)
	var r_tgt := r_sh + Vector2(0, p.HAND_LEN)

	if p._first_frame:
		p._lh_trk = l_tgt
		p._rh_trk = r_tgt
		p._first_frame = false

	# Spring tracking с весом (gravity pull)
	var sdt := p._dt / 3.0
	for _i in 3:
		p._lh_tv.x += (HAND_K * (l_tgt.x - p._lh_trk.x) - HAND_D * p._lh_tv.x) * sdt
		p._lh_tv.y += (
			(HAND_K * 0.6 * (l_tgt.y - p._lh_trk.y) - HAND_D * p._lh_tv.y + HAND_GRAV_PULL) * sdt
		)
		p._lh_trk += p._lh_tv * sdt
		p._rh_tv.x += (HAND_K * (r_tgt.x - p._rh_trk.x) - HAND_D * p._rh_tv.x) * sdt
		p._rh_tv.y += (
			(HAND_K * 0.6 * (r_tgt.y - p._rh_trk.y) - HAND_D * p._rh_tv.y + HAND_GRAV_PULL) * sdt
		)
		p._rh_trk += p._rh_tv * sdt

	# Arm swing
	var walk_r := clampf(absf(p.velocity.x) / p.MAX_SPEED, 0.0, 1.0)
	var walk_eased := walk_r * walk_r * (3.0 - 2.0 * walk_r)
	var arm_h := (ARM_SWING_WALK * walk_eased + ARM_SWING_SPRINT_BONUS * sprint_f) * p._wblend
	var dip_base := (ARM_DIP_WALK * walk_eased + ARM_DIP_SPRINT_BONUS * sprint_f) * p._wblend

	var l_raw := sin(p._wphase + 0.15)
	var r_raw := sin(p._wphase + PI)
	var l_shaped := signf(l_raw) * pow(maxf(absf(l_raw), 0.001), 0.6)
	var r_shaped := signf(r_raw) * pow(maxf(absf(r_raw), 0.001), 0.85)

	p._lh_pos = p._lh_trk
	p._rh_pos = p._rh_trk
	p._lh_pos.x += l_shaped * arm_h * p._dir
	p._rh_pos.x += r_shaped * arm_h * p._dir
	p._lh_pos.y += (1.0 - absf(l_raw)) * dip_base * 1.1
	p._rh_pos.y += (1.0 - absf(r_raw)) * dip_base * 0.9

	var l_swing := l_shaped * p._wblend
	var r_swing := r_shaped * p._wblend
	var rot_range := PI / 5.0
	p._lh_rot = (PI / 2.0 - l_swing * rot_range) * p._vdir + p._lh_tv.x * 0.001 * p._vdir
	p._rh_rot = (PI / 2.0 - r_swing * rot_range) * p._vdir + p._rh_tv.x * 0.001 * p._vdir

	_compose_feet(idle_f, arm_spd_raw)


func _compose_feet(idle_f: float, arm_spd_raw: float) -> void:
	var stride_base: float = SPRINT_STRIDE if p._sprinting else STRIDE_MAX
	var stride := stride_base * p._spd_r
	var walk_backward := p.velocity.x * p._dir < -10.0
	var stride_dir: float = -p._dir if walk_backward else p._dir
	if walk_backward:
		stride *= 0.7

	var air_tuck := 0.0
	var air_spread := 0.0
	var air_fwd := 0.0
	if p._js == Player.JS.RISING:
		var rise_t := clampf(-p.velocity.y / 400.0, 0.0, 1.0)
		air_tuck = rise_t * AIR_TUCK
		air_spread = rise_t * 6.0
		air_fwd = clampf(p.velocity.x / p.MAX_SPEED, -1.0, 1.0) * 10.0
	elif p._js == Player.JS.FALLING:
		var fall_t := clampf(p.velocity.y / 400.0, 0.0, 1.0)
		air_tuck = maxf(AIR_TUCK * 0.3 - fall_t * AIR_TUCK * 0.5, -4.0)
		air_spread = (1.0 - fall_t) * 4.0
		air_fwd = clampf(p.velocity.x / p.MAX_SPEED, -1.0, 1.0) * 6.0
	elif p._js == Player.JS.SQUAT:
		air_tuck = -p._squash * 25.0
		air_spread = p._squash * 40.0

	var br_spread := sin(p._bt * BR_FREQ * 0.5) * 0.5 * idle_f
	var cur_step_h := lerpf(STEP_HEIGHT, SPRINT_STEP_H, clampf(arm_spd_raw - 1.0, 0.0, 1.0))

	for i in 2:
		var st := _step(p._wphase + float(i) * PI, stride, cur_step_h)
		var sx: float = st[0]
		var sy: float = st[1]
		var sa: float = st[2]
		var spv: float = st[3]

		var extra_sp := air_spread * (-1.0 if i == 0 else 1.0)
		var rest_x := (
			((-p.FOOT_SPREAD + extra_sp) if i == 0 else (p.FOOT_SPREAD + extra_sp)) * p._dir
		)
		var fx := lerpf(rest_x, sx * stride_dir, p._wblend)
		var fy := sy * p._wblend - air_tuck
		fx += air_fwd

		if p._js == Player.JS.LANDING:
			var spread_extra := p._squash * 60.0
			if i == 0:
				fx -= spread_extra * p._dir
			else:
				fx += spread_extra * p._dir

		if i == 0:
			fx -= br_spread
		else:
			fx += br_spread

		var foot_cy := p.GND - p.SZ_FOOT.y / 2.0 + fy
		var fang := sa * p._dir * p._wblend
		var pvoff := Vector2(spv * p.SZ_FOOT.x / 2.0 * p._dir, p.SZ_FOOT.y / 2.0) * p._wblend

		p._fp[i] = Vector2(fx, foot_cy)
		p._fa[i] = fang
		p._fpv[i] = pvoff


# ════════════════════════════════════════════════════════════════
#  SYNC FISTS  (Area2D позиции для дамми-детекта)
# ════════════════════════════════════════════════════════════════
func sync_fists() -> void:
	if p._lf_area:
		p._lf_area.position = p._lh_pos
	if p._rf_area:
		p._rf_area.position = p._rh_pos


# ════════════════════════════════════════════════════════════════
#  DRAW  (z-order: задняя рука → ноги → торс → голова → передняя рука)
# ════════════════════════════════════════════════════════════════
func draw_all() -> void:
	var back_is_left := p._dir > 0.0

	_dr_hand(back_is_left)
	p.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_dr_foot(0)
	_dr_foot(1)
	_dr_torso()
	_dr_head()
	_dr_hand(not back_is_left)
	p.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dr_torso() -> void:
	var w: float = p.SZ_BODY.x * p._t_scl.x
	var h: float = p.SZ_BODY.y * p._t_scl.y
	p.draw_set_transform(p._t_ctr, p._t_rot, Vector2.ONE)
	var clip := 4.0
	p.draw_rect(Rect2(-w / 2.0 - p.SW, -h / 2.0 + clip, w + p.SW * 2, h - clip + p.SW), p.OL)
	p.draw_rect(Rect2(-w / 2.0, -h / 2.0 + clip, w, h - clip), p.FL)


func _dr_head() -> void:
	var hw: float = p.SZ_HEAD.x
	var sx := 1.0 if p._vdir >= 0.0 else -1.0
	p.draw_set_transform(p._h_ctr, p._h_rot, Vector2(sx, 1.0))

	if p._thead:
		p.draw_texture_rect(p._thead, Rect2(-hw / 2.0, -p.SZ_HEAD.y / 2.0, hw, p.SZ_HEAD.y), false)
	else:
		_box(Vector2(-hw / 2.0, -p.SZ_HEAD.y / 2.0), Vector2(hw, p.SZ_HEAD.y))

	# Eyes
	var eye_w := 12.0
	var eye_h := 28.0
	var eye_gap := 6.0
	var eye_y := 14.0
	var mouse_w := p.get_global_mouse_position()
	var look_x := clampf((mouse_w.x - p.global_position.x) / 200.0, -1.0, 1.0)
	var look_y := clampf((mouse_w.y - p.global_position.y) / 300.0, -1.0, 1.0)
	var look_local := look_x * sx
	var eye_shift_x := look_local * 14.0
	var pair_w := eye_w * 2.0 + eye_gap
	var margin := 3.0
	var pair_left := -pair_w / 2.0 + eye_shift_x
	pair_left = clampf(pair_left, -hw / 2.0 + margin, hw / 2.0 - margin - pair_w)
	var le_x := pair_left
	var re_x := pair_left + eye_w + eye_gap
	p.draw_rect(Rect2(le_x, eye_y - eye_h / 2.0, eye_w, eye_h), p.OL)
	p.draw_rect(Rect2(re_x, eye_y - eye_h / 2.0, eye_w, eye_h), p.OL)
	var pup_w := 6.0
	var pup_h := 8.0
	var pup_x := look_local * (eye_w - pup_w) / 2.0
	var pup_y := look_y * (eye_h - pup_h) / 2.0
	var le_cx := le_x + eye_w / 2.0
	var re_cx := re_x + eye_w / 2.0
	p.draw_rect(Rect2(le_cx - pup_w / 2.0 + pup_x, eye_y - pup_h / 2.0 + pup_y, pup_w, pup_h), p.FL)
	p.draw_rect(Rect2(re_cx - pup_w / 2.0 + pup_x, eye_y - pup_h / 2.0 + pup_y, pup_w, pup_h), p.FL)

	# Blink
	var skin_col := Color(0.72, 0.52, 0.38)
	if p._blink_phase > 0.0:
		var blink_t := 1.0 - absf(p._blink_phase / 0.06 - 1.0)
		var lid_h := eye_h * 0.5 * blink_t
		p.draw_rect(Rect2(le_x, eye_y - eye_h / 2.0, eye_w, lid_h), skin_col)
		p.draw_rect(Rect2(re_x, eye_y - eye_h / 2.0, eye_w, lid_h), skin_col)
		p.draw_rect(Rect2(le_x, eye_y + eye_h / 2.0 - lid_h, eye_w, lid_h), skin_col)
		p.draw_rect(Rect2(re_x, eye_y + eye_h / 2.0 - lid_h, eye_w, lid_h), skin_col)


func _dr_foot(idx: int) -> void:
	p.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_rbox(p._fp[idx], p.SZ_FOOT, p._fa[idx], p._fpv[idx])


func _dr_hand(is_left: bool) -> void:
	var pos: Vector2
	var rot: float
	var tex: Texture2D

	# Sprites: _to=left fist, _ti=right fist (естественная пара).
	# При повороте налево кулаки меняются местами (видим другую сторону).
	if is_left:
		pos = p._lh_pos
		rot = p._lh_rot
		tex = p._to if p._dir > 0.0 else p._ti
	else:
		pos = p._rh_pos
		rot = p._rh_rot
		tex = p._ti if p._dir > 0.0 else p._to

	if tex == null:
		p.draw_set_transform(pos, rot, Vector2.ONE)
		_box(-p.HAND_SZ / 2.0, p.HAND_SZ)
		return

	var sx := 1.0 if p._vdir >= 0.0 else -1.0
	p.draw_set_transform(pos, rot, Vector2(sx, 1.0))
	p.draw_texture_rect(tex, Rect2(-p.HAND_SZ / 2.0, p.HAND_SZ), false)


# ────────────────────────────────────────────────────────────────
#  DRAW PRIMITIVES
# ────────────────────────────────────────────────────────────────
func _box(pos: Vector2, sz: Vector2) -> void:
	p.draw_rect(Rect2(pos - Vector2(p.SW, p.SW), sz + Vector2(p.SW * 2, p.SW * 2)), p.OL)
	p.draw_rect(Rect2(pos, sz), p.FL)


func _rbox(ctr: Vector2, sz: Vector2, ang: float, poff: Vector2 = Vector2.ZERO) -> void:
	if absf(ang) < 0.001:
		_box(ctr - sz / 2.0, sz)
		return
	var piv := ctr + poff
	var half := sz / 2.0
	var oh := half + Vector2(p.SW, p.SW)
	var fp := PackedVector2Array()
	var op := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		fp.append(piv + (c * half - poff).rotated(ang))
		op.append(piv + (c * oh - poff).rotated(ang))
	p.draw_polygon(op, PackedColorArray([p.OL]))
	p.draw_polygon(fp, PackedColorArray([p.FL]))


func _ss(t: float) -> float:
	# Quintic smoothstep — нулевые 1-я и 2-я производные на концах.
	var c := clampf(t, 0.0, 1.0)
	return c * c * c * (c * (c * 6.0 - 15.0) + 10.0)
