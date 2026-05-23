# polish_flow_runtime_checks.gd
# Runtime checks for the polished title -> Afterglow -> expedition/result flow.
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
	_expect(manager != null, "GameManager exists")
	_expect(hud != null, "HUD exists")
	if manager == null or hud == null:
		_finish(scene)
		return

	_expect(manager.get("current_location") != null, "GameManager tracks current_location")
	if manager.get("current_location") != null:
		_expect(int(manager.get("current_location")) == 0, "Boot starts at title location")

	_expect(scene.has_method("get_active_map_name"), "Game3D exposes active map name")
	if scene.has_method("get_active_map_name"):
		_expect(scene.get_active_map_name() == "title", "Game starts on title overlay, not expedition")

	_expect(hud.has_method("_on_title_clicked"), "HUD exposes title click handler")
	if hud.has_method("_on_title_clicked"):
		hud._on_title_clicked()
	await process_frame
	if manager.get("current_location") != null:
		_expect(int(manager.get("current_location")) == 1, "Title click enters Afterglow map")
	if scene.has_method("get_active_map_name"):
		_expect(scene.get_active_map_name() == "afterglow", "Afterglow map is active after title click")
	_expect(scene.get_node_or_null("World/AfterglowMap/WarehousePoint") != null, "Afterglow has warehouse point")
	_expect(scene.get_node_or_null("World/AfterglowMap/DeparturePoint") != null, "Afterglow has departure point")
	var afterglow_map := scene.get_node_or_null("World/AfterglowMap")
	_expect(afterglow_map != null and afterglow_map.scene_file_path.ends_with("afterglow_map.tscn"), "Afterglow map is an editable Godot scene instance")
	_expect(scene.get_node_or_null("World/WorldPrompt") is Label3D, "World prompt exists as an editable scene node")

	_expect(scene.has_method("set_player_near_afterglow_point"), "Game3D can place player near Afterglow points for tests")
	_expect(scene.has_method("complete_departure_hold_for_test"), "Game3D can complete departure hold for tests")
	if scene.has_method("set_player_near_afterglow_point") and scene.has_method("complete_departure_hold_for_test"):
		scene.set_player_near_afterglow_point("departure")
		await process_frame
		scene.complete_departure_hold_for_test()
		await process_frame
		if manager.get("current_location") != null:
			_expect(int(manager.get("current_location")) == 2, "Departure hold starts expedition")
		if scene.has_method("get_active_map_name"):
			_expect(scene.get_active_map_name() == "expedition", "Expedition map is active after departure")

	manager.set_state(manager.State.DEAD)
	await process_frame
	if hud.has_method("_return_to_home_from_result"):
		hud._return_to_home_from_result()
	await process_frame
	if manager.get("current_location") != null:
		_expect(int(manager.get("current_location")) == 1, "Result returns to Afterglow map")
	if scene.has_method("get_active_map_name"):
		_expect(scene.get_active_map_name() == "afterglow", "Afterglow map is active after result")

	_finish(scene)


func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if _failures.is_empty():
		print("Polish flow runtime checks passed.")
		quit(0)
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
