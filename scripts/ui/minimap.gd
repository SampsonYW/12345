# minimap.gd
# 小地图 UI 组件：显示玩家位置、高风险区边界及被唤醒的敌人红点警示。
# 2D HUD minimap for expedition bounds, obstacles, spawn points, and player heading.
# [AI-ASSISTED] 2026-05-22 - Based on docs/polish_plan.md Plan 2.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
class_name Minimap
extends Control

const MAP_SIZE := Vector2(240.0, 120.0)
const PLAYER_DOT_RADIUS := 4.0
const SPAWN_DOT_RADIUS := 2.5
const OBSTACLE_HALF_SIZE := Vector2(2.5, 2.5)

var _world_bounds := Rect2(Vector2(-300.0, -175.0), Vector2(600.0, 350.0))
var _obstacle_positions: Array[Vector2] = []
var _spawn_points: Array[Vector3] = []
var _player: Node3D = null
var _map_node: Node = null
var _spawn_manager: Node = null
var _static_data_loaded: bool = false


func _ready() -> void:
	custom_minimum_size = MAP_SIZE
	size = MAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_player()
	_refresh_static_sources()


func _process(_delta: float) -> void:
	if not visible:
		return
	_bind_player()
	if not _static_data_loaded:
		_refresh_static_sources()
	queue_redraw()


func world_to_minimap(world_pos: Vector3) -> Vector2:
	var ratio := (Vector2(world_pos.x, world_pos.z) - _world_bounds.position) / _world_bounds.size
	return Vector2(clampf(ratio.x, 0.0, 1.0), clampf(ratio.y, 0.0, 1.0)) * MAP_SIZE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.025, 0.035, 0.032, 0.74), true)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.40, 0.50, 0.42, 0.62), false, 1.0)
	for obstacle_pos in _obstacle_positions:
		var minimap_pos := world_to_minimap(Vector3(obstacle_pos.x, 0.0, obstacle_pos.y))
		draw_rect(
			Rect2(minimap_pos - OBSTACLE_HALF_SIZE, OBSTACLE_HALF_SIZE * 2.0),
			Color(0.32, 0.34, 0.31, 0.84),
			true
		)
	for spawn_point in _spawn_points:
		draw_circle(world_to_minimap(spawn_point), SPAWN_DOT_RADIUS, Color(1.0, 0.28, 0.18, 0.86))
	_draw_player()


func _draw_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center := world_to_minimap(_player.global_position)
	var forward := Vector2(-_player.global_transform.basis.z.x, -_player.global_transform.basis.z.z)
	if forward.length_squared() < 0.01:
		forward = Vector2.UP
	forward = forward.normalized()
	var right := forward.rotated(PI * 0.5)
	var points := PackedVector2Array([
		center + forward * 8.0,
		center - forward * 5.0 + right * 4.0,
		center - forward * 5.0 - right * 4.0,
	])
	draw_colored_polygon(points, Color(0.34, 0.94, 0.55, 0.96))
	draw_circle(center, PLAYER_DOT_RADIUS, Color(0.08, 0.18, 0.10, 0.86))


func _bind_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D


func _refresh_static_sources() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _map_node == null or not is_instance_valid(_map_node):
		_map_node = scene.get_node_or_null("World/ExpeditionMap")
	if _map_node != null:
		if _map_node.has_method("get_bounds"):
			_world_bounds = _map_node.get_bounds()
		if _map_node.has_method("collect_obstacle_positions"):
			_obstacle_positions = _map_node.collect_obstacle_positions()
	if _spawn_manager == null or not is_instance_valid(_spawn_manager):
		_spawn_manager = scene.get_node_or_null("SpawnManager")
	if _spawn_manager != null and _spawn_manager.has_method("get_spawn_points"):
		_spawn_points = _spawn_manager.get_spawn_points()
	_static_data_loaded = _map_node != null and _spawn_manager != null
