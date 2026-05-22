# expedition_map.gd
# Self-contained expedition map script.
# Owns: risk zones, container wiring, container interactions, collision management.
extends Node3D

const EXPEDITION_BOUNDS := Rect2(Vector2(-300.0, -175.0), Vector2(600.0, 350.0))
const RISK_ZONE_DATA := [
	{
		"name": "Ash Outskirts",
		"center": Vector2(-132.0, 0.0),
		"size": Vector2(192.0, 210.0),
		"risk": "low",
		"enemy_density": 0.35,
		"container_density": 0.45,
		"high_value_weight": 0.15,
	},
	{
		"name": "Broken Rail",
		"center": Vector2(8.0, -22.0),
		"size": Vector2(176.0, 182.0),
		"risk": "low",
		"enemy_density": 0.55,
		"container_density": 0.65,
		"high_value_weight": 0.25,
	},
	{
		"name": "Black Yard",
		"center": Vector2(132.0, 8.0),
		"size": Vector2(184.0, 214.0),
		"risk": "high",
		"enemy_density": 1.35,
		"container_density": 1.45,
		"high_value_weight": 0.8,
	},
	{
		"name": "Core Wreck",
		"center": Vector2(32.0, 66.0),
		"size": Vector2(120.0, 92.0),
		"risk": "high",
		"enemy_density": 1.8,
		"container_density": 1.7,
		"high_value_weight": 0.95,
	},
	{
		"name": "Frozen Depot",
		"center": Vector2(-200.0, 100.0),
		"size": Vector2(140.0, 100.0),
		"risk": "low",
		"enemy_density": 0.42,
		"container_density": 0.52,
		"high_value_weight": 0.18,
	},
	{
		"name": "Silent Array",
		"center": Vector2(220.0, -80.0),
		"size": Vector2(130.0, 120.0),
		"risk": "high",
		"enemy_density": 1.55,
		"container_density": 1.6,
		"high_value_weight": 0.88,
	},
]

var _player: Node3D = null
var _hud: Node = null
var _world_prompt: Label3D = null
var _container_hint_shown: bool = false


func activate(player: Node3D, hud: Node, world_prompt: Label3D = null) -> void:
	_player = player
	_hud = hud
	_world_prompt = world_prompt
	_container_hint_shown = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_collision_active(true)
	_wire_containers()


func deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_set_collision_active(false)


func update(delta: float) -> void:
	if _player == null:
		return
	_update_risk_label()
	_update_container_interactions()


# ---------------------------------------------------------------------------
# Public queries
# ---------------------------------------------------------------------------

func get_bounds() -> Rect2:
	return EXPEDITION_BOUNDS


func get_risk_zones() -> Array:
	var zones: Array = []
	for data in RISK_ZONE_DATA:
		zones.append(data.duplicate(true))
	return zones


func get_zone_density_summary() -> Dictionary:
	var low_enemy := 0.0
	var low_container := 0.0
	var low_value := 0.0
	var low_count := 0.0
	var high_enemy := 0.0
	var high_container := 0.0
	var high_value := 0.0
	var high_count := 0.0
	for zone in RISK_ZONE_DATA:
		if zone.get("risk", "") == "high":
			high_enemy += float(zone.get("enemy_density", 0.0))
			high_container += float(zone.get("container_density", 0.0))
			high_value += float(zone.get("high_value_weight", 0.0))
			high_count += 1.0
		else:
			low_enemy += float(zone.get("enemy_density", 0.0))
			low_container += float(zone.get("container_density", 0.0))
			low_value += float(zone.get("high_value_weight", 0.0))
			low_count += 1.0
	return {
		"low_enemy_density": low_enemy / maxf(low_count, 1.0),
		"low_container_density": low_container / maxf(low_count, 1.0),
		"low_value_weight": low_value / maxf(low_count, 1.0),
		"high_enemy_density": high_enemy / maxf(high_count, 1.0),
		"high_container_density": high_container / maxf(high_count, 1.0),
		"high_value_weight": high_value / maxf(high_count, 1.0),
	}


func get_player_zone_info() -> Dictionary:
	var info := {"name": "Wasteland", "risk": "low"}
	if _player == null:
		return info
	var pos := Vector2(_player.global_position.x, _player.global_position.z)
	for zone in RISK_ZONE_DATA:
		if _zone_contains(zone, pos):
			info["name"] = zone.get("name", "")
			info["risk"] = zone.get("risk", "low")
	return info


func get_player_risk_label() -> String:
	var info := get_player_zone_info()
	return "High Risk" if info["risk"] == "high" else "Low Risk"


func get_containers_node() -> Node:
	return get_node_or_null("Containers")


func collect_obstacle_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var obstacles := get_node_or_null("Obstacles")
	if obstacles == null:
		return positions
	for child in obstacles.get_children():
		if child is Node3D:
			var node := child as Node3D
			positions.append(Vector2(node.global_position.x, node.global_position.z))
	return positions


# ---------------------------------------------------------------------------
# Container wiring
# ---------------------------------------------------------------------------

func _wire_containers() -> void:
	var containers := get_node_or_null("Containers")
	if containers == null:
		return
	for child in containers.get_children():
		if child.has_signal("cracked") and not child.cracked.is_connected(_on_container_cracked):
			child.cracked.connect(_on_container_cracked)
		if "risk" in child:
			child.set_meta("risk", child.risk)


func _on_container_cracked(container: StaticBody3D) -> void:
	if _hud != null and _hud.has_method("open_container_search"):
		_hud.open_container_search(container)


# ---------------------------------------------------------------------------
# Container interactions
# ---------------------------------------------------------------------------

func _update_container_interactions() -> void:
	if GameManager.ui_blocking_input:
		return
	var container := _find_nearby_container()
	if container == null:
		_set_prompt_text("")
		return
	var prompt_pos := (container as Node3D).global_position + Vector3(0.0, 0.0, 1.8) if container is Node3D else Vector3.INF
	if container.has_method("is_opened") and container.is_opened():
		if not _container_hint_shown:
			_set_prompt_text("E Search", prompt_pos)
		else:
			_set_prompt_text("")
		if Input.is_action_just_pressed("interact") and _hud != null and _hud.has_method("open_container_search"):
			_container_hint_shown = true
			_set_prompt_text("")
			_hud.open_container_search(container)
	else:
		if not _container_hint_shown:
			_set_prompt_text("Hold E Open", prompt_pos)
		else:
			_set_prompt_text("")


func _find_nearby_container() -> Node:
	if _player == null:
		return null
	var containers := get_node_or_null("Containers")
	if containers == null:
		return null
	for container in containers.get_children():
		if container is Node3D and _player.global_position.distance_to((container as Node3D).global_position) <= 3.2:
			return container
	return null


# ---------------------------------------------------------------------------
# Risk zone label
# ---------------------------------------------------------------------------

func _update_risk_label() -> void:
	var info := get_player_zone_info()
	if _hud != null and _hud.has_method("set_zone_info"):
		_hud.set_zone_info(info["name"], info["risk"])
	elif _hud != null and _hud.has_method("set_risk_label_text"):
		_hud.set_risk_label_text("Risk  %s" % get_player_risk_label())


# ---------------------------------------------------------------------------
# Collision management
# ---------------------------------------------------------------------------

func _set_collision_active(active: bool) -> void:
	_toggle_collision_recursive(self, active)


func _toggle_collision_recursive(node: Node, active: bool) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		if active:
			body.collision_layer = int(body.get_meta("_saved_collision_layer", body.collision_layer))
		else:
			# Only save if not already deactivated (layer > 0), to avoid
			# overwriting the saved original value on repeated deactivate calls.
			if body.collision_layer > 0:
				body.set_meta("_saved_collision_layer", body.collision_layer)
			body.collision_layer = 0
	for child in node.get_children():
		_toggle_collision_recursive(child, active)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _zone_contains(zone: Dictionary, pos: Vector2) -> bool:
	var center: Vector2 = zone.get("center")
	var size: Vector2 = zone.get("size")
	var rect := Rect2(center - size * 0.5, size)
	return rect.has_point(pos)


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
			target_pos = _player.global_position + Vector3(0.0, 0.0, 2.8) if _player != null else Vector3.ZERO
		var y := 0.09 if world_position == Vector3.INF else maxf(target_pos.y + 0.01, 0.09)
		_world_prompt.global_position = Vector3(target_pos.x, y, target_pos.z)
