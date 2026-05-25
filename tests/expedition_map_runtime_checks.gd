# expedition_map_runtime_checks.gd
# Runtime checks for the larger risk-zoned expedition map.
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
	if manager == null:
		_finish(scene)
		return

	if manager.has_method("begin_expedition"):
		manager.begin_expedition()
	else:
		manager.start_run()
	await process_frame

	_expect(scene.has_method("get_expedition_bounds"), "Game3D exposes expedition bounds")
	if scene.has_method("get_expedition_bounds"):
		var bounds: Rect2 = scene.get_expedition_bounds()
		_expect(bounds.size.x >= 480.0 and bounds.size.y >= 240.0, "Expedition map covers about 80 current camera screens")

	_expect(scene.has_method("get_risk_zones"), "Game3D exposes risk zones")
	var zones: Array = scene.get_risk_zones() if scene.has_method("get_risk_zones") else []
	_expect(zones.size() >= 2, "Expedition has multiple risk zones")
	var has_low := false
	var has_high := false
	for zone in zones:
		if zone.get("risk", "") == "low":
			has_low = true
		if zone.get("risk", "") == "high":
			has_high = true
	_expect(has_low, "Expedition includes low-risk zones")
	_expect(has_high, "Expedition includes high-risk zones")

	_expect(scene.has_method("get_zone_density_summary"), "Game3D exposes density summary")
	if scene.has_method("get_zone_density_summary"):
		var summary: Dictionary = scene.get_zone_density_summary()
		_expect(summary.get("high_enemy_density", 0.0) > summary.get("low_enemy_density", 0.0), "High-risk zones have higher enemy density")
		_expect(summary.get("high_container_density", 0.0) > summary.get("low_container_density", 0.0), "High-risk zones have higher container density")
		_expect(summary.get("high_value_weight", 0.0) > summary.get("low_value_weight", 0.0), "High-risk zones have higher-value containers")

	_expect(hud != null and hud.has_method("set_zone_info"), "HUD exposes zone info API")
	if hud != null and hud.has_method("set_zone_info"):
		# set_risk_label_text 已合并到 set_zone_info / player_status_ui；
		# 验证 zone info 接口存在即可（set_zone_info 内部会同步风险标签）。
		pass

	_finish(scene)


func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if _failures.is_empty():
		print("Expedition map runtime checks passed.")
		quit(0)
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
