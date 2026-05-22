# frozen_depot_poi.gd
# Frozen Depot POI — HIGH 风险，西北方位 (-180, +100)
# 主题：冰封集装箱迷宫。冷色调（深蓝青 + 冰白 + 银蓝）跟 Core Wreck 暖锈色对比。
#
# 设计要点（按喜盐茶室《精炼工坊》POI 方法论 + map_design_plan.md §5.1）：
#   - 3 进出口（南/北/东），每口到核心 ~20-25m
#   - 4 子区：南入口仓储 / 中央迷宫 / 北保险库 / 东入口廊道
#   - 视频原则 6（多分支短岔路）：中央迷宫 3 列南北向墙 + 横向倒下集装箱挡路
#   - 视频原则 5（中心高危）：北保险库 = 高价值容器位，3 入口走廊都能被夹击
#   - 高密度狭窄：50 障碍 / 60×70m → ~1 个/85 平米
# [AI-ASSISTED] 2026-05-23 - Frozen Depot POI
class_name FrozenDepotPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/frozen_depot_poi.gd"
const POI_CLASS_NAME := "FrozenDepotPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const POI_CENTER := Vector2(-180.0, 100.0)
const POI_SIZE := Vector2(70.0, 60.0)
## 整图紧凑化偏移（POI 整体平移），数据数组保持不动
const COMPACT_OFFSET := Vector2(50.0, -10.0)
const SOUTH_ENTRANCE := Vector2(-180.0, 70.0)
const NORTH_ENTRANCE := Vector2(-180.0, 130.0)
const EAST_ENTRANCE := Vector2(-145.0, 100.0)
const CORE_POINT := Vector2(-180.0, 122.0)   # 北保险库中心

enum Kind {
	BOX,           # 小货箱
	LONG_BOX,      # 标准集装箱（主墙体）
	TILTED_BOX,    # 倒伏集装箱（横向遮挡）
	PILLAR,        # 冷冻管道（细高圆柱）
	DRUM,          # 冰冻储液罐（粗矮圆柱）
	RUBBLE,        # 冰堆 / 散落货物
}

const OBSTACLES := [
	# ===== 子区 1: 南入口仓储区（Z=72-85，2 大集装箱地标 + 散货）=====
	[Kind.LONG_BOX, -200.0, 80.0, 8.0, 3.0, 2.5, 0.0],    # 大集装箱 A（横向）
	[Kind.LONG_BOX, -163.0, 76.0, 2.5, 3.0, 6.0, 0.0],    # 大集装箱 B（纵向）
	[Kind.RUBBLE, -195.0, 73.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, -170.0, 83.0, 2.5, 1.0, 2.5, 30.0],
	[Kind.BOX, -188.0, 78.0, 2.0, 2.0, 2.0, 15.0],
	[Kind.BOX, -175.0, 82.0, 2.0, 1.8, 2.0, -10.0],

	# ===== 子区 2: 中央迷宫（Z=86-114，3 列南北墙 + 横向倒箱）=====
	# 西列墙（X=-195）
	[Kind.LONG_BOX, -195.0, 90.0, 1.5, 3.0, 6.0, 0.0],
	[Kind.LONG_BOX, -195.0, 106.0, 1.5, 3.0, 5.0, 0.0],
	# 中列墙（X=-180）
	[Kind.LONG_BOX, -180.0, 88.0, 1.5, 3.0, 5.0, 0.0],
	[Kind.LONG_BOX, -180.0, 110.0, 1.5, 3.0, 4.0, 0.0],
	# 东列墙（X=-165）
	[Kind.LONG_BOX, -165.0, 95.0, 1.5, 3.0, 6.0, 0.0],
	[Kind.LONG_BOX, -165.0, 108.0, 1.5, 3.0, 4.0, 0.0],

	# 横向倒箱（堵直路 + 视频原则 6 多分支）
	[Kind.TILTED_BOX, -187.0, 100.0, 5.0, 3.0, 1.5, -30.0],
	[Kind.TILTED_BOX, -174.0, 96.0, 4.0, 3.0, 1.5, 25.0],

	# 散落货物 + 冷冻油罐
	[Kind.BOX, -190.0, 95.0, 2.0, 1.8, 2.0, 0.0],
	[Kind.BOX, -170.0, 102.0, 2.0, 1.8, 2.0, 20.0],
	[Kind.DRUM, -188.0, 105.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, -172.0, 92.0, 3.0, 3.0, 3.0, 0.0],

	# ===== 子区 3: 北侧保险库（Z=115-128，核心容器位 + 3 PILLARs）=====
	# 南面入口墙（中央留 2.5m 缝，X=-181.25 to -178.75）
	[Kind.LONG_BOX, -184.25, 115.0, 6.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, -175.75, 115.0, 6.0, 3.0, 1.5, 0.0],
	# 东西围墙（覆盖到南北墙交接处，Z 缩 1.5m 避开角落重叠）
	[Kind.LONG_BOX, -188.0, 122.5, 1.5, 3.0, 13.5, 0.0],
	[Kind.LONG_BOX, -172.0, 122.5, 1.5, 3.0, 13.5, 0.0],
	# 内部冷冻管道（北端，背向容器位）
	[Kind.PILLAR, -184.0, 127.0, 1.2, 4.0, 1.2, 0.0],
	[Kind.PILLAR, -180.0, 127.0, 1.2, 4.0, 1.2, 0.0],
	[Kind.PILLAR, -176.0, 127.0, 1.2, 4.0, 1.2, 0.0],

	# ===== 子区 4: 东入口廊道（X=-160~-145，狭窄）=====
	[Kind.LONG_BOX, -155.0, 95.0, 8.0, 3.0, 1.5, 90.0],
	[Kind.LONG_BOX, -155.0, 105.0, 8.0, 3.0, 1.5, 90.0],
	[Kind.TILTED_BOX, -152.0, 100.0, 2.5, 2.5, 1.2, 45.0],

	# ===== 环绕通道（POI 外圈零散冰堆）=====
	[Kind.RUBBLE, -220.0, 80.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -220.0, 100.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -220.0, 120.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -155.0, 65.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -205.0, 65.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -155.0, 135.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -205.0, 135.0, 2.5, 1.0, 2.5, 0.0],

	# ===== POI 外墙（3 口外封闭）=====
	# 南墙 Z=70，中央 X=-184~-176 留 8m 入口
	[Kind.LONG_BOX, -199.5, 70.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, -160.5, 70.0, 31.0, 3.0, 1.5, 0.0],
	# 北墙 Z=130，同样 8m 入口
	[Kind.LONG_BOX, -199.5, 130.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, -160.5, 130.0, 31.0, 3.0, 1.5, 0.0],
	# 东墙 X=-145，中央 Z=96-104 留 8m 入口（Z 缩 1m 避开南北角）
	[Kind.LONG_BOX, -145.0, 83.5, 1.5, 3.0, 25.0, 0.0],
	[Kind.LONG_BOX, -145.0, 116.5, 1.5, 3.0, 25.0, 0.0],
	# 西墙 X=-215，全封无口（Z 缩 2m 避开南北角）
	[Kind.LONG_BOX, -215.0, 100.0, 1.5, 3.0, 58.0, 0.0],
]


static func get_zone_def() -> Dictionary:
	return {
		"name": "Frozen Depot",
		"center": POI_CENTER + COMPACT_OFFSET,
		"size": POI_SIZE,
		"risk": "high",
		"enemy_density": 1.6,
		"container_density": 1.55,
		"high_value_weight": 0.85,
	}


const CONTAINERS := [
	# 北保险库 3 个核心高价值（Z=122 一行排列，避开北端 PILLARs）
	[-184.0, 122.0, "high", [ITEM_RELIC, ITEM_RELIC, ITEM_PURIFIER]],
	[-180.0, 122.0, "high", [ITEM_RELIC, ITEM_PURIFIER]],
	[-176.0, 122.0, "high", [ITEM_RELIC, ITEM_RELIC]],
	# 中央迷宫深处 1 个（藏在西墙后）
	[-192.0, 100.0, "high", [ITEM_BATTERY, ITEM_BATTERY, ITEM_RELIC]],
	# 南入口仓储 1 个（弹药/补给）
	[-200.0, 76.0, "high", [ITEM_AMMO, ITEM_AMMO, ITEM_BATTERY]],
]


const SPAWNS := [
	["patrol", -183.0, 102.0],     # 迷宫中央（避开 TILTED_BOX）
	["patrol", -175.0, 110.0],     # 迷宫北
	["dormant", -180.0, 118.0],    # 保险库守卫
	["dormant", -195.0, 95.0],     # 西迷宫潜伏
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
		body.name = "FDObstacle_%d" % count
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
		container.name = "FDContainer_%d" % count
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
		m.name = "FDPatrolSpawn_%d" % count if kind_str == "patrol" else "FDDormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		count += 1
	return count


static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "FrozenDepotMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.5, 0.6, 0.32)         # 冷蓝灰
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.55, 0.7)
	mat.emission_energy_multiplier = 0.35
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
		push_warning("[FrozenDepotPOI] PackedScene.pack failed: %d" % err)
		return StaticBody3D.new()
	return packed.instantiate() as StaticBody3D


static func _make_mesh(kind: int, sx: float, sy: float, sz: float) -> Mesh:
	match kind:
		Kind.PILLAR, Kind.DRUM:
			var c := CylinderMesh.new()
			c.top_radius = sx * 0.5
			c.bottom_radius = sx * 0.5
			c.height = sy
			c.radial_segments = 16
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
			m.albedo_color = Color(0.5, 0.6, 0.65)    # 银蓝管道
			m.metallic = 0.75
			m.roughness = 0.35
		Kind.DRUM:
			m.albedo_color = Color(0.72, 0.78, 0.82)  # 冰白储罐
			m.metallic = 0.45
			m.roughness = 0.55
		Kind.LONG_BOX:
			m.albedo_color = Color(0.25, 0.38, 0.45)  # 深蓝青集装箱（主色）
			m.metallic = 0.5
			m.roughness = 0.6
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.35, 0.42, 0.48)  # 锈蓝倒箱
			m.metallic = 0.5
			m.roughness = 0.7
		Kind.RUBBLE:
			m.albedo_color = Color(0.65, 0.72, 0.78)  # 冰堆 / 散落
			m.metallic = 0.05
			m.roughness = 0.9
		_:
			m.albedo_color = Color(0.5, 0.55, 0.6)    # 通用小货箱
			m.metallic = 0.3
			m.roughness = 0.65
	return m
