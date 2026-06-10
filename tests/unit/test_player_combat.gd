# GdUnit4 — модульные тесты PlayerCombat
# Проверяют: именованные константы (Этап 8 техдолг), тайминги ударов.
extends GdUnitTestSuite


# ════════════════════════════════════════════════════════════════
#  UT-01 — Константа отдачи головы по X (вынесено из магического 30.0)
# ════════════════════════════════════════════════════════════════
func test_ut01_punch_head_kickback_x_constant() -> void:
	assert_float(PlayerCombat.PUNCH_HEAD_KICKBACK_X).is_equal(30.0)


# ════════════════════════════════════════════════════════════════
#  UT-02 — Константа отдачи головы по Y (вынесено из магического 15.0)
# ════════════════════════════════════════════════════════════════
func test_ut02_punch_head_kickback_y_constant() -> void:
	assert_float(PlayerCombat.PUNCH_HEAD_KICKBACK_Y).is_equal(15.0)


# ════════════════════════════════════════════════════════════════
#  UT-03 — Тайминги ударов: суммарная длительность фазы в адекватных пределах
#  WINDUP + STRIKE должно быть достаточно для анимации, но не затягивать бой.
# ════════════════════════════════════════════════════════════════
func test_ut03_punch_total_duration_in_range() -> void:
	var total := PlayerCombat.PUNCH_WINDUP + PlayerCombat.PUNCH_STRIKE
	assert_float(total).is_greater(0.3).is_less(0.5)
	assert_float(PlayerCombat.PUNCH_WINDUP).is_greater(0.0)
	assert_float(PlayerCombat.PUNCH_STRIKE).is_greater(0.0)
	assert_float(PlayerCombat.PUNCH_RECOVER).is_greater(0.0)
