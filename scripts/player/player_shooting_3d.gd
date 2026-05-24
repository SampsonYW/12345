# player_shooting_3d.gd
# 射击系统：管理玩家主武器开火、弹药限制、装弹冷却和射击噪音触发。
# 3D 玩家射击：从 FirePoint 沿玩家瞄准方向生成 3D 子弹，保留弹药信号接口给 HUD。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写射击
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node

signal ammo_changed(current: int, max_value: int)

@export var bullet_scene: PackedScene
@export var fire_rate: float = 0.15
@export var bullet_speed: float = 18.0
@export var max_ammo: int = 60
@export var bullet_pool_size: int = 18

var current_ammo: int = 0
var _bullet_pool: Array[Area3D] = []
var _fire_cooldown: float = 0.0

@onready var _fire_point: Marker3D = %FirePoint
@onready var _player: Node3D = get_parent() as Node3D


func _ready() -> void:
	current_ammo = max_ammo
	_build_bullet_pool()
	ammo_changed.emit(current_ammo, max_ammo)


func _process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if (
		GameManager.current_state != GameManager.State.RUNNING
		and GameManager.current_state != GameManager.State.EXTRACTING
	):
		return
	if GameManager.ui_blocking_input:
		return
	if Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0 and current_ammo > 0:
		fire()


func fire() -> void:
	if current_ammo <= 0:
		return
	if GameManager.ui_blocking_input:
		return
	if bullet_scene == null:
		push_warning("PlayerShooting3D.bullet_scene 未设置")
		return
	var bullet := _get_pooled_bullet()
	if bullet == null:
		push_warning("PlayerShooting3D 子弹池已耗尽")
		return
	var dir: Vector3 = _get_fire_direction()
	if bullet.has_method("activate"):
		bullet.activate(_fire_point.global_position, dir, bullet_speed)
	current_ammo -= 1
	_fire_cooldown = fire_rate
	ammo_changed.emit(current_ammo, max_ammo)
	NoiseManager.emit_noise(_player.global_position, NoiseManager.Level.HIGH)


func add_ammo(amount: int) -> void:
	current_ammo = mini(current_ammo + amount, max_ammo)
	ammo_changed.emit(current_ammo, max_ammo)


func refill_ammo() -> void:
	current_ammo = max_ammo
	ammo_changed.emit(current_ammo, max_ammo)


func _get_fire_direction() -> Vector3:
	if _player.has_method("get_aim_direction"):
		return _player.get_aim_direction()
	return -_fire_point.global_transform.basis.z.normalized()


func _build_bullet_pool() -> void:
	if bullet_scene == null:
		return
	var parent := _find_projectile_parent()
	var needed = bullet_pool_size - _bullet_pool.size()
	var start_index := _bullet_pool.size()
	for i in needed:
		var bullet: Area3D = bullet_scene.instantiate()
		bullet.name = "Bullet3DPool%d" % (start_index + i)
		parent.add_child(bullet)
		if bullet.has_method("deactivate"):
			bullet.deactivate()
		_bullet_pool.append(bullet)


func _get_pooled_bullet() -> Area3D:
	for i in range(_bullet_pool.size() - 1, -1, -1):
		if not is_instance_valid(_bullet_pool[i]):
			_bullet_pool.remove_at(i)

	if _bullet_pool.size() < bullet_pool_size:
		_build_bullet_pool()

	for bullet in _bullet_pool:
		if is_instance_valid(bullet) and not bullet.visible:
			return bullet
	return null


func _find_projectile_parent() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var projectiles: Node = scene.get_node_or_null("Entities/Projectiles")
		if projectiles != null:
			return projectiles
		return scene
	return get_tree().root
