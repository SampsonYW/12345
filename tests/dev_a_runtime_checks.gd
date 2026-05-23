# dev_a_runtime_checks.gd
# Godot runtime checks for Dev A global state behavior.
extends SceneTree

const GameManagerScript := preload("res://scripts/managers/game_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	var manager: Node = GameManagerScript.new()
	var counters := {
		"signal_count": 0,
		"finished_count": 0,
	}

	manager.signal_flare_fired.connect(func(_origin: Vector3) -> void:
		counters.signal_count += 1
	)
	manager.run_finished.connect(func(_state: int) -> void:
		counters.finished_count += 1
	)

	manager.start_run()
	_expect(manager.current_state == manager.State.RUNNING, "start_run() should enter RUNNING")

	manager._process(60.0)
	_expect(
		manager.player_erosion > 2.4 and manager.player_erosion < 2.6,
		"60 seconds should add about 2.5 percent erosion"
	)

	var fired: bool = manager.fire_signal_flare(Vector3(12.0, 0.0, 34.0))
	_expect(fired, "First signal flare should be accepted")
	_expect(manager.current_state == manager.State.EXTRACTING, "Signal flare should enter EXTRACTING")
	_expect(manager.signal_flare_used, "Signal flare should be marked used")
	_expect(manager.signal_flare_position == Vector3(12.0, 0.0, 34.0), "Signal flare position should be stored")
	_expect(counters.signal_count == 1, "Signal flare signal should emit once")

	var fired_again: bool = manager.fire_signal_flare(Vector3.ZERO)
	_expect(not fired_again, "Second signal flare should be rejected")
	_expect(counters.signal_count == 1, "Rejected signal flare should not emit")

	manager.set_state(manager.State.DEAD)
	_expect(counters.finished_count == 1, "Terminal state should emit run_finished")
	manager.set_state(manager.State.RUNNING)
	_expect(manager.current_state == manager.State.DEAD, "Terminal state should ignore non-reset transitions")
	manager.reset_run()
	_expect(manager.current_state == manager.State.PREPARING, "reset_run() should leave terminal state for restart")
	manager.request_start_after_reload()
	_expect(manager.consume_start_after_reload(), "start-after-reload request should be consumed once")
	_expect(not manager.consume_start_after_reload(), "start-after-reload request should clear after consume")
	manager.start_run()
	_expect(manager.current_state == manager.State.RUNNING, "start_run() should work after terminal reset")
	manager.free()

	if _failures.is_empty():
		print("Dev A runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
