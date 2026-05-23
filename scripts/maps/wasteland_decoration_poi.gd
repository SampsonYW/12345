# wasteland_decoration_poi.gd
# 装饰用 POI — 在主 POI 之间的空地散布零碎掩体，给地图增添废土感。
# 不参与 zone 逻辑（build_all 返回空 dict），不放容器、不放 spawn。
# [AI-ASSISTED] 2026-05-23 - 紧凑化地图后的装饰填充
class_name WastelandDecorationPOI
extends RefCounted

const POIDumpUtilityScript := preload("res://scripts/maps/poi_dump_utility.gd")

const SOURCE_FILE_PATH := "res://scripts/maps/wasteland_decoration_poi.gd"
const POI_CLASS_NAME := "WastelandDecorationPOI"

enum Kind {
	BOX,
	PILLAR,
	DRUM,
	RUBBLE,
}

# 散布在 POI 之间的空地。位置精心选过，不跟主 POI 外墙冲突。
const OBSTACLES := [
	# ===== 北部 POI 间走廊（Z 50~65，FD-CW-SA 之间）=====
	[Kind.RUBBLE, -60.0, 50.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.PILLAR, -70.0, 55.0, 1.0, 3.0, 1.0, 0.0],
	[Kind.BOX, -55.0, 45.0, 2.0, 2.0, 2.0, 15.0],
	[Kind.RUBBLE, 60.0, 50.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.PILLAR, 70.0, 55.0, 1.0, 3.0, 1.0, 0.0],
	[Kind.BOX, 55.0, 45.0, 2.0, 2.0, 2.0, -15.0],

	# ===== 中央 spawn 周边（Z -15~+25，CW/AO/BR/SPAWN 之间）=====
	[Kind.RUBBLE, -10.0, 10.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 10.0, 10.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, -20.0, -10.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 20.0, -10.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.DRUM, -55.0, 0.0, 2.0, 2.0, 2.0, 0.0],
	[Kind.DRUM, 55.0, 0.0, 2.0, 2.0, 2.0, 0.0],

	# ===== SA 与 BY 之间过渡区（Z -75~-90）=====
	[Kind.RUBBLE, -15.0, -80.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.RUBBLE, 15.0, -80.0, 2.0, 1.0, 2.0, 0.0],
	[Kind.BOX, 0.0, -85.0, 2.0, 1.5, 2.0, 0.0],

	# ===== 南端废土（Z < -115，BY 之后）=====
	[Kind.RUBBLE, -50.0, -150.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 50.0, -150.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.PILLAR, 0.0, -160.0, 1.2, 3.0, 1.2, 0.0],

	# ===== 北端废土（Z > +120）=====
	[Kind.RUBBLE, -80.0, 140.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 80.0, 140.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.PILLAR, 0.0, 145.0, 1.2, 3.5, 1.2, 0.0],
	[Kind.BOX, -150.0, 145.0, 2.0, 2.0, 2.0, 20.0],
	[Kind.BOX, 150.0, 145.0, 2.0, 2.0, 2.0, -20.0],

	# ===== 远东远西边界装饰 =====
	[Kind.RUBBLE, -250.0, 0.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -250.0, 80.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, -250.0, -80.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 250.0, 0.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 250.0, 80.0, 2.5, 1.0, 2.5, 0.0],
	[Kind.RUBBLE, 250.0, -80.0, 2.5, 1.0, 2.5, 0.0],
]

# 装饰 POI 没有容器和 spawn
const CONTAINERS := []
const SPAWNS := []


## 装饰 POI 不参与 zone 逻辑，返回空 dict（expedition_map 会跳过）
static func get_zone_def() -> Dictionary:
	return {}


static func build_all(parents: Dictionary) -> Dictionary:
	build_obstacles(parents["obstacles"])
	return {}


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
		body.name = "WDObstacle_%d" % count
		body.set_meta("poi_class", POI_CLASS_NAME)
		body.set_meta("poi_data_index", count)
		obstacles_parent.add_child(body)
		body.global_position = Vector3(x, sy * 0.5, z)
		body.rotation = Vector3(0.0, deg_to_rad(rot_deg), 0.0)
		count += 1
	return count


static func build_containers(_containers_parent: Node3D) -> int:
	return 0


static func build_spawns(_spawns_parent: Node3D) -> int:
	return 0


static func build_zone_marker(_risk_zones_parent: Node3D) -> void:
	pass


static func dump_current_state(parents: Dictionary) -> Dictionary:
	return POIDumpUtilityScript.dump(SOURCE_FILE_PATH, POI_CLASS_NAME, parents)


static func _make_static_body(kind: int, sx: float, sy: float, sz: float) -> StaticBody3D:
	var prototype := StaticBody3D.new()
	prototype.name = "Decor"
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
		push_warning("[WastelandDecorationPOI] PackedScene.pack failed: %d" % err)
		return StaticBody3D.new()
	return packed.instantiate() as StaticBody3D


static func _make_mesh(kind: int, sx: float, sy: float, sz: float) -> Mesh:
	match kind:
		Kind.PILLAR, Kind.DRUM:
			var c := CylinderMesh.new()
			c.top_radius = sx * 0.5
			c.bottom_radius = sx * 0.5
			c.height = sy
			c.radial_segments = 10
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
			m.albedo_color = Color(0.32, 0.3, 0.28)
			m.metallic = 0.5
			m.roughness = 0.55
		Kind.DRUM:
			m.albedo_color = Color(0.42, 0.32, 0.22)
			m.metallic = 0.35
			m.roughness = 0.75
		Kind.RUBBLE:
			m.albedo_color = Color(0.42, 0.38, 0.32)   # 中性灰褐废土
			m.metallic = 0.0
			m.roughness = 1.0
		_:
			m.albedo_color = Color(0.4, 0.38, 0.35)
			m.metallic = 0.2
			m.roughness = 0.8
	return m
