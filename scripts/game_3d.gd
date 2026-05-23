# game_3d.gd
# 3D game root: thin orchestrator for maps, player, camera, and runtime systems.
# Map-specific logic lives in afterglow_map.gd and expedition_map.gd.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node3D

const PLAYER_SCENE := preload("res://scenes/player_3d.tscn")
const PATROL_ENEMY_SCENE := preload("res://scenes/patrol_enemy_3d.tscn")
const DORMANT_ENEMY_SCENE := preload("res://scenes/dormant_enemy_3d.tscn")
const EXPEDITION_MAP_SCENE := preload("res://scenes/expedition_map.tscn")
const AFTERGLOW_MAP_SCENE := preload("res://scenes/afterglow_map.tscn")
const EXTRACTION_SCRIPT := preload("res://scripts/systems/extraction.gd")
const FOG_OF_WAR_SCENE := preload("res://scenes/fog_of_war.tscn")
const SPAWN_MANAGER_SCRIPT := preload("res://scripts/managers/spawn_manager.gd")

const CAMERA_OFFSET := Vector3(0.0, 18.0, 18.0)

var _player: Node3D = null
var _spawn_manager: Node = null
var _fog_of_war: Node3D = null
var _afterglow_map: Node3D = null
var _expedition_map: Node3D = null

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _enemies: Node3D = $Entities/Enemies
@onready var _pickups: Node3D = $Entities/Pickups
@onready var _projectiles: Node3D = $Entities/Projectiles
@onready var _hud: Node = $UI/HUD
@onready var _world_prompt: Label3D = $World/WorldPrompt


func _ready() -> void:
	_ensure_map_roots()
	_spawn_player()
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
			if _afterglow_map != null:
				_afterglow_map.update(delta)
		GameManager.Location.EXPEDITION:
			if _expedition_map != null:
				_expedition_map.update(delta)


# ---------------------------------------------------------------------------
# Public API (test-facing, delegates to map scripts)
# ---------------------------------------------------------------------------

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
	if _afterglow_map != null and _afterglow_map.has_method("set_player_near_point"):
		_afterglow_map.set_player_near_point(point_name)


func complete_departure_hold_for_test() -> void:
	if _afterglow_map != null and _afterglow_map.has_method("complete_departure_for_test"):
		_afterglow_map.complete_departure_for_test()


func get_expedition_bounds() -> Rect2:
	if _expedition_map != null and _expedition_map.has_method("get_bounds"):
		return _expedition_map.get_bounds()
	return Rect2()


func get_risk_zones() -> Array:
	if _expedition_map != null and _expedition_map.has_method("get_risk_zones"):
		return _expedition_map.get_risk_zones()
	return []


func get_zone_density_summary() -> Dictionary:
	if _expedition_map != null and _expedition_map.has_method("get_zone_density_summary"):
		return _expedition_map.get_zone_density_summary()
	return {}


func get_player_zone_info() -> Dictionary:
	if _expedition_map != null and _expedition_map.has_method("get_player_zone_info"):
		return _expedition_map.get_player_zone_info()
	return {"name": "", "risk": "low"}


func get_player_risk_label() -> String:
	if _expedition_map != null and _expedition_map.has_method("get_player_risk_label"):
		return _expedition_map.get_player_risk_label()
	return "低风险"


# ---------------------------------------------------------------------------
# Scene setup
# ---------------------------------------------------------------------------

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


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player3D"
	$Entities.add_child(_player)
	_player.global_position = Vector3.ZERO
	GameManager.player_position = _player.global_position


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


func _spawn_enemies() -> void:
	if _spawn_manager != null and _spawn_manager.has_method("seed_initial_enemies"):
		_spawn_manager.seed_initial_enemies()


# ---------------------------------------------------------------------------
# State & location callbacks
# ---------------------------------------------------------------------------

func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.RUNNING:
		_spawn_enemies()


func _on_location_changed(location: int) -> void:
	_apply_location(location)


func _apply_location(location: int) -> void:
	var expedition_active := location == GameManager.Location.EXPEDITION
	var afterglow_active := location == GameManager.Location.AFTERGLOW

	# Deactivate all maps first
	if _afterglow_map != null and _afterglow_map.has_method("deactivate"):
		_afterglow_map.deactivate()
	if _expedition_map != null and _expedition_map.has_method("deactivate"):
		_expedition_map.deactivate()

	# Reset player health when switching locations (fixes HP persisting across runs)
	_reset_player_health()

	# Activate target map
	if afterglow_active and _afterglow_map != null and _afterglow_map.has_method("activate"):
		_afterglow_map.activate(_player, _hud, _world_prompt)
		if _player != null:
			_player.global_position = Vector3(0.0, 0.0, 5.0)
			GameManager.player_position = _player.global_position
		_set_risk_label_text("余晖号")
	elif expedition_active:
		# Reset expedition map state (containers, loot) without re-instantiating
		_reset_expedition_map()
		if _expedition_map != null and _expedition_map.has_method("activate"):
			_expedition_map.activate(_player, _hud, _world_prompt)
		# 构建 A* 寻路网格（延迟到下一物理帧，确保障碍物已注册）
		if _expedition_map != null and _expedition_map.has_method("get_bounds"):
			PathfindManager.build_grid(_expedition_map.get_bounds())
		if _player != null:
			_player.global_position = Vector3.ZERO
			GameManager.player_position = _player.global_position
	else:
		# Title state
		_clear_children(_enemies)
		_set_risk_label_text("标题")

	# Clear expedition-only entities on every transition so nothing leaks
	if not expedition_active:
		_clear_children(_enemies)
		_clear_children(_pickups)
		_clear_children(_projectiles)

	# Expedition-only entities & systems
	_enemies.visible = expedition_active
	_pickups.visible = expedition_active
	_projectiles.visible = expedition_active
	_set_branch_process(_enemies, expedition_active)
	_set_branch_process(_pickups, expedition_active)
	_set_branch_process(_projectiles, expedition_active)

	if _fog_of_war != null:
		_fog_of_war.visible = expedition_active
		_fog_of_war.process_mode = (
			Node.PROCESS_MODE_INHERIT if expedition_active
			else Node.PROCESS_MODE_DISABLED
		)

	_set_prompt_text("")


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _update_camera() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_camera.global_position = _player.global_position + CAMERA_OFFSET
	_camera.look_at(_player.global_position, Vector3.UP)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _set_branch_process(node: Node, active: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _set_prompt_text(text: String) -> void:
	if _hud != null and _hud.has_method("set_prompt_text"):
		_hud.set_prompt_text(text)
	if _world_prompt == null:
		return
	_world_prompt.text = text
	_world_prompt.visible = text.strip_edges() != ""
	if _world_prompt.visible:
		var target_position := (
			_player.global_position + Vector3(0.0, 0.0, 2.8)
			if _player != null
			else Vector3.ZERO
		)
		_world_prompt.global_position = Vector3(target_position.x, 0.09, target_position.z)


func _set_risk_label_text(text: String) -> void:
	if _hud != null and _hud.has_method("set_risk_label_text"):
		_hud.set_risk_label_text(text)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _reset_player_health() -> void:
	if _player == null:
		return
	var ph: Node = _player.get_node_or_null("PlayerHealth")
	if ph != null and ph.has_method("reset_health"):
		ph.reset_health()


func _reset_expedition_map() -> void:
	if _expedition_map != null and _expedition_map.has_method("reset"):
		_expedition_map.reset()
