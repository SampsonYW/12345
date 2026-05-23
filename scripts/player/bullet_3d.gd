# bullet_3d.gd
# 3D 子弹实体：向前飞行，碰撞障碍物或敌人（触发 take_damage）。
# 3D 子弹：Area3D 沿方向飞行，命中 enemies group 时调用 take_damage。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写子弹
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Area3D

signal deactivated(bullet: Area3D)

@export var speed: float = 18.0
@export var damage: float = 20.0
@export var lifetime: float = 1.5

var direction: Vector3 = Vector3.FORWARD
var age: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	deactivate()


func activate(origin: Vector3, travel_direction: Vector3, travel_speed: float) -> void:
	global_position = origin
	direction = travel_direction.normalized()
	speed = travel_speed
	age = 0.0
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)


func deactivate() -> void:
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)
	deactivated.emit(self)


func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * speed * delta
	age += delta
	if age >= lifetime:
		deactivate()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		call_deferred("deactivate")
		return
	call_deferred("deactivate")
