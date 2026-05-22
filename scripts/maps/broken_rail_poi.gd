# broken_rail_poi.gd
# Broken Rail POI — LOW 风险，东方位 (+150, 0)
# 主题：倒伏磁轨 + 翻倒车厢。颜色：深钢灰 + 暗锈橙，对称 Ash Outskirts 在西侧。
#
# 设计要点：
#   - 3 进出口（西/南/北），东墙全封
#   - 4 子区：西接入 / 中央铁轨场 / 北储存 / 南死端
#   - 中央铁轨场 = 4 条平行铁轨段 + 大型横躺车厢（主视觉锚定）
# [AI-ASSISTED] 2026-05-23 - Broken Rail POI
class_name BrokenRailPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/broken_rail_poi.gd"
const POI_CLASS_NAME := "BrokenRailPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const POI_CENTER := Vector2(150.0, 0.0)
const POI_SIZE := Vector2(70.0, 60.0)
const COMPACT_OFFSET := Vector2(-40.0, 0.0)
const WEST_ENTRANCE := Vector2(115.0, 0.0)
const SOUTH_ENTRANCE := Vector2(150.0, -30.0)
const NORTH_ENTRANCE := Vector2(150.0, 30.0)
const CORE_POINT := Vector2(150.0, 0.0)   # 中央铁轨场

enum Kind {
	BOX,
	LONG_BOX,
	TILTED_BOX,
	PILLAR,
	DRUM,
	RUBBLE,
}

const OBSTACLES := [
	# ===== 子区 1: 西接入廊（X 115~130）=====
	[Kind.BOX, 122.0, -2.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.BOX, 125.0, 8.0, 2.0, 2.0, 2.0, 15.0],
	[Kind.RUBBLE, 128.0, -8.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 127.0, 5.0, 2.0, 1.0, 2.0, 0.0],

	# ===== 子区 2: 中央铁轨场（X 135~165, Z -15~+15）=====
	# 4 条平行铁轨（X 轴向，矮扁）
	[Kind.LONG_BOX, 150.0, -15.0, 30.0, 0.6, 0.8, 0.0],
	[Kind.LONG_BOX, 150.0, -5.0, 30.0, 0.6, 0.8, 0.0],
	[Kind.LONG_BOX, 150.0, 5.0, 30.0, 0.6, 0.8, 0.0],
	[Kind.LONG_BOX, 150.0, 15.0, 30.0, 0.6, 0.8, 0.0],
	# 横躺大车厢（主视觉锚定）
	[Kind.TILTED_BOX, 150.0, 0.0, 10.0, 3.0, 3.5, 0.0],
	# 货柜散落
	[Kind.BOX, 140.0, 0.0, 2.5, 2.0, 2.5, 0.0],
	[Kind.BOX, 160.0, 0.0, 2.5, 2.0, 2.5, 0.0],
	[Kind.BOX, 140.0, 10.0, 2.0, 2.0, 2.0, 20.0],
	[Kind.BOX, 160.0, -10.0, 2.0, 2.0, 2.0, -20.0],
	# 信号柱
	[Kind.PILLAR, 135.0, 0.0, 1.0, 3.0, 1.0, 0.0],
	[Kind.PILLAR, 165.0, 0.0, 1.0, 3.0, 1.0, 0.0],
	# 废罐（避开 rotated BOX 的扩展 AABB）
	[Kind.DRUM, 137.0, 10.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.DRUM, 163.0, -10.0, 2.0, 2.0, 2.0, 0.0],

	# ===== 子区 3: 北储存（Z 22-28）=====
	[Kind.LONG_BOX, 147.0, 25.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.LONG_BOX, 153.0, 25.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.BOX, 150.0, 22.0, 2.0, 2.0, 2.0, 0.0],

	# ===== 子区 4: 南死端（Z -28~-22）=====
	[Kind.LONG_BOX, 147.0, -25.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.LONG_BOX, 153.0, -25.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.BOX, 150.0, -22.0, 2.0, 2.0, 2.0, 0.0],

	# ===== 环绕通道 =====
	[Kind.RUBBLE, 110.0, 0.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 110.0, 20.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 190.0, 0.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 190.0, 20.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 110.0, -20.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 190.0, -20.0, 2.5, 1.0, 2.5, 0.0],

	# ===== POI 外墙（3 入口外封闭，东墙全封）=====
	# 南墙 Z=-30，中央 X=146~154 留 8m 入口
	[Kind.LONG_BOX, 130.5, -30.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 169.5, -30.0, 31.0, 3.0, 1.5, 0.0],
	# 北墙 Z=+30，中央 8m 入口
	[Kind.LONG_BOX, 130.5, 30.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 169.5, 30.0, 31.0, 3.0, 1.5, 0.0],
	# 西墙 X=115，中央 Z=-4~+4 留 8m 入口（Z 缩避开南北角）
	[Kind.LONG_BOX, 115.0, -16.5, 1.5, 3.0, 25.0, 0.0],
	[Kind.LONG_BOX, 115.0, 16.5, 1.5, 3.0, 25.0, 0.0],
	# 东墙 X=185，全封无口
	[Kind.LONG_BOX, 185.0, 0.0, 1.5, 3.0, 58.0, 0.0],
]


static func get_zone_def() -> Dictionary:
	return {
		"name": "断裂铁轨",
		"center": POI_CENTER + COMPACT_OFFSET,
		"size": POI_SIZE,
		"risk": "low",
		"enemy_density": 0.55,
		"container_density": 0.55,
		"high_value_weight": 0.2,
	}


const CONTAINERS := [
	# 北储存 1 个（含净化剂）
	[150.0, 26.0, "low", [ITEM_PURIFIER, ITEM_BATTERY]],
	# 中央铁轨场附近 1 个（藏在车厢北侧）
	[150.0, 18.0, "low", [ITEM_AMMO, ITEM_BATTERY]],
	# 南死端 1 个
	[150.0, -26.0, "low", [ITEM_AMMO, ITEM_AMMO]],
]


const SPAWNS := [
	["patrol", 140.0, -8.0],     # 西铁轨场（避开中央 BOX）
	["patrol", 160.0, 8.0],      # 东铁轨场（避开中央 BOX）
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
		body.name = "BRObstacle_%d" % count
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
		container.name = "BRContainer_%d" % count
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
		m.name = "BRPatrolSpawn_%d" % count if kind_str == "patrol" else "BRDormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		count += 1
	return count


static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "BrokenRailMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.45, 0.25)  # 钢蓝灰
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.4, 0.5)
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
		push_warning("[BrokenRailPOI] PackedScene.pack failed: %d" % err)
		return StaticBody3D.new()
	return packed.instantiate() as StaticBody3D


static func _make_mesh(kind: int, sx: float, sy: float, sz: float) -> Mesh:
	match kind:
		Kind.PILLAR, Kind.DRUM:
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
		Kind.PILLAR, Kind.DRUM:
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
			m.albedo_color = Color(0.25, 0.27, 0.3)   # 黑灰信号柱
			m.metallic = 0.6
			m.roughness = 0.45
		Kind.DRUM:
			m.albedo_color = Color(0.5, 0.4, 0.25)    # 暗橙废罐
			m.metallic = 0.35
			m.roughness = 0.75
		Kind.LONG_BOX:
			m.albedo_color = Color(0.3, 0.3, 0.32)    # 深钢灰铁轨
			m.metallic = 0.7
			m.roughness = 0.4
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.35, 0.35, 0.4)   # 钢蓝车厢
			m.metallic = 0.55
			m.roughness = 0.6
		Kind.RUBBLE:
			m.albedo_color = Color(0.4, 0.38, 0.35)   # 深灰砾石
			m.metallic = 0.1
			m.roughness = 0.95
		_:
			m.albedo_color = Color(0.5, 0.35, 0.2)    # 锈橙货柜
			m.metallic = 0.4
			m.roughness = 0.6
	return m
