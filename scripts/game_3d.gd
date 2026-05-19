# game_3d.gd
# 3D 主游戏场景：正交斜俯视相机、3D 玩家/敌人/容器占位和一局 Run 初始化。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写主玩法路径
extends Node3D

const PLAYER_SCENE := preload("res://scenes/player_3d.tscn")
const PATROL_ENEMY_SCENE := preload("res://scenes/patrol_enemy_3d.tscn")
const DORMANT_ENEMY_SCENE := preload("res://scenes/dormant_enemy_3d.tscn")
const CONTAINER_SCENE := preload("res://scenes/container_3d.tscn")

const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const CAMERA_OFFSET := Vector3(0.0, 18.0, 18.0)
const OBSTACLE_DATA := [
	{ "pos": Vector3(-10.0, 0.75, -7.0), "size": Vector3(3.0, 1.5, 5.0) },
	{ "pos": Vector3(7.0, 0.65, -9.0), "size": Vector3(5.0, 1.3, 2.5) },
	{ "pos": Vector3(-4.0, 0.6, 3.0), "size": Vector3(2.5, 1.2, 2.5) },
	{ "pos": Vector3(10.0, 0.85, 6.0), "size": Vector3(4.0, 1.7, 4.0) },
	{ "pos": Vector3(14.0, 0.7, -13.0), "size": Vector3(2.0, 1.4, 6.0) },
]

var _player: Node3D = null

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _enemies: Node3D = $Entities/Enemies
@onready var _containers: Node3D = $Entities/Containers
@onready var _obstacles: Node3D = $World/Obstacles


func _ready() -> void:
	_spawn_player()
	_spawn_obstacles()
	_spawn_containers()
	_spawn_enemies()
	GameManager.start_run()
	_update_camera()


func _process(_delta: float) -> void:
	_update_camera()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player3D"
	$Entities.add_child(_player)
	_player.global_position = Vector3.ZERO


func _spawn_obstacles() -> void:
	for data in OBSTACLE_DATA:
		var body := StaticBody3D.new()
		body.name = "Obstacle3D"
		body.position = data.pos
		body.collision_layer = 4
		body.collision_mask = 0

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = data.size
		collision.shape = shape
		body.add_child(collision)

		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = data.size
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _make_material(Color(0.28, 0.27, 0.25, 1.0))
		body.add_child(mesh_instance)

		_obstacles.add_child(body)


func _spawn_containers() -> void:
	var data := [
		{ "pos": Vector3(4.0, 0.0, -4.0), "loot": [ITEM_RELIC, ITEM_AMMO] },
		{ "pos": Vector3(-8.0, 0.0, 2.0), "loot": [ITEM_BATTERY] },
		{ "pos": Vector3(13.0, 0.0, 9.0), "loot": [ITEM_RELIC, ITEM_RELIC, ITEM_AMMO] },
		{ "pos": Vector3(-14.0, 0.0, -5.0), "loot": [ITEM_PURIFIER] },
	]
	for entry in data:
		var container: Node3D = CONTAINER_SCENE.instantiate()
		container.position = entry.pos
		var typed_loot: Array[ItemData] = []
		typed_loot.assign(entry.loot)
		container.loot_table = typed_loot
		_containers.add_child(container)


func _spawn_enemies() -> void:
	var patrol_positions := [Vector3(9.0, 0.0, -12.0), Vector3(-12.0, 0.0, 10.0)]
	var dormant_positions := [Vector3(14.0, 0.0, 7.0), Vector3(-14.0, 0.0, -7.0)]
	for pos in patrol_positions:
		var enemy: Node3D = PATROL_ENEMY_SCENE.instantiate()
		enemy.position = pos
		_enemies.add_child(enemy)
	for pos in dormant_positions:
		var enemy: Node3D = DORMANT_ENEMY_SCENE.instantiate()
		enemy.position = pos
		_enemies.add_child(enemy)


func _update_camera() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_camera.global_position = _player.global_position + CAMERA_OFFSET
	_camera.look_at(_player.global_position, Vector3.UP)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material
