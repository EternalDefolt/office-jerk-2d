extends Node
## Enemy AI — drives the Dummy around the office with a small state machine.
## States: IDLE / WANDER (stroll) / APPROACH (curious) / HURT (stunned by a hit,
## no walking — lets hit physics play out) / RETREAT (commits to one escape
## direction after a beating; never ping-pongs).
## Limb reactions stay with BodyAI/dummy.gd — this node only moves the root.

enum State { IDLE, WANDER, APPROACH, HURT, RETREAT }

const WALK_SPEED := 90.0
const RETREAT_SPEED := 170.0
# Player-style movement physics (player: ACCEL 1400 / DECEL 2000, scaled down
# for a heavier, lazier office body)
const ACCEL := 900.0  # px/s^2 while speeding up
const DECEL := 1500.0  # px/s^2 while braking
const ROOM_MIN_X := 200.0
const ROOM_MAX_X := 1180.0
const APPROACH_DIST := 420.0  # farther than this -> may come closer
const PERSONAL_SPACE := 180.0  # never walks closer than this
const RETREAT_DIST := 340.0  # backs off until this far from player
const SCARE_HITS := 4  # hits within the window that trigger retreat
const SCARE_WINDOW := 3.0
const HURT_TIME := 0.7  # frozen after a hit; pushback physics owns the body
const CALM_AFTER_HIT := 1.2  # no wander/approach decisions this long after a hit

var _dummy: Node2D = null
var _player: Node2D = null
var _state: int = State.IDLE
var _state_t := 0.0  # time left in current state
var _target_x := 0.0
var _vel_x := 0.0
var _recent_hits: Array[float] = []  # timestamps of recent hits
var _last_hit_count := 0
var _last_hit_t := -100.0
var _retreat_dir := 1.0  # locked escape direction for the whole retreat
var _now := 0.0


func _ready() -> void:
	var root := get_parent()
	_dummy = root.get_node_or_null("Dummy")
	_player = root.get_node_or_null("Player")
	if _dummy:
		_target_x = _dummy.position.x
	_enter(State.IDLE)


func _physics_process(delta: float) -> void:
	if _dummy == null:
		return
	# Hands off while ragdoll / finisher / downed owns the body
	if _dummy._ragdoll or _dummy.finisher_active or _dummy.is_downed:
		_vel_x = 0.0
		_dummy.walk_vel = 0.0
		return
	_now += delta
	_track_hits()
	_state_t -= delta
	match _state:
		State.IDLE:
			_do_idle()
		State.WANDER:
			_do_wander()
		State.APPROACH:
			_do_approach()
		State.HURT:
			_do_hurt()
		State.RETREAT:
			_do_retreat()
	_apply_motion(delta)


## ── Hit tracking ──
## Any fresh hit -> HURT (stand still, let the punch physics play out).
## Too many hits in a short window -> commit to RETREAT in ONE direction.
func _track_hits() -> void:
	var hc: int = _dummy._hit_count
	var fresh := hc > _last_hit_count
	if fresh:
		for _i in hc - _last_hit_count:
			_recent_hits.append(_now)
		_last_hit_count = hc
		_last_hit_t = _now
	while not _recent_hits.is_empty() and _now - _recent_hits[0] > SCARE_WINDOW:
		_recent_hits.pop_front()
	if fresh:
		if _recent_hits.size() >= SCARE_HITS:
			if _state != State.RETREAT:
				_enter(State.RETREAT)
		elif _state != State.RETREAT:
			_enter(State.HURT)  # re-entering refreshes the stun timer


## ── States ──
func _enter(s: int) -> void:
	_state = s
	match s:
		State.IDLE:
			_state_t = randf_range(1.5, 3.5)
		State.WANDER:
			_state_t = randf_range(3.0, 6.0)
			_target_x = _pick_wander_x()
		State.APPROACH:
			_state_t = randf_range(2.0, 4.0)
		State.HURT:
			_state_t = HURT_TIME
		State.RETREAT:
			_state_t = randf_range(2.5, 4.0)
			_recent_hits.clear()
			# Lock ONE escape direction: away from player, toward the larger
			# side of the room so he doesn't bounce off a wall and flip.
			var away := 1.0
			if _player:
				away = signf(_dummy.position.x - _player.position.x)
				if away == 0.0:
					away = 1.0
			var room_left := _dummy.position.x - ROOM_MIN_X
			var room_right := ROOM_MAX_X - _dummy.position.x
			if away < 0.0 and room_left < 150.0:
				away = 1.0
			elif away > 0.0 and room_right < 150.0:
				away = -1.0
			_retreat_dir = away
			_target_x = clampf(
				_dummy.position.x + _retreat_dir * 1000.0, ROOM_MIN_X, ROOM_MAX_X
			)


func _do_idle() -> void:
	_target_x = _dummy.position.x
	# Stay put while the last hit is still fresh — no nervous pacing
	if _state_t <= 0.0 and _now - _last_hit_t > CALM_AFTER_HIT:
		# Curious about a far-away player, otherwise just stroll
		if _player and absf(_player.position.x - _dummy.position.x) > APPROACH_DIST and randf() < 0.4:
			_enter(State.APPROACH)
		else:
			_enter(State.WANDER)


func _do_wander() -> void:
	if _state_t <= 0.0 or absf(_dummy.position.x - _target_x) < 8.0:
		_enter(State.IDLE)


func _do_approach() -> void:
	if _player == null:
		_enter(State.IDLE)
		return
	var dx := _player.position.x - _dummy.position.x
	# Stop at the edge of personal space, never on top of the player
	_target_x = _player.position.x - signf(dx) * PERSONAL_SPACE
	if absf(dx) <= PERSONAL_SPACE + 12.0 or _state_t <= 0.0:
		_enter(State.IDLE)


func _do_hurt() -> void:
	# Frozen: target is wherever the pushback left him, so the AI never
	# fights the hit physics by walking back to a stale target.
	_target_x = _dummy.position.x
	if _state_t <= 0.0:
		_enter(State.IDLE)


func _do_retreat() -> void:
	if _player == null:
		_enter(State.IDLE)
		return
	# Direction is LOCKED at state entry — no re-deciding mid-run
	var dist := absf(_dummy.position.x - _player.position.x)
	var at_wall := (
		(_retreat_dir < 0.0 and _dummy.position.x <= ROOM_MIN_X + 4.0)
		or (_retreat_dir > 0.0 and _dummy.position.x >= ROOM_MAX_X - 4.0)
	)
	if dist >= RETREAT_DIST or at_wall or _state_t <= 0.0:
		_enter(State.IDLE)


func _pick_wander_x() -> float:
	for _i in 6:
		var x := randf_range(ROOM_MIN_X, ROOM_MAX_X)
		# Not inside the player's personal space, and not a pointless 2-step shuffle
		var far_from_player := _player == null or absf(x - _player.position.x) > PERSONAL_SPACE
		if far_from_player and absf(x - _dummy.position.x) > 80.0:
			return x
	return _dummy.position.x


## ── Motion: player-style accel/decel physics; gait animation lives in dummy.gd ──
func _apply_motion(delta: float) -> void:
	var spd := RETREAT_SPEED if _state == State.RETREAT else WALK_SPEED
	var dx := _target_x - _dummy.position.x
	var want := clampf(dx / 40.0, -1.0, 1.0) * spd  # ease in near the target
	if absf(dx) < 14.0 or _state == State.HURT:
		want = 0.0
	# Same scheme as Player: move_toward with separate accel/brake rates.
	# Braking (slowing down or reversing) uses the stronger DECEL.
	var prev := _vel_x
	var speeding_up := absf(want) > absf(_vel_x) and signf(want) == signf(_vel_x if _vel_x != 0.0 else want)
	var rate := ACCEL if speeding_up else DECEL
	_vel_x = move_toward(_vel_x, want, rate * delta)
	_dummy.position.x = clampf(_dummy.position.x + _vel_x * delta, ROOM_MIN_X, ROOM_MAX_X)
	# Feed the dummy's procedural animation: velocity drives the walk cycle,
	# acceleration drives the body lean (exactly like Player._accel_x)
	_dummy.walk_vel = _vel_x
	_dummy.walk_accel = clampf((_vel_x - prev) / maxf(delta, 0.001), -ACCEL * 2.0, ACCEL * 2.0)
