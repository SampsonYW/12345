# enemy_base.gd
# 所有敌人的基类：警戒值、HP、侵蚀倍率属性、导航移动
# 子类（patrol_enemy.gd / dormant_enemy.gd）扩展具体 AI 行为
extends CharacterBody2D

signal awakened
signal died(enemy)

# ----- 共有参数（implementation.md §4.2 / §13）-----
@export var alert_threshold: float = 100.0
@export var decay_rate: float = 5.0           # 警戒值每秒消退
@export var base_hp: float = 40.0
@export var base_damage: float = 15.0

# ----- 内部状态 -----
var current_alert: float = 0.0
var is_awake: bool = false
var erosion_tier: int = 0
var current_hp: float = 0.0

@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D")


func _ready() -> void:
	add_to_group("enemies")
	current_hp = get_scaled_hp()
	if nav_agent != null:
		nav_agent.path_desired_distance = 6.0
		nav_agent.target_desired_distance = 12.0
		nav_agent.radius = 14.0


func _process(delta: float) -> void:
	# 警戒值随时间衰减
	if not is_awake and current_alert > 0.0:
		current_alert = maxf(0.0, current_alert - decay_rate * delta)


# ----- 侵蚀属性倍率 -----
func get_scaled_hp() -> float:
	return base_hp * GameManager.EROSION_STAT_MULTIPLIER[erosion_tier]


func get_scaled_damage() -> float:
	return base_damage * GameManager.EROSION_STAT_MULTIPLIER[erosion_tier]


# ----- 噪音接收 -----
func receive_noise(value: float) -> void:
	if is_awake:
		return
	current_alert += value
	if current_alert >= alert_threshold:
		awaken()


# 强制觉醒（被攻击 / 事件触发）
func force_awaken() -> void:
	if not is_awake:
		awaken()


func awaken() -> void:
	is_awake = true
	current_alert = alert_threshold
	awakened.emit()


# ----- 受伤 / 死亡 -----
func take_damage(amount: float, from_player: bool = true) -> void:
	current_hp -= amount
	if from_player:
		force_awaken()
	if current_hp <= 0.0:
		die()


func die() -> void:
	died.emit(self)
	if GameManager:
		GameManager.register_kill()
	queue_free()


# ----- 导航移动 -----
# 沿 navmesh 路径走向 target；返回 true 表示已到达目标
func nav_move_to(target: Vector2, speed: float) -> bool:
	if nav_agent == null:
		# 退化为直线移动（极端 fallback）
		var to_target: Vector2 = target - global_position
		if to_target.length() < 12.0:
			velocity = Vector2.ZERO
			return true
		velocity = to_target.normalized() * speed
		_face_velocity()
		move_and_slide()
		return false

	nav_agent.target_position = target
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return true
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	var dir: Vector2 = (next_pos - global_position).normalized()
	velocity = dir * speed
	_face_velocity()
	move_and_slide()
	return false


func _face_velocity() -> void:
	if velocity.length_squared() > 1.0:
		rotation = velocity.angle()


# 把任意点贴到 navmesh 的最近可行走位置；map 未同步时返回原点
func snap_to_navmesh(point: Vector2) -> Vector2:
	var map: RID = get_world_2d().navigation_map
	if not NavigationServer2D.map_is_active(map):
		return point
	var iter_count: int = NavigationServer2D.map_get_iteration_id(map)
	if iter_count == 0:
		return point
	return NavigationServer2D.map_get_closest_point(map, point)
