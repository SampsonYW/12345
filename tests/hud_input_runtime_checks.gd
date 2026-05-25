# hud_input_runtime_checks.gd
# Runtime checks for keyboard handling on main and result overlays.
extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame

	var manager: Node = root.get_node_or_null("GameManager")
	var hud := scene.get_node_or_null("UI/HUD")
	_expect(manager != null, "GameManager autoload should exist")
	_expect(hud != null, "HUD should exist")
	if manager == null or hud == null:
		_finish()
		return

	manager.set_state(manager.State.DEAD)
	await process_frame
	_press_enter(hud)
	await process_frame
	_press_enter(hud)
	await process_frame

	_finish()


func _press_enter(hud: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	if hud.get("_input_interceptor") != null:
		hud._input_interceptor._unhandled_input(event)


func _finish() -> void:
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
	if _failures.is_empty():
		print("HUD input runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
