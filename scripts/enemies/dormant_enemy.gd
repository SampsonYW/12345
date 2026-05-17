# dormant_enemy.gd
# 休眠型敌人：默认静止，靠噪音范围唤醒（继承自 enemy_base 的 receive_noise）
# 觉醒后追击 + 近身攻击。觉醒/休眠态视觉色区分。
# design.md §8.2 / implementation.md §5.2
extends "res://scripts/enemies/enemy_base.gd"

enum State { SLEEP, CHASE, ATTACK }

@export var chase_speed: float = 150.0
@export var melee_range: float = 80.0
@export var attack_cooldown: float = 1.5

var state: State = State.SLEEP
var attack_timer: float = 0.0
var _player_cache: Node2D = null

const SLEEP_COLOR := Color(0.35, 0.2, 0.45, 1)
const AWAKE_COLOR := Color(0.75, 0.3, 0.6, 1)

@onready var visual: Polygon2D = $BodyVisual


func _ready() -> void:
	super._ready()
	awakened.connect(_on_awakened)
	visual.color = SLEEP_COLOR


func _on_awakened() -> void:
	if state == State.SLEEP:
		state = State.CHASE
	visual.color = AWAKE_COLOR


func _physics_process(delta: float) -> void:
	if state == State.SLEEP:
		return
	var player: Node2D = _get_player()
	if player == null:
		return
	match state:
		State.CHASE:
			_update_chase(delta, player)
		State.ATTACK:
			_update_attack(delta, player)


func _update_chase(_delta: float, player: Node2D) -> void:
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= melee_range:
		state = State.ATTACK
		velocity = Vector2.ZERO
		return
	nav_move_to(player.global_position, chase_speed)


func _update_attack(delta: float, player: Node2D) -> void:
	var to_p: Vector2 = player.global_position - global_position
	rotation = to_p.angle()
	attack_timer -= delta
	if attack_timer <= 0.0:
		_deal_damage(player)
		attack_timer = attack_cooldown
	if to_p.length() > melee_range * 1.5:
		state = State.CHASE


func _deal_damage(player: Node2D) -> void:
	var ph: Node = player.get_node_or_null("PlayerHealth")
	if ph and ph.has_method("take_damage"):
		ph.take_damage(get_scaled_damage())


func _get_player() -> Node2D:
	if _player_cache == null or not is_instance_valid(_player_cache):
		_player_cache = get_tree().get_first_node_in_group("player")
	return _player_cache
