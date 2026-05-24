# afterglow_map.gd
# Self-contained Afterglow Express (母车) map script.
# Owns: warehouse/departure interactions, collision management.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
# [AI-ASSISTED] 2026-05-23 — 添加甲板边界墙壁和出发门碰撞体
extends Node3D

const INTERACTION_RANGE := 1.5
const DEPARTURE_HOLD_TIME := 1.4

# 甲板尺寸（与 .tscn 中 Box_deck size 一致）
const DECK_WIDTH := 92.0
const DECK_DEPTH := 52.0
const WALL_HEIGHT := 2.5
const WALL_THICKNESS := 0.5

var _player: Node3D = null
var _hud: Node = null
var _world_prompt: Label3D = null
var _departure_hold: float = 0.0
var _active_point: String = ""
var _walls_built: bool = false


func _ready() -> void:
	if not _walls_built:
		_build_boundary_walls()
		_walls_built = true


func activate(player: Node3D, hud: Node, world_prompt: Label3D = null) -> void:
	_player = player
	_hud = hud
	_world_prompt = world_prompt
	_departure_hold = 0.0
	_active_point = ""
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_collision_active(true)


func deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_set_collision_active(false)
	_hide_progress()
	_departure_hold = 0.0
	_active_point = ""


func update(_delta: float) -> void:
	if _player == null:
		return
	_update_interactions(_delta)


## Test helper: place the player near a named interaction point.
func set_player_near_point(point_name: String) -> void:
	var point := _get_point(point_name)
	if point == null or _player == null:
		return
	_player.global_position = point.global_position + Vector3(0.0, 0.0, 1.25)
	GameManager.player_position = _player.global_position
	_update_interactions(0.0)


## Test helper: immediately complete the departure hold.
func complete_departure_for_test() -> void:
	_begin_expedition()


func get_active_point() -> String:
	return _active_point


# ---------------------------------------------------------------------------
# Interactions
# ---------------------------------------------------------------------------

func _update_interactions(delta: float) -> void:
	if _player == null:
		return
	var nearby := _find_nearby_point()
	_active_point = nearby
	if nearby == "warehouse":
		_departure_hold = 0.0
		_set_prompt_text("E 打开仓库")
		if Input.is_action_just_pressed("interact") and not GameManager.ui_blocking_input:
			if _hud != null and _hud.has_method("open_storage"):
				_hud.open_storage()
	elif nearby == "departure":
		var departure_point := _get_point("departure")
		var prompt_pos := (
			departure_point.global_position + Vector3(0.0, 0.6, -2.5)
			if departure_point != null
			else Vector3(32.0, 0.8, 10.5)
		)
		if GameManager.ui_blocking_input:
			_departure_hold = 0.0
			_set_prompt_text("")
			_hide_progress()
			return
		if Input.is_action_pressed("interact"):
			_departure_hold += delta
			var ratio := clampf(_departure_hold / DEPARTURE_HOLD_TIME, 0.0, 1.0)
			_set_prompt_text("长按 E  出发", prompt_pos)
			_show_progress(ratio, "出发中  %d%%" % int(round(ratio * 100.0)))
			if ratio >= 1.0:
				_hide_progress()
				_begin_expedition()
		else:
			_departure_hold = 0.0
			_set_prompt_text("")
			_hide_progress()
	else:
		_departure_hold = 0.0
		_set_prompt_text("")


func _find_nearby_point() -> String:
	if _player == null:
		return ""
	var p_pos := _player.global_position
	
	# WarehouseArea 所在的透明地块 (中心 x=-31, z=13, 尺寸 20x20)
	var w_rect := Rect2(-31.0 - 10.0, 13.0 - 10.0, 20.0, 20.0)
	if w_rect.has_point(Vector2(p_pos.x, p_pos.z)):
		return "warehouse"
		
	# DepartureHatchArea 所在的深色地块 (中心 x=32, z=13, 尺寸 19x18)
	var d_rect := Rect2(32.0 - 9.5, 13.0 - 9.0, 19.0, 18.0)
	if d_rect.has_point(Vector2(p_pos.x, p_pos.z)):
		return "departure"
		
	return ""


func _get_point(point_name: String) -> Node3D:
	match point_name:
		"warehouse":
			return get_node_or_null("WarehousePoint") as Node3D
		"departure":
			return get_node_or_null("DeparturePoint") as Node3D
	return null


func _begin_expedition() -> void:
	_departure_hold = 0.0
	_set_prompt_text("")
	GameManager.begin_expedition()


# ---------------------------------------------------------------------------
# Collision management
# ---------------------------------------------------------------------------

func _set_collision_active(active: bool) -> void:
	for child in get_children():
		if child is CollisionObject3D:
			var body := child as CollisionObject3D
			if active:
				body.collision_layer = int(body.get_meta("_saved_collision_layer", body.collision_layer))
			else:
				if body.collision_layer > 0:
					body.set_meta("_saved_collision_layer", body.collision_layer)
				body.collision_layer = 0


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _set_prompt_text(text: String, world_position: Vector3 = Vector3.INF) -> void:
	if _hud != null and _hud.has_method("set_prompt_text"):
		_hud.set_prompt_text(text)
	if _world_prompt == null:
		return
	_world_prompt.text = text
	_world_prompt.visible = text.strip_edges() != ""
	if _world_prompt.visible:
		var target_pos := world_position
		if target_pos == Vector3.INF:
			target_pos = (
				_player.global_position + Vector3(0.0, 0.0, 2.8)
				if _player != null
				else Vector3.ZERO
			)
		var y := 0.09 if world_position == Vector3.INF else maxf(target_pos.y + 0.01, 0.09)
		_world_prompt.global_position = Vector3(target_pos.x, y, target_pos.z)


func _show_progress(ratio: float, text: String = "") -> void:
	if _hud != null and _hud.has_method("show_hold_progress"):
		_hud.show_hold_progress(ratio, text)


func _hide_progress() -> void:
	if _hud != null and _hud.has_method("hide_hold_progress"):
		_hud.hide_hold_progress()


# ---------------------------------------------------------------------------
# Boundary walls (甲板边界碰撞 + 出发门碰撞)
# ---------------------------------------------------------------------------

## 在甲板四周创建不可见碰撞墙壁，防止玩家走出船体
## 同时为 DepartureDoor 添加碰撞体
func _build_boundary_walls() -> void:
	var half_w := DECK_WIDTH * 0.5
	var half_d := DECK_DEPTH * 0.5
	var hy := WALL_HEIGHT * 0.5
	var ht := WALL_THICKNESS * 0.5

	# 北墙（-Z 方向）
	_add_wall_body("WallNorth",
		Vector3(0.0, hy, -half_d - ht),
		Vector3(DECK_WIDTH, WALL_HEIGHT, WALL_THICKNESS))
	# 南墙（+Z 方向）
	_add_wall_body("WallSouth",
		Vector3(0.0, hy, half_d + ht),
		Vector3(DECK_WIDTH, WALL_HEIGHT, WALL_THICKNESS))
	# 西墙（-X 方向）
	_add_wall_body("WallWest",
		Vector3(-half_w - ht, hy, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, DECK_DEPTH + WALL_THICKNESS * 2.0))
	# 东墙（+X 方向）
	_add_wall_body("WallEast",
		Vector3(half_w + ht, hy, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, DECK_DEPTH + WALL_THICKNESS * 2.0))

	# DepartureDoor 碰撞（位置/尺寸与 .tscn 中 DepartureDoor MeshInstance3D 一致）
	_add_wall_body("DepartureDoorCollision",
		Vector3(32.0, 1.3, 19.0),
		Vector3(9.0, 2.6, 1.0))


func _add_wall_body(wall_name: String, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = 4  # layer 3: Obstacles (per rules.md §3.2)
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	shape_node.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	add_child(body)
	body.global_position = pos
