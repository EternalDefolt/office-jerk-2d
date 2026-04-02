extends CharacterBody2D
## Office Jerk 2D — Physics-rich character controller
## Pendulum hands, breathing, body sway, inertial walk, squash/stretch

# ════════════════════════════════════════════════════════════════
#  MOVEMENT
# ════════════════════════════════════════════════════════════════
const MAX_SPEED := 220.0
const SPRINT_SPEED := 340.0   # shift sprint
const ACCEL := 1400.0         # responsive but not instant
const DECEL := 2000.0         # sharp stop → body overshoots
const AIR_ACCEL := 400.0      # half control in air
const GRAVITY := 980.0
const JUMP_VEL := -500.0
const JUMP_SQUAT_T := 0.04    # pre-jump squat duration
const COYOTE_T := 0.08        # grace period after leaving edge
const JUMP_BUF_T := 0.1       # buffer for early jump presses

# ════════════════════════════════════════════════════════════════
#  DRAW STYLE
# ════════════════════════════════════════════════════════════════
const OL := Color(0.05, 0.05, 0.05)
const FL := Color(1.0, 1.0, 1.0)
const SW := 3.0

# ════════════════════════════════════════════════════════════════
#  PROPORTIONS  (smaller torso, bigger gap to feet)
# ════════════════════════════════════════════════════════════════
const SZ_HEAD := Vector2(68, 64)
const SZ_BODY := Vector2(46, 82)
const SZ_FOOT := Vector2(44, 16)
const HAND_SZ := Vector2(48, 48)
const GAP_HB := 10.0          # head ↔ body
const GAP_BF := 36.0          # body ↔ feet
const FOOT_SPREAD := 8.0      # close at rest, stride does the spread
const SHOULDER_OFF := -6.0    # shoulder inside torso edge (hands near body center)
# collision half-height: (76+10+82+42+16)/2 = 113
const GND := 113.0

# ════════════════════════════════════════════════════════════════
#  WALK CYCLE  (time-based cadence, NOT distance-based)
# ════════════════════════════════════════════════════════════════
const WALK_CADENCE := 1.4     # Hz — grounded, deliberate
const SPRINT_CADENCE := 2.2   # Hz — brisk running cadence (~132 steps/min)
const STRIDE_MAX := 50.0
const SPRINT_STRIDE := 68.0
const STEP_HEIGHT := 14.0
const SPRINT_STEP_H := 18.0   # knee lift at sprint
const WALK_BLEND_IN := 12.0
const WALK_BLEND_OUT := 8.0
const FOOT_TOE_OFF := -0.15   # subtle toe-off
const FOOT_HEEL_STRIKE := 0.12 # subtle heel-strike

# ════════════════════════════════════════════════════════════════
#  BREATHING  (3-layer sine for organic feel)
# ════════════════════════════════════════════════════════════════
const BR_FREQ := 2.8          # primary breath frequency (rad/s)
const BR_AMP_Y := 1.5         # torso vertical oscillation (px)
const BR_AMP_X := 0.15        # torso horizontal drift (px)
const BR_SCALE := 0.005       # torso inhale/exhale scale

# ════════════════════════════════════════════════════════════════
#  BODY SWAY  (two-layer rocking)
# ════════════════════════════════════════════════════════════════
const SWAY_F1 := 1.3          # primary frequency
const SWAY_A1 := 0.005        # primary amplitude (rad)
const SWAY_F2 := 2.1          # secondary frequency
const SWAY_A2 := 0.002        # secondary amplitude (rad)
const WALK_SWAY := 0.015      # walk-locked sway amplitude

# ════════════════════════════════════════════════════════════════
#  BODY LEAN  (acceleration-driven spring-damper)
# ════════════════════════════════════════════════════════════════
const LEAN_MAX := 0.09        # max lean from accel (rad)
const LEAN_RUN := 0.03        # sustained lean while running
const LEAN_K := 120.0         # stiff → snappy response
const LEAN_DAMP := 5.0        # low → overshoot on stop/turn

# ════════════════════════════════════════════════════════════════
#  PENDULUM HANDS  (damped pendulums from shoulder anchors)
# ════════════════════════════════════════════════════════════════
const HAND_LEN := 50.0        # shoulder → hand distance
const HAND_K := 50.0          # spring stiffness
const HAND_D := 12.0          # near-critical damping (liquid, not rubber)
# critical = 2*sqrt(K) ≈ 14.1, using 12 = slight underdamp (tiny overshoot)
const HAND_REST_ANG := 0.10

# ════════════════════════════════════════════════════════════════
#  HEAD BOB  (spring-tracked with walk bob + counter-tilt)
# ════════════════════════════════════════════════════════════════
const HEAD_K := 160.0         # stiff → snappy head
const HEAD_DAMP := 5.0        # low → head overshoots then settles
const HEAD_BOB_Y := 3.5       # visible walk bob
const HEAD_SWAY_X := 2.5      # visible walk sway
const HEAD_LAG := 0.02        # positional lag factor
const HEAD_LOOK := 0.03       # look-ahead multiplier

# ════════════════════════════════════════════════════════════════
#  JUMP / LAND
# ════════════════════════════════════════════════════════════════
const LAND_SQUASH := 0.20     # punchy landing squash
const LAND_RECOV := 0.18      # faster recovery → snappy
const AIR_TUCK := 16.0        # foot tuck when rising (px)

# ════════════════════════════════════════════════════════════════
#  COMBAT
# ════════════════════════════════════════════════════════════════
const PUNCH_WINDUP := 0.18    # wind-up
const PUNCH_STRIKE := 0.20    # strike
const PUNCH_RECOVER := 0.25   # ease-back
const PUNCH_REACH := 140.0    # fist FAR out
const PUNCH_PULLBACK := 0.45
const TREMOR_AMP := 1.5

# ════════════════════════════════════════════════════════════════
#  STATE
# ════════════════════════════════════════════════════════════════
enum JS { GROUND, SQUAT, RISING, FALLING, LANDING }
enum CS { NONE, PUNCHING, BLOCK }

# textures
var _ti: Texture2D             # inner (palm)
var _to: Texture2D             # outer (knuckles)
var _tif: Texture2D            # inner flipped
var _tof: Texture2D            # outer flipped
var _thead: Texture2D          # head sprite

# core
var _dt := 0.016
var _first_frame := true
var _prev_vel := Vector2.ZERO
var _accel_x := 0.0
var _js := JS.GROUND
var _squat_tmr := 0.0
var _land_tmr := 0.0
var _squash := 0.0
var _coyote := 0.0
var _jbuf := 0.0
var _prev_dir := 1.0
var _dir := 1.0
var _vdir := 1.0              # smoothed visual direction for body lean
var _sprinting := false
var _mouse_lean := 0.0        # smooth lean toward mouse

# combat
var _cs := CS.NONE
var _combo_tmr := 0.0         # time left in current punch
var _combo_window := 0.0      # time left to chain next hit
var _punch_t := 0.0           # 0→1 progress of current punch
var _blocking := false
var _lmb_prev := false
var _block_blend := 0.0
var _next_hand := 0           # 0=left next, 1=right next (alternates)

# face
var _blink_tmr := 0.0         # time until next blink
var _blink_phase := 0.0       # 0=open, >0 = closing/opening
var _brow_l := 0.0            # left brow offset (-1=angry, 0=neutral, 1=raised)
var _brow_r := 0.0            # right brow offset
var _brow_target_l := 0.0
var _brow_target_r := 0.0
var _punch_body_lean := 0.0   # continuous lean driven by punch phase
# Per-hand punch state [left, right]
var _ph_on := [false, false]
var _ph_t := [0.0, 0.0]
var _ph_tmr := [0.0, 0.0]
var _ph_dir := [Vector2.ZERO, Vector2.ZERO]
var _ph_arc := [0.0, 0.0]
var _ph_vert := [0.0, 0.0]
var _ph_woff := [0.0, 0.0]
var _ph_recov := [0.0, 0.0]  # recover blend: 1=just ended, decays to 0
var _ph_end_pos := [Vector2.ZERO, Vector2.ZERO]  # where punch ended

# walk
var _wphase := 0.0
var _wblend := 0.0
var _spd_r := 0.0

# breath
var _bt := 0.0

# sway
var _sway := 0.0

# lean spring
var _lean := 0.0
var _lean_v := 0.0

# hand spring tracking (position + velocity in local space)
var _lh_trk := Vector2.ZERO
var _rh_trk := Vector2.ZERO
var _lh_tv := Vector2.ZERO
var _rh_tv := Vector2.ZERO

# head spring
var _hoff := Vector2.ZERO
var _hvel := Vector2.ZERO
var _htilt := 0.0

# composite per-part transforms
var _t_pos := Vector2.ZERO    # torso position (top-left relative)
var _t_ctr := Vector2.ZERO    # torso center
var _t_rot := 0.0
var _t_scl := Vector2.ONE
var _h_pos := Vector2.ZERO    # head top-left
var _h_ctr := Vector2.ZERO    # head center
var _h_rot := 0.0
var _lh_pos := Vector2.ZERO   # left hand draw pos
var _rh_pos := Vector2.ZERO   # right hand draw pos
var _lh_rot := 0.0
var _rh_rot := 0.0
var _fp := [Vector2.ZERO, Vector2.ZERO]  # foot center positions
var _fa := [0.0, 0.0]         # foot angles
var _fpv := [Vector2.ZERO, Vector2.ZERO] # foot pivot offsets


# ════════════════════════════════════════════════════════════════
#  INIT
# ════════════════════════════════════════════════════════════════
func _ready() -> void:
	_ti = load("res://assets/img/hand_inner.png")
	_to = load("res://assets/img/hand_outer.png")
	_thead = load("res://assets/img/head.png")
	if _ti:
		var img := _ti.get_image()
		img.flip_x()
		_tif = ImageTexture.create_from_image(img)
	if _to:
		var img := _to.get_image()
		img.flip_x()
		_tof = ImageTexture.create_from_image(img)
	# Init hand positions at rest
	var sh_y := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y + SZ_BODY.y * 0.15
	_lh_trk = Vector2(-(SZ_BODY.x / 2.0 + SHOULDER_OFF), sh_y + HAND_LEN)
	_rh_trk = Vector2(SZ_BODY.x / 2.0 + SHOULDER_OFF, sh_y + HAND_LEN)


# ════════════════════════════════════════════════════════════════
#  MAIN PHYSICS TICK
# ════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	_dt = delta
	if finisher_active:
		queue_redraw()
		return
	# ── Gravity ──
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# ── Input ──
	var h := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		h = -1.0
	if Input.is_physical_key_pressed(KEY_D):
		h = 1.0

	# Sprint
	_sprinting = Input.is_physical_key_pressed(KEY_SHIFT) and is_on_floor() and absf(h) > 0.1
	var cur_max := SPRINT_SPEED if _sprinting else MAX_SPEED

	# Inertial horizontal movement
	var tgt := h * cur_max
	var a := DECEL
	if h != 0.0:
		a = ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, tgt, a * delta)

	# Facing: follows MOUSE position (not movement)
	var mouse_w := get_global_mouse_position()
	var to_mouse := mouse_w - global_position
	var new_dir := 1.0 if to_mouse.x >= 0.0 else -1.0
	if new_dir != _dir:
		# Turn impulse
		_lean_v += new_dir * 25.0
		_hvel.x -= new_dir * 60.0
		_lh_tv.x -= new_dir * 80.0
		_rh_tv.x -= new_dir * 80.0
	_dir = new_dir
	# Smooth visual direction (smooth turn, no snap)
	_vdir = lerpf(_vdir, _dir, _dt * 8.0)

	# Mouse lean: body tilts toward cursor
	var mouse_lean_tgt := clampf(to_mouse.x / 300.0, -1.0, 1.0) * 0.06
	mouse_lean_tgt += clampf(-to_mouse.y / 400.0, -0.5, 0.5) * 0.03
	_mouse_lean = lerpf(_mouse_lean, mouse_lean_tgt, delta * 8.0)

	# Jump buffer
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_accept"):
		_jbuf = JUMP_BUF_T

	# ── Coyote time ──
	if is_on_floor():
		_coyote = COYOTE_T
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	# ── Jump squat completion (pre-move) ──
	if _js == JS.SQUAT:
		_squat_tmr -= delta
		if _squat_tmr <= 0.0:
			velocity.y = JUMP_VEL
			_js = JS.RISING
			# Jump: hands fly down, head snaps up, body compresses
			_lh_tv.y += 200.0
			_rh_tv.y += 200.0
			_hvel.y -= 60.0
			_lean_v += velocity.x * 0.05  # lean in movement direction

	# ── Move ──
	move_and_slide()

	# ── Acceleration tracking ──
	var dt_safe := maxf(delta, 0.0005)
	_accel_x = clampf((velocity.x - _prev_vel.x) / dt_safe, -ACCEL * 2.0, ACCEL * 2.0)
	_prev_vel = velocity
	_jbuf = maxf(_jbuf - delta, 0.0)

	# ── Post-move state machine ──
	var on_fl := is_on_floor()
	match _js:
		JS.GROUND:
			if not on_fl:
				_js = JS.FALLING
			elif _jbuf > 0.0:
				_js = JS.SQUAT
				_squat_tmr = JUMP_SQUAT_T
				_jbuf = 0.0
		JS.SQUAT:
			pass # handled pre-move
		JS.RISING:
			if velocity.y >= 0.0:
				_js = JS.FALLING
		JS.FALLING:
			if on_fl:
				# Landing
				_js = JS.LANDING
				_land_tmr = LAND_RECOV
				_squash = clampf(absf(_prev_vel.y) / 500.0, 0.0, 1.0) * LAND_SQUASH
				# Landing: hands bounce up, head slams down, body compresses
				_lh_tv.y -= 280.0
				_rh_tv.y -= 280.0
				_hvel.y += 200.0
				_lean_v -= velocity.x * 0.03  # counter-lean from impact
			elif _jbuf > 0.0 and _coyote > 0.0:
				# Coyote jump
				velocity.y = JUMP_VEL
				_js = JS.RISING
				_jbuf = 0.0
				_coyote = 0.0
				_lh_tv.y += 180.0
				_rh_tv.y += 180.0
		JS.LANDING:
			_land_tmr -= delta
			if _land_tmr <= 0.0:
				_js = JS.GROUND
			elif _jbuf > 0.0:
				# Jump buffer on landing
				_js = JS.SQUAT
				_squat_tmr = JUMP_SQUAT_T
				_jbuf = 0.0

	# ── Combat input ──
	_upd_combat(delta)

	# ── Sub-system updates ──
	_upd_walk(delta)
	_upd_breath(delta)
	_upd_sway(delta)
	_upd_lean(delta)
	_upd_hands(delta)
	_upd_head(delta)
	_upd_squash(delta)
	_upd_face(delta)
	_compose()
	queue_redraw()


# ════════════════════════════════════════════════════════════════
#  COMBAT  (LMB=punch combo, RMB=block)
# ════════════════════════════════════════════════════════════════
func _upd_combat(delta: float) -> void:
	# Block: RMB
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_blocking = rmb
	if rmb:
		_cs = CS.BLOCK
	elif _cs == CS.BLOCK:
		_cs = CS.NONE

	# LMB click
	var lmb_now := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var lmb_click := lmb_now and not _lmb_prev
	_lmb_prev = lmb_now

	# Punch: click → fire the NEXT hand (can punch while other hand is still out)
	if lmb_click and not _blocking:
		var hi := _next_hand
		_next_hand = 1 - _next_hand  # alternate
		var mouse_w := get_global_mouse_position()
		var to_mouse := mouse_w - global_position
		var pdir := to_mouse.normalized() if to_mouse.length() > 5.0 else Vector2(_dir, 0)
		var side := -1.0 if hi == 0 else 1.0
		_ph_on[hi] = true
		_ph_tmr[hi] = PUNCH_WINDUP + PUNCH_STRIKE
		_ph_t[hi] = 0.0
		_ph_dir[hi] = pdir
		_ph_arc[hi] = randf_range(25.0, 55.0) * side
		_ph_vert[hi] = randf_range(-35.0, 20.0)
		_ph_woff[hi] = randf_range(-0.4, 0.4)
		_ph_recov[hi] = 0.0
		_cs = CS.PUNCHING
		# Impulse: head flinches, other hand kicks
		_hvel.x -= pdir.x * 30.0
		_hvel.y -= pdir.y * 15.0

	# Advance each hand's punch independently
	var any_punching := false
	for hi in 2:
		if _ph_on[hi]:
			var prev_t: float = _ph_t[hi]
			_ph_tmr[hi] -= delta
			_ph_t[hi] = 1.0 - _ph_tmr[hi] / (PUNCH_WINDUP + PUNCH_STRIKE)
			# Strike moment: when crossing from windup to strike phase → body lurches
			var wf_check := PUNCH_WINDUP / (PUNCH_WINDUP + PUNCH_STRIKE)
			# Continuous body lean following punch phase
			var pd: Vector2 = _ph_dir[hi]
			var pt_now: float = _ph_t[hi]
			if pt_now < wf_check:
				# WINDUP: body leans BACK (coiling)
				var coil := pt_now / wf_check
				_punch_body_lean = -pd.x * 0.07 * coil
				_squash = lerpf(_squash, 0.04 * coil, _dt * 15.0)
			else:
				# STRIKE: body lunges FORWARD
				var strike_t := (pt_now - wf_check) / (1.0 - wf_check)
				var lunge := sin(strike_t * PI)  # 0→1→0
				_punch_body_lean = pd.x * 0.10 * lunge
				_squash = lerpf(_squash, -0.04 * lunge, _dt * 15.0)
				# Head follows the lunge
				_hvel += pd * 3.0 * lunge
				# Schizo twitch at peak
				if strike_t > 0.3 and strike_t < 0.5:
					_hvel.x += randf_range(-15.0, 15.0)
			if _ph_tmr[hi] <= 0.0:
				_ph_on[hi] = false
				_ph_recov[hi] = 1.0
				_punch_body_lean = 0.0
			else:
				any_punching = true
		# Recover decay
		if _ph_recov[hi] > 0.0:
			_ph_recov[hi] = maxf(_ph_recov[hi] - delta / PUNCH_RECOVER, 0.0)
			any_punching = true

	if not any_punching and _cs == CS.PUNCHING:
		_cs = CS.NONE
	if not any_punching:
		_punch_body_lean = lerpf(_punch_body_lean, 0.0, delta * 8.0)


# ════════════════════════════════════════════════════════════════
#  FACE (blink + brows)
# ════════════════════════════════════════════════════════════════
func _upd_face(delta: float) -> void:
	# Blink: random interval 2-5s, blink lasts 0.12s
	_blink_tmr -= delta
	if _blink_tmr <= 0.0 and _blink_phase <= 0.0:
		_blink_phase = 0.12  # start blink
		_blink_tmr = randf_range(2.0, 5.0)
	if _blink_phase > 0.0:
		_blink_phase -= delta

	# Brows react to actions
	if _cs == CS.PUNCHING:
		_brow_target_l = -0.6  # angry during punch
		_brow_target_r = -0.6
	elif _blocking:
		_brow_target_l = 0.3   # focused during block
		_brow_target_r = -0.3
	elif _js == JS.RISING:
		_brow_target_l = 0.8   # surprised on jump
		_brow_target_r = 0.8
	elif _js == JS.FALLING:
		_brow_target_l = -0.2  # worried falling
		_brow_target_r = 0.4
	else:
		# Idle: slight asymmetric (schizo)
		_brow_target_l = sin(_bt * 0.7) * 0.15
		_brow_target_r = sin(_bt * 0.5 + 1.0) * 0.15
	_brow_l = lerpf(_brow_l, _brow_target_l, delta * 6.0)
	_brow_r = lerpf(_brow_r, _brow_target_r, delta * 6.0)


# ════════════════════════════════════════════════════════════════
#  WALK CYCLE  (time-based cadence, variable stride)
# ════════════════════════════════════════════════════════════════
func _upd_walk(delta: float) -> void:
	var cur_max := SPRINT_SPEED if _sprinting else MAX_SPEED
	_spd_r = clampf(absf(velocity.x) / cur_max, 0.0, 1.0)
	var walking := is_on_floor() and _spd_r > 0.05

	if walking:
		_wblend = minf(_wblend + WALK_BLEND_IN * delta, 1.0)
		var cadence := SPRINT_CADENCE if _sprinting else WALK_CADENCE
		_wphase += cadence * _spd_r * delta * TAU
	else:
		_wblend = maxf(_wblend - WALK_BLEND_OUT * delta, 0.0)
		if _wblend < 0.01:
			_wblend = 0.0
			_wphase = 0.0


# ════════════════════════════════════════════════════════════════
#  BREATHING  (3-layer sine → organic rhythm)
# ════════════════════════════════════════════════════════════════
func _upd_breath(delta: float) -> void:
	_bt += delta


func _breath_val() -> float:
	# 3 overlapping sines for non-mechanical breathing
	return sin(_bt * BR_FREQ) + sin(_bt * BR_FREQ * 0.37) * 0.3 + sin(_bt * BR_FREQ * 1.7) * 0.15


# ════════════════════════════════════════════════════════════════
#  BODY SWAY  (idle rocking + walk-locked sway)
# ════════════════════════════════════════════════════════════════
func _upd_sway(_delta: float) -> void:
	var idle := sin(_bt * SWAY_F1) * SWAY_A1 + sin(_bt * SWAY_F2) * SWAY_A2
	var walk := sin(_wphase) * WALK_SWAY * _wblend
	_sway = idle * (1.0 - _wblend) + walk


# ════════════════════════════════════════════════════════════════
#  BODY LEAN  (spring-damper driven by horizontal acceleration)
# ════════════════════════════════════════════════════════════════
func _upd_lean(delta: float) -> void:
	var target := clampf(-_accel_x / ACCEL, -1.0, 1.0) * LEAN_MAX
	_lean_v += (LEAN_K * (target - _lean) - LEAN_DAMP * _lean_v) * delta
	_lean += _lean_v * delta
	_lean = clampf(_lean, -0.15, 0.15)


# ════════════════════════════════════════════════════════════════
#  PENDULUM HANDS  (damped pendulums with walk drive & body coupling)
# ════════════════════════════════════════════════════════════════
func _upd_hands(delta: float) -> void:
	# Hands are spring-tracked to shoulder+hang targets
	# Movement comes from body movement (bob, sway, lean) + impulses (turn, jump, land)
	# NO explicit walk animation — just physics response to body motion
	pass  # actual tracking done in _compose after targets are computed


# ════════════════════════════════════════════════════════════════
#  HEAD BOB  (spring-tracked position + walk bob + counter-tilt)
# ════════════════════════════════════════════════════════════════
func _upd_head(delta: float) -> void:
	var idle_f := 1.0 - _wblend
	# Walk bob (double frequency — bobs on each footstep)
	var wb_y := sin(_wphase * 2.0) * HEAD_BOB_Y * _wblend * _spd_r
	var wb_x := sin(_wphase) * HEAD_SWAY_X * _wblend * _spd_r
	# Breath (delayed phase for wave-up-body feel)
	var br_y := sin(_bt * BR_FREQ + 0.3) * BR_AMP_Y * 1.2 * idle_f
	# Look-ahead: head leads body + shifts toward mouse
	var mouse_w := get_global_mouse_position()
	var to_mouse := mouse_w - global_position
	var mouse_x := clampf(to_mouse.x / 250.0, -1.0, 1.0) * 6.0  # head shifts toward mouse
	var mouse_y := clampf(to_mouse.y / 350.0, -1.0, 1.0) * 4.0
	var look := velocity.x * HEAD_LOOK + mouse_x
	# Spring target
	var tgt := Vector2(look + wb_x, wb_y + br_y + mouse_y)
	_hvel += (HEAD_K * (tgt - _hoff) - HEAD_DAMP * _hvel) * delta
	_hoff += _hvel * delta
	# Head tilt: counter body lean + extra tilt toward mouse
	var mouse_tilt := clampf(to_mouse.x / 400.0, -1.0, 1.0) * 0.04
	var tilt_tgt := -(_lean + _sway) * 0.3 + _mouse_lean * 0.8 + mouse_tilt
	_htilt = lerpf(_htilt, tilt_tgt, delta * 6.0)


# ════════════════════════════════════════════════════════════════
#  SQUASH / STRETCH  (jump phases)
# ════════════════════════════════════════════════════════════════
func _upd_squash(delta: float) -> void:
	match _js:
		JS.SQUAT:
			# Hydraulic pre-jump compression
			var t := 1.0 - _squat_tmr / maxf(JUMP_SQUAT_T, 0.001)
			_squash = t * 0.15
		JS.RISING:
			# Stretch upward (negative = taller/narrower)
			var rise_t := clampf(-velocity.y / 500.0, 0.0, 1.0)
			_squash = lerpf(_squash, -rise_t * 0.10, delta * 15.0)
		JS.FALLING:
			# Ease back to slight compression (bracing for landing)
			var fall_t := clampf(velocity.y / 400.0, 0.0, 1.0)
			_squash = lerpf(_squash, fall_t * 0.04, delta * 6.0)
		JS.LANDING:
			# Hydraulic bounce: fast squash decay with spring overshoot
			_squash = lerpf(_squash, -0.03, delta * 10.0)
			if absf(_squash) < 0.01:
				_squash = 0.0
		JS.GROUND:
			_squash = lerpf(_squash, 0.0, delta * 12.0)


# ════════════════════════════════════════════════════════════════
#  WALK STEP CURVE  (smoothstep easing, toe-off / heel-strike)
# ════════════════════════════════════════════════════════════════
func _step(ph: float, stride: float, step_h: float = STEP_HEIGHT, duty: float = 0.6, sprint_r: float = 0.0) -> Array:
	var n := fposmod(ph, TAU) / TAU
	var x := 0.0
	var y := 0.0
	var ang := 0.0
	var pv := 0.0

	if n < duty:
		# ── STANCE: foot on ground, slides backward ──
		var t := n / duty
		var et := _ss(t)
		x = lerpf(stride * 0.5, -stride * 0.5, et)

		# Walk: gentle toe-off at very end
		var w_ang := 0.0
		var w_pv := 0.0
		if t > 0.82:
			var u := (t - 0.82) / 0.18
			w_ang = u * FOOT_TOE_OFF
			w_pv = 1.0

		# Sprint: earlier + stronger toe push-off (forefoot runner)
		var s_ang := 0.0
		var s_pv := 0.0
		if t > 0.65:
			var u := (t - 0.65) / 0.35
			s_ang = u * -0.30      # strong toe-down push
			s_pv = 1.0             # pivot at toe

		ang = lerpf(w_ang, s_ang, sprint_r)
		pv = lerpf(w_pv, s_pv, sprint_r)
	else:
		# ── SWING: foot in air, arcs forward ──
		var t := (n - duty) / (1.0 - duty)
		var et := _ss(t)
		x = lerpf(-stride * 0.5, stride * 0.5, et)
		y = -step_h * sin(t * PI)

		# Walk: toe-off fade → flat → heel-strike
		var w_ang := 0.0
		var w_pv := 0.0
		if t < 0.2:
			w_ang = lerpf(FOOT_TOE_OFF, 0.0, t / 0.2)
			w_pv = 1.0
		elif t > 0.82:
			w_ang = ((t - 0.82) / 0.18) * FOOT_HEEL_STRIKE
			w_pv = -1.0

		# Sprint foot cycle (real running biomechanics):
		#  0.00-0.25: toe DOWN (back-kick, trailing foot curls)
		#  0.25-0.60: transition (foot passes under hip, toe rises)
		#  0.60-1.00: toe UP (dorsiflexion — forefoot landing prep)
		var s_ang := 0.0
		var s_pv := 0.0
		if t < 0.25:
			s_ang = lerpf(-0.28, -0.16, t / 0.25)
			s_pv = 1.0
		elif t < 0.60:
			var u := (t - 0.25) / 0.35
			s_ang = lerpf(-0.16, 0.10, u)
		else:
			var u := (t - 0.60) / 0.40
			s_ang = lerpf(0.10, 0.24, u)
			s_pv = -1.0

		ang = lerpf(w_ang, s_ang, sprint_r)
		pv = lerpf(w_pv, s_pv, sprint_r)

	return [x, y, ang, pv]


# ════════════════════════════════════════════════════════════════
#  COMPOSE  (all systems → per-part transforms)
# ════════════════════════════════════════════════════════════════
func _compose() -> void:
	var idle_f := 1.0 - _wblend

	# ── Speed ratios ──
	var arm_spd_raw := clampf(absf(velocity.x) / MAX_SPEED, 0.0, 2.0)
	var sprint_f := clampf(arm_spd_raw - 1.0, 0.0, 1.0)

	# ── Breathing ──
	var bv := _breath_val()
	var br_y := bv * BR_AMP_Y * idle_f
	var br_x := sin(_bt * BR_FREQ * 0.5) * BR_AMP_X * idle_f
	var br_sx := bv * BR_SCALE * idle_f
	var br_sy := -bv * BR_SCALE * idle_f

	# ── Walk bob ──
	var bob_raw := sin(_wphase * 2.0)
	var bob_amp := lerpf(3.2, 2.0, sprint_f)
	var wbob := -absf(bob_raw) * bob_amp * _wblend * _spd_r
	var step_contact := maxf(-bob_raw, 0.0)

	# ── Lateral shift ──
	var shift_amp := lerpf(3.5, 1.0, sprint_f)
	var wshift := sin(_wphase) * shift_amp * _wblend * _spd_r

	# ── Hip twist ──
	var hip_amp := lerpf(0.012, 0.014, sprint_f)
	var whip := sin(_wphase) * hip_amp * _wblend * _spd_r

	# ── Shoulder counter-rotation ──
	var shoulder_twist := -whip * 1.5

	# ── Step-synced torso rock ──
	var step_rock := sin(_wphase * 2.0) * lerpf(0.005, 0.008, sprint_f) * _wblend * _spd_r * _dir

	# ── Air tilt ──
	var air_lean := 0.0
	if _js == JS.RISING or _js == JS.FALLING:
		air_lean = clampf(velocity.x / MAX_SPEED, -1.0, 1.0) * 0.08
		if velocity.y < 0:
			air_lean += _dir * 0.03
		else:
			air_lean -= _dir * 0.02

	# ── Total rotation (sprint: forward lean) ──
	var cur_max := SPRINT_SPEED if _sprinting else MAX_SPEED
	var run_lean := velocity.x / cur_max * LEAN_RUN
	var sprint_lean := sprint_f * _dir * 0.07 * _wblend
	var total_rot := _lean + run_lean + _sway + whip + _mouse_lean + air_lean + _punch_body_lean + sprint_lean + step_rock

	# ── TORSO ──
	var base_top := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y
	_t_pos = Vector2(-SZ_BODY.x / 2.0 + br_x + wshift, base_top + br_y + wbob)
	_t_ctr = _t_pos + SZ_BODY / 2.0
	_t_rot = total_rot
	var turn_squish := (1.0 - absf(_vdir)) * 0.3
	_t_scl = Vector2(1.0 + _squash + br_sx - turn_squish, 1.0 - _squash + br_sy)

	# Step impact squash (punchier contact feel)
	var ws := step_contact * lerpf(0.018, 0.016, sprint_f) * _wblend * _spd_r
	_t_scl.x += ws
	_t_scl.y -= ws * 1.6

	# ── HEAD (leans forward with body at sprint) ──
	var head_gap := GAP_HB
	if _js == JS.RISING:
		head_gap += clampf(-velocity.y / 400.0, 0.0, 1.0) * 8.0
	elif _js == JS.SQUAT:
		head_gap -= _squash * 40.0
	elif _js == JS.LANDING:
		head_gap -= _squash * 30.0

	var head_base_y := _t_pos.y - head_gap - SZ_HEAD.y
	# Sprint: head shifts forward (follows body lean)
	var head_fwd := sprint_f * 6.0 * _dir * _wblend
	_h_pos = Vector2(
		-SZ_HEAD.x / 2.0 + _hoff.x + br_x * 0.8 + wshift * 0.7 + head_fwd,
		head_base_y + _hoff.y
	)
	_h_ctr = _h_pos + SZ_HEAD / 2.0
	# Head tilts forward at sprint
	_h_rot = _htilt + whip * 0.4 + sprint_f * _dir * 0.04 * _wblend

	# ── HANDS ──
	var shoulder_lift := arm_spd_raw * arm_spd_raw * lerpf(3.0, 5.0, sprint_f)
	var sh_y := _t_pos.y + SZ_BODY.y * 0.25 + br_y * 0.5 - shoulder_lift
	var twist_off := shoulder_twist * 24.0 * _dir
	var l_sh := Vector2(_t_ctr.x - SZ_BODY.x / 2.0 - SHOULDER_OFF + twist_off, sh_y)
	var r_sh := Vector2(_t_ctr.x + SZ_BODY.x / 2.0 + SHOULDER_OFF - twist_off, sh_y)

	var l_tgt := l_sh + Vector2(0, HAND_LEN)
	var r_tgt := r_sh + Vector2(0, HAND_LEN)

	if _first_frame:
		_lh_trk = l_tgt
		_rh_trk = r_tgt
		_first_frame = false

	# Spring tracking
	var sdt := _dt / 3.0
	var grav_pull := lerpf(140.0, 100.0, sprint_f)
	for _i in 3:
		_lh_tv.x += (HAND_K * (l_tgt.x - _lh_trk.x) - HAND_D * _lh_tv.x) * sdt
		_lh_tv.y += (HAND_K * 0.6 * (l_tgt.y - _lh_trk.y) - HAND_D * _lh_tv.y + grav_pull) * sdt
		_lh_trk += _lh_tv * sdt
		_rh_tv.x += (HAND_K * (r_tgt.x - _rh_trk.x) - HAND_D * _rh_tv.x) * sdt
		_rh_tv.y += (HAND_K * 0.6 * (r_tgt.y - _rh_trk.y) - HAND_D * _rh_tv.y + grav_pull) * sdt
		_rh_trk += _rh_tv * sdt

	# Step impact on hands
	var kick := step_contact * lerpf(6.0, 3.0, sprint_f) * _wblend * _spd_r
	_lh_tv.y += kick * _dt * 50.0
	_rh_tv.y += kick * _dt * 50.0

	# ════════════════════════════════════════════════════════════
	#  ARM SWING
	#  Walk (sprint_f=0): pendulum arc from shoulder
	#  Sprint (sprint_f=1): arm pump — fwd=chest height, back=hip level
	#  Blended via sprint_f for smooth walk→run transition
	# ════════════════════════════════════════════════════════════
	var arm_spd := clampf(absf(velocity.x) / MAX_SPEED, 0.0, 2.0)
	var spd_eased := arm_spd * arm_spd * (3.0 - 2.0 * minf(arm_spd, 1.0))

	# Contra-lateral phase (-1 to +1, positive = forward)
	var l_phase := sin(_wphase + PI)
	var r_phase := sin(_wphase)

	# ── Pendulum: walk=wide free swing, sprint=compact ──
	var swing_amp := lerpf(0.42, 0.20, sprint_f) * _wblend * spd_eased
	var pend_len := HAND_LEN * lerpf(1.0, 0.80, sprint_f)

	var l_theta := l_phase * swing_amp
	var r_theta := r_phase * swing_amp

	_lh_pos = _lh_trk
	_rh_pos = _rh_trk

	# Pendulum arc
	_lh_pos.x += pend_len * sin(l_theta) * _dir
	_lh_pos.y -= pend_len * (1.0 - cos(l_theta))
	_rh_pos.x += pend_len * sin(r_theta) * _dir
	_rh_pos.y -= pend_len * (1.0 - cos(r_theta))

	# Sprint: arms tuck inward
	var sprint_tuck := sprint_f * 3.0 * _wblend
	_lh_pos.x += sprint_tuck * _dir
	_rh_pos.x -= sprint_tuck * _dir

	# IK noise: organic micro-jitter (arms feel alive, not robotic)
	var ik_amp := lerpf(0.8, 1.8, sprint_f) * _wblend
	_lh_pos.x += (sin(_bt * 7.3) * 1.0 + sin(_bt * 13.1) * 0.5) * ik_amp
	_lh_pos.y += (cos(_bt * 8.7) * 0.8 + cos(_bt * 11.9) * 0.4) * ik_amp
	_rh_pos.x += (sin(_bt * 9.1 + 2.0) * 1.0 + sin(_bt * 14.3 + 1.0) * 0.5) * ik_amp
	_rh_pos.y += (cos(_bt * 10.3 + 3.0) * 0.8 + cos(_bt * 12.7 + 2.0) * 0.4) * ik_amp

	# Rotation
	_lh_rot = (PI / 2.0 - l_theta * 0.25) * _vdir
	_rh_rot = (PI / 2.0 - r_theta * 0.25) * _vdir

	# ── COMBAT POSE ──
	_block_blend = lerpf(_block_blend, 1.0 if _blocking else 0.0, _dt * 8.0)

	if _block_blend > 0.01:
		var bl := _block_blend
		var raise := bl * bl
		# Block: fists UP near head, pointing UPWARD
		var block_y := _h_ctr.y - 5.0
		var block_fwd := 35.0 * _dir     # well in front of head
		var shake_l := sin(_wphase) * 2.5 * _wblend * _spd_r
		var shake_r := sin(_wphase + PI) * 2.5 * _wblend * _spd_r
		var l_block := Vector2(_t_ctr.x + block_fwd - 12.0, block_y + shake_l)
		var r_block := Vector2(_t_ctr.x + block_fwd + 12.0, block_y + shake_r)
		_lh_pos = _lh_pos.lerp(l_block, raise)
		_rh_pos = _rh_pos.lerp(r_block, raise)
		# Fists point UP in guard (-PI/2 * _vdir compensates for scale flip)
		_lh_rot = lerpf(_lh_rot, -PI / 2.0 * _vdir, raise)
		_rh_rot = lerpf(_rh_rot, -PI / 2.0 * _vdir, raise)

	# Per-hand punch + recover + tremor
	var hand_poses: Array[Vector2] = [_lh_pos, _rh_pos]
	var hand_rots: Array[float] = [_lh_rot, _rh_rot]
	var total := PUNCH_WINDUP + PUNCH_STRIKE
	var wf := PUNCH_WINDUP / total

	for hi in 2:
		var is_active: bool = _ph_on[hi] or _ph_recov[hi] > 0.0
		if not is_active:
			continue

		var sh_x := _t_ctr.x + (-SZ_BODY.x / 2.0 if hi == 0 else SZ_BODY.x / 2.0)
		var sh_pos := Vector2(sh_x, _t_ctr.y - 5.0)
		var pd: Vector2 = _ph_dir[hi]
		var pp := Vector2(-pd.y, pd.x)
		var p_arc: float = _ph_arc[hi]
		var p_vert: float = _ph_vert[hi]
		var p_woff: float = _ph_woff[hi]
		var p_t: float = _ph_t[hi]

		var trot := atan2(pd.y, pd.x) - (PI if _vdir < 0.0 else 0.0)

		if _ph_on[hi]:
			var pt := clampf(p_t, 0.0, 1.0)
			var punch_pos: Vector2
			var body_ctr := Vector2(_t_ctr.x, _t_ctr.y - 5.0)
			# Full endpoint: way past body
			var endpoint := body_ctr + pd * PUNCH_REACH

			if pt < wf:
				# PULLBACK: hand winds up behind body
				var wt := pt / wf
				var pull := wt * wt  # ease-in
				var wdir := (-pd + pp * p_woff * 0.5).normalized()
				punch_pos = sh_pos + wdir * PUNCH_REACH * PUNCH_PULLBACK * pull
				punch_pos.y += p_vert * 0.3 * pull
			else:
				# STRIKE: 3-part curve
				# 0.0-0.5: EXPLODE from pullback to endpoint (cubic ease-in)
				# 0.5-0.8: HOLD near endpoint (barely moves)
				# 0.8-1.0: slight retract (hand settles)
				var st := (pt - wf) / (1.0 - wf)
				var pullback_pos := sh_pos - pd * PUNCH_REACH * PUNCH_PULLBACK * 0.8

				if st < 0.5:
					# EXPLODE: cubic ease-in (slow→fast→SNAP to target)
					var t := st / 0.5
					var et := t * t * t  # cubic = violent acceleration
					# Bezier from pullback through arc to endpoint
					var p0 := pullback_pos
					var p1 := body_ctr + pp * p_arc + Vector2(0, p_vert)
					var u := 1.0 - et
					punch_pos = u * u * p0 + 2.0 * u * et * p1 + et * et * endpoint
				elif st < 0.8:
					# HOLD: fist stays at endpoint, micro-vibrate from impact
					var shake := sin(st * 80.0) * 2.0 * (0.8 - st) / 0.3
					punch_pos = endpoint + Vector2(shake, shake * 0.5)
				else:
					# SETTLE: slight retract
					var t := (st - 0.8) / 0.2
					punch_pos = endpoint.lerp(endpoint - pd * 8.0, t)

			hand_poses[hi] = punch_pos
			hand_rots[hi] = trot
			_ph_end_pos[hi] = punch_pos

		elif _ph_recov[hi] > 0.0:
			# Position eases back from punch end to idle
			var r: float = _ph_recov[hi]
			var idle_pos: Vector2 = hand_poses[hi]
			var end_pos: Vector2 = _ph_end_pos[hi]
			hand_poses[hi] = end_pos.lerp(idle_pos, 1.0 - r)
			# Rotation: just use idle rot (no spinning from punch direction)

	# Schizo tremor: amplified during combat
	var combat_tremor := 3.0 if (_cs == CS.PUNCHING) else 1.0
	var tr_amp := TREMOR_AMP * combat_tremor
	var tr_l := Vector2(sin(_bt * 37.0) * tr_amp, cos(_bt * 41.0) * tr_amp)
	var tr_r := Vector2(sin(_bt * 43.0 + 1.7) * tr_amp, cos(_bt * 31.0 + 2.3) * tr_amp)

	_lh_pos = hand_poses[0] + tr_l
	_rh_pos = hand_poses[1] + tr_r
	_lh_rot = hand_rots[0]
	_rh_rot = hand_rots[1]

	# ── FEET ──
	var stride_base := SPRINT_STRIDE if _sprinting else STRIDE_MAX
	var stride := stride_base * _spd_r
	# Walking backward? (velocity opposite to facing direction)
	var walk_backward := velocity.x * _dir < -10.0
	# Backward walk: invert stride direction, shorter steps
	var stride_dir := -_dir if walk_backward else _dir
	if walk_backward:
		stride *= 0.7  # shorter backward steps

	var air_tuck := 0.0
	var air_spread := 0.0
	var air_fwd := 0.0  # forward/back tilt in air
	if _js == JS.RISING:
		var rise_t := clampf(-velocity.y / 400.0, 0.0, 1.0)
		air_tuck = rise_t * AIR_TUCK
		air_spread = rise_t * 6.0
		# Feet shift forward if moving forward, back if moving back
		air_fwd = clampf(velocity.x / MAX_SPEED, -1.0, 1.0) * 10.0
	elif _js == JS.FALLING:
		var fall_t := clampf(velocity.y / 400.0, 0.0, 1.0)
		air_tuck = maxf(AIR_TUCK * 0.3 - fall_t * AIR_TUCK * 0.5, -4.0)
		air_spread = (1.0 - fall_t) * 4.0
		# Feet extend down and forward for landing preparation
		air_fwd = clampf(velocity.x / MAX_SPEED, -1.0, 1.0) * 6.0
	elif _js == JS.SQUAT:
		air_tuck = -_squash * 25.0
		air_spread = _squash * 40.0

	var br_spread := sin(_bt * BR_FREQ * 0.5) * 0.5 * idle_f

	# Duty factor: walk 60% stance / 40% swing, sprint 38% stance / 62% swing
	var duty := lerpf(0.6, 0.38, sprint_f)
	var cur_step_h := lerpf(STEP_HEIGHT, SPRINT_STEP_H, sprint_f)
	for i in 2:
		var st := _step(_wphase + float(i) * PI, stride, cur_step_h, duty, sprint_f)
		var sx: float = st[0]
		var sy: float = st[1]
		var sa: float = st[2]
		var spv: float = st[3]

		var extra_sp := air_spread * (-1.0 if i == 0 else 1.0)
		var rest_x := ((-FOOT_SPREAD + extra_sp) if i == 0 else (FOOT_SPREAD + extra_sp)) * _dir
		var fx := lerpf(rest_x, sx * stride_dir, _wblend)
		var fy := sy * _wblend - air_tuck
		# Air shift: feet drift in velocity direction
		fx += air_fwd

		# Landing foot spread
		if _js == JS.LANDING:
			var spread_extra := _squash * 60.0
			if i == 0:
				fx -= spread_extra * _dir
			else:
				fx += spread_extra * _dir

		if i == 0:
			fx -= br_spread
		else:
			fx += br_spread

		var foot_cy := GND - SZ_FOOT.y / 2.0 + fy
		var fang := sa * _dir * _wblend
		var pvoff := Vector2(spv * SZ_FOOT.x / 2.0 * _dir, SZ_FOOT.y / 2.0) * _wblend

		_fp[i] = Vector2(fx, foot_cy)
		_fa[i] = fang
		_fpv[i] = pvoff


# ════════════════════════════════════════════════════════════════
#  DRAW  (z-ordered: back hand → feet → torso → head → front hand)
# ════════════════════════════════════════════════════════════════
func _draw() -> void:
	var back_is_left := _dir > 0.0

	# 1. Back hand
	_dr_hand(back_is_left)

	# 2. Feet (no body lean — feet stay flat on ground)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_dr_foot(0)
	_dr_foot(1)

	# 3. Torso (with lean + sway)
	_dr_torso()

	# 4. Head (independent tilt)
	_dr_head()

	# 5. Front hand
	_dr_hand(not back_is_left)

	# Reset
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dr_torso() -> void:
	var w := SZ_BODY.x * _t_scl.x
	var h := SZ_BODY.y * _t_scl.y
	draw_set_transform(_t_ctr, _t_rot, Vector2.ONE)
	# Outline+fill starts a few px below top (hidden under head gap)
	var clip := 4.0  # hide top edge under head
	draw_rect(Rect2(-w / 2.0 - SW, -h / 2.0 + clip, w + SW * 2, h - clip + SW), OL)
	draw_rect(Rect2(-w / 2.0, -h / 2.0 + clip, w, h - clip), FL)


func _dr_head() -> void:
	var hw := SZ_HEAD.x
	var sx := 1.0 if _vdir >= 0.0 else -1.0
	draw_set_transform(_h_ctr, _h_rot, Vector2(sx, 1.0))

	# Head sprite — slightly larger than collision box, aligned to square
	if _thead:
		draw_texture_rect(_thead, Rect2(-hw / 2.0, -SZ_HEAD.y / 2.0, hw, SZ_HEAD.y), false)
	else:
		_box(Vector2(-hw / 2.0, -SZ_HEAD.y / 2.0), Vector2(hw, SZ_HEAD.y))

	# Eyes ON TOP of head sprite (stay in lower face area):
	var eye_w := 12.0
	var eye_h := 28.0
	var eye_gap := 6.0
	var eye_y := 14.0   # well below hair line, on skin
	# Eyes shift toward mouse — whole eyes move to face side
	var mouse_w := get_global_mouse_position()
	var look_x := clampf((mouse_w.x - global_position.x) / 200.0, -1.0, 1.0)
	var look_y := clampf((mouse_w.y - global_position.y) / 300.0, -1.0, 1.0)
	# Convert to head-local space (sx flips X axis)
	var look_local := look_x * sx
	var eye_shift_x := look_local * 14.0
	var eye_shift_y := look_y * 2.0
	# Total eye pair width
	var pair_w := eye_w * 2.0 + eye_gap
	var margin := 3.0
	# Clamp entire pair inside head
	var pair_left := -pair_w / 2.0 + eye_shift_x
	pair_left = clampf(pair_left, -hw / 2.0 + margin, hw / 2.0 - margin - pair_w)
	var le_x := pair_left
	var re_x := pair_left + eye_w + eye_gap
	draw_rect(Rect2(le_x, eye_y - eye_h / 2.0, eye_w, eye_h), OL)
	draw_rect(Rect2(re_x, eye_y - eye_h / 2.0, eye_w, eye_h), OL)
	# White pupils (smaller rects inside, shifted by look direction)
	var pup_w := 6.0
	var pup_h := 8.0
	# Pupils travel full length of eye socket
	var pup_x := look_local * (eye_w - pup_w) / 2.0
	var pup_y := look_y * (eye_h - pup_h) / 2.0
	var le_cx := le_x + eye_w / 2.0
	var re_cx := re_x + eye_w / 2.0
	draw_rect(Rect2(le_cx - pup_w / 2.0 + pup_x, eye_y - pup_h / 2.0 + pup_y, pup_w, pup_h), FL)
	draw_rect(Rect2(re_cx - pup_w / 2.0 + pup_x, eye_y - pup_h / 2.0 + pup_y, pup_w, pup_h), FL)

	# Blink: eyelids close from top and bottom (skin-colored, not white)
	var skin_col := Color(0.72, 0.52, 0.38)
	if _blink_phase > 0.0:
		var blink_t := 1.0 - absf(_blink_phase / 0.06 - 1.0)
		var lid_h := eye_h * 0.5 * blink_t
		draw_rect(Rect2(le_x, eye_y - eye_h / 2.0, eye_w, lid_h), skin_col)
		draw_rect(Rect2(re_x, eye_y - eye_h / 2.0, eye_w, lid_h), skin_col)
		draw_rect(Rect2(le_x, eye_y + eye_h / 2.0 - lid_h, eye_w, lid_h), skin_col)
		draw_rect(Rect2(re_x, eye_y + eye_h / 2.0 - lid_h, eye_w, lid_h), skin_col)




func _dr_foot(idx: int) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_rbox(_fp[idx], SZ_FOOT, _fa[idx], _fpv[idx])


func _dr_hand(is_left: bool) -> void:
	var pos: Vector2
	var rot: float
	var tex: Texture2D

	# Sprites are a natural pair: _to=left fist, _ti=right fist
	# When facing right: left=outer, right=inner
	# When facing left: swap (we see the other side)
	if is_left:
		pos = _lh_pos
		rot = _lh_rot
		tex = _to if _dir > 0.0 else _ti
	else:
		pos = _rh_pos
		rot = _rh_rot
		tex = _ti if _dir > 0.0 else _to

	if tex == null:
		draw_set_transform(pos, rot, Vector2.ONE)
		_box(-HAND_SZ / 2.0, HAND_SZ)
		return

	# Scale.x from smooth _vdir — sprite flips gradually with direction
	var sx := 1.0 if _vdir >= 0.0 else -1.0
	draw_set_transform(pos, rot, Vector2(sx, 1.0))
	draw_texture_rect(tex, Rect2(-HAND_SZ / 2.0, HAND_SZ), false)


# ════════════════════════════════════════════════════════════════
#  DRAW PRIMITIVES
# ════════════════════════════════════════════════════════════════
func _box(pos: Vector2, sz: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(SW, SW), sz + Vector2(SW * 2, SW * 2)), OL)
	draw_rect(Rect2(pos, sz), FL)


func _rbox(ctr: Vector2, sz: Vector2, ang: float, poff: Vector2 = Vector2.ZERO) -> void:
	if absf(ang) < 0.001:
		_box(ctr - sz / 2.0, sz)
		return
	var piv := ctr + poff
	var half := sz / 2.0
	var oh := half + Vector2(SW, SW)
	var fp := PackedVector2Array()
	var op := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		fp.append(piv + (c * half - poff).rotated(ang))
		op.append(piv + (c * oh - poff).rotated(ang))
	draw_polygon(op, PackedColorArray([OL]))
	draw_polygon(fp, PackedColorArray([FL]))


func _ss(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * c * (c * (c * 6.0 - 15.0) + 10.0)


# ════════════════════════════════════════════════════════════════
#  DEBUG LOG (prints every 0.5s)
# ════════════════════════════════════════════════════════════════
var finisher_active := false

var _dbg_t := 0.0
func _debug_log(delta: float) -> void:
	_dbg_t += delta
	if _dbg_t < 0.5:
		return
	_dbg_t = 0.0

	var states: Array[String] = ["GROUND", "SQUAT", "RISING", "FALLING", "LANDING"]
	var state_name: String = states[_js]
	var lh_dx := _lh_pos.x - (-SZ_BODY.x / 2.0 - SHOULDER_OFF)
	var rh_dx := _rh_pos.x - (SZ_BODY.x / 2.0 + SHOULDER_OFF)

	print("═══ PLAYER DEBUG ═══")
	print("  vel=(%.0f, %.0f) spd_r=%.2f dir=%.0f vdir=%.2f sprint=%s state=%s" % [
		velocity.x, velocity.y, _spd_r, _dir, _vdir, _sprinting, state_name])
	print("  walk: phase=%.2f blend=%.2f cadence=%s" % [
		fmod(_wphase, TAU), _wblend,
		"SPRINT" if _sprinting else "WALK"])
	print("  body: lean=%.3f lean_v=%.1f sway=%.4f squash=%.3f" % [
		_lean, _lean_v, _sway, _squash])
	print("  L hand: pos=(%.1f,%.1f) trk=(%.1f,%.1f) vel=(%.1f,%.1f) rot=%.2f dx=%.1f" % [
		_lh_pos.x, _lh_pos.y, _lh_trk.x, _lh_trk.y,
		_lh_tv.x, _lh_tv.y, _lh_rot, lh_dx])
	print("  R hand: pos=(%.1f,%.1f) trk=(%.1f,%.1f) vel=(%.1f,%.1f) rot=%.2f dx=%.1f" % [
		_rh_pos.x, _rh_pos.y, _rh_trk.x, _rh_trk.y,
		_rh_tv.x, _rh_tv.y, _rh_rot, rh_dx])
	print("  head: off=(%.1f,%.1f) vel=(%.1f,%.1f) tilt=%.3f" % [
		_hoff.x, _hoff.y, _hvel.x, _hvel.y, _htilt])
	print("  feet: [0]=(%.1f,%.1f) [1]=(%.1f,%.1f)" % [
		_fp[0].x, _fp[0].y, _fp[1].x, _fp[1].y])
