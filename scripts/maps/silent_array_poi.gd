# silent_array_poi.gd
# Silent Array POI — HIGH 风险，东北方位 (+180, +100)
# 主题：倒塌的天线阵塔林。绿色金属调（深绿天线 + 棕红天线底座 + 混凝土碎片），跟 Frozen Depot 冷蓝、Core Wreck 暖锈区分。
#
# 设计要点（按喜盐茶室《精炼工坊》POI 方法论 + map_design_plan.md §5.1）：
#   - 3 进出口（南/北/西），每口到核心 ~25m
#   - 5 子区：南入口荒原 / 天线塔林 / 中央倒塌塔废墟 / 北控制掩体 / 西入口廊道
#   - 视频原则 5（中心高危）：北控制掩体 = 高价值容器位
#   - 视频原则 3（主题区分）：天线塔林是大量高细 PILLAR 形成视觉阻断 + 视野困难
#   - 跟 Frozen Depot 主题区分：天线阵 vs 集装箱迷宫，避免视觉雷同
# [AI-ASSISTED] 2026-05-23 - Silent Array POI
class_name SilentArrayPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/silent_array_poi.gd"
const POI_CLASS_NAME := "SilentArrayPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const POI_CENTER := Vector2(180.0, 100.0)
const POI_SIZE := Vector2(70.0, 60.0)
const COMPACT_OFFSET := Vector2(-50.0, -10.0)
const SOUTH_ENTRANCE := Vector2(180.0, 70.0)
const NORTH_ENTRANCE := Vector2(180.0, 130.0)
const WEST_ENTRANCE := Vector2(145.0, 100.0)
const CORE_POINT := Vector2(180.0, 124.0)   # 北控制掩体中心

enum Kind {
	BOX,           # 控制箱
	LONG_BOX,      # 倒下天线杆 / 掩体围墙
	TILTED_BOX,    # 倾斜装甲板
	PILLAR,        # 天线塔（高细，主视觉特征）
	DRUM,          # 天线底座（粗矮圆柱）
	WEDGE,         # 混凝土塔基残片
	RUBBLE,        # 锈蚀碎片
}

const OBSTACLES := [
	# ===== 子区 1: 南入口荒原（Z=72-85，散落天线碎片，开放）=====
	[Kind.RUBBLE, 175.0, 75.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 190.0, 78.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.LONG_BOX, 200.0, 82.0, 5.0, 1.5, 1.0, 30.0],   # 倒下的天线杆
	[Kind.LONG_BOX, 163.0, 80.0, 6.0, 1.5, 1.0, -20.0],
	[Kind.BOX, 180.0, 84.0, 2.0, 2.0, 2.0, 15.0],

	# ===== 子区 2: 天线塔林（Z=86-108，14 根高细 PILLAR 网格 + 视觉阻断）=====
	# 第一排（Z 88-91）
	[Kind.PILLAR, 168.0, 90.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 175.0, 88.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 183.0, 90.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 192.0, 88.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 200.0, 91.0, 1.2, 5.5, 1.2, 0.0],
	# 第二排（Z 96-102）
	[Kind.PILLAR, 163.0, 98.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 172.0, 99.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 186.0, 96.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 195.0, 102.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 205.0, 100.0, 1.2, 5.5, 1.2, 0.0],
	# 第三排（Z 105-108）
	[Kind.PILLAR, 167.0, 105.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 178.0, 107.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 190.0, 108.0, 1.2, 5.5, 1.2, 0.0],
	[Kind.PILLAR, 202.0, 106.0, 1.2, 5.5, 1.2, 0.0],

	# 天线底座（DRUM）锚定塔林视觉
	[Kind.DRUM, 175.0, 102.0, 3.0, 2.0, 3.0, 0.0],
	[Kind.DRUM, 198.0, 95.0, 3.0, 2.0, 3.0, 0.0],

	# ===== 子区 3: 中央倒塌塔废墟（Z=110-118）=====
	# 大型倒塌天线塔（横向），形成天然掩体线
	[Kind.LONG_BOX, 180.0, 112.0, 12.0, 1.8, 1.5, 0.0],
	[Kind.LONG_BOX, 180.0, 116.0, 10.0, 1.8, 1.5, 5.0],
	# 塔基混凝土残片（向外推 2m 避免与 LONG_BOX 22 紧贴）
	[Kind.WEDGE, 170.0, 113.0, 4.0, 2.5, 2.0, 60.0],
	[Kind.WEDGE, 190.0, 113.0, 4.0, 2.5, 2.0, -60.0],

	# ===== 子区 4: 北控制掩体（Z=120-128，核心容器位）=====
	# 小型混凝土堡垒（南北开口 + 北端短柱）
	[Kind.LONG_BOX, 180.0, 120.0, 8.0, 2.8, 1.5, 0.0],     # 南墙（带核心入口）
	[Kind.LONG_BOX, 173.0, 124.0, 1.5, 2.8, 7.0, 0.0],     # 西墙
	[Kind.LONG_BOX, 187.0, 124.0, 1.5, 2.8, 7.0, 0.0],     # 东墙
	[Kind.PILLAR, 180.0, 127.0, 1.2, 3.0, 1.2, 0.0],       # 内部短柱（北端，背向容器位）

	# ===== 子区 5: 西入口廊道（X=148-160，狭窄）=====
	# 廊道墙位于 X=158（POI 内部 13m），形成 4m 宽 funnel
	[Kind.LONG_BOX, 158.0, 94.0, 8.0, 3.0, 1.5, 90.0],
	[Kind.LONG_BOX, 158.0, 106.0, 8.0, 3.0, 1.5, 90.0],
	[Kind.TILTED_BOX, 152.0, 100.0, 2.5, 2.5, 1.2, -45.0], # 入口前掩体

	# ===== 环绕通道（POI 外圈）=====
	[Kind.RUBBLE, 220.0, 80.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 220.0, 100.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 220.0, 120.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 155.0, 65.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 205.0, 65.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 155.0, 135.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 205.0, 135.0, 2.5, 1.0, 2.5, 0.0],

	# ===== POI 外墙（3 入口外封闭；侧/南北墙缩短避免角落重叠）=====
	# 南墙 Z=70，中央 8m 入口
	[Kind.LONG_BOX, 199.5, 70.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 160.5, 70.0, 31.0, 3.0, 1.5, 0.0],
	# 北墙 Z=130，中央 8m 入口
	[Kind.LONG_BOX, 199.5, 130.0, 31.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 160.5, 130.0, 31.0, 3.0, 1.5, 0.0],
	# 西墙 X=145，中央 8m 入口（Z 缩 1m 避开南北角）
	[Kind.LONG_BOX, 145.0, 83.5, 1.5, 3.0, 25.0, 0.0],
	[Kind.LONG_BOX, 145.0, 116.5, 1.5, 3.0, 25.0, 0.0],
	# 东墙 X=215，全封无口（Z 缩 2m 避开南北角）
	[Kind.LONG_BOX, 215.0, 100.0, 1.5, 3.0, 58.0, 0.0],
]


static func get_zone_def() -> Dictionary:
	return {
		"name": "静默阵列",
		"center": POI_CENTER + COMPACT_OFFSET,
		"size": POI_SIZE,
		"risk": "high",
		"enemy_density": 1.55,
		"container_density": 1.5,
		"high_value_weight": 0.88,
	}


const CONTAINERS := [
	# 北控制掩体 3 个核心高价值（Z=122 一行，避开北端 PILLAR）
	[176.0, 122.0, "high", [ITEM_RELIC, ITEM_RELIC, ITEM_PURIFIER]],
	[180.0, 122.0, "high", [ITEM_RELIC, ITEM_PURIFIER]],
	[184.0, 122.0, "high", [ITEM_RELIC, ITEM_RELIC]],
	# 塔林北部 1 个（藏在 PILLAR 与中央塔废墟之间）
	[172.0, 108.0, "high", [ITEM_BATTERY, ITEM_RELIC]],
	# 南入口 1 个（弹药）
	[195.0, 78.0, "high", [ITEM_AMMO, ITEM_AMMO, ITEM_BATTERY]],
]


const SPAWNS := [
	["patrol", 175.0, 95.0],      # 塔林西侧巡逻
	["patrol", 195.0, 100.0],     # 塔林东侧巡逻
	["patrol", 180.0, 110.0],     # 中央塔废墟巡逻（避开 LONG_BOX 23）
	["dormant", 180.0, 125.0],    # 控制掩体守卫
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
		body.name = "SAyObstacle_%d" % count
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
		container.name = "SAyContainer_%d" % count
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
		m.name = "SAyPatrolSpawn_%d" % count if kind_str == "patrol" else "SAyDormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		count += 1
	return count


static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "SilentArrayMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.35, 0.32)   # 暗绿
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.6, 0.35)
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
		push_warning("[SilentArrayPOI] PackedScene.pack failed: %d" % err)
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
		Kind.WEDGE:
			var p := PrismMesh.new()
			p.size = Vector3(sx, sy, sz)
			p.left_to_right = 0.5
			return p
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
			m.albedo_color = Color(0.25, 0.4, 0.3)    # 深绿天线
			m.metallic = 0.7
			m.roughness = 0.4
		Kind.DRUM:
			m.albedo_color = Color(0.45, 0.3, 0.2)    # 锈红天线底座
			m.metallic = 0.4
			m.roughness = 0.7
		Kind.WEDGE:
			m.albedo_color = Color(0.4, 0.4, 0.42)    # 混凝土碎片
			m.metallic = 0.1
			m.roughness = 0.95
		Kind.LONG_BOX:
			m.albedo_color = Color(0.3, 0.38, 0.32)   # 暗绿掩体围墙
			m.metallic = 0.45
			m.roughness = 0.6
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.35, 0.4, 0.38)   # 锈绿装甲板
			m.metallic = 0.5
			m.roughness = 0.65
		Kind.RUBBLE:
			m.albedo_color = Color(0.5, 0.4, 0.3)     # 锈蚀碎片
			m.metallic = 0.1
			m.roughness = 0.95
		_:
			m.albedo_color = Color(0.35, 0.4, 0.3)    # 暗橄榄控制箱
			m.metallic = 0.3
			m.roughness = 0.7
	return m
