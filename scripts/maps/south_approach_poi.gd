# south_approach_poi.gd
# South Approach POI — 最小 LOW 风险占位区，验证 POI 接口 + 满足 test 的"至少 1 LOW zone"约束。
# 待后续扩展为完整设计（参考喜盐茶室 POI 方法论）。
#
# 当前内容：1 中央广场 + 几条铁轨段 + 3 容器 + 2 spawn marker。
# 位置：玩家出生点正南 (0, -50)，距 SPAWN ~50m。
# [AI-ASSISTED] 2026-05-23 - 最小 LOW POI 骨架，等待完整设计
class_name SouthApproachPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/south_approach_poi.gd"
const POI_CLASS_NAME := "SouthApproachPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

const POI_CENTER := Vector2(0.0, -60.0)
const POI_SIZE := Vector2(60.0, 50.0)
const COMPACT_OFFSET := Vector2(0.0, 15.0)

enum Kind { BOX, LONG_BOX, TILTED_BOX, PILLAR, RUBBLE }

const OBSTACLES := [
	# ===== 子区 1: 北入口接近（Z -38~-50，散落入门）=====
	[Kind.BOX, -10.0, -40.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.BOX, 10.0, -40.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.RUBBLE, -15.0, -45.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 15.0, -45.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 0.0, -50.0, 2.0, 1.0, 2.0, 0.0],

	# ===== 子区 2: 中央磁轨场（Z -55~-72，3 平行铁轨 + 倾倒车厢段）=====
	[Kind.LONG_BOX, 0.0, -58.0, 24.0, 0.6, 0.8, 0.0],
	[Kind.LONG_BOX, 0.0, -63.0, 24.0, 0.6, 0.8, 0.0],
	[Kind.LONG_BOX, 0.0, -68.0, 24.0, 0.6, 0.8, 0.0],
	[Kind.TILTED_BOX, 0.0, -65.5, 4.0, 2.5, 1.5, 30.0],   # 倾倒车厢段（缩小以避开 rails）
	[Kind.BOX, -8.0, -55.0, 2.5, 2.0, 2.5, 0.0],
	[Kind.BOX, 8.0, -72.0, 2.5, 2.0, 2.5, 0.0],
	[Kind.PILLAR, -14.0, -60.0, 1.0, 3.0, 1.0, 0.0],
	[Kind.PILLAR, 14.0, -60.0, 1.0, 3.0, 1.0, 0.0],

	# ===== 子区 3: 南出口（Z -75~-83）=====
	[Kind.LONG_BOX, -10.0, -78.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.LONG_BOX, 10.0, -78.0, 4.0, 2.0, 1.5, 0.0],
	[Kind.BOX, 0.0, -82.0, 2.0, 2.0, 2.0, 0.0],

	# ===== 子区 4: 东侧货栈（X 18~28）=====
	[Kind.BOX, 22.0, -50.0, 2.5, 2.0, 2.5, 0.0],
	[Kind.BOX, 24.0, -70.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.LONG_BOX, 27.0, -60.0, 1.5, 2.0, 6.0, 0.0],
	[Kind.RUBBLE, 25.0, -78.0, 2.0, 1.0, 2.0, 0.0],

	# ===== 环绕通道 =====
	[Kind.RUBBLE, -35.0, -50.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, -35.0, -75.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 35.0, -45.0, 2.0, 1.0, 2.0, 0.0],

	# ===== POI 外墙（3 入口外封闭：北/南/东）=====
	# 北墙 Z=-35，中央 X=-4~+4 留 8m 入口
	[Kind.LONG_BOX, -17.5, -35.0, 25.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 17.5, -35.0, 25.0, 3.0, 1.5, 0.0],
	# 南墙 Z=-85，中央 8m 入口
	[Kind.LONG_BOX, -17.5, -85.0, 25.0, 3.0, 1.5, 0.0],
	[Kind.LONG_BOX, 17.5, -85.0, 25.0, 3.0, 1.5, 0.0],
	# 东墙 X=30，中央 Z=-64~-56 留 8m 入口
	[Kind.LONG_BOX, 30.0, -75.5, 1.5, 3.0, 17.0, 0.0],
	[Kind.LONG_BOX, 30.0, -44.5, 1.5, 3.0, 17.0, 0.0],
	# 西墙 X=-30，全封无口
	[Kind.LONG_BOX, -30.0, -60.0, 1.5, 3.0, 48.0, 0.0],
]

const CONTAINERS := [
	# 中央磁轨场附近 1 个（rails 之间的空隙 Z -58~-63）
	[-5.0, -60.5, "low", [ITEM_AMMO, ITEM_BATTERY]],
	# 南出口 1 个
	[0.0, -75.0, "low", [ITEM_AMMO, ITEM_PURIFIER]],
	# 东侧货栈 1 个
	[22.0, -60.0, "low", [ITEM_BATTERY, ITEM_AMMO]],
]

const SPAWNS := [
	["patrol", -18.0, -60.0],     # 中央磁轨西侧
	["patrol", 18.0, -55.0],      # 中央磁轨东侧（错开避开 PILLAR）
]


static func get_zone_def() -> Dictionary:
	return {
		"name": "南方走廊",
		"center": POI_CENTER + COMPACT_OFFSET,
		"size": POI_SIZE,
		"risk": "low",
		"enemy_density": 0.4,
		"container_density": 0.45,
		"high_value_weight": 0.15,
	}


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
		body.name = "SAObstacle_%d" % count
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
		container.name = "SAContainer_%d" % count
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
		m.name = "SAPatrolSpawn_%d" % count if kind_str == "patrol" else "SADormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x + COMPACT_OFFSET.x, 0.0, z + COMPACT_OFFSET.y)
		count += 1
	return count


## dump 当前编辑器里 SouthApproachPOI 节点位置回写到 SOURCE_FILE_PATH
static func dump_current_state(parents: Dictionary) -> Dictionary:
	return POIDumpUtilityScript.dump(SOURCE_FILE_PATH, POI_CLASS_NAME, parents)


static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "SouthApproachMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.5, 0.3, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 0.3)
	mat.emission_energy_multiplier = 0.25
	marker.material_override = mat
	risk_zones_parent.add_child(marker)
	marker.global_position = Vector3(def["center"].x, 0.001, def["center"].y)


static func _make_static_body(kind: int, sx: float, sy: float, sz: float) -> StaticBody3D:
	var prototype := StaticBody3D.new()
	prototype.name = "Obstacle"  # 同 core_wreck_poi：pack 前必须有非空 name
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

	# Pack 成 PackedScene 实例化（同 core_wreck_poi 解释）
	var packed := PackedScene.new()
	var err: int = packed.pack(prototype)
	prototype.free()
	if err != OK:
		push_warning("[SouthApproachPOI] PackedScene.pack failed: %d" % err)
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
			m.albedo_color = Color(0.3, 0.3, 0.32)    # 黑灰信号柱
			m.metallic = 0.6
			m.roughness = 0.5
		Kind.LONG_BOX:
			m.albedo_color = Color(0.42, 0.4, 0.36)   # 锈铁轨
			m.metallic = 0.5
			m.roughness = 0.6
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.35, 0.35, 0.35)  # 钢灰倾倒
			m.metallic = 0.5
			m.roughness = 0.65
		Kind.RUBBLE:
			m.albedo_color = Color(0.4, 0.35, 0.28)   # 沙石
			m.metallic = 0.0
			m.roughness = 1.0
		_:
			m.albedo_color = Color(0.45, 0.43, 0.4)
			m.metallic = 0.3
			m.roughness = 0.7
	return m
