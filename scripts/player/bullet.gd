# bullet.gd
# 子弹：Area2D，沿 direction 直线运动，撞敌人造成伤害，撞障碍/边界自毁
extends Area2D

@export var speed: float = 800.0
@export var damage: float = 20.0
@export var lifetime: float = 1.5

var direction: Vector2 = Vector2.RIGHT
var age: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	position += direction * speed * delta
	age += delta
	if age >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
		return
	# 撞到障碍物 / 边界 → 自毁
	queue_free()
