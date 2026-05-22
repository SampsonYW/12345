# poi_overlap_runtime_checks.gd
# 遍历所有 POI 节点（Obstacles + Containers + InitialSpawns），做 AABB pair-wise 重叠检测。
# 发现重叠（OVERLAP）= fail；发现紧贴（< 0.25m gap，TIGHT）= warn。
# 同 POI 的 obstacle-obstacle pair 不做 TIGHT 检查（墙之间挨着是正常的）。
extends SceneTree

var _failures: Array[String] = []
var _warnings: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	for i in 8:
		await physics_frame

	var expedition := scene.get_node_or_null("World/ExpeditionMap")
	if expedition == null:
		push_error("Cannot find World/ExpeditionMap")
		quit(1)
		return

	var obstacles_parent := expedition.get_node_or_null("Obstacles") as Node
	var containers_parent := expedition.get_node_or_null("Containers") as Node
	var spawns_parent := expedition.get_node_or_null("InitialSpawns") as Node

	if obstacles_parent == null or containers_parent == null or spawns_parent == null:
		push_error("Missing parent nodes")
		quit(1)
		return

	var entries: Array = []
	for child in obstacles_parent.get_children():
		var e := _collect_obstacle(child)
		if not e.is_empty():
			entries.append(e)
	for child in containers_parent.get_children():
		entries.append(_make_entry(child, "container", 0.6, 0.6))
	for child in spawns_parent.get_children():
		# Spawn marker: treat as 0.5m radius (enemy footprint)
		entries.append(_make_entry(child, "spawn", 0.5, 0.5))

	# Pairwise check
	for i in entries.size():
		for j in range(i + 1, entries.size()):
			_check_pair(entries[i], entries[j])

	_finish(scene)


func _collect_obstacle(node: Node) -> Dictionary:
	if not (node is Node3D):
		return {}
	# Find inner Mesh + Shape (PackedScene instance has them as children)
	var mesh_inst: MeshInstance3D = null
	for child in node.get_children():
		if child is MeshInstance3D:
			mesh_inst = child
			break
	if mesh_inst == null:
		return {}
	var mesh := mesh_inst.mesh
	if mesh == null:
		return {}
	# Use mesh AABB rotated by parent's Y rotation
	var local_aabb := mesh.get_aabb()
	var half_x := absf(local_aabb.size.x) * 0.5
	var half_z := absf(local_aabb.size.z) * 0.5
	# For CylinderMesh, size returns 2*radius which is correct
	var rot_y: float = (node as Node3D).rotation.y
	var world_half_x: float = absf(half_x * cos(rot_y)) + absf(half_z * sin(rot_y))
	var world_half_z: float = absf(half_x * sin(rot_y)) + absf(half_z * cos(rot_y))
	var pos: Vector3 = (node as Node3D).global_position
	return {
		"name": node.name,
		"x": pos.x,
		"z": pos.z,
		"hx": world_half_x,
		"hz": world_half_z,
		"kind": "obstacle",
	}


func _make_entry(node: Node, kind: String, hx: float, hz: float) -> Dictionary:
	var pos: Vector3 = (node as Node3D).global_position
	return {
		"name": node.name,
		"x": pos.x,
		"z": pos.z,
		"hx": hx,
		"hz": hz,
		"kind": kind,
	}


func _check_pair(a: Dictionary, b: Dictionary) -> void:
	var dx: float = absf(a["x"] - b["x"])
	var dz: float = absf(a["z"] - b["z"])
	var sum_x: float = a["hx"] + b["hx"]
	var sum_z: float = a["hz"] + b["hz"]
	var gap_x: float = dx - sum_x  # positive = no overlap
	var gap_z: float = dz - sum_z
	if gap_x < 0 and gap_z < 0:
		_failures.append("OVERLAP: %s (%s @ %.1f,%.1f) <-> %s (%s @ %.1f,%.1f) — overlap X=%.2f Z=%.2f" % [
			a["name"], a["kind"], a["x"], a["z"],
			b["name"], b["kind"], b["x"], b["z"],
			-gap_x, -gap_z
		])
		return
	# Tight clearance (excluding obstacle-obstacle which is fine to be near each other)
	var skip_tight: bool = (a["kind"] == "obstacle" and b["kind"] == "obstacle")
	if not skip_tight and gap_x < 0.25 and gap_z < 0.25:
		_warnings.append("TIGHT: %s (%s) <-> %s (%s) — gap X=%.2f Z=%.2f" % [
			a["name"], a["kind"], b["name"], b["kind"], gap_x, gap_z
		])


func _finish(scene: Node) -> void:
	scene.queue_free()
	for w in _warnings:
		push_warning(w)
	if _failures.is_empty():
		print("POI overlap checks passed. (%d tight clearances)" % _warnings.size())
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("POI overlap checks FAILED — %d overlaps, %d tight." % [_failures.size(), _warnings.size()])
	quit(1)
