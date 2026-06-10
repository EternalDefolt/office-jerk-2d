# GdUnit4 — модульный тест Player root constants.
# Проверяет, что глобальные константы движения и пропорций
# имеют осмысленные значения (sprint > walk, размеры положительны).
extends GdUnitTestSuite


# ════════════════════════════════════════════════════════════════
#  UT-07 — Player.SPRINT_SPEED строго больше Player.MAX_SPEED.
#  Если эта инварианта нарушится — спринт перестанет быть спринтом
#  и walk-cycle забажит (sprint blend упадёт в 0).
# ════════════════════════════════════════════════════════════════
func test_ut07_sprint_faster_than_walk() -> void:
	assert_float(Player.SPRINT_SPEED).is_greater(Player.MAX_SPEED)
	assert_float(Player.MAX_SPEED).is_greater(0.0)
	assert_float(Player.ACCEL).is_greater(0.0)
	assert_float(Player.DECEL).is_greater(Player.ACCEL)  # тормоз резче разгона
	# Пропорции тела позитивны
	assert_float(Player.SZ_BODY.x).is_greater(0.0)
	assert_float(Player.SZ_BODY.y).is_greater(0.0)
	assert_float(Player.GND).is_greater(0.0)
