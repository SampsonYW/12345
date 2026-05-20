# game_3d.gd
# 3D game root: title flow, Afterglow Express map, expedition map, and runtime setup.
extends Node3D

const PLAYER_SCENE := preload("res://scenes/player_3d.tscn")
const PATROL_ENEMY_SCENE := preload("res://scenes/patrol_enemy_3d.tscn")
const DORMANT_ENEMY_SCENE := preload("res://scenes/dormant_enemy_3d.tscn")
const CONTAINER_SCENE := preload("res://scenes/container_3d.tscn")
const EXPEDITION_MAP_SCENE := preload("res://scenes/expedition_map.tscn")
const AFTERGLOW_MAP_SCENE := preload("res://scenes/afterglow_map.tscn")
const EXTRACTION_SCRIPT := preload("res://scripts/systems/extraction.gd")
const FOG_OF_WAR_SCENE := preload("res://scenes/fog_of_war.tscn")
const SPAWN_MANAGER_SCRIPT := preload("res://scripts/managers/spawn_manager.gd")
const ItemDataResource := preload("res://scripts/items/item_data.gd")

const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const CAMERA_OFFSET := Vector3(0.0, 18.0, 18.0)
const AFTERGLOW_INTERACTION_RANGE := 3.25
const AFTERGLOW_DEPARTURE_HOLD_TIME := 1.4
const EXPEDITION_BOUNDS := Rect2(Vector2(-240.0, -120.0), Vector2(480.0, 240.0))
const OBSTACLE_DATA := [
	{ "pos": Vector3(-72.0, 0.75, -30.0), "size": Vector3(18.0, 1.5, 7.0) },
	{ "pos": Vector3(-42.0, 0.7, 32.0), "size": Vector3(11.0, 1.4, 16.0) },
	{ "pos": Vector3(-6.0, 0.6, -52.0), "size": Vector3(24.0, 1.2, 5.0) },
	{ "pos": Vector3(28.0, 0.75, 22.0), "size": Vector3(13.0, 1.5, 13.0) },
	{ "pos": Vector3(64.0, 0.9, -10.0), "size": Vector3(9.0, 1.8, 27.0) },
	{ "pos": Vector3(96.0, 0.75, 48.0), "size": Vector3(22.0, 1.5, 8.0) },
	{ "pos": Vector3(-126.0, 0.65, 52.0), "size": Vector3(14.0, 1.3, 18.0) },
	{ "pos": Vector3(142.0, 0.85, -54.0), "size": Vector3(18.0, 1.7, 12.0) },
]
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
]

var _player: Node3D = null
var _spawn_manager: Node = null
var _fog_of_war: Node3D = null
var _afterglow_map: Node3D = null
var _expedition_map: Node3D = null
var _departure_hold: float = 0.0
var _active_afterglow_point: String = ""

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _ground: StaticBody3D = $World/Ground
@onready var _enemies: Node3D = $Entities/Enemies
@onready var _containers: Node3D = $Entities/Containers
@onready var _pickups: Node3D = $Entities/Pickups
@onready var _projectiles: Node3D = $Entities/Projectiles
@onready var _obstacles: Node3D = $World/Obstacles
@onready var _hud: Node = $UI/HUD
@onready var _world_prompt: Label3D = $World/WorldPrompt


func _ready() -> void:
	_ensure_map_roots()
	_spawn_player()
	_build_afterglow_map()
	_build_expedition_map()
	_add_spawn_manager()
	_add_fog_of_war()
	_add_extraction_system()
	if not GameManager.state_changed.is_connected(_on_game_state_changed):
		GameManager.state_changed.connect(_on_game_state_changed)
	if not GameManager.location_changed.is_connected(_on_location_changed):
		GameManager.location_changed.connect(_on_location_changed)
	_apply_location(GameManager.current_location)
	if GameManager.current_state == GameManager.State.RUNNING:
		_spawn_enemies()
	_update_camera()


func _process(delta: float) -> void:
	_update_camera()
	match GameManager.current_location:
		GameManager.Location.AFTERGLOW:
			_update_afterglow_interactions(delta)
		GameManager.Location.EXPEDITION:
			_update_risk_label()
			_update_expedition_interactions()


func get_active_map_name() -> String:
	match GameManager.current_location:
		GameManager.Location.TITLE:
			return "title"
		GameManager.Location.AFTERGLOW:
			return "afterglow"
		GameManager.Location.EXPEDITION:
			return "expedition"
	return "unknown"


func set_player_near_afterglow_point(point_name: String) -> void:
	var point := _get_afterglow_point(point_name)
	if point == null or _player == null:
		return
	_player.global_position = point.global_position + Vector3(0.0, 0.0, 1.25)
	GameManager.player_position = _player.global_position
	_update_afterglow_interactions(0.0)


func complete_departure_hold_for_test() -> void:
	if GameManager.current_location == GameManager.Location.AFTERGLOW:
		_begin_expedition_from_afterglow()


func get_expedition_bounds() -> Rect2:
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


func get_player_risk_label() -> String:
	var risk := "Low Risk"
	if _player == null:
		return risk
	var pos := Vector2(_player.global_position.x, _player.global_position.z)
	for zone in RISK_ZONE_DATA:
		if _zone_contains(zone, pos):
			risk = "High Risk" if zone.get("risk", "") == "high" else "Low Risk"
	return risk


func _ensure_map_roots() -> void:
	_afterglow_map = $World.get_node_or_null("AfterglowMap") as Node3D
	if _afterglow_map == null:
		_afterglow_map = AFTERGLOW_MAP_SCENE.instantiate() as Node3D
		_afterglow_map.name = "AfterglowMap"
		$World.add_child(_afterglow_map)
	_expedition_map = $World.get_node_or_null("ExpeditionMap") as Node3D
	if _expedition_map == null:
		_expedition_map = EXPEDITION_MAP_SCENE.instantiate() as Node3D
		_expedition_map.name = "ExpeditionMap"
		$World.add_child(_expedition_map)

		# Wire preplaced containers inside the scene to the global _containers group
		var map_containers = _expedition_map.get_node_or_null("Containers")
		if map_containers != null and _containers != null:
			for child in map_containers.get_children():
				map_containers.remove_child(child)
				_containers.add_child(child)
				if child.has_signal("cracked") and not child.cracked.is_connected(_on_container_cracked):
					child.cracked.connect(_on_container_cracked)
				if "risk" in child:
					child.set_meta("risk", child.risk)


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player3D"
	$Entities.add_child(_player)
	_player.global_position = Vector3.ZERO
	GameManager.player_position = _player.global_position


func _build_afterglow_map() -> void:
	if _afterglow_map.scene_file_path != "":
		return
	_clear_children(_afterglow_map)
	_add_visual_box(_afterglow_map, "AfterglowDeck", Vector3(0.0, -0.02, 0.0), Vector3(92.0, 0.08, 52.0), Color(0.16, 0.20, 0.18, 1.0))
	_add_visual_box(_afterglow_map, "CockpitStatusArea", Vector3(0.0, 0.08, -19.0), Vector3(34.0, 0.16, 12.0), Color(0.18, 0.28, 0.30, 1.0))
	_add_visual_box(_afterglow_map, "RestCommonArea", Vector3(0.0, 0.08, 0.0), Vector3(30.0, 0.16, 18.0), Color(0.20, 0.23, 0.18, 1.0))
	_add_visual_box(_afterglow_map, "WarehouseArea", Vector3(-31.0, 0.08, 13.0), Vector3(20.0, 0.16, 20.0), Color(0.28, 0.22, 0.16, 0.42))
	_add_visual_box(_afterglow_map, "DepartureHatchArea", Vector3(32.0, 0.08, 13.0), Vector3(19.0, 0.16, 18.0), Color(0.20, 0.24, 0.31, 1.0))
	_add_visual_box(_afterglow_map, "WarehouseCrates", Vector3(-31.0, 1.0, 13.0), Vector3(7.0, 2.0, 5.0), Color(0.38, 0.30, 0.20, 1.0))
	_add_static_collision_box(_afterglow_map, "WarehouseCollision", Vector3(-31.0, 1.0, 13.0), Vector3(7.0, 2.0, 5.0))
	_add_visual_box(_afterglow_map, "DepartureDoor", Vector3(32.0, 1.3, 19.0), Vector3(9.0, 2.6, 1.0), Color(0.32, 0.42, 0.50, 1.0))
	_add_afterglow_point("WarehousePoint", Vector3(-31.0, 0.1, 7.0), Color(0.9, 0.62, 0.22, 1.0))
	_add_afterglow_point("DeparturePoint", Vector3(32.0, 0.1, 10.0), Color(0.38, 0.78, 1.0, 1.0))
	_add_label3d(_afterglow_map, "ControlsHint", "WASD Move  E Interact  B Backpack  Q Signal Flare", Vector3(0.0, 0.08, -2.0), Color(0.84, 0.92, 0.88, 1.0))
	_add_label3d(_afterglow_map, "WarehouseHint", "E Open Storage", Vector3(-31.0, 0.17, 9.0), Color(1.0, 0.76, 0.35, 1.0))
	_add_label3d(_afterglow_map, "DepartureHint", "Hold E Depart", Vector3(32.0, 0.17, 12.0), Color(0.58, 0.86, 1.0, 1.0))
	_add_label3d(_afterglow_map, "CockpitHint", "AFTERGLOW EXPRESS", Vector3(0.0, 0.08, -24.0), Color(0.93, 0.88, 0.68, 1.0))


func _build_expedition_map() -> void:
	if _expedition_map.scene_file_path != "":
		return
	_resize_ground_for_expedition()
	_clear_children(_expedition_map)
	_spawn_obstacles()
	_spawn_containers()
	_add_zone_visuals()


func _resize_ground_for_expedition() -> void:
	_ground.global_position = Vector3(
		EXPEDITION_BOUNDS.position.x + EXPEDITION_BOUNDS.size.x * 0.5,
		-0.05,
		EXPEDITION_BOUNDS.position.y + EXPEDITION_BOUNDS.size.y * 0.5
	)
	var ground_visual := _ground.get_node_or_null("GroundVisual") as MeshInstance3D
	if ground_visual != null and ground_visual.mesh is BoxMesh:
		(ground_visual.mesh as BoxMesh).size = Vector3(EXPEDITION_BOUNDS.size.x, 0.1, EXPEDITION_BOUNDS.size.y)
	var collision := _ground.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		(collision.shape as BoxShape3D).size = Vector3(EXPEDITION_BOUNDS.size.x, 0.1, EXPEDITION_BOUNDS.size.y)


func _spawn_obstacles() -> void:
	_clear_children(_obstacles)
	for data in OBSTACLE_DATA:
		var body := StaticBody3D.new()
		body.name = "Obstacle3D"
		body.position = data.pos
		body.collision_layer = 4
		body.collision_mask = 0

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = data.size
		collision.shape = shape
		body.add_child(collision)

		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = data.size
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _make_material(Color(0.28, 0.27, 0.25, 1.0))
		body.add_child(mesh_instance)

		_obstacles.add_child(body)


func _spawn_containers() -> void:
	_clear_children(_containers)
	var data := [
		{ "pos": Vector3(-172.0, 0.0, -58.0), "loot": [ITEM_AMMO, ITEM_BATTERY], "risk": "low" },
		{ "pos": Vector3(-116.0, 0.0, 44.0), "loot": [ITEM_BATTERY], "risk": "low" },
		{ "pos": Vector3(-28.0, 0.0, -36.0), "loot": [ITEM_AMMO, ITEM_RELIC], "risk": "low" },
		{ "pos": Vector3(34.0, 0.0, -72.0), "loot": [ITEM_BATTERY, ITEM_AMMO], "risk": "low" },
		{ "pos": Vector3(96.0, 0.0, -42.0), "loot": [ITEM_RELIC, ITEM_RELIC, ITEM_AMMO], "risk": "high" },
		{ "pos": Vector3(148.0, 0.0, 38.0), "loot": [ITEM_PURIFIER, ITEM_RELIC], "risk": "high" },
		{ "pos": Vector3(46.0, 0.0, 72.0), "loot": [ITEM_RELIC, ITEM_PURIFIER, ITEM_AMMO], "risk": "high" },
		{ "pos": Vector3(12.0, 0.0, 96.0), "loot": [ITEM_RELIC, ITEM_RELIC, ITEM_PURIFIER], "risk": "high" },
	]
	for entry in data:
		var container: Node3D = CONTAINER_SCENE.instantiate()
		container.position = entry.pos
		container.set_meta("risk", entry.risk)
		var typed_loot: Array[ItemDataResource] = []
		typed_loot.assign(entry.loot)
		container.loot_table = typed_loot
		if container.has_signal("cracked"):
			container.cracked.connect(_on_container_cracked)
		_containers.add_child(container)


func _add_zone_visuals() -> void:
	for zone in RISK_ZONE_DATA:
		var color := Color(0.12, 0.23, 0.16, 0.32)
		if zone.get("risk", "") == "high":
			color = Color(0.35, 0.10, 0.12, 0.34)
		var center: Vector2 = zone.get("center")
		var size: Vector2 = zone.get("size")
		_add_visual_box(
			_expedition_map,
			"%sZone" % String(zone.get("name", "Risk")),
			Vector3(center.x, 0.015, center.y),
			Vector3(size.x, 0.03, size.y),
			color
		)
		_add_label3d(
			_expedition_map,
			"%sLabel" % String(zone.get("name", "Risk")),
			"%s  %s" % [String(zone.get("name", "Zone")), String(zone.get("risk", "risk")).to_upper()],
			Vector3(center.x, 0.08, center.y),
			Color(0.92, 0.88, 0.72, 1.0)
		)


func _spawn_enemies() -> void:
	if _spawn_manager != null and _spawn_manager.has_method("seed_initial_enemies"):
		_spawn_manager.seed_initial_enemies()


func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.RUNNING:
		_spawn_enemies()


func _on_location_changed(location: int) -> void:
	_apply_location(location)


func _apply_location(location: int) -> void:
	var expedition_active := location == GameManager.Location.EXPEDITION
	var afterglow_active := location == GameManager.Location.AFTERGLOW
	_afterglow_map.visible = afterglow_active
	_expedition_map.visible = expedition_active
	_ground.visible = expedition_active and _expedition_map.scene_file_path == ""
	_obstacles.visible = expedition_active and _expedition_map.scene_file_path == ""
	_containers.visible = expedition_active
	_enemies.visible = expedition_active
	_pickups.visible = expedition_active
	_projectiles.visible = expedition_active
	if _fog_of_war != null:
		_fog_of_war.visible = expedition_active
		_fog_of_war.process_mode = Node.PROCESS_MODE_INHERIT if expedition_active else Node.PROCESS_MODE_DISABLED
		if not expedition_active and _fog_of_war.has_method("clear_trail"):
			_fog_of_war.clear_trail()
	_set_branch_process(_containers, expedition_active)
	_set_branch_process(_enemies, expedition_active)
	_set_branch_process(_pickups, expedition_active)
	_set_branch_process(_projectiles, expedition_active)
	_departure_hold = 0.0
	_active_afterglow_point = ""
	if location == GameManager.Location.AFTERGLOW:
		_clear_children(_enemies)
		if _player != null:
			_player.global_position = Vector3(0.0, 0.0, 5.0)
			GameManager.player_position = _player.global_position
		_set_prompt_text("")
		_set_risk_label_text("Afterglow Express")
	elif location == GameManager.Location.EXPEDITION:
		if _player != null:
			_player.global_position = Vector3.ZERO
			GameManager.player_position = _player.global_position
		_set_prompt_text("")
		_update_risk_label()
	else:
		_clear_children(_enemies)
		_set_prompt_text("")
		_set_risk_label_text("Title")


func _set_branch_process(node: Node, active: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _update_afterglow_interactions(delta: float) -> void:
	if _player == null:
		return
	var nearby := _find_nearby_afterglow_point()
	_active_afterglow_point = nearby
	if nearby == "warehouse":
		_departure_hold = 0.0
		var warehouse_point := _get_afterglow_point("warehouse")
		if _hud != null and _hud.has_method("set_prompt_text"):
			_hud.set_prompt_text("E Open Storage")
		if _world_prompt != null:
			_world_prompt.visible = false
		if Input.is_action_pressed("interact") and not GameManager.ui_blocking_input:
			if _hud != null and _hud.has_method("open_storage"):
				_hud.open_storage()
	elif nearby == "departure":
		var departure_point := _get_afterglow_point("departure")
		var prompt_position := Vector3(32.0, 0.17, 12.0)
		if GameManager.ui_blocking_input:
			_departure_hold = 0.0
			_set_prompt_text("")
			return
		if Input.is_action_pressed("interact"):
			_departure_hold += delta
			var ratio := clampf(_departure_hold / AFTERGLOW_DEPARTURE_HOLD_TIME, 0.0, 1.0)
			_set_prompt_text("Hold E Depart  %d%%" % int(round(ratio * 100.0)), prompt_position)
			if ratio >= 1.0:
				_begin_expedition_from_afterglow()
		else:
			_departure_hold = 0.0
			_set_prompt_text("")
	else:
		_departure_hold = 0.0
		_set_prompt_text("")


func _find_nearby_afterglow_point() -> String:
	var warehouse := _get_afterglow_point("warehouse")
	var departure := _get_afterglow_point("departure")
	if warehouse != null and _player.global_position.distance_to(warehouse.global_position) <= AFTERGLOW_INTERACTION_RANGE:
		return "warehouse"
	if departure != null and _player.global_position.distance_to(departure.global_position) <= AFTERGLOW_INTERACTION_RANGE:
		return "departure"
	return ""


func _get_afterglow_point(point_name: String) -> Node3D:
	match point_name:
		"warehouse":
			return _afterglow_map.get_node_or_null("WarehousePoint") as Node3D
		"departure":
			return _afterglow_map.get_node_or_null("DeparturePoint") as Node3D
	return null


func _begin_expedition_from_afterglow() -> void:
	_departure_hold = 0.0
	_set_prompt_text("")
	GameManager.begin_expedition()


func _update_risk_label() -> void:
	_set_risk_label_text("Risk  %s" % get_player_risk_label())


func _update_expedition_interactions() -> void:
	if GameManager.ui_blocking_input:
		return
	var container := _find_nearby_container()
	if container == null:
		_set_prompt_text("")
		return
	if container.has_method("is_opened") and container.is_opened():
		_set_prompt_text("E Search", (container as Node3D).global_position + Vector3(0.0, 0.0, 1.8))
		if Input.is_action_just_pressed("interact") and _hud != null and _hud.has_method("open_container_search"):
			_hud.open_container_search(container)
	else:
		_set_prompt_text("Hold E Open", (container as Node3D).global_position + Vector3(0.0, 0.0, 1.8))


func _find_nearby_container() -> Node:
	if _player == null:
		return null
	for container in _containers.get_children():
		if container is Node3D and _player.global_position.distance_to((container as Node3D).global_position) <= 3.2:
			return container
	return null


func _on_container_cracked(container: StaticBody3D) -> void:
	if _hud != null and _hud.has_method("open_container_search"):
		_hud.open_container_search(container)


func _add_extraction_system() -> void:
	if get_node_or_null("Extraction") != null:
		return
	var extraction := Node3D.new()
	extraction.name = "Extraction"
	extraction.set_script(EXTRACTION_SCRIPT)
	add_child(extraction)


func _add_spawn_manager() -> void:
	var existing := get_node_or_null("SpawnManager")
	if existing != null:
		_spawn_manager = existing
	else:
		_spawn_manager = Node3D.new()
		_spawn_manager.name = "SpawnManager"
		_spawn_manager.set_script(SPAWN_MANAGER_SCRIPT)
		add_child(_spawn_manager)
	if _spawn_manager.has_method("configure"):
		_spawn_manager.configure(_enemies, PATROL_ENEMY_SCENE, DORMANT_ENEMY_SCENE)


func _add_fog_of_war() -> void:
	var existing := get_node_or_null("FogOfWar") as Node3D
	if existing != null:
		_fog_of_war = existing
		return
	var fog := FOG_OF_WAR_SCENE.instantiate() as Node3D
	add_child(fog)
	_fog_of_war = fog


func _update_camera() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_camera.global_position = _player.global_position + CAMERA_OFFSET
	_camera.look_at(_player.global_position, Vector3.UP)


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
		var target_position := world_position
		if target_position == Vector3.INF:
			target_position = _player.global_position + Vector3(0.0, 0.0, 2.8) if _player != null else Vector3.ZERO
		var target_y := target_position.y
		if world_position == Vector3.INF:
			target_y = 0.09
		else:
			if target_y <= 0.0:
				target_y = 0.09
			else:
				target_y = target_y + 0.01
		_world_prompt.global_position = Vector3(target_position.x, target_y, target_position.z)


func _set_risk_label_text(text: String) -> void:
	if _hud != null and _hud.has_method("set_risk_label_text"):
		_hud.set_risk_label_text(text)


func _add_afterglow_point(node_name: String, position: Vector3, color: Color) -> void:
	var point := Node3D.new()
	point.name = node_name
	point.position = position
	_afterglow_map.add_child(point)
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.05
	mesh.bottom_radius = 1.05
	mesh.height = 0.08
	mesh.radial_segments = 32
	marker.mesh = mesh
	marker.material_override = _make_material(color)
	point.add_child(marker)


func _add_visual_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(color)
	parent.add_child(mesh_instance)


func _add_static_collision_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = 4
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _add_label3d(parent: Node3D, node_name: String, text: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = position
	label.rotation_degrees = Vector3(49.5, 0.0, 0.0)
	label.font_size = 128
	label.modulate = color
	parent.add_child(label)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()
