# black_yard_poi.gd
# Black Yard POI — HIGH 风险，南远方位 (0, -150)
# 主题：碾碎磁轨车场 + 油罐密集区。颜色调：深钢灰 + 暗橙锈红（油罐）。
#
# 设计要点：
#   - 3 进出口（北/东/西），南接地图边界（无入口，地图自带 boundary）
#   - 5 子区：北接近 / 中央车厢残骸 / 西油罐簇 / 东油罐簇 / 南死区核心容器位
#   - 视频原则 5（中心高危）：南死区 = 高价值容器位，3 入口都需穿越东西油罐簇才能抵达
#   - 视频原则 3（主题区分）：碾碎车厢横躺 + 大量 DRUM 油罐 跟其它 POI 区分
# [AI-ASSISTED] 2026-05-23 - Black Yard POI
class_name BlackYardPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/black_yard_poi.gd"
const POI_CLASS_NAME := "BlackYardPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const POI_CENTER := Vector2(0.0, -150.0)
const POI_SIZE := Vector2(80.0, 50.0)
const COMPACT_OFFSET := Vector2(0.0, 35.0)
const NORTH_ENTRANCE := Vector2(0.0, -125.0)
const EAST_ENTRANCE := Vector2(40.0, -150.0)
const WEST_ENTRANCE := Vector2(-40.0, -150.0)
const CORE_POINT := Vector2(0.0, -170.0)   # 南死区核心

enum Kind {
	BOX,
	LONG_BOX,      # 大型碾碎车厢
	TILTED_BOX,    # 倾倒车厢段
	PILLAR,        # 弯折磁轨柱
	DRUM,          # 油罐（密集）
	WEDGE,         # 塌陷顶盖
	RUBBLE,        # 散落金属碎片
}

const OBSTACLES := [
	# ===== 子区 1: 北接近（Z -125~-135，零散导入）=====
	[Kind.BOX, -10.0, -130.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.BOX, 10.0, -130.0, 2.0, 2.0, 2.0, 15.0],
	[Kind.RUBBLE, -20.0, -132.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 20.0, -132.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 0.0, -136.0, 2.5, 1.0, 2.5, 30.0],

	# ===== 子区 2: 中央车厢残骸（Z -140~-160，X -16~16）=====
	# 2 大型横躺车厢（X 轴向，错位，避开中央 TILTED_BOX 的旋转 AABB）
	[Kind.LONG_BOX, -10.0, -141.0, 12.0, 3.0, 3.5, 0.0],
	[Kind.LONG_BOX, 10.0, -159.0, 12.0, 3.0, 3.5, 0.0],
	# 倾倒车厢段
	[Kind.TILTED_BOX, 0.0, -150.0, 8.0, 3.0, 2.5, 45.0],
	# 塌陷顶盖
	[Kind.WEDGE, 0.0, -161.0, 6.0, 2.5, 3.0, 0.0],

	# ===== 子区 3: 西油罐簇（X -35~-22，Z -140~-162）=====
	[Kind.DRUM, -30.0, -140.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, -34.0, -150.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, -26.0, -155.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, -32.0, -160.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, -25.0, -145.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.PILLAR, -28.0, -134.0, 1.2, 4.0, 1.2, 0.0],
	[Kind.PILLAR, -28.0, -167.0, 1.2, 4.0, 1.2, 0.0],

	# ===== 子区 4: 东油罐簇（X 22~35，Z -140~-162，镜像）=====
	[Kind.DRUM, 30.0, -140.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, 34.0, -150.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, 26.0, -155.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, 32.0, -160.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.DRUM, 25.0, -145.0, 3.0, 3.0, 3.0, 0.0],
	[Kind.PILLAR, 28.0, -134.0, 1.2, 4.0, 1.2, 0.0],
	[Kind.PILLAR, 28.0, -167.0, 1.2, 4.0, 1.2, 0.0],

	# ===== 子区 5: 南死区（Z -165~-173，核心容器位 + 哨柱）=====
	[Kind.LONG_BOX, -18.0, -170.0, 6.0, 2.5, 1.5, 0.0],   # 分隔墙左
	[Kind.LONG_BOX, 18.0, -170.0, 6.0, 2.5, 1.5, 0.0],    # 分隔墙右
	[Kind.PILLAR, 0.0, -172.0, 1.2, 4.0, 1.2, 0.0],       # 中央哨柱

	# ===== 环绕通道（POI 外圈）=====
	[Kind.RUBBLE, -45.0, -130.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -45.0, -150.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -45.0, -170.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 45.0, -130.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 45.0, -150.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 45.0, -170.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -30.0, -120.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 30.0, -120.0, 2.5, 1.0, 2.5, 0.0],

	# ===== POI 外墙（3 入口外封闭，Z 缩 1-2m 避开角落）=====
	# 北墙 Z=-125，中央 8m 入口
	[Kind.LONG_BOX, -22.0, -125.0, 36.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 22.0, -125.0, 36.0, 3.0, 1.5, 0.0],
	# 南墙 Z=-175 全封（接地图边界）
	[Kind.LONG_BOX, 0.0, -175.0, 80.0, 3.0, 1.5, 0.0],
	# 东墙 X=40，中央 Z=-154~-146 留 8m 入口（Z 缩 1m）
	[Kind.LONG_BOX, 40.0, -163.5, 1.5, 3.0, 21.0, 0.0],
	[Kind.LONG_BOX, 40.0, -136.5, 1.5, 3.0, 21.0, 0.0],
	# 西墙 X=-40，中央 8m 入口
	[Kind.LONG_BOX, -40.0, -163.5, 1.5, 3.0, 21.0, 0.0],
	[Kind.LONG_BOX, -40.0, -136.5, 1.5, 3.0, 21.0, 0.0],
]


static func get_zone_def() -> Dictionary:
	return {
		"name": "黑域场",
		"center": POI_CENTER + COMPACT_OFFSET,
		"size": POI_SIZE,
		"risk": "high",
		"enemy_density": 1.7,
		"container_density": 1.55,
		"high_value_weight": 0.9,
	}


const CONTAINERS := [
	# 南死区 3 个核心高价值
	[-10.0, -168.0, "high", [ITEM_RELIC, ITEM_RELIC, ITEM_PURIFIER]],
	[0.0, -168.0, "high", [ITEM_RELIC, ITEM_PURIFIER]],
	[10.0, -168.0, "high", [ITEM_RELIC, ITEM_RELIC]],
	# 西油罐簇 1 个（藏在罐间）
	[-30.0, -148.0, "high", [ITEM_BATTERY, ITEM_BATTERY, ITEM_RELIC]],
	# 东油罐簇 1 个
	[30.0, -148.0, "high", [ITEM_AMMO, ITEM_BATTERY, ITEM_RELIC]],
]


const SPAWNS := [
	["patrol", -18.0, -140.0],     # 中央车厢西（避开 carriage 1）
	["patrol", 15.0, -140.0],      # 中央车厢东
	["patrol", 0.0, -164.0],       # 南死区前哨（避开 WEDGE）
	["dormant", -32.0, -146.0],    # 西油罐潜伏
	["dormant", 32.0, -146.0],     # 东油罐潜伏
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
		body.name = "BYObstacle_%d" % count
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
		container.name = "BYContainer_%d" % count
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
		m.name = "BYPatrolSpawn_%d" % count if kind_str == "patrol" else "BYDormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		count += 1
	return count


static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "BlackYardMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.3, 0.1, 0.35)  # 暗橙锈红
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.25, 0.08)
	mat.emission_energy_multiplier = 0.4
	marker.material_override = mat
	risk_zones_parent.add_child(marker)
	marker.global_position = Vector3(def["center"].x, 0.001, def["center"].y)


static func dump_current_state(parents: Dictionary) -> Dictionary:
	return POIDumpUtilityScript.dump(SOURCE_FILE_PATH, POI_CLASS_NAME, parents)


static func _make_static_body(kind: int, sx: float, sy: float, sz: float) -> StaticBody3D:
	var prototype := StaticBody3D.new()
	prototype.name = "Obstacle"
	prototype.collision_layer = 64 if sy <= 1.0 else 4
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
		push_warning("[BlackYardPOI] PackedScene.pack failed: %d" % err)
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
			m.albedo_color = Color(0.32, 0.3, 0.28)  # 暗钢灰（弯铁轨）
			m.metallic = 0.6
			m.roughness = 0.55
		Kind.DRUM:
			m.albedo_color = Color(0.6, 0.32, 0.12)  # 暗橙锈红（油罐）
			m.metallic = 0.5
			m.roughness = 0.65
		Kind.WEDGE:
			m.albedo_color = Color(0.32, 0.3, 0.3)   # 钢灰塌顶
			m.metallic = 0.4
			m.roughness = 0.75
		Kind.LONG_BOX:
			m.albedo_color = Color(0.3, 0.28, 0.26)  # 深钢灰（碎车厢）
			m.metallic = 0.55
			m.roughness = 0.55
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.4, 0.3, 0.25)   # 锈钢（倾倒）
			m.metallic = 0.55
			m.roughness = 0.7
		Kind.RUBBLE:
			m.albedo_color = Color(0.4, 0.32, 0.25)  # 暗褐金属碎片
			m.metallic = 0.15
			m.roughness = 0.95
		_:
			m.albedo_color = Color(0.35, 0.3, 0.28)
			m.metallic = 0.3
			m.roughness = 0.7
	return m
