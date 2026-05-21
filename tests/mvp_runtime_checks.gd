# mvp_runtime_checks.gd
# Runtime checks for the Day 4 P0 MVP loop: spawn pressure, fog, and extraction.
extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	for i in 8:
		await physics_frame

	var manager: Node = root.get_node_or_null("GameManager")
	_expect(manager != null, "GameManager autoload should exist")
	if manager == null:
		_finish(scene)
		return

	var spawn_manager := scene.get_node_or_null("SpawnManager")
	_expect(spawn_manager != null, "Game3D should create SpawnManager")
	_expect(
		spawn_manager != null and spawn_manager.has_method("get_current_spawns_per_minute"),
		"SpawnManager should expose current spawn pressure"
	)

	var extraction := scene.get_node_or_null("Extraction")
	_expect(extraction != null, "Game3D should create Extraction")
	if extraction != null:
		_expect(extraction.wait_time >= 60.0, "Extraction default wait time should be doc-aligned before test override")
		extraction.wait_time = 0.1

	var fog := scene.get_node_or_null("FogOfWar")
	_expect(fog != null, "Game3D should create FogOfWar")
	_expect(
		fog != null and fog.has_method("get_current_radius"),
		"FogOfWar should expose the current erosion-scaled radius"
	)

	manager.start_run()
	for i in 4:
		await physics_frame

	var enemies := scene.get_node_or_null("Entities/Enemies")
	_expect(enemies != null and enemies.get_child_count() >= 4, "Run start should seed enemies")
	var initial_enemy_count: int = enemies.get_child_count() if enemies != null else 0

	if spawn_manager != null:
		var base_spm: float = spawn_manager.get_current_spawns_per_minute()
		manager.elapsed_time = 120.0
		manager.player_erosion = 75.0
		var late_spm: float = spawn_manager.get_current_spawns_per_minute()
		_expect(late_spm > base_spm, "Spawn pressure should rise with elapsed time and erosion")
		spawn_manager.spawn_enemy(manager.elapsed_time, manager.get_erosion_tier())
		await physics_frame
		_expect(enemies.get_child_count() > initial_enemy_count, "SpawnManager.spawn_enemy() should add enemies")
		var procedural_count_before_timer := enemies.get_child_count()
		manager.elapsed_time = 0.0
		manager.player_erosion = 0.0
		if spawn_manager.has_method("reset_pressure"):
			spawn_manager.reset_pressure()
		for i in 90:
			manager._process(1.0)
			spawn_manager._process(1.0)
		_expect(
			enemies.get_child_count() >= procedural_count_before_timer + 3,
			"SpawnManager should continue spawning as the time curve rises"
		)
		var spawn_positions := {}
		for i in 4:
			var spawned: Node3D = spawn_manager.spawn_enemy(180.0, 2)
			if spawned != null:
				spawn_positions[str(spawned.global_position)] = true
		_expect(spawn_positions.size() >= 2, "SpawnManager should vary procedural spawn points")

	if fog != null:
		manager.player_erosion = 0.0
		fog._process(0.0)
		var full_radius: float = fog.get_current_radius()
		manager.player_erosion = 100.0
		fog._process(0.0)
		var minimum_radius: float = fog.get_current_radius()
		_expect(minimum_radius < full_radius, "View distance should shrink at high erosion")
		_expect(minimum_radius >= full_radius * 0.45, "Minimum view distance should be around 50% of base")

	manager.player_erosion = 0.0
	manager.elapsed_time = 0.0
	var player := scene.get_node_or_null("Entities/Player3D") as Node3D
	_expect(player != null, "Player should exist for extraction flow")
	if player != null and extraction != null:
		var accepted: bool = manager.fire_signal_flare(player.global_position)
		_expect(accepted, "Signal flare should be accepted during RUNNING")
		await process_frame
		_expect(manager.current_state == manager.State.EXTRACTING, "Signal flare should enter EXTRACTING")
		if spawn_manager != null:
			_expect(spawn_manager.is_signal_active(), "Signal flare should activate spawn pressure")
			_expect(
				spawn_manager.get_current_spawns_per_minute() >= spawn_manager.signal_min_spawns_per_minute,
				"Signal-active spawn pressure should have an immediate minimum"
			)
		for i in 16:
			await process_frame
		_expect(extraction.has_arrived(), "Extraction should arrive after wait time")
		player.global_position = extraction.get_landing_position()
		_expect(extraction.try_board(), "Player in boarding range should be able to board")
		_expect(manager.current_state == manager.State.SUCCESS, "Boarding should complete the run")
		_expect(
			extraction.get_node_or_null("MothershipExtractionMarker") == null,
			"Extraction marker should clear on terminal state"
		)

	_finish(scene)


func _finish(scene: Node) -> void:
	scene.queue_free()
	if _failures.is_empty():
		print("MVP runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
