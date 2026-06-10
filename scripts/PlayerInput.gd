class_name PlayerInput extends RefCounted
## Player input + locomotion + JS state machine.
## Отвечает за: WASD/Shift, направление лица по мыши, mouse_lean,
## инерционное движение через move_and_slide, конечный автомат прыжков
## (GROUND → SQUAT → RISING → FALLING → LANDING → GROUND).
## Гравитации в диораме нет — переходы между состояниями происходят
## по факту нажатия прыжка и приземления; on_floor() для 4-направленной
## прогулки всегда true.

# ════════════════════════════════════════════════════════════════
#  INPUT THRESHOLDS  (минимальный наклон стика, до которого мы
#  считаем игрока стоящим — нужно, чтобы стик-дрейф не запускал
#  спринт и инерционное движение)
# ════════════════════════════════════════════════════════════════
const STICK_DEADZONE := 0.1

# ════════════════════════════════════════════════════════════════
#  FACING / MOUSE LEAN  (магия наклона тела к курсору)
# ════════════════════════════════════════════════════════════════
const MOUSE_LEAN_X_DIV := 300.0  # делитель горизонтали для наклона
const MOUSE_LEAN_Y_DIV := 400.0  # делитель вертикали
const MOUSE_LEAN_X_AMP := 0.06  # амплитуда X-наклона (rad)
const MOUSE_LEAN_Y_AMP := 0.03  # амплитуда Y-наклона
const MOUSE_LEAN_LERP := 8.0  # скорость подгонки к target
const VDIR_LERP := 8.0  # скорость smooth-flip _vdir → _dir

# ════════════════════════════════════════════════════════════════
#  TURN IMPULSES  (импульсы при смене направления — голова и руки
#  получают толчок «по инерции», как будто их кинуло поворотом)
# ════════════════════════════════════════════════════════════════
const TURN_LEAN_IMPULSE := 25.0
const TURN_HEAD_IMPULSE := 60.0
const TURN_HAND_IMPULSE := 80.0

# ════════════════════════════════════════════════════════════════
#  LANDING IMPULSES  (импульсы, которые приземление передаёт
#  пружинным системам — руки подскакивают, голова бьёт вниз)
# ════════════════════════════════════════════════════════════════
const LAND_HAND_IMPULSE := 280.0
const LAND_HEAD_IMPULSE := 200.0
const LAND_LEAN_FACTOR := 0.03

# ════════════════════════════════════════════════════════════════
#  JUMP IMPULSES  (импульс рук при отрыве — coyote-jump)
# ════════════════════════════════════════════════════════════════
const JUMP_HAND_IMPULSE := 180.0

var p: Player


func _init(player: Player) -> void:
	p = player


# ════════════════════════════════════════════════════════════════
#  UPDATE  (вход → движение → ориентация → коллизия → KSM)
# ════════════════════════════════════════════════════════════════
func update(delta: float) -> void:
	var h := _read_horizontal()
	var v := _read_vertical()

	# Sprint: Shift + любое направление (с дедзоной, чтобы дрифт стика
	# не активировал спринт — это раздражало в плейтестах)
	p._sprinting = (
		Input.is_physical_key_pressed(KEY_SHIFT)
		and (absf(h) > STICK_DEADZONE or absf(v) > STICK_DEADZONE)
	)
	var cur_max: float = p.SPRINT_SPEED if p._sprinting else p.MAX_SPEED

	_apply_movement(h, v, cur_max, delta)
	_update_facing(delta)

	# ── Move ──
	# Коллизия с Dummy теперь через настоящий StaticBody2D (см. dummy.tscn),
	# не через hardcoded проверку X-расстояния. Можно свободно обходить
	# dummy сверху/снизу по Y.
	p.move_and_slide()

	_update_accel(delta)
	_update_state_machine(delta)


# ────────────────────────────────────────────────────────────────
#  AXIS READING
# ────────────────────────────────────────────────────────────────
func _read_horizontal() -> float:
	var h := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		h = -1.0
	if Input.is_physical_key_pressed(KEY_D):
		h = 1.0
	return h


func _read_vertical() -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		v = -1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		v = 1.0
	return v


# ────────────────────────────────────────────────────────────────
#  MOVEMENT  (инерционное скольжение к target velocity)
# ────────────────────────────────────────────────────────────────
func _apply_movement(h: float, v: float, cur_max: float, delta: float) -> void:
	var tgt_x := h * cur_max
	# Вертикаль медленнее — перспективный «псевдо-3D» вид сверху
	var tgt_y := v * cur_max * 0.7
	var moving := absf(h) > STICK_DEADZONE or absf(v) > STICK_DEADZONE
	var a: float = p.ACCEL if moving else p.DECEL
	p.velocity.x = move_toward(p.velocity.x, tgt_x, a * delta)
	p.velocity.y = move_toward(p.velocity.y, tgt_y, a * delta)


# ────────────────────────────────────────────────────────────────
#  FACING  (направление лица всегда к курсору, не к движению)
# ────────────────────────────────────────────────────────────────
func _update_facing(delta: float) -> void:
	var mouse_w := p.get_global_mouse_position()
	var to_mouse := mouse_w - p.global_position
	var new_dir := 1.0 if to_mouse.x >= 0.0 else -1.0

	# При смене направления — импульсы по инерции
	if new_dir != p._dir:
		p._lean_v += new_dir * TURN_LEAN_IMPULSE
		p._hvel.x -= new_dir * TURN_HEAD_IMPULSE
		p._lh_tv.x -= new_dir * TURN_HAND_IMPULSE
		p._rh_tv.x -= new_dir * TURN_HAND_IMPULSE
	p._dir = new_dir
	p._vdir = lerpf(p._vdir, p._dir, p._dt * VDIR_LERP)

	# Mouse lean: тело клонится к курсору по обоим осям
	var mouse_lean_tgt := clampf(to_mouse.x / MOUSE_LEAN_X_DIV, -1.0, 1.0) * MOUSE_LEAN_X_AMP
	mouse_lean_tgt += clampf(-to_mouse.y / MOUSE_LEAN_Y_DIV, -0.5, 0.5) * MOUSE_LEAN_Y_AMP
	p._mouse_lean = lerpf(p._mouse_lean, mouse_lean_tgt, delta * MOUSE_LEAN_LERP)


# ────────────────────────────────────────────────────────────────
#  ACCELERATION TRACKING  (для пружинного наклона тела)
# ────────────────────────────────────────────────────────────────
func _update_accel(delta: float) -> void:
	var dt_safe := maxf(delta, 0.0005)
	p._accel_x = clampf((p.velocity.x - p._prev_vel.x) / dt_safe, -p.ACCEL * 2.0, p.ACCEL * 2.0)
	p._prev_vel = p.velocity
	p._jbuf = maxf(p._jbuf - delta, 0.0)


# ────────────────────────────────────────────────────────────────
#  JUMP STATE MACHINE  (5 состояний)
# ────────────────────────────────────────────────────────────────
func _update_state_machine(delta: float) -> void:
	# В диораме гравитации нет — пол всегда под ногами.
	# Логика автомата сохранена для обратной совместимости с
	# финишером и потенциальной 2D-платформер-веткой.
	var on_fl := true
	match p._js:
		Player.JS.GROUND:
			_state_ground(on_fl)
		Player.JS.SQUAT:
			pass  # обрабатывается до move_and_slide в будущей ветке
		Player.JS.RISING:
			if p.velocity.y >= 0.0:
				p._js = Player.JS.FALLING
		Player.JS.FALLING:
			_state_falling(on_fl)
		Player.JS.LANDING:
			_state_landing(delta)


func _state_ground(on_fl: bool) -> void:
	if not on_fl:
		p._js = Player.JS.FALLING
	elif p._jbuf > 0.0:
		p._js = Player.JS.SQUAT
		p._squat_tmr = p.JUMP_SQUAT_T
		p._jbuf = 0.0


func _state_falling(on_fl: bool) -> void:
	if on_fl:
		# Landing: импульсы передаются пружинам
		p._js = Player.JS.LANDING
		p._land_tmr = p.LAND_RECOV
		p._squash = clampf(absf(p._prev_vel.y) / 500.0, 0.0, 1.0) * p.LAND_SQUASH
		p._lh_tv.y -= LAND_HAND_IMPULSE
		p._rh_tv.y -= LAND_HAND_IMPULSE
		p._hvel.y += LAND_HEAD_IMPULSE
		p._lean_v -= p.velocity.x * LAND_LEAN_FACTOR
	elif p._jbuf > 0.0 and p._coyote > 0.0:
		# Coyote jump
		p.velocity.y = p.JUMP_VEL
		p._js = Player.JS.RISING
		p._jbuf = 0.0
		p._coyote = 0.0
		p._lh_tv.y += JUMP_HAND_IMPULSE
		p._rh_tv.y += JUMP_HAND_IMPULSE


func _state_landing(delta: float) -> void:
	p._land_tmr -= delta
	if p._land_tmr <= 0.0:
		p._js = Player.JS.GROUND
	elif p._jbuf > 0.0:
		p._js = Player.JS.SQUAT
		p._squat_tmr = p.JUMP_SQUAT_T
		p._jbuf = 0.0
