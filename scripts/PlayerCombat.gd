class_name PlayerCombat extends RefCounted
## Player combat module — punches, blocks, tremor, hand pose overlay.
## ЛКМ → удар (чередует руки), ПКМ → блок.
## Управляет фазами удара (windup → strike → recover) и накладывает позу
## на руки поверх idle-позы, посчитанной аниматором.

# ════════════════════════════════════════════════════════════════
#  PUNCH TIMING
# ════════════════════════════════════════════════════════════════
const PUNCH_WINDUP := 0.18
const PUNCH_STRIKE := 0.20
const PUNCH_RECOVER := 0.25
const PUNCH_REACH := 140.0
const PUNCH_PULLBACK := 0.45
const TREMOR_AMP := 1.5

# ════════════════════════════════════════════════════════════════
#  PUNCH HEAD KICKBACK  (вынесено из магических чисел этапа 6)
#  Импульс, который удар передаёт голове в момент инициации:
#  голова дёргается в сторону, противоположную направлению удара.
# ════════════════════════════════════════════════════════════════
const PUNCH_HEAD_KICKBACK_X := 30.0
const PUNCH_HEAD_KICKBACK_Y := 15.0

var p: Player


func _init(player: Player) -> void:
	p = player


# ════════════════════════════════════════════════════════════════
#  UPDATE  (input → state advance per frame)
# ════════════════════════════════════════════════════════════════
func update(delta: float) -> void:
	# Block: RMB
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	p._blocking = rmb
	if rmb:
		p._cs = Player.CS.BLOCK
	elif p._cs == Player.CS.BLOCK:
		p._cs = Player.CS.NONE

	# LMB click edge
	var lmb_now := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var lmb_click := lmb_now and not p._lmb_prev
	p._lmb_prev = lmb_now

	# Fire next hand on click (alternates L/R)
	if lmb_click and not p._blocking:
		_fire_punch()

	_advance_punches(delta)


func _fire_punch() -> void:
	var hi := p._next_hand
	p._next_hand = 1 - p._next_hand
	var mouse_w := p.get_global_mouse_position()
	var to_mouse := mouse_w - p.global_position
	var pdir := to_mouse.normalized() if to_mouse.length() > 5.0 else Vector2(p._dir, 0)
	var side := -1.0 if hi == 0 else 1.0
	p._ph_on[hi] = true
	p._ph_tmr[hi] = PUNCH_WINDUP + PUNCH_STRIKE
	p._ph_t[hi] = 0.0
	p._ph_dir[hi] = pdir
	p._ph_arc[hi] = randf_range(25.0, 55.0) * side
	p._ph_vert[hi] = randf_range(-35.0, 20.0)
	p._ph_woff[hi] = randf_range(-0.4, 0.4)
	p._ph_recov[hi] = 0.0
	p._cs = Player.CS.PUNCHING
	# Head kickback impulse — было магическим числом до этапа 8
	p._hvel.x -= pdir.x * PUNCH_HEAD_KICKBACK_X
	p._hvel.y -= pdir.y * PUNCH_HEAD_KICKBACK_Y


func _advance_punches(delta: float) -> void:
	var any_punching := false
	for hi in 2:
		if p._ph_on[hi]:
			p._ph_tmr[hi] -= delta
			p._ph_t[hi] = 1.0 - p._ph_tmr[hi] / (PUNCH_WINDUP + PUNCH_STRIKE)
			var wf_check := PUNCH_WINDUP / (PUNCH_WINDUP + PUNCH_STRIKE)
			var pd: Vector2 = p._ph_dir[hi]
			var pt_now: float = p._ph_t[hi]
			if pt_now < wf_check:
				# WINDUP: тело уходит назад, копит
				var coil := pt_now / wf_check
				p._punch_body_lean = -pd.x * 0.07 * coil
				p._squash = lerpf(p._squash, 0.04 * coil, p._dt * 15.0)
			else:
				# STRIKE: выпад вперёд
				var strike_t := (pt_now - wf_check) / (1.0 - wf_check)
				var lunge := sin(strike_t * PI)
				p._punch_body_lean = pd.x * 0.10 * lunge
				p._squash = lerpf(p._squash, -0.04 * lunge, p._dt * 15.0)
				p._hvel += pd * 3.0 * lunge
				if strike_t > 0.3 and strike_t < 0.5:
					p._hvel.x += randf_range(-15.0, 15.0)
			if p._ph_tmr[hi] <= 0.0:
				p._ph_on[hi] = false
				p._ph_recov[hi] = 1.0
				p._punch_body_lean = 0.0
			else:
				any_punching = true
		if p._ph_recov[hi] > 0.0:
			p._ph_recov[hi] = maxf(p._ph_recov[hi] - delta / PUNCH_RECOVER, 0.0)
			any_punching = true

	if not any_punching and p._cs == Player.CS.PUNCHING:
		p._cs = Player.CS.NONE
	if not any_punching:
		p._punch_body_lean = lerpf(p._punch_body_lean, 0.0, delta * 8.0)


# ════════════════════════════════════════════════════════════════
#  APPLY POSE  (накладывает блок/удар/тремор поверх idle-позы рук)
#  Вызывается аниматором ПОСЛЕ compose() — берёт _lh_pos/_rh_pos
#  как стартовую позицию и переписывает их.
# ════════════════════════════════════════════════════════════════
func apply_pose() -> void:
	# ── BLOCK ──
	p._block_blend = lerpf(p._block_blend, 1.0 if p._blocking else 0.0, p._dt * 8.0)
	if p._block_blend > 0.01:
		_apply_block_pose()

	# ── PUNCH per-hand ──
	var hand_poses: Array[Vector2] = [p._lh_pos, p._rh_pos]
	var hand_rots: Array[float] = [p._lh_rot, p._rh_rot]
	var total := PUNCH_WINDUP + PUNCH_STRIKE
	var wf := PUNCH_WINDUP / total

	for hi in 2:
		var is_active: bool = p._ph_on[hi] or p._ph_recov[hi] > 0.0
		if not is_active:
			continue
		_apply_punch_pose(hi, wf, hand_poses, hand_rots)

	# ── TREMOR (только во время удара) ──
	var tr_l := Vector2.ZERO
	var tr_r := Vector2.ZERO
	if p._cs == Player.CS.PUNCHING:
		var tr_amp := TREMOR_AMP * 3.0
		tr_l = Vector2(sin(p._bt * 37.0) * tr_amp, cos(p._bt * 41.0) * tr_amp)
		tr_r = Vector2(sin(p._bt * 43.0 + 1.7) * tr_amp, cos(p._bt * 31.0 + 2.3) * tr_amp)

	p._lh_pos = hand_poses[0] + tr_l
	p._rh_pos = hand_poses[1] + tr_r
	p._lh_rot = hand_rots[0]
	p._rh_rot = hand_rots[1]


func _apply_block_pose() -> void:
	var bl := p._block_blend
	var raise := bl * bl
	var block_y := p._h_ctr.y - 5.0
	var block_fwd := 35.0 * p._dir
	var shake_l := sin(p._wphase) * 2.5 * p._wblend * p._spd_r
	var shake_r := sin(p._wphase + PI) * 2.5 * p._wblend * p._spd_r
	var l_block := Vector2(p._t_ctr.x + block_fwd - 12.0, block_y + shake_l)
	var r_block := Vector2(p._t_ctr.x + block_fwd + 12.0, block_y + shake_r)
	p._lh_pos = p._lh_pos.lerp(l_block, raise)
	p._rh_pos = p._rh_pos.lerp(r_block, raise)
	p._lh_rot = lerpf(p._lh_rot, -PI / 2.0 * p._vdir, raise)
	p._rh_rot = lerpf(p._rh_rot, -PI / 2.0 * p._vdir, raise)


func _apply_punch_pose(
	hi: int, wf: float, hand_poses: Array[Vector2], hand_rots: Array[float]
) -> void:
	var sh_x: float = p._t_ctr.x + (-p.SZ_BODY.x / 2.0 if hi == 0 else p.SZ_BODY.x / 2.0)
	var sh_pos := Vector2(sh_x, p._t_ctr.y - 5.0)
	var pd: Vector2 = p._ph_dir[hi]
	var pp := Vector2(-pd.y, pd.x)
	var p_arc: float = p._ph_arc[hi]
	var p_vert: float = p._ph_vert[hi]
	var p_woff: float = p._ph_woff[hi]
	var p_t: float = p._ph_t[hi]

	var trot := atan2(pd.y, pd.x) - (PI if p._vdir < 0.0 else 0.0)

	if p._ph_on[hi]:
		var pt := clampf(p_t, 0.0, 1.0)
		var punch_pos: Vector2
		var body_ctr := Vector2(p._t_ctr.x, p._t_ctr.y - 5.0)
		var endpoint := body_ctr + pd * PUNCH_REACH

		if pt < wf:
			# PULLBACK
			var wt := pt / wf
			var pull := wt * wt
			var wdir := (-pd + pp * p_woff * 0.5).normalized()
			punch_pos = sh_pos + wdir * PUNCH_REACH * PUNCH_PULLBACK * pull
			punch_pos.y += p_vert * 0.3 * pull
		else:
			# STRIKE: 3-фазная кривая
			var st := (pt - wf) / (1.0 - wf)
			var pullback_pos := sh_pos - pd * PUNCH_REACH * PUNCH_PULLBACK * 0.8
			if st < 0.5:
				# EXPLODE: bezier через arc
				var t := st / 0.5
				var et := t * t * t
				var p0 := pullback_pos
				var p1 := body_ctr + pp * p_arc + Vector2(0, p_vert)
				var u := 1.0 - et
				punch_pos = u * u * p0 + 2.0 * u * et * p1 + et * et * endpoint
			elif st < 0.8:
				# HOLD с микро-вибрацией
				var shake := sin(st * 80.0) * 2.0 * (0.8 - st) / 0.3
				punch_pos = endpoint + Vector2(shake, shake * 0.5)
			else:
				# SETTLE
				var t := (st - 0.8) / 0.2
				punch_pos = endpoint.lerp(endpoint - pd * 8.0, t)

		hand_poses[hi] = punch_pos
		hand_rots[hi] = trot
		p._ph_end_pos[hi] = punch_pos

	elif p._ph_recov[hi] > 0.0:
		var r: float = p._ph_recov[hi]
		var idle_pos: Vector2 = hand_poses[hi]
		var end_pos: Vector2 = p._ph_end_pos[hi]
		hand_poses[hi] = end_pos.lerp(idle_pos, 1.0 - r)


# ════════════════════════════════════════════════════════════════
#  FACE BROW REACTIONS  (выражение лица в зависимости от боя)
# ════════════════════════════════════════════════════════════════
func update_brows(delta: float) -> void:
	if p._cs == Player.CS.PUNCHING:
		p._brow_target_l = -0.6
		p._brow_target_r = -0.6
	elif p._blocking:
		p._brow_target_l = 0.3
		p._brow_target_r = -0.3
	elif p._js == Player.JS.RISING:
		p._brow_target_l = 0.8
		p._brow_target_r = 0.8
	elif p._js == Player.JS.FALLING:
		p._brow_target_l = -0.2
		p._brow_target_r = 0.4
	else:
		p._brow_target_l = sin(p._bt * 0.7) * 0.15
		p._brow_target_r = sin(p._bt * 0.5 + 1.0) * 0.15
	p._brow_l = lerpf(p._brow_l, p._brow_target_l, delta * 6.0)
	p._brow_r = lerpf(p._brow_r, p._brow_target_r, delta * 6.0)
