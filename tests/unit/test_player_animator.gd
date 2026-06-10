# GdUnit4 — модульные тесты PlayerAnimator
# Проверяют чистую математику аниматора: квинтический smoothstep _ss(),
# walk-step curve _step() и базовое поведение _breath_val().
extends GdUnitTestSuite

var animator: PlayerAnimator
var fake_player: Player


func before_test() -> void:
	# Player.new() создаёт CharacterBody2D, но в дерево не добавляется —
	# _ready() не сработает, что нам и нужно (мы не тестируем _ready).
	fake_player = auto_free(Player.new())
	animator = PlayerAnimator.new(fake_player)


# ════════════════════════════════════════════════════════════════
#  UT-04 — Quintic smoothstep _ss(): концы кривой строго 0 и 1
#  Это гарантирует, что фазы анимации не «перескакивают» границы.
# ════════════════════════════════════════════════════════════════
func test_ut04_smoothstep_endpoints() -> void:
	assert_float(animator._ss(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(animator._ss(1.0)).is_equal_approx(1.0, 0.001)
	# Clamp behaviour: за пределами [0,1] не уходит
	assert_float(animator._ss(-0.5)).is_equal_approx(0.0, 0.001)
	assert_float(animator._ss(1.5)).is_equal_approx(1.0, 0.001)


# ════════════════════════════════════════════════════════════════
#  UT-05 — _ss(0.5) симметричен относительно середины (==0.5).
#  Свойство квинтического smoothstep'а: f(0.5) = 0.5 точно.
# ════════════════════════════════════════════════════════════════
func test_ut05_smoothstep_midpoint_symmetry() -> void:
	assert_float(animator._ss(0.5)).is_equal_approx(0.5, 0.001)


# ════════════════════════════════════════════════════════════════
#  UT-06 — Walk step curve: на фазе 0 нога в начале stance.
#  По спеке шага: n=0 → t=0 в stance phase, x = stride*0.5 (впереди).
# ════════════════════════════════════════════════════════════════
func test_ut06_step_curve_stance_start() -> void:
	var stride := 100.0
	var result := animator._step(0.0, stride)
	# Возвращает [x, y, ang, pv]
	assert_float(result[0] as float).is_equal_approx(stride * 0.5, 1.0)
	assert_float(result[1] as float).is_equal_approx(0.0, 0.001)  # y=0 на стэнсе
