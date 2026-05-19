# game_3d_runtime_checks.gd
# Loads the 3D rewrite scene and verifies the core runtime pieces exist.
extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	for i in 8:
		await physics_frame

	_expect(scene is Node3D, "3D main scene root should be Node3D")
	var manager: Node = root.get_node_or_null("GameManager")
	_expect(manager != null, "GameManager autoload should exist")
	if manager != null:
		_expect(manager.current_state == manager.State.PREPARING, "3D scene should wait on the main screen")

	var camera := scene.get_node_or_null("CameraRig/Camera3D") as Camera3D
	_expect(camera != null, "3D scene should have Camera3D under CameraRig")
	if camera != null:
		_expect(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Camera3D should be orthogonal")
		_expect(camera.rotation_degrees.x < -35.0, "Camera3D should tilt down for Don't Starve-like perspective")

	var player := scene.get_node_or_null("Entities/Player3D") as CharacterBody3D
	_expect(player != null, "3D player should exist")
	if player != null:
		_expect(player.is_in_group("player"), "3D player should be in player group")
		_expect(player.get_node_or_null("PlayerHealth") != null, "3D player should keep PlayerHealth")
		var shooting := player.get_node_or_null("PlayerShooting")
		_expect(shooting != null, "3D player should have shooting")
		if shooting != null:
			_expect(shooting._bullet_pool.size() >= 8, "3D shooting should prebuild a bullet pool")
		_expect(player.get_node_or_null("Inventory") != null, "3D player should keep Inventory")

	var hud := scene.get_node_or_null("UI/HUD")
	_expect(hud != null, "3D scene should keep HUD")
	if hud != null:
		var main_overlay := hud.get_node_or_null("MainOverlay") as Control
		_expect(main_overlay != null and main_overlay.visible, "HUD should show the main overlay before start")

	if manager != null:
		manager.start_run()
		for i in 4:
			await physics_frame
		_expect(manager.current_state == manager.State.RUNNING, "start_run() should enter RUNNING")

	var enemies := scene.get_node_or_null("Entities/Enemies")
	_expect(enemies != null and enemies.get_child_count() > 0, "3D scene should spawn enemies")
	if enemies != null:
		var kinds := {}
		for enemy in enemies.get_children():
			if enemy.has_method("get_enemy_kind"):
				kinds[enemy.get_enemy_kind()] = true
		_expect(kinds.has("patrol"), "3D scene should spawn patrol enemies")
		_expect(kinds.has("dormant"), "3D scene should spawn dormant enemies")

	var containers := scene.get_node_or_null("Entities/Containers")
	_expect(containers != null and containers.get_child_count() > 0, "3D scene should spawn containers")

	scene.queue_free()
	await process_frame

	if _failures.is_empty():
		print("3D runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
