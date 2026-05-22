# core_wreck_poi.gd
# Core Wreck POI 程序化构建器（数据驱动，非随机）。
# 基于喜盐茶室《精炼工坊》POI 设计方法论 + 余晖号 PvE 适配。
#
# 设计要点：
#   - 3 进出口（南/西/东），每口到核心点距离 ~25m（公平进入）
#   - 4 子区主题：漏斗 / 压力舱 / 反应核心 / 维护廊道
#   - 中心高危：4 根反应柱 + 拱壁形成多角度夹击位
#   - 环绕通道：POI 外圈零散掩体，撤离迂回用
#
# 每个 POI 自包含：zone 定义 + 障碍 + 容器 + 初始 spawn marker + 地面 zone 标识。
# 在 expedition_map.gd._ready() 中调用 build_all(parents) 一次。
# [AI-ASSISTED] 2026-05-23 - Core Wreck POI 完整布局（POI 驱动重构）
class_name CoreWreckPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

# 自识别用：dump 时回写到此文件 + 节点 meta["poi_class"] 写此字符串
const SOURCE_FILE_PATH := "res://scripts/maps/core_wreck_poi.gd"
const POI_CLASS_NAME := "CoreWreckPOI"

const ContainerScene := preload("res://scenes/container_3d.tscn")
const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")

# POI 几何参考（外部查询用）
const POI_CENTER := Vector2(0.0, 80.0)
const POI_SIZE := Vector2(80.0, 60.0)
const SOUTH_ENTRANCE := Vector2(0.0, 50.0)
const WEST_ENTRANCE := Vector2(-40.0, 80.0)
const EAST_ENTRANCE := Vector2(40.0, 80.0)
const CORE_POINT := Vector2(0.0, 85.0)

# 障碍物类型（决定 mesh shape + 主题材质）
enum Kind {
	BOX,           # 标准方块（通用掩体）
	LONG_BOX,      # 长扁条（铁轨、管道、矮墙）
	TILTED_BOX,    # 旋转方块（倾斜金属板）
	PILLAR,        # 高细圆柱（反应核心柱，标志性 landmark）
	DRUM,          # 粗矮圆柱（工业油罐）
	WEDGE,         # 三角楔（塌陷拱壁）
	RUBBLE,        # 矮小石堆（环绕通道）
}

# 单条障碍数据格式：[Kind, x, z, sx, sy, sz, rotation_y_deg]
#   x/z 为中心坐标（世界系，y 自动落地）
#   sx/sy/sz 为尺寸；PILLAR/DRUM 取 sx 为直径
#   rotation_y_deg 为绕 Y 轴的偏航角（度）
const OBSTACLES := [
	# ===== 子区 1: 南入口漏斗区（Z=50-70，开放低掩体，狙击位多）=====
	[Kind.TILTED_BOX, -10.0, 58.0, 6.0, 2.5, 0.6, -22.0],
	[Kind.TILTED_BOX, 10.0, 58.0, 6.0, 2.5, 0.6, 22.0],
	[Kind.RUBBLE, -15.0, 65.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 15.0, 65.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 0.0, 62.0, 2.0, 1.0, 2.0, 45.0],
	[Kind.RUBBLE, -6.0, 68.0, 1.8, 1.0, 1.8, 30.0],
	[Kind.RUBBLE, 6.0, 68.0, 1.8, 1.0, 1.8, -30.0],

	# 漏斗两侧的隔断（区分子区，保留中间狙击视线）
	[Kind.LONG_BOX, -19.0, 68.0, 1.5, 2.5, 10.0, 0.0],
	[Kind.LONG_BOX, 19.0, 68.0, 1.5, 2.5, 10.0, 0.0],

	# ===== 子区 2: 中央反应核心（X=-15 to +15, Z=75-100）=====
	# 4 根高细柱：标志性 landmark，从远处可见
	[Kind.PILLAR, -8.0, 80.0, 1.5, 5.0, 1.5, 0.0],
	[Kind.PILLAR, 8.0, 80.0, 1.5, 5.0, 1.5, 0.0],
	[Kind.PILLAR, -11.54, 95.0, 1.5, 5.0, 1.5, 0.0],
	[Kind.PILLAR, 8.0, 95.0, 1.5, 5.0, 1.5, 0.0],

	# 塌陷拱壁：半包围核心容器位
	[Kind.WEDGE, -10.0, 87.0, 6.0, 3.5, 2.0, 30.0],
	[Kind.WEDGE, 10.0, 87.0, 6.0, 3.5, 2.0, -30.0],

	# 核心内部散落掩体（避开 (-3, 88) / (3, 88) / (0, 98) 容器，给 1m+ 边缘间距）
	[Kind.BOX, 0.0, 92.0, 3.0, 2.0, 3.0, 0.0],
	[Kind.BOX, -6.0, 95.0, 2.0, 1.8, 2.0, 15.0],
	[Kind.BOX, 6.0, 95.0, 2.0, 1.8, 2.0, -15.0],

	# ===== 子区 3: 西侧压力舱（X=-40 to -15, Z=70-100）=====
	# 油罐组 = 主题视觉锚定
	[Kind.DRUM, -30.0, 78.0, 4.0, 4.0, 4.0, 0.0],
	[Kind.DRUM, -32.0, 88.0, 4.0, 4.0, 4.0, 0.0],
	[Kind.DRUM, -22.0, 92.0, 4.0, 4.0, 4.0, 0.0],
	[Kind.DRUM, -25.0, 73.0, 4.0, 4.0, 4.0, 0.0],

	# 罐组间的掩体（避开 (-28, 84) 容器位）+ 倒下的管道
	[Kind.BOX, -25.0, 80.0, 2.5, 1.8, 2.5, 30.0],
	[Kind.LONG_BOX, -36.0, 82.0, 1.0, 2.5, 6.0, 0.0],
	[Kind.LONG_BOX, -20.0, 85.0, 1.0, 1.8, 4.0, 60.0],

	# ===== 子区 4: 东侧维护廊道（X=+15 to +40, Z=70-100）=====
	# 平行管道（主题视觉锚定）
	[Kind.LONG_BOX, 28.0, 74.0, 18.0, 1.5, 1.0, 0.0],
	[Kind.LONG_BOX, 32.0, 78.0, 14.0, 1.5, 1.0, 0.0],
	[Kind.LONG_BOX, 25.0, 90.0, 16.0, 1.5, 1.0, 0.0],
	[Kind.LONG_BOX, 35.0, 95.0, 8.0, 1.5, 1.0, 0.0],

	# 集装箱节点
	[Kind.BOX, 22.0, 80.0, 3.5, 2.8, 2.5, 0.0],
	[Kind.BOX, 38.0, 88.0, 3.5, 2.8, 2.5, 0.0],
	[Kind.BOX, 30.0, 100.0, 2.5, 2.8, 3.5, 0.0],

	# ===== 环绕通道：POI 外圈零散掩体，撤离迂回 =====
	[Kind.RUBBLE, -48.0, 60.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, -52.0, 90.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, -48.0, 112.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 48.0, 60.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 52.0, 90.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 48.0, 112.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 0.0, 118.0, 4.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, -20.0, 42.0, 3.0, 1.0, 3.0, 0.0],
	[Kind.RUBBLE, 20.0, 42.0, 3.0, 1.0, 3.0, 0.0],

	# ===== POI 外墙：把 3 进出口以外的方向封死 =====
	# 南墙（中央留 8m 入口宽）
	[Kind.LONG_BOX, -25.0, 50.0, 30.0, 2.5, 1.5, 0.0],
	[Kind.LONG_BOX, 25.0, 50.0, 30.0, 2.5, 1.5, 0.0],
	# 西墙（中央留 8m 入口宽）
	[Kind.LONG_BOX, -40.0, 64.0, 1.5, 2.5, 12.0, 0.0],
	[Kind.LONG_BOX, -40.0, 100.0, 1.5, 2.5, 14.0, 0.0],
	# 东墙
	[Kind.LONG_BOX, 40.0, 64.0, 1.5, 2.5, 12.0, 0.0],
	[Kind.LONG_BOX, 40.0, 100.0, 1.5, 2.5, 14.0, 0.0],
	# 北墙（无入口，全封）
	[Kind.LONG_BOX, -20.0, 110.0, 40.0, 2.5, 1.5, 0.0],
	[Kind.LONG_BOX, 20.0, 110.0, 40.0, 2.5, 1.5, 0.0],
]


## POI 的逻辑 zone 定义（HUD 显示 + spawn_manager 密度查询用）
static func get_zone_def() -> Dictionary:
	return {
		"name": "核心残骸",
		"center": POI_CENTER,
		"size": POI_SIZE,
		"risk": "high",
		"enemy_density": 1.8,
		"container_density": 1.7,
		"high_value_weight": 0.95,
	}


## 容器数据：[x, z, risk, loot_array]
## 集中在反应核心，少量在维护廊道
const CONTAINERS := [
	# 核心 3 个高价值容器（遗物 + 净化剂混合）
	[-3.0, 88.0, "high", [ITEM_RELIC, ITEM_RELIC, ITEM_PURIFIER]],
	[3.0, 88.0, "high", [ITEM_RELIC, ITEM_PURIFIER]],
	[0.0, 98.0, "high", [ITEM_RELIC, ITEM_RELIC]],
	# 压力舱 1 个（油罐间藏货）
	[-28.0, 84.0, "high", [ITEM_BATTERY, ITEM_BATTERY, ITEM_PURIFIER]],
	# 维护廊道 1 个
	[30.0, 84.0, "high", [ITEM_AMMO, ITEM_BATTERY, ITEM_RELIC]],
]


## 初始敌人 spawn marker：[kind ("patrol"/"dormant"), x, z]
## 高风险：3 patrol + 2 dormant
const SPAWNS := [
	["patrol", -15.0, 85.0],     # 西南巡逻
	["patrol", 15.0, 85.0],      # 东南巡逻
	["patrol", 0.0, 103.0],      # 北侧巡逻（避开 (0, 98) 容器）
	["dormant", -25.0, 95.0],    # 压力舱潜伏
	["dormant", 28.0, 95.0],     # 维护廊道潜伏
]


## 一键构建本 POI 的全部内容
## parents: { "obstacles": Node3D, "containers": Node3D, "spawns": Node3D, "risk_zones": Node3D }
## 返回 zone def（供 expedition_map 收集进 _risk_zones）
static func build_all(parents: Dictionary) -> Dictionary:
	build_obstacles(parents["obstacles"])
	build_containers(parents["containers"])
	build_spawns(parents["spawns"])
	build_zone_marker(parents["risk_zones"])
	return get_zone_def()


## 把 Core Wreck POI 全部障碍物作为 StaticBody3D 子节点加进 obstacles_parent。
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
		body.name = "CWObstacle_%d" % count
		body.set_meta("poi_class", POI_CLASS_NAME)
		body.set_meta("poi_data_index", count)
		obstacles_parent.add_child(body)
		body.global_position = Vector3(x, sy * 0.5, z)
		body.rotation = Vector3(0.0, deg_to_rad(rot_deg), 0.0)
		count += 1
	return count


static func _make_static_body(kind: int, sx: float, sy: float, sz: float) -> StaticBody3D:
	var prototype := StaticBody3D.new()
	prototype.name = "Obstacle"  # 给 pack() 一个非空名，否则 Godot 报 p_name.is_empty() 警告
	prototype.collision_layer = 4  # layer 3 (Obstacles) per rules.md §3.2
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

	# 把 body+mesh+shape 打包成 PackedScene 再实例化。
	# 这样 editor 把它当作"场景实例"对待（editable_children=false），viewport 点 mesh
	# 视觉时直接选中 body 实例根，拖动整体一起动。
	var packed := PackedScene.new()
	var err: int = packed.pack(prototype)
	prototype.free()
	if err != OK:
		push_warning("[CoreWreckPOI] PackedScene.pack failed: %d" % err)
		return StaticBody3D.new()
	return packed.instantiate() as StaticBody3D


## 把容器加进 containers_parent
static func build_containers(containers_parent: Node3D) -> int:
	var count: int = 0
	for entry in CONTAINERS:
		var x: float = entry[0]
		var z: float = entry[1]
		var risk: String = entry[2]
		var loot_list: Array = entry[3]
		var container := ContainerScene.instantiate() as StaticBody3D
		container.name = "CWContainer_%d" % count
		container.set_meta("poi_class", POI_CLASS_NAME)
		container.set_meta("poi_data_index", count)
		containers_parent.add_child(container)
		container.global_position = Vector3(x, 0.0, z)
		container.risk = risk
		# typed array assignment trick（避免 "Invalid assignment of property loot_table"）
		var typed_loot: Array[ItemData] = []
		typed_loot.assign(loot_list)
		container.loot_table = typed_loot
		count += 1
	return count


## 把初始 spawn Marker3D 加进 spawns_parent（spawn_manager 按 name.contains("dormant") 识别类型）
static func build_spawns(spawns_parent: Node3D) -> int:
	var count: int = 0
	for entry in SPAWNS:
		var kind_str: String = entry[0]
		var x: float = entry[1]
		var z: float = entry[2]
		var m := Marker3D.new()
		m.name = "CWPatrolSpawn_%d" % count if kind_str == "patrol" else "CWDormantSpawn_%d" % count
		m.set_meta("poi_class", POI_CLASS_NAME)
		m.set_meta("poi_data_index", count)
		spawns_parent.add_child(m)
		m.global_position = Vector3(x, 0.0, z)
		count += 1
	return count


## dump 当前编辑器里 CoreWreckPOI 节点的位置回写到 SOURCE_FILE_PATH
static func dump_current_state(parents: Dictionary) -> Dictionary:
	return POIDumpUtilityScript.dump(SOURCE_FILE_PATH, POI_CLASS_NAME, parents)


## 在 risk_zones_parent 下创建一个地面 zone 边界标识（半透明色块）
static func build_zone_marker(risk_zones_parent: Node3D) -> void:
	var def := get_zone_def()
	var marker := MeshInstance3D.new()
	marker.name = "CoreWreckMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def["size"].x, 0.02, def["size"].y)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.2, 0.18, 0.35)   # 高风险 = 暗红
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.15, 0.1)
	mat.emission_energy_multiplier = 0.4
	marker.material_override = mat
	risk_zones_parent.add_child(marker)
	marker.global_position = Vector3(def["center"].x, 0.001, def["center"].y)


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
			m.albedo_color = Color(0.45, 0.5, 0.55)   # 冷灰金属
			m.metallic = 0.7
			m.roughness = 0.35
		Kind.DRUM:
			m.albedo_color = Color(0.55, 0.32, 0.22)  # 锈红铁罐
			m.metallic = 0.5
			m.roughness = 0.7
		Kind.WEDGE:
			m.albedo_color = Color(0.3, 0.3, 0.32)    # 深灰塌陷拱壁
			m.metallic = 0.3
			m.roughness = 0.9
		Kind.LONG_BOX:
			m.albedo_color = Color(0.4, 0.42, 0.38)   # 工业灰
			m.metallic = 0.4
			m.roughness = 0.6
		Kind.TILTED_BOX:
			m.albedo_color = Color(0.5, 0.45, 0.38)   # 锈金属板
			m.metallic = 0.5
			m.roughness = 0.6
		Kind.RUBBLE:
			m.albedo_color = Color(0.38, 0.32, 0.25)  # 沙石褐
			m.metallic = 0.0
			m.roughness = 1.0
		_:
			m.albedo_color = Color(0.45, 0.43, 0.4)
			m.metallic = 0.3
			m.roughness = 0.7
	return m
