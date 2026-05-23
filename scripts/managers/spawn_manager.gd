# spawn_manager.gd
# Time and erosion driven enemy pressure for the 3D MVP run loop.
# [AI-ASSISTED] 2026-05-20 - Day 4 P0 spawn pressure.
# [AI-ASSISTED] 2026-05-21 - Fix enemies spawning on obstacles.
# [AI-ASSISTED] 2026-05-22 - Add spawn_occurred signal for HUD pulse (polish_plan §4)
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node3D

signal spawn_occurred(position: Vector3, kind: String)

const DEFAULT_SPAWN_POINTS := [
	Vector3(-270.0, 0.0, -140.0),
	Vector3(-200.0, 0.0, 140.0),
	Vector3(-100.0, 0.0, -155.0),
	Vector3(0.0, 0.0, 145.0),
	Vector3(80.0, 0.0, -158.0),
	Vector3(160.0, 0.0, 130.0),
	Vector3(240.0, 0.0, -145.0),
	Vector3(280.0, 0.0, 80.0),
	Vector3(-280.0, 0.0, -50.0),
	Vector3(-260.0, 0.0, 80.0),
	Vector3(150.0, 0.0, 150.0),
	Vector3(-150.0, 0.0, -140.0),
]

@export var signal_flare_multiplier: float = 3.0
@export var signal_min_spawns_per_minute: float = 8.0
@export var max_alive_enemies: int = 32
@export var minimum_spawn_distance: float = 12.0
@export var obstacle_collision_mask: int = 4
@export var obstacle_clear_radius: float = 2.5

var spawn_curve := [
	[0.0, 0.0],
	[30.0, 2.0],
	[60.0, 4.0],
	[120.0, 8.0],
	[180.0, 15.0],
	[240.0, 25.0],
	[300.0, 40.0],
]

var _spawn_budget: float = 0.0
var _spawn_point_cursor: int = 0
var _signal_active: bool = false
var _initial_spawned: bool = false
var _enemy_parent: Node = null
var _patrol_scene: PackedScene = null
var _dormant_scene: PackedScene = null
var _spawn_points: Array[Vector3] = []
var _visible_avoidance_center: Vector3 = Vector3.ZERO
var _visible_avoidance_radius: float = 0.0
var _last_spawn_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	_spawn_points.assign(DEFAULT_SPAWN_POINTS)
	if not GameManager.state_changed.is_connected(_on_game_state_changed):
		GameManager.state_changed.connect(_on_game_state_changed)


func _process(delta: float) -> void:
	var state := GameManager.current_state
	if state != GameManager.State.RUNNING and state != GameManager.State.EXTRACTING:
		return
	var spm := get_current_spawns_per_minute()
	if spm <= 0.0:
		return
	_spawn_budget += spm * delta / 60.0
	var spawned_this_frame := 0
	while _spawn_budget >= 1.0 and spawned_this_frame < 3:
		spawn_enemy(GameManager.elapsed_time, GameManager.get_erosion_tier())
		_spawn_budget -= 1.0
		spawned_this_frame += 1


func configure(enemy_parent: Node, patrol_scene: PackedScene, dormant_scene: PackedScene) -> void:
	_enemy_parent = enemy_parent
	_patrol_scene = patrol_scene
	_dormant_scene = dormant_scene


func get_spawn_points() -> Array[Vector3]:
	return _spawn_points.duplicate()


func seed_initial_enemies() -> void:
	if _initial_spawned:
		return
	_initial_spawned = true

	var map = get_node_or_null("../World/ExpeditionMap")
	var initial_spawns = map.get_node_or_null("InitialSpawns") if map != null else null
	if initial_spawns != null:
		for spawn in initial_spawns.get_children():
			if spawn is Node3D:
				var is_dormant = spawn.name.to_lower().contains("dormant")
				var scene = _dormant_scene if is_dormant else _patrol_scene
				_spawn_fixed(scene, spawn.global_position)
		return

	# Fallback: spawn enemies at hardcoded positions (used when .tscn has no InitialSpawns)
	# --- Low risk: Ash Outskirts ---
	_spawn_fixed(_patrol_scene, Vector3(-160.0, 0.0, -30.0))
	_spawn_fixed(_dormant_scene, Vector3(-140.0, 0.0, 50.0))
	# --- Low risk: Broken Rail ---
	_spawn_fixed(_patrol_scene, Vector3(-20.0, 0.0, -40.0))
	_spawn_fixed(_dormant_scene, Vector3(30.0, 0.0, -60.0))
	# --- High risk: Black Yard ---
	_spawn_fixed(_patrol_scene, Vector3(100.0, 0.0, -30.0))
	_spawn_fixed(_patrol_scene, Vector3(170.0, 0.0, 10.0))
	_spawn_fixed(_dormant_scene, Vector3(125.0, 0.0, -45.0))
	_spawn_fixed(_dormant_scene, Vector3(155.0, 0.0, -15.0))
	_spawn_fixed(_dormant_scene, Vector3(195.0, 0.0, 35.0))
	_spawn_fixed(_dormant_scene, Vector3(145.0, 0.0, 55.0))
	# --- High risk: Core Wreck ---
	_spawn_fixed(_patrol_scene, Vector3(40.0, 0.0, 65.0))
	_spawn_fixed(_patrol_scene, Vector3(25.0, 0.0, 85.0))
	_spawn_fixed(_dormant_scene, Vector3(55.0, 0.0, 75.0))
	_spawn_fixed(_dormant_scene, Vector3(10.0, 0.0, 90.0))


func spawn_enemy(elapsed: float, tier: int) -> Node3D:
	if _get_enemy_parent() == null:
		return null
	if _get_enemy_parent().get_child_count() >= max_alive_enemies:
		return null
	var spawn_dormant := elapsed > 60.0 and randf() < _get_dormant_ratio(tier)
	var scene := _dormant_scene if spawn_dormant else _patrol_scene
	var point := get_farthest_spawn_point()
	var enemy := _spawn_fixed(scene, point, tier)
	if enemy != null:
		var kind := "dormant" if spawn_dormant else "patrol"
		spawn_occurred.emit(point, kind)
	return enemy


func on_signal_flare() -> void:
	_signal_active = true
	_spawn_budget = maxf(_spawn_budget, 1.0)


func reset_pressure() -> void:
	_spawn_budget = 0.0
	_spawn_point_cursor = 0
	_signal_active = false


func is_signal_active() -> bool:
	return _signal_active


func set_visible_spawn_avoidance(center: Vector3, radius: float) -> void:
	_visible_avoidance_center = center
	_visible_avoidance_radius = maxf(radius, 0.0)


func get_spawn_direction() -> Vector3:
	var point := _last_spawn_point
	if point == Vector3.ZERO:
		var ranked := _get_ranked_spawn_points()
		if not ranked.is_empty():
			point = ranked[0]
	var direction := point - GameManager.player_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.01 else Vector3.ZERO


func get_pressure_status() -> Dictionary:
	return {
		"spawns_per_minute": get_current_spawns_per_minute(),
		"signal_active": _signal_active,
		"spawn_direction": get_spawn_direction(),
		"spawn_budget": _spawn_budget,
		"max_alive_enemies": max_alive_enemies,
	}


func get_current_spawns_per_minute() -> float:
	var tier := GameManager.get_erosion_tier()
	var spm := sample_curve(GameManager.elapsed_time)
	if _signal_active:
		spm = maxf(spm * signal_flare_multiplier, signal_min_spawns_per_minute)
	var interval_multiplier: float = GameManager.EROSION_SPAWN_INTERVAL_MULTIPLIER[tier]
	if interval_multiplier > 0.0:
		spm /= interval_multiplier
	return spm


func sample_curve(t: float) -> float:
	for i in range(spawn_curve.size() - 1):
		var current: Array = spawn_curve[i]
		var next: Array = spawn_curve[i + 1]
		if t >= current[0] and t < next[0]:
			var ratio: float = (t - current[0]) / (next[0] - current[0])
			return lerpf(current[1], next[1], ratio)
	return spawn_curve[spawn_curve.size() - 1][1]


func get_farthest_spawn_point() -> Vector3:
	if _signal_active:
		set_visible_spawn_avoidance(GameManager.player_position, maxf(_visible_avoidance_radius, 28.0))
		# 信号弹阶段：优先选择靠近信号弹位置的刷怪点
		var signal_position := GameManager.signal_flare_position
		var signal_valid: Array[Vector3] = []
		for point in _spawn_points:
			if point.distance_to(GameManager.player_position) >= minimum_spawn_distance:
				signal_valid.append(point)
		if not signal_valid.is_empty():
			# 按距离信号弹位置排序（近的优先）
			signal_valid.sort_custom(func(a: Vector3, b: Vector3) -> bool:
				return a.distance_to(signal_position) < b.distance_to(signal_position)
			)
			var candidate_count: int = mini(signal_valid.size(), 3)
			var point := signal_valid[_spawn_point_cursor % candidate_count]
			_spawn_point_cursor += 1
			_last_spawn_point = point
			return point

	var valid := _get_ranked_spawn_points()
	if valid.is_empty():
		return Vector3.ZERO
	var candidate_count: int = mini(valid.size(), 4)
	var point := valid[_spawn_point_cursor % candidate_count]
	_spawn_point_cursor += 1
	_last_spawn_point = point
	return point


func _get_ranked_spawn_points() -> Array[Vector3]:
	var valid: Array[Vector3] = []
	for point in _spawn_points:
		if point.distance_to(GameManager.player_position) >= minimum_spawn_distance:
			valid.append(point)
	if _visible_avoidance_radius > 0.0:
		var outside_visible: Array[Vector3] = []
		for point in valid:
			if point.distance_to(_visible_avoidance_center) >= _visible_avoidance_radius:
				outside_visible.append(point)
		if not outside_visible.is_empty():
			valid = outside_visible
	if valid.is_empty():
		valid = _spawn_points.duplicate()
	valid.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var a_visible_distance := a.distance_to(_visible_avoidance_center)
		var b_visible_distance := b.distance_to(_visible_avoidance_center)
		var is_approx := is_equal_approx(a_visible_distance, b_visible_distance)
		if _visible_avoidance_radius > 0.0 and not is_approx:
			return a_visible_distance > b_visible_distance
		return a.distance_to(GameManager.player_position) > b.distance_to(GameManager.player_position)
	)
	return valid


func _spawn_fixed(scene: PackedScene, point: Vector3, tier: int = -1) -> Node3D:
	if scene == null or _get_enemy_parent() == null:
		return null
	var clear_point := _find_clear_spawn_position(point)
	var enemy := scene.instantiate() as Node3D
	_get_enemy_parent().add_child(enemy)
	enemy.global_position = clear_point
	if enemy.has_method("set_erosion_tier"):
		enemy.set_erosion_tier(GameManager.get_erosion_tier() if tier < 0 else tier)
	return enemy


func _get_enemy_parent() -> Node:
	if _enemy_parent != null and is_instance_valid(_enemy_parent):
		return _enemy_parent
	var scene: Node = get_tree().current_scene
	if scene != null:
		_enemy_parent = scene.get_node_or_null("Entities/Enemies")
	return _enemy_parent


func _get_dormant_ratio(tier: int) -> float:
	var safe_tier := clampi(tier, 0, GameManager.EROSION_DORMANT_RATIO.size() - 1)
	return GameManager.EROSION_DORMANT_RATIO[safe_tier]


## Check if a spawn point overlaps an obstacle and find a clear alternative.
## Uses a downward raycast from above; if it hits an obstacle, tries offsets.
func _find_clear_spawn_position(point: Vector3) -> Vector3:
	var candidate := Vector3(point.x, 0.0, point.z)
	if not _is_point_on_obstacle(candidate):
		return candidate
	# Try offset positions in a spiral pattern to escape the obstacle
	var offsets: Array[Vector3] = [
		Vector3(obstacle_clear_radius, 0.0, 0.0),
		Vector3(-obstacle_clear_radius, 0.0, 0.0),
		Vector3(0.0, 0.0, obstacle_clear_radius),
		Vector3(0.0, 0.0, -obstacle_clear_radius),
		Vector3(obstacle_clear_radius, 0.0, obstacle_clear_radius),
		Vector3(-obstacle_clear_radius, 0.0, obstacle_clear_radius),
		Vector3(obstacle_clear_radius, 0.0, -obstacle_clear_radius),
		Vector3(-obstacle_clear_radius, 0.0, -obstacle_clear_radius),
		Vector3(obstacle_clear_radius * 2.0, 0.0, 0.0),
		Vector3(-obstacle_clear_radius * 2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, obstacle_clear_radius * 2.0),
		Vector3(0.0, 0.0, -obstacle_clear_radius * 2.0),
	]
	for offset: Vector3 in offsets:
		var test: Vector3 = candidate + offset
		if not _is_point_on_obstacle(test):
			return test
	# All nearby positions blocked – fall back to original but force ground level
	return candidate


## Returns true if the given ground-level position overlaps with an obstacle.
func _is_point_on_obstacle(point: Vector3) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var world := tree.root.get_world_3d()
	if world == null:
		return false
	var space_state := world.direct_space_state
	if space_state == null:
		return false
	# Cast a ray from above the point straight down
	var ray_origin := Vector3(point.x, 10.0, point.z)
	var ray_end := Vector3(point.x, -1.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, obstacle_collision_mask)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	# If the hit point is above ground level (y > 0.05), we're on an obstacle
	var hit_pos: Vector3 = result["position"]
	return hit_pos.y > 0.05


func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.PREPARING:
		reset_pressure()
		_initial_spawned = false
