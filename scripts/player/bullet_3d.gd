# bullet_3d.gd
# 3D 子弹实体：向前飞行，碰撞障碍物或敌人（触发 take_damage）。
# 3D 子弹：Area3D 沿方向飞行，命中 enemies group 时调用 take_damage。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写子弹
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
# [AI-ASSISTED] 2026-05-26 — 命中时 spawn 美术贴图 VFX
extends Area3D

signal deactivated(bullet: Area3D)

const HIT_MECH_TEXTURE := preload("res://assets/sprites/effects/effect_bullet_hit_mech.png")
const HIT_METAL_TEXTURE := preload("res://assets/sprites/effects/effect_bullet_hit_metal.png")
const HIT_VFX_DURATION := 0.25

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
	var hit_pos := global_position
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_spawn_hit_vfx(hit_pos, HIT_MECH_TEXTURE)
		call_deferred("deactivate")
		return
	_spawn_hit_vfx(hit_pos, HIT_METAL_TEXTURE)
	call_deferred("deactivate")


func _spawn_hit_vfx(pos: Vector3, tex: Texture2D) -> void:
	if tex == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.position = pos + Vector3(0, 0.5, 0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 命中 PNG ≈ 1700×1500；pixel_size 0.0006 → ≈ 1.0×0.9m
	sprite.pixel_size = 0.0006
	sprite.shaded = false
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	parent.add_child(sprite)
	parent.get_tree().create_timer(HIT_VFX_DURATION).timeout.connect(Callable(sprite, "queue_free"))
