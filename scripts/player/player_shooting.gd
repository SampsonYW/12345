# player_shooting.gd
# 玩家射击：按住 shoot 持续半自动开火、弹药计数、子弹生成
# 挂在 Player 下的 PlayerShooting Node 上，引用 GunPivot/FirePoint
extends Node

signal ammo_changed(current: int, max_value: int)

@export var bullet_scene: PackedScene
@export var fire_rate: float = 0.15
@export var bullet_speed: float = 800.0
@export var max_ammo: int = 60

var current_ammo: int = 0
var fire_cooldown: float = 0.0

@onready var fire_point: Marker2D = %FirePoint
@onready var player: Node2D = get_parent()


func _ready() -> void:
	current_ammo = max_ammo
	ammo_changed.emit(current_ammo, max_ammo)


func _process(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and current_ammo > 0:
		fire()


func fire() -> void:
	if bullet_scene == null:
		push_warning("PlayerShooting.bullet_scene 未设置")
		return
	var bullet := bullet_scene.instantiate()
	bullet.global_position = fire_point.global_position
	var dir: Vector2 = fire_point.global_transform.x.normalized()
	bullet.direction = dir
	bullet.rotation = dir.angle()
	bullet.speed = bullet_speed
	get_tree().current_scene.add_child(bullet)
	current_ammo -= 1
	fire_cooldown = fire_rate
	ammo_changed.emit(current_ammo, max_ammo)
	NoiseManager.emit_noise(player.global_position, NoiseManager.Level.HIGH)


func add_ammo(amount: int) -> void:
	current_ammo = mini(current_ammo + amount, max_ammo)
	ammo_changed.emit(current_ammo, max_ammo)
