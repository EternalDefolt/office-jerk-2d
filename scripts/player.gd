class_name Player extends CharacterBody2D
## Office Jerk 2D — Physics-rich character controller (root module).
## Содержит общие константы, состояние и оркестрацию подмодулей:
## PlayerInput → PlayerCombat → PlayerAnimator → draw.
## Кат-сцена финишера (finisher.gd) лазает в наши per-part переменные
## напрямую — поэтому ВСЁ общее состояние живёт здесь, на корне.

# ════════════════════════════════════════════════════════════════
#  MOVEMENT
# ════════════════════════════════════════════════════════════════
const MAX_SPEED := 220.0
const SPRINT_SPEED := 340.0
const ACCEL := 1400.0
const DECEL := 2000.0
const AIR_ACCEL := 400.0
const GRAVITY := 980.0
const JUMP_VEL := -500.0
const JUMP_SQUAT_T := 0.04
const COYOTE_T := 0.08
const JUMP_BUF_T := 0.1

# ════════════════════════════════════════════════════════════════
#  DRAW STYLE
# ════════════════════════════════════════════════════════════════
const OL := Color(0.05, 0.05, 0.05)
const FL := Color(1.0, 1.0, 1.0)
const SW := 3.0

# ════════════════════════════════════════════════════════════════
#  PROPORTIONS
# ════════════════════════════════════════════════════════════════
const SZ_HEAD := Vector2(68, 64)
const SZ_BODY := Vector2(46, 82)
const SZ_FOOT := Vector2(44, 16)
const HAND_SZ := Vector2(48, 48)
const HAND_LEN := 50.0
const GAP_HB := 10.0
const GAP_BF := 36.0
const FOOT_SPREAD := 8.0
const SHOULDER_OFF := 8.0
const GND := 113.0

# ════════════════════════════════════════════════════════════════
#  JUMP / LAND  (используют и input state machine, и animator squash)
# ════════════════════════════════════════════════════════════════
const LAND_SQUASH := 0.20
const LAND_RECOV := 0.18

# ════════════════════════════════════════════════════════════════
#  STATE ENUMS
# ════════════════════════════════════════════════════════════════
enum JS { GROUND, SQUAT, RISING, FALLING, LANDING }
enum CS { NONE, PUNCHING, BLOCK }

# ── textures ──
var _ti: Texture2D
var _to: Texture2D
var _tif: Texture2D
var _tof: Texture2D
var _thead: Texture2D

# ── core shared state ──
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
var _dir := 1.0
var _vdir := 1.0
var _sprinting := false
var _mouse_lean := 0.0

# ── combat state ──
var _cs := CS.NONE
var _blocking := false
var _lmb_prev := false
var _block_blend := 0.0
var _next_hand := 0
var _punch_body_lean := 0.0
var _ph_on := [false, false]
var _ph_t := [0.0, 0.0]
var _ph_tmr := [0.0, 0.0]
var _ph_dir := [Vector2.ZERO, Vector2.ZERO]
var _ph_arc := [0.0, 0.0]
var _ph_vert := [0.0, 0.0]
var _ph_woff := [0.0, 0.0]
var _ph_recov := [0.0, 0.0]
var _ph_end_pos := [Vector2.ZERO, Vector2.ZERO]

# ── face state ──
var _blink_tmr := 0.0
var _blink_phase := 0.0
var _brow_l := 0.0
var _brow_r := 0.0
var _brow_target_l := 0.0
var _brow_target_r := 0.0

# ── animation state ──
var _wphase := 0.0
var _wblend := 0.0
var _spd_r := 0.0
var _bt := 0.0
var _sway := 0.0
var _lean := 0.0
var _lean_v := 0.0
var _lh_trk := Vector2.ZERO
var _rh_trk := Vector2.ZERO
var _lh_tv := Vector2.ZERO
var _rh_tv := Vector2.ZERO
var _hoff := Vector2.ZERO
var _hvel := Vector2.ZERO
var _htilt := 0.0

# ── fist Area2D ──
var _lf_area: Area2D
var _rf_area: Area2D

# ── per-part composite transforms (читает finisher.gd) ──
var _t_pos := Vector2.ZERO
var _t_ctr := Vector2.ZERO
var _t_rot := 0.0
var _t_scl := Vector2.ONE
var _h_pos := Vector2.ZERO
var _h_ctr := Vector2.ZERO
var _h_rot := 0.0
var _lh_pos := Vector2.ZERO
var _rh_pos := Vector2.ZERO
var _lh_rot := 0.0
var _rh_rot := 0.0
var _fp := [Vector2.ZERO, Vector2.ZERO]
var _fa := [0.0, 0.0]
var _fpv := [Vector2.ZERO, Vector2.ZERO]

# ── finisher hook ──
var finisher_active := false

# ── sub-modules ──
var _input: PlayerInput
var _combat: PlayerCombat
var _animator: PlayerAnimator


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
	_lf_area = get_node_or_null("LeftFist")
	_rf_area = get_node_or_null("RightFist")
	# Snap hands to rest-target до первого compose
	var sh_y := GND - SZ_FOOT.y - GAP_BF - SZ_BODY.y + SZ_BODY.y * 0.15
	_lh_trk = Vector2(-(SZ_BODY.x / 2.0 + SHOULDER_OFF), sh_y + HAND_LEN)
	_rh_trk = Vector2(SZ_BODY.x / 2.0 + SHOULDER_OFF, sh_y + HAND_LEN)
	# Подмодули
	_input = PlayerInput.new(self)
	_combat = PlayerCombat.new(self)
	_animator = PlayerAnimator.new(self)


func _physics_process(delta: float) -> void:
	_dt = delta
	if finisher_active:
		queue_redraw()
		return
	_input.update(delta)
	_combat.update(delta)
	_animator.update(delta)
	_animator.compose()
	_combat.apply_pose()
	_animator.sync_fists()
	queue_redraw()


func _draw() -> void:
	_animator.draw_all()
