# extraction_pressure_runtime_checks.gd
# Runtime checks for extraction pressure APIs, enemy HP UI, and signal flare reactions.
extends SceneTree

const PATROL_SCENE := preload("res://scenes/patrol_enemy_3d.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_enemy_hp_bar_tracks_damage()
	_check_patrol_enemy_reacts_to_signal_flare()
	_check_spawn_manager_avoids_visible_radius_and_reports_pressure()
	_check_extraction_reports_direction_and_status()
	_check_extraction_avoidance_tracks_current_player_position()

	if _failures.is_empty():
		print("Extraction pressure runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_enemy_hp_bar_tracks_damage() -> void:
	var enemy = PATROL_SCENE.instantiate()
	root.add_child(enemy)

	_expect(enemy.has_method("get_hp_ratio"), "Enemy should expose an HP ratio for UI/HUD checks")
	if enemy.has_method("get_hp_ratio"):
		_expect(is_equal_approx(enemy.get_hp_ratio(), 1.0), "Enemy HP ratio should start full")

	var hp_bar := enemy.get_node_or_null("HpBar") as Node3D
	_expect(hp_bar != null, "Enemy should create a visible 3D HpBar child")
	var hp_fill := enemy.get_node_or_null("HpBar/HpFill") as MeshInstance3D
	_expect(hp_fill != null, "Enemy HpBar should include a visible red fill mesh")

	enemy.take_damage(enemy.base_hp * 0.25, false)
	if enemy.has_method("get_hp_ratio") and hp_bar != null and hp_fill != null:
		_expect(enemy.get_hp_ratio() < 0.76 and enemy.get_hp_ratio() > 0.73, "Enemy HP ratio should drop after damage")
		_expect(
			is_equal_approx(float(hp_bar.get_meta("hp_ratio", -1.0)), enemy.get_hp_ratio()),
			"HpBar metadata should match HP ratio after damage"
		)
		_expect(hp_fill.scale.x < 0.76 and hp_fill.scale.x > 0.73, "HpBar fill scale should reflect damage")

	_cleanup(enemy)


func _check_patrol_enemy_reacts_to_signal_flare() -> void:
	var manager: Node = root.get_node_or_null("GameManager")
	if manager != null:
		manager.start_run()
		manager.set_state(manager.State.EXTRACTING)

	var enemy = PATROL_SCENE.instantiate()
	root.add_child(enemy)
	enemy.global_position = Vector3.ZERO
	enemy.patrol_speed = 6.0
	enemy.chase_speed = 6.0

	_expect(enemy.has_method("react_to_signal_flare"), "Patrol enemy should expose signal flare reaction API")
	if enemy.has_method("react_to_signal_flare"):
		enemy.react_to_signal_flare(Vector3(12.0, 0.0, 0.0), Vector3(18.0, 0.0, 0.0))
		_expect(enemy.is_awake(), "Signal flare should keep/wake patrol enemy into active response")
		_expect(enemy.has_method("get_signal_focus_position"), "Enemy should expose signal focus position for verification/HUD")
		if enemy.has_method("get_signal_focus_position"):
			_expect(enemy.get_signal_focus_position().distance_to(Vector3(18.0, 0.0, 0.0)) < 0.01, "Patrol enemy should redirect toward extraction area")
		enemy._physics_process(0.25)
		_expect(enemy.global_position.x > 0.1 or enemy.velocity.x > 0.1, "Signal flare response should move patrol enemy toward signal/extraction focus")

	_cleanup(enemy)
	if manager != null:
		manager.reset_run()


func _check_spawn_manager_avoids_visible_radius_and_reports_pressure() -> void:
	var manager = load("res://scripts/managers/spawn_manager.gd").new()
	root.add_child(manager)
	manager.minimum_spawn_distance = 0.0

	_expect(manager.has_method("set_visible_spawn_avoidance"), "SpawnManager should expose visible/camera spawn avoidance API")
	if manager.has_method("set_visible_spawn_avoidance"):
		manager.set_visible_spawn_avoidance(Vector3.ZERO, 24.0)
		var point: Vector3 = manager.get_farthest_spawn_point()
		_expect(point.distance_to(Vector3.ZERO) >= 24.0, "SpawnManager should prefer spawn points outside visible/camera radius")

	_expect(manager.has_method("get_pressure_status"), "SpawnManager should expose pressure status for HUD")
	if manager.has_method("get_pressure_status"):
		var status: Dictionary = manager.get_pressure_status()
		_expect(status.has("spawns_per_minute"), "Pressure status should include spawns_per_minute")
		_expect(status.has("signal_active"), "Pressure status should include signal_active")
		_expect(status.has("spawn_direction"), "Pressure status should include spawn_direction")

	_cleanup(manager)


func _check_extraction_reports_direction_and_status() -> void:
	var extraction = load("res://scripts/systems/extraction.gd").new()
	root.add_child(extraction)
	extraction.wait_time = 5.0
	extraction._on_signal_flare_fired(Vector3(8.0, 0.0, 0.0))

	_expect(extraction.has_method("get_pressure_status"), "Extraction should expose extraction pressure/status for HUD")
	if extraction.has_method("get_pressure_status"):
		var status: Dictionary = extraction.get_pressure_status()
		_expect(status.has("status_text"), "Extraction pressure status should include status_text")
		_expect(status.has("remaining_time"), "Extraction pressure status should include remaining_time")
		_expect(status.has("landing_position"), "Extraction pressure status should include landing_position")

	_expect(extraction.has_method("get_extraction_direction"), "Extraction should expose direction from player/signal to landing area")
	if extraction.has_method("get_extraction_direction"):
		var direction: Vector3 = extraction.get_extraction_direction(Vector3(8.0, 0.0, 8.0))
		_expect(direction.length() > 0.9 and direction.z < -0.5, "Extraction direction should point from supplied position toward landing area")

	_cleanup(extraction)


func _check_extraction_avoidance_tracks_current_player_position() -> void:
	var manager: Node = root.get_node_or_null("GameManager")
	if manager == null:
		return
	manager.start_run()
	manager.set_state(manager.State.EXTRACTING)
	manager.player_position = Vector3.ZERO

	var spawn_manager = load("res://scripts/managers/spawn_manager.gd").new()
	spawn_manager.name = "SpawnManager"
	root.add_child(spawn_manager)
	spawn_manager.minimum_spawn_distance = 0.0

	var extraction = load("res://scripts/systems/extraction.gd").new()
	root.add_child(extraction)
	extraction.wait_time = 5.0
	extraction._on_signal_flare_fired(Vector3.ZERO)

	manager.player_position = Vector3(224.0, 0.0, 48.0)
	await process_frame
	var point: Vector3 = spawn_manager.get_farthest_spawn_point()
	_expect(
		point.distance_to(manager.player_position) >= 28.0,
		"Extraction spawn avoidance should track the current player view, not only flare-time position"
	)

	_cleanup(extraction)
	_cleanup(spawn_manager)
	manager.reset_run()


func _cleanup(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
