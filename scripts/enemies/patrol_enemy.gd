# patrol_enemy.gd
# 巡逻型敌人：随机巡逻 + 视觉锥发现玩家 + 追击 + 近身攻击
# design.md §8.2 / implementation.md §5.1
# [AI-ASSISTED] 2026-05-19 - 按 docs/rules.md 规范化脚本结构和私有状态
extends "res://scripts/enemies/enemy_base.gd"

enum State { PATROL, CHASE, ATTACK }

const MAX_PATROL_TIME := 5.0
const VISION_RAY_MASK := 36  # Obstacles(4) + Boundary(32)

@export var patrol_speed: float = 100.0
@export var chase_speed: float = 200.0
@export var view_angle: float = 60.0       # 视觉锥角度（度）
@export var view_range: float = 300.0      # 视觉锥距离（像素）
@export var attack_range: float = 60.0
@export var attack_cooldown: float = 1.0
@export var patrol_radius: float = 250.0

var _state: State = State.PATROL
var _patrol_target: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _patrol_stuck_timer: float = 0.0
var _player_cache: Node2D = null


func _ready() -> void:
	super._ready()
	_pick_patrol_target()
	awakened.connect(_on_awakened)


func _physics_process(delta: float) -> void:
	var player: Node2D = _get_player()
	if player == null:
		return
	match _state:
		State.PATROL:
			_update_patrol(delta, player)
		State.CHASE:
			_update_chase(delta, player)
		State.ATTACK:
			_update_attack(delta, player)


func _on_awakened() -> void:
	if _state != State.CHASE and _state != State.ATTACK:
		_state = State.CHASE


func _update_patrol(delta: float, player: Node2D) -> void:
	_patrol_stuck_timer += delta
	var reached: bool = nav_move_to(_patrol_target, patrol_speed)
	if reached or _patrol_stuck_timer > MAX_PATROL_TIME:
		_pick_patrol_target()
		_patrol_stuck_timer = 0.0

	# 视觉锥发现 → 立刻觉醒并追击
	if _can_see(player):
		force_awaken()
		_state = State.CHASE


func _update_chase(_delta: float, player: Node2D) -> void:
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= attack_range:
		_state = State.ATTACK
		velocity = Vector2.ZERO
		return
	nav_move_to(player.global_position, chase_speed)


func _update_attack(delta: float, player: Node2D) -> void:
	# 持续面向玩家
	var to_p: Vector2 = player.global_position - global_position
	rotation = to_p.angle()
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_deal_damage(player)
		_attack_timer = attack_cooldown
	if to_p.length() > attack_range * 1.5:
		_state = State.CHASE


func _deal_damage(player: Node2D) -> void:
	var ph: Node = player.get_node_or_null("PlayerHealth")
	if ph and ph.has_method("take_damage"):
		ph.take_damage(get_scaled_damage())


func _can_see(player: Node2D) -> bool:
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist > view_range:
		return false
	var facing: Vector2 = Vector2.from_angle(rotation)
	var angle_deg: float = abs(rad_to_deg(facing.angle_to(to_player)))
	if angle_deg > view_angle / 2.0:
		return false
	# 视线被障碍物/边界遮挡 → 看不见
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position, player.global_position, VISION_RAY_MASK, [self])
	var result: Dictionary = space.intersect_ray(query)
	return result.is_empty()


func _pick_patrol_target() -> void:
	var raw_pos: Vector2 = global_position + Vector2(
		randf_range(-patrol_radius, patrol_radius),
		randf_range(-patrol_radius, patrol_radius)
	)
	_patrol_target = snap_to_navmesh(raw_pos)


func _get_player() -> Node2D:
	if _player_cache == null or not is_instance_valid(_player_cache):
		_player_cache = get_tree().get_first_node_in_group("player")
	return _player_cache
