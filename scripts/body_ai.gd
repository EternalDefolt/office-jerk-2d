class_name BodyAI
## Procedural body reaction AI — generates human-like responses
## Each limb has its own "desire" system that smoothly pursues targets
## No teleporting, no hardcoded animations — just goals and physics


# ═══════════════════════════════════════
#  LIMB: one body part with desire-driven motion
# ═══════════════════════════════════════
class Limb:
	var pos := Vector2.ZERO  # current position (local to body)
	var vel := Vector2.ZERO  # velocity
	var target := Vector2.ZERO  # where it WANTS to be
	var rest := Vector2.ZERO  # default resting position
	var stiffness := 80.0  # how fast it chases target
	var damping := 9.0  # how much it overshoots
	var weight := 1.0  # mass (heavier = slower response)
	var max_speed := 400.0  # cap on velocity

	func update(delta: float) -> void:
		# Spring-damper toward target
		var force := stiffness * (target - pos) / weight
		var drag := damping * vel
		vel += (force - drag) * delta
		# Cap speed
		if vel.length() > max_speed:
			vel = vel.normalized() * max_speed
		pos += vel * delta

	func set_target_smooth(tgt: Vector2, urgency: float = 1.0) -> void:
		# Don't snap — blend toward new target
		target = target.lerp(tgt, urgency)

	func impulse(imp: Vector2) -> void:
		vel += imp / weight


# ═══════════════════════════════════════
#  BEHAVIOR: what the body is trying to do
# ═══════════════════════════════════════
enum Intent {
	IDLE,  # standing, breathing
	FLINCH,  # just got hit — recoil
	STAGGER,  # heavy hit — stumble
	GRABBED,  # being held — struggle to escape
	CHOKING,  # being choked — panic, grab at throat
	THROWN,  # ragdoll in air
	DOWNED,  # on the ground
	GETTING_UP,  # recovering to stand
}

var intent := Intent.IDLE
var intent_time := 0.0  # how long in current intent
var pain := 0.0  # 0=fresh, 1=nearly dead (affects energy)
var panic := 0.0  # 0=calm, 1=max panic
var energy := 1.0  # 1=full strength, 0=exhausted

# The 6 limbs: head, body, lhand, rhand, lfoot, rfoot
var limbs: Array[Limb] = []

# External inputs
var hit_dir := Vector2.ZERO  # last hit direction
var grab_point := Vector2.ZERO  # where the grabber's hand is (local to body)
var facing_dir := 1.0  # which way attacker is (-1 or 1)

# Action state machine
var _action_timer := 0.0
var _action_type := 0  # current sub-action within intent
var _action_dur := 0.3  # how long current action lasts
var _breath_t := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	for i in 6:
		limbs.append(Limb.new())
	# Set default properties per limb
	# Head
	limbs[0].stiffness = 100.0
	limbs[0].damping = 10.0
	limbs[0].weight = 0.8
	# Body
	limbs[1].stiffness = 120.0
	limbs[1].damping = 12.0
	limbs[1].weight = 2.0  # heaviest
	# Hands
	limbs[2].stiffness = 70.0
	limbs[2].damping = 7.0
	limbs[2].weight = 0.5  # lightest = fastest
	limbs[3].stiffness = 70.0
	limbs[3].damping = 7.0
	limbs[3].weight = 0.5
	# Feet
	limbs[4].stiffness = 90.0
	limbs[4].damping = 11.0
	limbs[4].weight = 1.2
	limbs[5].stiffness = 90.0
	limbs[5].damping = 11.0
	limbs[5].weight = 1.2


func setup_rest_positions(positions: Array[Vector2]) -> void:
	for i in mini(positions.size(), 6):
		limbs[i].rest = positions[i]
		limbs[i].pos = positions[i]
		limbs[i].target = positions[i]


func update(delta: float) -> void:
	intent_time += delta
	_breath_t += delta
	_action_timer += delta

	# Energy drains with pain
	energy = maxf(1.0 - pain * 0.7, 0.1)

	# Generate targets based on intent
	match intent:
		Intent.IDLE:
			_do_idle(delta)
		Intent.FLINCH:
			_do_flinch(delta)
		Intent.STAGGER:
			_do_stagger(delta)
		Intent.GRABBED:
			_do_grabbed(delta)
		Intent.CHOKING:
			_do_choking(delta)
		Intent.THROWN:
			_do_thrown(delta)
		Intent.DOWNED:
			_do_downed(delta)
		Intent.GETTING_UP:
			_do_getting_up(delta)

	# Update all limbs toward their targets
	for limb in limbs:
		limb.update(delta)


func set_intent(new_intent: Intent) -> void:
	if intent != new_intent:
		intent = new_intent
		intent_time = 0.0
		_action_timer = 0.0
		_pick_new_action()


func receive_hit(direction: Vector2, force: float) -> void:
	hit_dir = direction.normalized()
	pain = minf(pain + force * 0.01, 1.0)
	panic = minf(panic + 0.2, 1.0)

	# Impulse all limbs in hit direction (heavier parts less)
	for i in 6:
		limbs[i].impulse(hit_dir * force * (0.5 + _rng.randf() * 0.5))

	# Head takes extra hit
	limbs[0].impulse(hit_dir * force * 0.8)

	if force > 60:
		set_intent(Intent.STAGGER)
	else:
		set_intent(Intent.FLINCH)


# ═══════════════════════════════════════
#  INTENT BEHAVIORS
# ═══════════════════════════════════════


func _do_idle(delta: float) -> void:
	var breath := sin(_breath_t * 2.8)
	for i in 6:
		var rest := limbs[i].rest
		var b := breath * (1.5 if i < 2 else 0.5)
		limbs[i].set_target_smooth(rest + Vector2(0, b), delta * 5.0)
	panic = maxf(panic - delta * 0.3, 0.0)
	# Schizo even in idle (twitches, nervous energy)
	if panic > 0.1:
		_apply_schizo(delta)


func _do_flinch(delta: float) -> void:
	if intent_time < 0.15:
		var recoil := hit_dir * 15.0 * energy
		for i in 6:
			limbs[i].set_target_smooth(limbs[i].rest + recoil * (1.0 if i < 2 else 0.5), 0.3)
		_apply_schizo(delta)
	else:
		set_intent(Intent.IDLE)


func _do_stagger(delta: float) -> void:
	if intent_time < 0.4:
		var stag := hit_dir * 25.0 * energy * (1.0 - intent_time / 0.4)
		limbs[0].set_target_smooth(limbs[0].rest + stag * 1.3, 0.2)
		limbs[1].set_target_smooth(limbs[1].rest + stag, 0.2)
		# Arms flail in hit direction
		limbs[2].set_target_smooth(
			limbs[2].rest + stag + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-5, 5)), 0.15
		)
		limbs[3].set_target_smooth(
			limbs[3].rest + stag + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-5, 5)), 0.15
		)
		# Feet stumble
		limbs[4].set_target_smooth(limbs[4].rest + hit_dir * 10.0, 0.1)
		limbs[5].set_target_smooth(limbs[5].rest - hit_dir * 5.0, 0.1)
	else:
		set_intent(Intent.IDLE)


func _do_grabbed(delta: float) -> void:
	# Being held — try to pull away
	if _action_timer >= _action_dur:
		_pick_new_action()

	var urg := 0.08 * energy  # slow, weighted movement

	match _action_type:
		0:  # Pull body away from grabber
			var away := -facing_dir * 12.0 * energy
			limbs[1].set_target_smooth(limbs[1].rest + Vector2(away, 0), urg)
			limbs[0].set_target_smooth(limbs[0].rest + Vector2(away * 0.8, -3.0), urg)
			# Hands push at grabber
			limbs[2].set_target_smooth(
				Vector2(facing_dir * 20.0, limbs[2].rest.y - 15.0), urg * 1.5
			)
			limbs[3].set_target_smooth(
				Vector2(facing_dir * 15.0, limbs[3].rest.y - 10.0), urg * 1.5
			)
		1:  # Twist body sideways
			limbs[1].set_target_smooth(limbs[1].rest + Vector2(8.0, 3.0) * energy, urg)
			limbs[0].set_target_smooth(limbs[0].rest + Vector2(-5.0, -2.0) * energy, urg)
			limbs[2].set_target_smooth(limbs[2].rest + Vector2(-15.0, -8.0) * energy, urg)
			limbs[3].set_target_smooth(limbs[3].rest + Vector2(10.0, 5.0) * energy, urg)
		2:  # Kick at grabber
			limbs[4].set_target_smooth(
				Vector2(facing_dir * 18.0, limbs[4].rest.y - 10.0 * energy), urg * 2.0
			)
			limbs[5].set_target_smooth(limbs[5].rest + Vector2(0, 3.0), urg * 0.5)
			# Upper body braces
			limbs[1].set_target_smooth(limbs[1].rest + Vector2(-facing_dir * 5.0, 2.0), urg)


func _do_choking(delta: float) -> void:
	if _action_timer >= _action_dur:
		_pick_new_action()

	var urg := 0.12 * energy  # how fast limbs pursue targets
	var throat := grab_point
	var gasp := sin(intent_time * 8.0) * 3.0 * energy
	var e := energy  # shorthand

	# 8 DIFFERENT ACTIONS — AI cycles through them randomly
	match _action_type:
		0:  # BOTH HANDS: desperately claw at the grip
			limbs[2].set_target_smooth(
				throat + Vector2(-6.0, sin(intent_time * 2.5) * 4.0) * e, urg * 2.0
			)
			limbs[3].set_target_smooth(
				throat + Vector2(6.0, sin(intent_time * 3.0) * 4.0) * e, urg * 2.0
			)
			# Feet kick wildly
			limbs[4].set_target_smooth(
				(
					limbs[4].rest
					+ Vector2(sin(intent_time * 3.0) * 20.0 * e, sin(intent_time * 2.0) * 8.0 * e)
				),
				urg * 1.5
			)
			limbs[5].set_target_smooth(
				(
					limbs[5].rest
					+ Vector2(sin(intent_time * 3.5) * 15.0 * e, sin(intent_time * 2.5) * 6.0 * e)
				),
				urg
			)

		1:  # LEFT HAND grips throat, RIGHT HAND punches at attacker
			limbs[2].set_target_smooth(
				throat + Vector2(sin(intent_time * 2.0) * 3.0 * e, 0), urg * 1.5
			)
			# Right hand reaches toward attacker and SWINGS
			var swing := sin(intent_time * 5.0)
			limbs[3].set_target_smooth(
				Vector2(facing_dir * (20.0 + swing * 15.0) * e, limbs[3].rest.y - 25.0 * e),
				urg * 2.5
			)
			limbs[4].set_target_smooth(limbs[4].rest + Vector2(facing_dir * 10.0 * e, 0), urg)
			limbs[5].set_target_smooth(limbs[5].rest, urg * 0.5)

		2:  # BODY TWIST — try to wrench free sideways
			limbs[1].set_target_smooth(
				limbs[1].rest + Vector2(-facing_dir * 15.0 * e, 3.0), urg * 1.5
			)
			limbs[0].set_target_smooth(limbs[0].rest + Vector2(-facing_dir * 10.0 * e, -2.0), urg)
			limbs[2].set_target_smooth(throat + Vector2(-facing_dir * 10.0 * e, 2.0), urg)
			limbs[3].set_target_smooth(limbs[3].rest + Vector2(-facing_dir * 8.0 * e, -5.0), urg)
			limbs[4].set_target_smooth(limbs[4].rest + Vector2(-facing_dir * 12.0 * e, 0), urg)
			limbs[5].set_target_smooth(
				limbs[5].rest + Vector2(facing_dir * 5.0 * e, 3.0), urg * 0.5
			)

		3:  # DOUBLE KICK — both feet kick forward at attacker
			limbs[4].set_target_smooth(
				Vector2(facing_dir * 22.0 * e, limbs[4].rest.y - 12.0 * e), urg * 2.0
			)
			limbs[5].set_target_smooth(
				Vector2(facing_dir * 18.0 * e, limbs[5].rest.y - 8.0 * e), urg * 1.8
			)
			# Hands brace on throat
			limbs[2].set_target_smooth(throat + Vector2(-4.0, 2.0), urg)
			limbs[3].set_target_smooth(throat + Vector2(4.0, 2.0), urg)

		4:  # RIGHT HAND grips throat, LEFT HAND pushes attacker's face
			limbs[3].set_target_smooth(
				throat + Vector2(sin(intent_time * 2.5) * 3.0 * e, 0), urg * 1.5
			)
			limbs[2].set_target_smooth(
				Vector2(facing_dir * 30.0 * e, limbs[0].rest.y - 5.0), urg * 2.0
			)
			limbs[4].set_target_smooth(
				limbs[4].rest + Vector2(sin(intent_time * 2.0) * 8.0 * e, 0), urg
			)
			limbs[5].set_target_smooth(
				limbs[5].rest + Vector2(0, sin(intent_time * 1.5) * 5.0 * e), urg * 0.5
			)

		5:  # FULL BODY JERK — sudden violent spasm trying to break free
			var jerk_dir := _rng.randf_range(-1.0, 1.0)
			for i in 6:
				limbs[i].impulse(Vector2(jerk_dir * 30.0 * e, _rng.randf_range(-15, 10) * e))
			# Reset stiffness briefly (body goes limp then snaps)
			for i in 6:
				limbs[i].stiffness *= 0.5
			_action_dur = 0.15  # very brief — spasm then next action

		6:  # WEAKENING — hands try to reach throat but can't quite make it
			var reach := e * 0.6  # can barely reach
			limbs[2].set_target_smooth(throat + Vector2(-5.0, 8.0 * (1.0 - reach)), urg * 0.8)
			limbs[3].set_target_smooth(throat + Vector2(5.0, 10.0 * (1.0 - reach)), urg * 0.8)
			# Feet barely move
			limbs[4].set_target_smooth(
				limbs[4].rest + Vector2(sin(intent_time * 1.0) * 5.0 * e, 0), urg * 0.5
			)
			limbs[5].set_target_smooth(limbs[5].rest, urg * 0.3)

		7:  # LAST GASP — one hand reaches toward camera/sky (dramatic)
			limbs[2].set_target_smooth(Vector2(0, limbs[2].rest.y - 35.0 * e), urg * 1.5)
			limbs[3].set_target_smooth(throat + Vector2(3.0, sin(intent_time * 3.0) * 2.0), urg)
			limbs[4].set_target_smooth(
				limbs[4].rest + Vector2(sin(intent_time * 0.8) * 3.0, 0), urg * 0.3
			)
			limbs[5].set_target_smooth(limbs[5].rest, urg * 0.2)

	# Head ALWAYS gasps and jerks
	limbs[0].set_target_smooth(
		(
			limbs[0].rest
			+ Vector2(
				gasp + _rng.randf_range(-1, 1) * e, -4.0 * e + sin(intent_time * 5.0) * 2.0 * e
			)
		),
		urg * 1.5
	)

	# Body heaves
	limbs[1].set_target_smooth(
		limbs[1].rest + Vector2(sin(intent_time * 3.5) * 3.0 * e, gasp * 0.4), urg
	)

	# SCHIZO LAYER: random twitches/convulsions on top of everything
	_apply_schizo(delta)

	# After spasm (type 5), restore stiffness
	if _action_type == 5 and _action_timer > 0.1:
		for i in 6:
			limbs[i].stiffness = [100.0, 120.0, 70.0, 70.0, 90.0, 90.0][i]

	energy = maxf(energy - delta * 0.12, 0.05)
	panic = minf(panic + delta * 0.08, 1.0)


func _do_thrown(delta: float) -> void:
	# In air — limbs trail behind body (ragdoll feel)
	# Body AI doesn't control position here — ragdoll physics does
	# Just set targets to "hanging loose"
	for i in 6:
		limbs[i].stiffness = 20.0  # very soft
		limbs[i].damping = 3.0
		limbs[i].set_target_smooth(
			limbs[i].rest + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-5, 10)), 0.05
		)


func _do_downed(delta: float) -> void:
	# On ground — occasional twitch, trying to recover
	var twitch := 0.0
	if fmod(intent_time, 1.5) < 0.1:
		twitch = _rng.randf_range(-5.0, 5.0) * energy

	for i in 6:
		limbs[i].stiffness = 40.0  # sluggish
		limbs[i].damping = 8.0
		limbs[i].set_target_smooth(
			limbs[i].pos + Vector2(twitch * (0.5 if i > 1 else 1.0), 0), 0.03
		)

	energy = minf(energy + delta * 0.08, 1.0)  # slowly recovering


func _do_getting_up(delta: float) -> void:
	var t := clampf(intent_time / 1.5, 0.0, 1.0)
	var et := t * t * (3.0 - 2.0 * t)
	var wobble := sin(intent_time * 4.0) * 5.0 * (1.0 - et)

	for i in 6:
		limbs[i].stiffness = lerpf(40.0, 80.0, et)
		limbs[i].damping = lerpf(8.0, 10.0, et)
		limbs[i].set_target_smooth(
			limbs[i].rest + Vector2(wobble * (0.3 if i > 3 else 1.0), 0), 0.1 + et * 0.15
		)

	if intent_time >= 1.5:
		set_intent(Intent.IDLE)
		for i in 6:
			limbs[i].stiffness = [100.0, 120.0, 70.0, 70.0, 90.0, 90.0][i]
			limbs[i].damping = [10.0, 12.0, 7.0, 7.0, 11.0, 11.0][i]


# ═══════════════════════════════════════
#  ACTION PICKER (randomized sub-actions)
# ═══════════════════════════════════════

# ═══════════════════════════════════════
#  SCHIZO LAYER — unpredictable twitches overlaid on any behavior
# ═══════════════════════════════════════

var _schizo_twitch_timer := 0.0
var _schizo_target_limb := 0
var _schizo_impulse := Vector2.ZERO


func _apply_schizo(delta: float) -> void:
	_schizo_twitch_timer -= delta

	if _schizo_twitch_timer <= 0.0:
		# Random twitch: pick a random limb and jerk it
		_schizo_twitch_timer = _rng.randf_range(0.08, 0.4)  # frequent small twitches
		_schizo_target_limb = _rng.randi_range(0, 5)
		var intensity := (panic * 0.7 + 0.3) * energy
		_schizo_impulse = Vector2(
			_rng.randf_range(-40, 40) * intensity, _rng.randf_range(-30, 20) * intensity
		)
		limbs[_schizo_target_limb].impulse(_schizo_impulse)

		# Sometimes multiple limbs twitch at once (convulsion)
		if _rng.randf() < panic * 0.4:
			var other := _rng.randi_range(0, 5)
			limbs[other].impulse(_schizo_impulse * _rng.randf_range(0.3, 0.7))

		# Rare FULL BODY convulsion
		if _rng.randf() < panic * 0.15:
			for i in 6:
				limbs[i].impulse(
					Vector2(
						_rng.randf_range(-25, 25) * intensity, _rng.randf_range(-20, 10) * intensity
					)
				)

	# Constant micro-tremor on hands (schizo hands never fully still)
	limbs[2].vel += (
		Vector2(sin(_breath_t * 31.0) * 8.0 * panic, cos(_breath_t * 37.0) * 5.0 * panic) * delta
	)
	limbs[3].vel += (
		Vector2(
			sin(_breath_t * 29.0 + 1.7) * 8.0 * panic, cos(_breath_t * 33.0 + 2.3) * 5.0 * panic
		)
		* delta
	)

	# Head micro-jerk
	limbs[0].vel += Vector2(sin(_breath_t * 23.0) * 4.0 * panic, 0) * delta


func _pick_new_action() -> void:
	_action_timer = 0.0
	match intent:
		Intent.GRABBED:
			_action_type = _rng.randi_range(0, 2)
			_action_dur = _rng.randf_range(0.3, 0.6)
		Intent.CHOKING:
			if energy > 0.6:
				# Strong: aggressive actions (punch, kick, twist, spasm)
				_action_type = _rng.randi_range(0, 5)
			elif energy > 0.3:
				# Weakening: mix of fighting and giving up
				_action_type = [0, 1, 2, 4, 6][_rng.randi_range(0, 4)]
			else:
				# Dying: weak reaches, last gasp
				_action_type = [6, 7, 7][_rng.randi_range(0, 2)]
			_action_dur = _rng.randf_range(0.3, 0.7)
		_:
			_action_type = 0
			_action_dur = 0.3


# ═══════════════════════════════════════
#  GETTERS for external use
# ═══════════════════════════════════════


func get_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for limb in limbs:
		result.append(limb.pos)
	return result


func get_offsets_from_rest() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for limb in limbs:
		result.append(limb.pos - limb.rest)
	return result
