# enemy_ai_runtime_checks.gd
# Runtime checks for enemy alert accumulation, awakening, and patrol sight.
extends SceneTree

const PATROL_SCENE := preload("res://scenes/patrol_enemy_3d.tscn")
const DORMANT_SCENE := preload("res://scenes/dormant_enemy_3d.tscn")
const ENEMY_TYPE_PATROL := 0
const ENEMY_TYPE_DORMANT := 1

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_dormant_noise_alert_decays_before_threshold()
	_check_noise_threshold_forces_chase()
	_check_take_damage_wakes_dormant_enemy()
	_check_patrol_noise_accumulates_before_threshold()
	_check_patrol_noise_threshold_forces_chase()
	_check_patrol_sight_requires_range_and_angle()
	await _check_patrol_sight_is_blocked_by_obstacles()
	_check_alert_bar_tracks_alert_ratio()

	if _failures.is_empty():
		print("Enemy AI runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_dormant_noise_alert_decays_before_threshold() -> void:
	var enemy = _make_enemy(ENEMY_TYPE_DORMANT)
	enemy.alert_threshold = 100.0
	enemy.decay_rate = 10.0

	enemy.receive_noise(40.0)
	var raised_ratio: float = enemy.get_alert_ratio()
	_expect(raised_ratio > 0.39 and raised_ratio < 0.41, "Dormant noise should raise alert ratio before threshold")
	_expect(not enemy.is_awake(), "Dormant enemy should stay asleep below alert threshold")

	enemy._process(1.0)
	_expect(enemy.get_alert_ratio() < raised_ratio, "Dormant alert ratio should decay while still asleep")
	_cleanup(enemy)


func _check_noise_threshold_forces_chase() -> void:
	var enemy = _make_enemy(ENEMY_TYPE_DORMANT)
	enemy.alert_threshold = 70.0

	enemy.receive_noise(70.0)
	_expect(enemy.is_awake(), "Dormant enemy should wake when alert reaches threshold")
	_expect(enemy.get_ai_state_name() == "CHASE", "Threshold wake should enter chase state")
	_expect(is_equal_approx(enemy.get_alert_ratio(), 1.0), "Threshold wake should fill alert ratio")
	_cleanup(enemy)


func _check_take_damage_wakes_dormant_enemy() -> void:
	var enemy = _make_enemy(ENEMY_TYPE_DORMANT)

	enemy.take_damage(1.0)
	_expect(enemy.is_awake(), "Player damage should wake a dormant enemy immediately")
	_expect(enemy.get_ai_state_name() == "CHASE", "Damage wake should enter chase state")
	_cleanup(enemy)


func _check_patrol_noise_accumulates_before_threshold() -> void:
	var enemy = _make_enemy(ENEMY_TYPE_PATROL)
	enemy.alert_threshold = 100.0
	enemy.decay_rate = 10.0

	# Patrol enemies must start not awake so they can accumulate noise
	_expect(not enemy.is_awake(), "Patrol enemy should start not awake (alert accumulation enabled)")
	_expect(enemy.get_ai_state_name() == "PATROL", "Patrol enemy should still be in PATROL state")

	enemy.receive_noise(40.0)
	var raised_ratio: float = enemy.get_alert_ratio()
	_expect(raised_ratio > 0.39 and raised_ratio < 0.41, "Patrol noise should raise alert ratio before threshold")
	_expect(not enemy.is_awake(), "Patrol enemy should stay in patrol below alert threshold")

	enemy._process(1.0)
	_expect(enemy.get_alert_ratio() < raised_ratio, "Patrol alert ratio should decay while still patrolling")
	_cleanup(enemy)


func _check_patrol_noise_threshold_forces_chase() -> void:
	var enemy = _make_enemy(ENEMY_TYPE_PATROL)
	enemy.alert_threshold = 50.0

	enemy.receive_noise(50.0)
	_expect(enemy.is_awake(), "Patrol enemy should wake when alert reaches threshold")
	_expect(enemy.get_ai_state_name() == "CHASE", "Patrol noise threshold should enter chase state")
	_expect(is_equal_approx(enemy.get_alert_ratio(), 1.0), "Patrol threshold wake should fill alert ratio")
	_cleanup(enemy)


func _check_patrol_sight_requires_range_and_angle() -> void:
	var player := Node3D.new()
	player.name = "SightTestPlayer"
	player.add_to_group("player")
	root.add_child(player)

	var enemy = _make_enemy(ENEMY_TYPE_PATROL)
	enemy.global_position = Vector3.ZERO
	enemy.view_range = 6.0
	enemy.view_angle = 60.0

	player.global_position = Vector3(0.0, 0.0, -5.0)
	_expect(enemy.can_see_player(player), "Patrol enemy should see a player in front within range and angle")

	player.global_position = Vector3(0.0, 0.0, -7.0)
	_expect(not enemy.can_see_player(player), "Patrol enemy should not see a player beyond view range")

	player.global_position = Vector3(0.0, 0.0, 5.0)
	_expect(not enemy.can_see_player(player), "Patrol enemy should not see a player behind its facing direction")
	enemy._update_patrol(player, 0.0)
	_expect(enemy.get_ai_state_name() == "PATROL", "Patrol enemy should not chase a player behind it")
	_cleanup(enemy)

	var front_enemy = _make_enemy(ENEMY_TYPE_PATROL)
	front_enemy.global_position = Vector3.ZERO
	front_enemy.view_range = 6.0
	front_enemy.view_angle = 60.0
	player.global_position = Vector3(0.0, 0.0, -5.0)
	front_enemy._update_patrol(player, 0.0)
	_expect(front_enemy.get_ai_state_name() == "CHASE", "Patrol enemy should chase after seeing player in its vision cone")

	_cleanup(front_enemy)
	_cleanup(player)


func _check_alert_bar_tracks_alert_ratio() -> void:
	var enemy = _make_enemy(ENEMY_TYPE_DORMANT)
	enemy.alert_threshold = 100.0

	var alert_bar := enemy.get_node_or_null("AlertBar") as Node3D
	_expect(alert_bar != null, "Enemy should create or expose a visible 3D AlertBar child")
	var alert_fill := enemy.get_node_or_null("AlertBar/AlertFill") as MeshInstance3D
	_expect(alert_fill != null, "Enemy AlertBar should include a visible 3D fill mesh")

	enemy.receive_noise(25.0)
	if alert_bar != null and alert_fill != null:
		_expect(
			is_equal_approx(float(alert_bar.get_meta("alert_ratio", -1.0)), enemy.get_alert_ratio()),
			"AlertBar metadata should match alert ratio after noise"
		)
		_expect(alert_fill.scale.x > 0.2 and alert_fill.scale.x < 0.3, "AlertBar fill scale should show partial alert after noise")

	enemy._process(1.0)
	if alert_bar != null and alert_fill != null:
		_expect(
			is_equal_approx(float(alert_bar.get_meta("alert_ratio", -1.0)), enemy.get_alert_ratio()),
			"AlertBar metadata should match alert ratio after decay"
		)
		_expect(alert_fill.scale.x < 0.25, "AlertBar fill scale should shrink after alert decay")
	_cleanup(enemy)


func _check_patrol_sight_is_blocked_by_obstacles() -> void:
	var player := Node3D.new()
	player.name = "BlockedSightPlayer"
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.0, -5.0)

	var enemy = _make_enemy(ENEMY_TYPE_PATROL)
	enemy.global_position = Vector3.ZERO
	enemy.view_range = 6.0
	enemy.view_angle = 60.0
	enemy.vision_obstacle_mask = 4

	var blocker := StaticBody3D.new()
	blocker.name = "SightBlocker"
	blocker.collision_layer = 4
	blocker.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.25)
	shape.shape = box
	blocker.add_child(shape)
	root.add_child(blocker)
	blocker.global_position = Vector3(0.0, 0.0, -2.5)

	await physics_frame
	_expect(not enemy.can_see_player(player), "Patrol sight should be blocked by obstacle collision layer")

	blocker.collision_layer = 0
	await physics_frame
	enemy.reset_vision_cache()
	_expect(enemy.can_see_player(player), "Patrol sight should recover when the obstacle stops blocking vision")

	_cleanup(enemy)
	_cleanup(player)
	_cleanup(blocker)


func _make_enemy(enemy_type: int):
	var scene: PackedScene = PATROL_SCENE if enemy_type == ENEMY_TYPE_PATROL else DORMANT_SCENE
	var enemy = scene.instantiate()
	root.add_child(enemy)
	return enemy


func _cleanup(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
