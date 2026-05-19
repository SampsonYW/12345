# enemy_3d.gd
# 3D 敌人基类：巡逻型主动游走追击，休眠型靠噪音/受击唤醒，近身攻击 PlayerHealth。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写敌人占位逻辑
extends CharacterBody3D

signal died(enemy: CharacterBody3D)

enum EnemyType { PATROL, DORMANT }
enum State { PATROL, SLEEP, CHASE, ATTACK }

@export var alert_threshold: float = 100.0
@export var decay_rate: float = 5.0
@export var base_hp: float = 40.0
@export var base_damage: float = 15.0
@export var enemy_type: EnemyType = EnemyType.PATROL
@export var patrol_speed: float = 2.2
@export var chase_speed: float = 4.2
@export var patrol_radius: float = 5.0
@export var view_range: float = 8.0
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


func _ready() -> void:
	add_to_group("enemies")
	_home_position = global_position
	_state = State.PATROL if enemy_type == EnemyType.PATROL else State.SLEEP
	_is_awake = enemy_type == EnemyType.PATROL
	_erosion_tier = GameManager.get_erosion_tier()
	_current_hp = get_scaled_hp()
	_pick_patrol_target()


func _process(delta: float) -> void:
	if not _is_awake and _current_alert > 0.0:
		_current_alert = maxf(0.0, _current_alert - decay_rate * delta)


func _physics_process(delta: float) -> void:
	if GameManager.current_state == GameManager.State.DEAD:
		velocity = Vector3.ZERO
		return
	var player := _get_player()
	if player == null:
		velocity = Vector3.ZERO
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


func get_enemy_kind() -> String:
	return "patrol" if enemy_type == EnemyType.PATROL else "dormant"


func get_scaled_hp() -> float:
	return base_hp * GameManager.EROSION_STAT_MULTIPLIER[_erosion_tier]


func get_scaled_damage() -> float:
	return base_damage * GameManager.EROSION_STAT_MULTIPLIER[_erosion_tier]


func receive_noise(value: float) -> void:
	if _is_awake:
		return
	_current_alert += value
	if _current_alert >= alert_threshold:
		force_awaken()


func force_awaken() -> void:
	_is_awake = true
	_current_alert = alert_threshold
	_state = State.CHASE


func take_damage(amount: float, from_player: bool = true) -> void:
	_current_hp -= amount
	if from_player:
		force_awaken()
	if _current_hp <= 0.0:
		_die()


func _update_patrol(player: Node3D) -> void:
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= view_range:
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
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist <= attack_range:
		_state = State.ATTACK
		velocity = Vector3.ZERO
		return
	_move_flat(to_player, chase_speed)


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


func _get_player() -> Node3D:
	if _player_cache == null or not is_instance_valid(_player_cache):
		_player_cache = get_tree().get_first_node_in_group("player") as Node3D
	return _player_cache


func _die() -> void:
	died.emit(self)
	GameManager.register_kill()
	queue_free()
