# enemy_3d.gd
# 3D 敌人基类：巡逻型主动游走追击，休眠型靠噪音/受击唤醒，近身攻击 PlayerHealth。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写敌人占位逻辑
extends CharacterBody3D

signal died(enemy: CharacterBody3D)

enum EnemyType { PATROL, DORMANT }
enum State { PATROL, SLEEP, CHASE, ATTACK }

const GAME_STATE_RUNNING := 1
const GAME_STATE_EXTRACTING := 2
const FALLBACK_EROSION_STAT_MULTIPLIER := [1.0, 1.0, 1.1, 1.2, 1.35]
const ALERT_BAR_WIDTH := 1.0
const ALERT_BAR_HEIGHT := 0.08
const ALERT_BAR_DEPTH := 0.04
const HP_BAR_WIDTH := 1.0
const HP_BAR_HEIGHT := 0.08
const HP_BAR_DEPTH := 0.04

@export var alert_threshold: float = 100.0
@export var decay_rate: float = 5.0
@export var base_hp: float = 40.0
@export var base_damage: float = 15.0
@export var enemy_type: EnemyType = EnemyType.PATROL
@export var patrol_speed: float = 2.2
@export var chase_speed: float = 4.2
@export var patrol_radius: float = 5.0
@export var view_angle: float = 60.0
@export var view_range: float = 8.0
@export var vision_obstacle_mask: int = 4
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.0

var _current_alert: float = 0.0
var _is_awake: bool = false
var _erosion_tier: int = 0
var _current_hp: float = 0.0
var _state: State = State.SLEEP
var _attack_timer: float = 0.0
var _home_position: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _player_cache: Node3D = null
var _alert_bar: Node3D = null
var _alert_bar_fill: MeshInstance3D = null
var _hp_bar: Node3D = null
var _hp_bar_fill: MeshInstance3D = null
var _game_manager_cache: Node = null
var _has_signal_focus: bool = false
var _signal_focus_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("enemies")
	_ensure_alert_bar()
	_ensure_hp_bar()
	_home_position = global_position
	_state = State.PATROL if enemy_type == EnemyType.PATROL else State.SLEEP
	_is_awake = enemy_type == EnemyType.PATROL
	_erosion_tier = _get_erosion_tier()
	_current_hp = get_scaled_hp()
	_pick_patrol_target()
	_update_alert_bar()
	_update_hp_bar()


func _process(delta: float) -> void:
	if not _is_awake and _current_alert > 0.0:
		_current_alert = maxf(0.0, _current_alert - decay_rate * delta)
		_update_alert_bar()


func _physics_process(delta: float) -> void:
	if not _is_gameplay_active():
		velocity = Vector3.ZERO
		return
	var player := _get_player()
	if player == null:
		if _has_signal_focus:
			_update_signal_focus()
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		# Clamp to ground level to prevent riding up on obstacles
		global_position.y = 0.0
		return
	match _state:
		State.PATROL:
			_update_patrol(player)
		State.SLEEP:
			velocity = Vector3.ZERO
		State.CHASE:
			_update_chase(player)
		State.ATTACK:
			_update_attack(delta, player)
	move_and_slide()
	# Clamp to ground level to prevent riding up on obstacles
	global_position.y = 0.0


func get_enemy_kind() -> String:
	return "patrol" if enemy_type == EnemyType.PATROL else "dormant"


func is_awake() -> bool:
	return _is_awake


func get_alert_ratio() -> float:
	if alert_threshold <= 0.0:
		return 1.0 if _current_alert > 0.0 else 0.0
	return clampf(_current_alert / alert_threshold, 0.0, 1.0)


func get_hp_ratio() -> float:
	var max_hp := get_scaled_hp()
	if max_hp <= 0.0:
		return 0.0
	return clampf(_current_hp / max_hp, 0.0, 1.0)


func get_signal_focus_position() -> Vector3:
	return _signal_focus_position


func get_ai_state_name() -> String:
	match _state:
		State.PATROL:
			return "PATROL"
		State.SLEEP:
			return "SLEEP"
		State.CHASE:
			return "CHASE"
		State.ATTACK:
			return "ATTACK"
	return "UNKNOWN"


func get_scaled_hp() -> float:
	return base_hp * FALLBACK_EROSION_STAT_MULTIPLIER[_erosion_tier]


func get_scaled_damage() -> float:
	return base_damage * FALLBACK_EROSION_STAT_MULTIPLIER[_erosion_tier]


func set_erosion_tier(tier: int) -> void:
	_erosion_tier = clampi(tier, 0, FALLBACK_EROSION_STAT_MULTIPLIER.size() - 1)
	_current_hp = get_scaled_hp()
	_update_hp_bar()


func receive_noise(value: float) -> void:
	if _is_awake:
		return
	_current_alert = maxf(0.0, _current_alert + value)
	if _current_alert >= alert_threshold:
		force_awaken()
	else:
		_update_alert_bar()


func force_awaken() -> void:
	_is_awake = true
	_current_alert = maxf(alert_threshold, _current_alert)
	_state = State.CHASE
	_update_alert_bar()


func take_damage(amount: float, from_player: bool = true) -> void:
	_current_hp -= amount
	_update_hp_bar()
	if from_player:
		force_awaken()
	if _current_hp <= 0.0:
		_die()


func react_to_signal_flare(origin: Vector3, extraction_position: Vector3 = Vector3.ZERO) -> void:
	if enemy_type != EnemyType.PATROL:
		return
	_signal_focus_position = extraction_position if extraction_position != Vector3.ZERO else origin
	_signal_focus_position.y = global_position.y
	_has_signal_focus = true
	_is_awake = true
	_current_alert = maxf(_current_alert, alert_threshold)
	_state = State.CHASE
	_update_alert_bar()


func _update_patrol(player: Node3D) -> void:
	if can_see_player(player):
		force_awaken()
		return
	var to_target: Vector3 = _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.4:
		_pick_patrol_target()
		to_target = _patrol_target - global_position
		to_target.y = 0.0
	_move_flat(to_target, patrol_speed)


func _update_chase(player: Node3D) -> void:
	if _has_signal_focus and not can_see_player(player):
		_update_signal_focus()
		return
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist <= attack_range:
		_state = State.ATTACK
		velocity = Vector3.ZERO
		return
	_move_flat(to_player, chase_speed)


func _update_signal_focus() -> void:
	var to_focus: Vector3 = _signal_focus_position - global_position
	to_focus.y = 0.0
	if to_focus.length() <= 0.5:
		_has_signal_focus = false
		_state = State.PATROL if enemy_type == EnemyType.PATROL else State.CHASE
		_pick_patrol_target()
		velocity = Vector3.ZERO
		return
	_move_flat(to_focus, maxf(chase_speed, patrol_speed))


func _update_attack(delta: float, player: Node3D) -> void:
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > attack_range * 1.4:
		_state = State.CHASE
		return
	velocity = Vector3.ZERO
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_deal_damage(player)
		_attack_timer = attack_cooldown
	_face_direction(to_player)


func _move_flat(direction: Vector3, speed: float) -> void:
	if direction.length_squared() <= 0.01:
		velocity = Vector3.ZERO
	else:
		var dir := direction.normalized()
		velocity = dir * speed
		_face_direction(dir)


func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		look_at(global_position + direction.normalized(), Vector3.UP)


func _pick_patrol_target() -> void:
	var offset := Vector3(
		randf_range(-patrol_radius, patrol_radius),
		0.0,
		randf_range(-patrol_radius, patrol_radius)
	)
	_patrol_target = _home_position + offset


func _deal_damage(player: Node3D) -> void:
	var ph: Node = player.get_node_or_null("PlayerHealth")
	if ph and ph.has_method("take_damage"):
		ph.take_damage(get_scaled_damage())


func can_see_player(player: Node3D) -> bool:
	if player == null or view_range <= 0.0:
		return false
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > view_range:
		return false
	if distance <= 0.01:
		return true

	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() <= 0.01:
		facing = Vector3.FORWARD
	var angle := rad_to_deg(facing.normalized().angle_to(to_player.normalized()))
	if angle > view_angle * 0.5:
		return false
	return _has_clear_line_to_player(player)


func _has_clear_line_to_player(player: Node3D) -> bool:
	if vision_obstacle_mask == 0:
		return true
	var world := get_world_3d()
	if world == null:
		return true
	var space_state := world.direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.7,
		player.global_position + Vector3.UP * 0.7,
		vision_obstacle_mask
	)
	query.exclude = [get_rid()]
	if player is CollisionObject3D:
		query.exclude.append((player as CollisionObject3D).get_rid())
	return space_state.intersect_ray(query).is_empty()


func _get_player() -> Node3D:
	if _player_cache == null or not is_instance_valid(_player_cache):
		_player_cache = get_tree().get_first_node_in_group("player") as Node3D
	return _player_cache


func _get_game_manager() -> Node:
	if _game_manager_cache == null or not is_instance_valid(_game_manager_cache):
		var tree := get_tree()
		if tree != null:
			_game_manager_cache = tree.root.get_node_or_null("GameManager")
	return _game_manager_cache


func _get_erosion_tier() -> int:
	var manager := _get_game_manager()
	if manager != null and manager.has_method("get_erosion_tier"):
		return manager.get_erosion_tier()
	return 0


func _is_gameplay_active() -> bool:
	var manager := _get_game_manager()
	if manager == null:
		return true
	var state: int = manager.get("current_state")
	return state == GAME_STATE_RUNNING or state == GAME_STATE_EXTRACTING


func _ensure_alert_bar() -> void:
	var existing := get_node_or_null("AlertBar")
	if existing is Node3D:
		_alert_bar = existing as Node3D
	elif existing == null:
		_alert_bar = Node3D.new()
		_alert_bar.name = "AlertBar"
		_alert_bar.position = Vector3(0.0, 1.65, 0.0)
		add_child(_alert_bar)
	if _alert_bar != null:
		_ensure_alert_bar_meshes()
		if _alert_bar_fill != null and _alert_bar_fill.material_override != null:
			_alert_bar_fill.material_override = _alert_bar_fill.material_override.duplicate()


func _update_alert_bar() -> void:
	if _alert_bar == null or not is_instance_valid(_alert_bar):
		return
	var ratio := get_alert_ratio()
	_alert_bar.set_meta("alert_ratio", ratio)
	if _alert_bar_fill == null or not is_instance_valid(_alert_bar_fill):
		return
	_alert_bar_fill.scale.x = ratio
	_alert_bar_fill.position.x = -ALERT_BAR_WIDTH * (1.0 - ratio) * 0.5


func _ensure_hp_bar() -> void:
	var existing := get_node_or_null("HpBar")
	if existing is Node3D:
		_hp_bar = existing as Node3D
	elif existing == null:
		_hp_bar = Node3D.new()
		_hp_bar.name = "HpBar"
		_hp_bar.position = Vector3(0.0, 1.82, 0.0)
		add_child(_hp_bar)
	if _hp_bar != null:
		_ensure_hp_bar_meshes()
		if _hp_bar_fill != null and _hp_bar_fill.material_override != null:
			_hp_bar_fill.material_override = _hp_bar_fill.material_override.duplicate()


func _update_hp_bar() -> void:
	if _hp_bar == null or not is_instance_valid(_hp_bar):
		return
	var ratio := get_hp_ratio()
	_hp_bar.set_meta("hp_ratio", ratio)
	if _hp_bar_fill == null or not is_instance_valid(_hp_bar_fill):
		return
	_hp_bar_fill.scale.x = ratio
	_hp_bar_fill.position.x = -HP_BAR_WIDTH * (1.0 - ratio) * 0.5


func _die() -> void:
	died.emit(self)
	var manager := _get_game_manager()
	if manager != null and manager.has_method("register_kill"):
		manager.register_kill()
	queue_free()


func _ensure_alert_bar_meshes() -> void:
	var back := _alert_bar.get_node_or_null("AlertBack") as MeshInstance3D
	if back == null:
		back = MeshInstance3D.new()
		back.name = "AlertBack"
		back.mesh = _make_alert_box_mesh(Vector3(ALERT_BAR_WIDTH, ALERT_BAR_HEIGHT, ALERT_BAR_DEPTH))
		back.material_override = _make_alert_material(Color(0.04, 0.05, 0.05, 0.9), Color(0.0, 0.0, 0.0, 1.0), 0.0)
		_alert_bar.add_child(back)

	_alert_bar_fill = _alert_bar.get_node_or_null("AlertFill") as MeshInstance3D
	if _alert_bar_fill == null:
		_alert_bar_fill = MeshInstance3D.new()
		_alert_bar_fill.name = "AlertFill"
		_alert_bar_fill.mesh = _make_alert_box_mesh(Vector3(ALERT_BAR_WIDTH, ALERT_BAR_HEIGHT * 0.65, ALERT_BAR_DEPTH * 1.2))
		_alert_bar_fill.material_override = _make_alert_material(Color(1.0, 0.65, 0.12, 1.0), Color(1.0, 0.35, 0.05, 1.0), 0.8)
		_alert_bar_fill.position.z = -0.01
		_alert_bar.add_child(_alert_bar_fill)


func _ensure_hp_bar_meshes() -> void:
	var back := _hp_bar.get_node_or_null("HpBack") as MeshInstance3D
	if back == null:
		back = MeshInstance3D.new()
		back.name = "HpBack"
		back.mesh = _make_alert_box_mesh(Vector3(HP_BAR_WIDTH, HP_BAR_HEIGHT, HP_BAR_DEPTH))
		back.material_override = _make_alert_material(Color(0.04, 0.04, 0.04, 0.9), Color(0.0, 0.0, 0.0, 1.0), 0.0)
		_hp_bar.add_child(back)

	_hp_bar_fill = _hp_bar.get_node_or_null("HpFill") as MeshInstance3D
	if _hp_bar_fill == null:
		_hp_bar_fill = MeshInstance3D.new()
		_hp_bar_fill.name = "HpFill"
		_hp_bar_fill.mesh = _make_alert_box_mesh(Vector3(HP_BAR_WIDTH, HP_BAR_HEIGHT * 0.65, HP_BAR_DEPTH * 1.2))
		_hp_bar_fill.material_override = _make_alert_material(Color(0.95, 0.08, 0.05, 1.0), Color(1.0, 0.04, 0.02, 1.0), 0.65)
		_hp_bar_fill.position.z = -0.01
		_hp_bar.add_child(_hp_bar_fill)


func _make_alert_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _make_alert_material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = emission_energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	material.roughness = 0.5
	if albedo.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
