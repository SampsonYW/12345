# game.gd
# 主游戏场景根节点脚本：初始化一局 Run，构建导航网格，预生成测试用敌人与容器
extends Node2D

const CONTAINER_SCENE := preload("res://scenes/container.tscn")
const PATROL_SCENE := preload("res://scenes/patrol_enemy.tscn")
const DORMANT_SCENE := preload("res://scenes/dormant_enemy.tscn")

const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const NAV_BOUNDS: float = 1450.0       # 内边界（墙厚 60，留 20 缓冲）
const NAV_OBSTACLE_PADDING: float = 35.0  # agent 半径 + 一点缓冲


func _ready() -> void:
	_build_navmesh()
	# NavigationServer 在物理帧末同步：第一帧让 region 注册，第二帧让 map 完成首次同步
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameManager.start_run()
	_spawn_containers()
	_spawn_enemies()


func _build_navmesh() -> void:
	var nav_region: NavigationRegion2D = $Map/NavigationRegion2D
	var source := NavigationMeshSourceGeometryData2D.new()

	# 外圈：可行走区域
	source.add_traversable_outline(PackedVector2Array([
		Vector2(-NAV_BOUNDS, -NAV_BOUNDS),
		Vector2(NAV_BOUNDS, -NAV_BOUNDS),
		Vector2(NAV_BOUNDS, NAV_BOUNDS),
		Vector2(-NAV_BOUNDS, NAV_BOUNDS),
	]))

	# 每个障碍物作为洞挖出
	for obs in $Map/Obstacles.get_children():
		var coll: Node = obs.get_node_or_null("CollisionShape2D")
		if coll == null:
			continue
		var shape := coll.shape as RectangleShape2D
		if shape == null:
			continue
		var half: Vector2 = shape.size * 0.5 + Vector2(NAV_OBSTACLE_PADDING, NAV_OBSTACLE_PADDING)
		var p: Vector2 = obs.position
		source.add_obstruction_outline(PackedVector2Array([
			p + Vector2(-half.x, -half.y),
			p + Vector2(half.x, -half.y),
			p + Vector2(half.x, half.y),
			p + Vector2(-half.x, half.y),
		]))

	var np := NavigationPolygon.new()
	np.agent_radius = 20.0
	NavigationServer2D.bake_from_source_geometry_data(np, source, Callable())
	nav_region.navigation_polygon = np


func _spawn_containers() -> void:
	# (位置, loot_table)
	var data := [
		{ "pos": Vector2(250, -200), "loot": [ITEM_RELIC, ITEM_AMMO] },
		{ "pos": Vector2(-500, 100), "loot": [ITEM_BATTERY] },
		{ "pos": Vector2(900, 600), "loot": [ITEM_RELIC, ITEM_RELIC, ITEM_AMMO] },
		{ "pos": Vector2(-900, -300), "loot": [ITEM_PURIFIER] },
		{ "pos": Vector2(400, 900), "loot": [ITEM_RELIC, ITEM_AMMO, ITEM_BATTERY] },
	]
	var parent: Node = $Entities/Containers
	for entry in data:
		var c: Node2D = CONTAINER_SCENE.instantiate()
		c.position = entry.pos
		var typed_loot: Array[ItemData] = []
		typed_loot.assign(entry.loot)
		c.loot_table = typed_loot
		parent.add_child(c)


func _spawn_enemies() -> void:
	var patrol_positions := [
		Vector2(600, -800),
		Vector2(-700, 700),
	]
	var dormant_positions := [
		Vector2(850, 500),   # 守在 (900, 600) 容器附近
		Vector2(-850, -250), # 守在 (-900, -300) 容器附近
	]
	var parent: Node = $Entities/Enemies
	for p in patrol_positions:
		var e: Node2D = PATROL_SCENE.instantiate()
		e.position = p
		parent.add_child(e)
	for p in dormant_positions:
		var e: Node2D = DORMANT_SCENE.instantiate()
		e.position = p
		parent.add_child(e)
