# ash_outskirts_poi.gd
# Ash Outskirts POI — LOW 风险，西方位 (-150, 0)
# 主题：灰沙废墟 + 矮墙开放迷宫。颜色：浅褐沙石 + 锈铁天线，跟其它 POI 区分。
#
# 设计要点（按 map_design_plan.md §5.2 + 喜盐茶室方法论）：
#   - 3 进出口（东/南/北），西墙全封
#   - 4 子区：东接入 / 中央矮墙废墟 / 南沙丘 / 北通信塔
#   - LOW POI 风格：稀疏布局、新手友好、矮掩体居多
# [AI-ASSISTED] 2026-05-23 - Ash Outskirts POI
class_name AshOutskirtsPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/ash_outskirts_poi.gd"
const POI_CLASS_NAME := "AshOutskirtsPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const POI_CENTER := Vector2(-150.0, 0.0)
const POI_SIZE := Vector2(70.0, 80.0)
const COMPACT_OFFSET := Vector2(40.0, 0.0)
const EAST_ENTRANCE := Vector2(-115.0, 0.0)
const SOUTH_ENTRANCE := Vector2(-150.0, -40.0)
const NORTH_ENTRANCE := Vector2(-150.0, 40.0)
const CORE_POINT := Vector2(-150.0, 30.0)   # 北通信塔附近

enum Kind {
	BOX,
	LONG_BOX,
	TILTED_BOX,
	PILLAR,
	RUBBLE,
}

const OBSTACLES := [
	# ===== 子区 1: 东接入廊（X -130~-115，散落入门）=====
	[Kind.BOX, -122.0, -2.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.BOX, -125.0, 8.0, 2.0, 2.0, 2.0, 15.0],
	[Kind.RUBBLE, -120.0, -8.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -128.0, 5.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, -125.0, -12.0, 2.0, 1.0, 2.0, 30.0],

	# ===== 子区 2: 中央矮墙废墟（X -165~-135, Z -20~+20）=====
	[Kind.LONG_BOX, -150.0, -12.0, 8.0, 2.0, 1.5, 0.0],
	[Kind.LONG_BOX, -140.0, 5.0, 1.5, 2.0, 6.0, 0.0],
	[Kind.LONG_BOX, -160.0, 8.0, 1.5, 2.0, 6.0, 0.0],
	[Kind.LONG_BOX, -147.0, 18.0, 8.0, 2.0, 1.5, 30.0],
	[Kind.LONG_BOX, -158.0, -18.0, 5.0, 2.0, 1.5, -20.0],
	[Kind.TILTED_BOX, -148.0, 2.0, 3.0, 2.0, 1.5, 45.0],
	[Kind.BOX, -152.0, 12.0, 2.5, 2.0, 2.5, 0.0],
	[Kind.BOX, -163.0, -5.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.RUBBLE, -143.0, -8.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, -155.0, 14.0, 2.0, 1.0, 2.0, 0.0],

	# ===== 子区 3: 南沙丘（Z -38~-25，沙石堆）=====
	[Kind.RUBBLE, -160.0, -30.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, -145.0, -32.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, -150.0, -36.0, 4.0, 1.0, 3.0, 0.0],
	[Kind.BOX, -155.0, -28.0, 2.0, 1.5, 2.0, 0.0],

	# ===== 子区 4: 北通信塔（Z 25~38）=====
	[Kind.PILLAR, -150.0, 32.0, 1.2, 6.0, 1.2, 0.0],   # 天线塔（地标，6m 高）
	[Kind.LONG_BOX, -146.0, 35.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.LONG_BOX, -154.0, 35.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.BOX, -150.0, 25.0, 2.0, 2.0, 2.0, 0.0],

	# ===== 环绕通道 =====
	[Kind.RUBBLE, -190.0, 0.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -190.0, 20.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -190.0, -20.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -110.0, 20.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -110.0, -20.0, 2.5, 1.0, 2.5, 0.0],

	# ===== POI 外墙（3 入口外封闭，西墙全封）=====
	# 南墙 Z=-40，中央 X=-154~-146 留 8m 入口
	[Kind.LONG_BOX, -169.5, -40.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, -130.5, -40.0, 31.0, 3.0, 1.5, 0.0],
	# 北墙 Z=+40，中央 8m 入口
	[Kind.LONG_BOX, -169.5, 40.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, -130.5, 40.0, 31.0, 3.0, 1.5, 0.0],
	# 东墙 X=-115，中央 Z=-4~+4 留 8m 入口（Z 缩避开南北角）
	[Kind.LONG_BOX, -115.0, -21.5, 1.5, 3.0, 35.0, 0.0],
	[Kind.LONG_BOX, -115.0, 21.5, 1.5, 3.0, 35.0, 0.0],
	# 西墙 X=-185，全封无口
	[Kind.LONG_BOX, -185.0, 0.0, 1.5, 3.0, 78.0, 0.0],
]


static func get_zone_def() -> Dictionary:
	return {
		"name": "Ash Outskirts",
		"center": POI_CENTER + COMPACT_OFFSET,
		"size": POI_SIZE,
		"risk": "low",
		"enemy_density": 0.4,
		"container_density": 0.5,
		"high_value_weight": 0.15,
	}


const CONTAINERS := [
	# 北通信塔附近 1 个（含净化剂）
	[-148.0, 30.0, "low", [ITEM_PURIFIER, ITEM_BATTERY]],
	# 中央废墟 1 个
	[-148.0, -2.0, "low", [ITEM_AMMO, ITEM_BATTERY]],
	# 东接入 1 个
	[-122.0, 0.0, "low", [ITEM_AMMO, ITEM_AMMO]],
]


const SPAWNS := [
	["patrol", -150.0, -20.0],     # 南废墟巡逻
	["patrol", -145.0, 22.0],      # 北废墟巡逻（避开 LONG_BOX rot 30）
]


static func build_all(parents: Dictionary) -> Dictionary:
	build_obstacles(parents["obstacles"])
	build_containers(parents["containers"])
	build_spawns(parents["spawns"])
	build_zone_marker(parents["risk_zones"])
	return get_zone_def()


static func build_obstacles(obstacles_parent: Node3D) -> int:
	var count: int = 0
	for data in OBSTACLES:
		var kind: int = data[0]
		var x: float = data[1]
		var z: float = data[2]
		var sx: float = data[3]
		var sy: float = data[4]
		var sz: float = data[5]
		var rot_deg: float = data[6]
		var body := _make_static_body(kind, sx, sy, sz)
		body.name = "AOObstacle_%d" % count
		body.set_meta("poi_class", POI_CLASS_NAME)
		body.set_meta("poi_data_index", count)
		obstacles_parent.add_child(body)
		body.global_position = Vector3(x + COMPACT_OFFSET.x, sy * 0.5, z + COMPACT_OFFSET.y)
		body.rotation = Vector3(0.0, deg_to_rad(rot_deg), 0.0)
		count += 1
	return count


static func build_containers(containers_parent: Node3D) -> int:
	var count: int = 0
	for entry in CONTAINERS:
		var x: float = entry[0]
		var z: float = entry[1]
		var risk: String = entry[2]
		var loot_list: Array = entry[3]
		var container := ContainerScene.instantiate() as StaticBody3D
		container.name = "AOContainer_%d" % count
		container.set_meta("poi_class", POI_CLASS_NAME)
		container.set_meta("poi_data_index", count)
		containers_parent.add_child(container)
		container.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		container.risk = risk
		var typed_loot: Array[ItemData] = []
		typed_loot.assign(loot_list)
		container.loot_table = typed_loot
		count += 1
	return count


static func build_spawns(spawns_parent: Node3D) -> int:
	var count: int = 0
	for entry in SPAWNS:
		var kind_str: String = entry[0]
		var x: float = entry[1]
		var z: float = entry[2]
		var m := Marker3D.new()
		m.name = "AOPatrolSpawn_%d" % count if kind_str == "patrol" else "AODormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		count += 1
	return count


static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "AshOutskirtsMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.32, 0.25)  # 浅褐沙石
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.5, 0.3)
	mat.emission_energy_multiplier = 0.25
	marker.material_override = mat
	risk_zones_parent.add_child(marker)
	marker.global_position = Vector3(def["center"].x, 0.001, def["center"].y)


static func dump_current_state(parents: Dictionary) -> Dictionary:
	return POIDumpUtilityScript.dump(SOURCE_FILE_PATH, POI_CLASS_NAME, parents)


static func _make_static_body(kind: int, sx: float, sy: float, sz: float) -> StaticBody3D:
	var prototype := StaticBody3D.new()
	prototype.name = "Obstacle"
	prototype.collision_layer = 4
	prototype.collision_mask = 0

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	mesh_inst.mesh = _make_mesh(kind, sx, sy, sz)
	mesh_inst.material_override = _make_material(kind)
	prototype.add_child(mesh_inst)
	mesh_inst.owner = prototype

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = _make_shape(kind, sx, sy, sz)
	prototype.add_child(shape)
	shape.owner = prototype

	var packed := PackedScene.new()
	var err: int = packed.pack(prototype)
	prototype.free()
	if err != OK:
		push_warning("[AshOutskirtsPOI] PackedScene.pack failed: %d" % err)
		return StaticBody3D.new()
	return packed.instantiate() as StaticBody3D


static func _make_mesh(kind: int, sx: float, sy: float, sz: float) -> Mesh:
	match kind:
		Kind.PILLAR:
			var c := CylinderMesh.new()
			c.top_radius = sx * 0.5
			c.bottom_radius = sx * 0.5
			c.height = sy
			c.radial_segments = 12
			return c
		_:
			var b := BoxMesh.new()
			b.size = Vector3(sx, sy, sz)
			return b


static func _make_shape(kind: int, sx: float, sy: float, sz: float) -> Shape3D:
	match kind:
		Kind.PILLAR:
			var c := CylinderShape3D.new()
			c.radius = sx * 0.5
			c.height = sy
			return c
		_:
			var b := BoxShape3D.new()
			b.size = Vector3(sx, sy, sz)
			return b


static func _make_material(kind: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match kind:
		Kind.PILLAR:
			m.albedo_color = Color(0.4, 0.32, 0.25)   # 锈铁天线
			m.metallic = 0.55
			m.roughness = 0.55
		Kind.LONG_BOX:
			m.albedo_color = Color(0.55, 0.5, 0.42)   # 浅褐废墟墙
			m.metallic = 0.1
			m.roughness = 0.9
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.5, 0.45, 0.38)   # 倒塌墙片
			m.metallic = 0.15
			m.roughness = 0.85
		Kind.RUBBLE:
			m.albedo_color = Color(0.65, 0.55, 0.4)   # 沙石浅黄
			m.metallic = 0.0
			m.roughness = 1.0
		_:
			m.albedo_color = Color(0.5, 0.45, 0.38)
			m.metallic = 0.15
			m.roughness = 0.8
	return m
