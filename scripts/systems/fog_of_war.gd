# fog_of_war.gd
# Player visibility system (Project Zomboid style).
# 视野锥（鼠标瞄向方向）+ 近距 360° 感知圆 + 障碍遮挡（layer-3 raycast）。
# 锥/圆外的 enemies/pickups 节点会被设为不可见（.visible = false）；进入视野后恢复。
# 视野锥长度随侵蚀缩短。
# 文件名沿用 fog_of_war 以保留 fog_of_war.tscn 的 script path 引用与 .uid。
# [AI-ASSISTED] 2026-05-21 - 由"探索迷雾"重构为"可视视野" (design.md §9.6)
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node3D

@export_group("Vision Shape")
## 视野锥最大射程（米），鼠标瞄向方向
@export var cone_range: float = 14.0
## 视野锥半夹角（度）。总开角 = 2× 此值；默认 60° → 120° 总开角
@export var cone_half_angle_deg: float = 60.0
## 近距全向感知圆半径（米）。在此圆内不受锥角限制，仍可见
@export var close_radius: float = 3.5

@export_group("Erosion Coupling")
## 侵蚀拉满时，cone_range 缩到此倍数（0.5 = 一半）。design.md §5.4
@export_range(0.1, 1.0, 0.05) var erosion_cone_shrink: float = 0.5
## 侵蚀拉满时，close_radius 缩到此倍数
@export_range(0.5, 1.0, 0.05) var erosion_close_shrink: float = 0.85

@export_group("Occlusion")
## 障碍物碰撞层位掩码。默认 bit 2 = layer 3 (Obstacles)，见 rules.md §3.2
@export_flags_3d_physics var obstacle_mask: int = 1 << 2
## 射线源/目标的离地抬升量，避免被地板/角色脚部碰撞剪掉
@export var ray_height_offset: float = 1.0

@export_group("Target Groups")
## 视野判定生效的 group 列表
@export var visibility_groups: PackedStringArray = PackedStringArray(["enemies", "pickups"])

@export_group("Performance")
## 视野判定刷新间隔（秒）。0.05 = 20Hz，已经够丝滑
@export var update_interval: float = 0.05

@export_group("Debug Visuals")
## 是否在地面绘制视野范围（透明半盘 + 锥）
@export var draw_debug_visuals: bool = true
## 锥扇形顶点细分数
@export_range(8, 64, 1) var cone_segments: int = 28

var _player: Node3D = null
var _tick_timer: float = 0.0
var _current_cone_range: float = 0.0
var _current_close_radius: float = 0.0

# Existing scene nodes (fog_of_war.tscn) — VisionDisc 复用为"近距感知圆"
var _close_disc: MeshInstance3D = null
# 运行时新建：视野锥可视化
var _cone_visual: MeshInstance3D = null
var _cone_mesh_cache_segments: int = -1

# 被本系统隐藏的实体（避免误恢复非本系统隐藏的节点）
var _hidden_entities: Dictionary = {}


func _ready() -> void:
	_current_cone_range = cone_range
	_current_close_radius = close_radius
	_setup_visuals()


func _process(delta: float) -> void:
	_bind_player()
	if _player == null:
		return
	_current_cone_range = _compute_cone_range()
	_current_close_radius = _compute_close_radius()
	_update_visuals()
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = update_interval
		_update_entity_visibility()


# ----- 公有 API -----

## 当前侵蚀下的视野锥实际射程（米）
func get_current_cone_range() -> float:
	return _current_cone_range


## 当前侵蚀下的近距感知圆半径（米）
func get_current_close_radius() -> float:
	return _current_close_radius


## 判断世界坐标点是否当前对玩家可见（含距离 + 角度 + 障碍）
func is_position_visible(world_position: Vector3) -> bool:
	if _player == null or not is_instance_valid(_player):
		_bind_player()
	if _player == null:
		return true
	return _in_view(_player, world_position)


## 当前被本系统隐藏的实体数（测试/调试用）
func get_hidden_entity_count() -> int:
	return _hidden_entities.size()


## 切换 Run 时（如撤离/死亡）调用，让所有被隐藏实体复位
func reset_visibility() -> void:
	for entity in _hidden_entities.keys():
		if entity is Node3D and is_instance_valid(entity):
			(entity as Node3D).visible = true
	_hidden_entities.clear()


## 兼容旧 API：原 fog_of_war 的"清空探索痕迹"调用点
func clear_trail() -> void:
	reset_visibility()


# ----- 内部 -----

func _bind_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D


func _compute_cone_range() -> float:
	var ratio := _erosion_ratio()
	return lerpf(cone_range, cone_range * erosion_cone_shrink, ratio)


func _compute_close_radius() -> float:
	var ratio := _erosion_ratio()
	return lerpf(close_radius, close_radius * erosion_close_shrink, ratio)


func _erosion_ratio() -> float:
	var max_e: float = maxf(GameManager.max_erosion, 1.0)
	return clampf(GameManager.player_erosion / max_e, 0.0, 1.0)


func _in_view(player: Node3D, target_pos: Vector3) -> bool:
	var dx: float = target_pos.x - player.global_position.x
	var dz: float = target_pos.z - player.global_position.z
	var dist_sq: float = dx * dx + dz * dz

	# 1. 近距感知圆：360° 不受角度限制
	if dist_sq <= _current_close_radius * _current_close_radius:
		return _has_clear_line(player.global_position, target_pos)

	# 2. 超出视野锥射程
	if dist_sq > _current_cone_range * _current_cone_range:
		return false

	# 3. 角度判定（鼠标瞄向方向 ± cone_half_angle_deg）
	var aim: Vector3 = _get_aim_direction(player)
	var to_target := Vector3(dx, 0.0, dz)
	if to_target.length_squared() < 0.0001:
		return true
	to_target = to_target.normalized()
	var angle_deg: float = rad_to_deg(aim.angle_to(to_target))
	if angle_deg > cone_half_angle_deg:
		return false

	# 4. 障碍遮挡
	return _has_clear_line(player.global_position, target_pos)


func _get_aim_direction(player: Node3D) -> Vector3:
	var aim: Vector3 = Vector3.FORWARD
	if player.has_method("get_aim_direction"):
		aim = player.call("get_aim_direction")
	else:
		aim = -player.global_transform.basis.z
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		aim = Vector3.FORWARD
	return aim.normalized()


func _has_clear_line(from_pos: Vector3, to_pos: Vector3) -> bool:
	if obstacle_mask == 0:
		return true
	var world := get_world_3d()
	if world == null:
		return true
	var space_state := world.direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		from_pos + Vector3.UP * ray_height_offset,
		to_pos + Vector3.UP * ray_height_offset,
		obstacle_mask
	)
	return space_state.intersect_ray(query).is_empty()


func _update_entity_visibility() -> void:
	var tree := get_tree()
	if tree == null or _player == null:
		return
	var seen_alive: Dictionary = {}
	for group_name in visibility_groups:
		for node in tree.get_nodes_in_group(group_name):
			if not (node is Node3D):
				continue
			var entity: Node3D = node
			seen_alive[entity] = true
			var in_view := _in_view(_player, entity.global_position)
			_apply_visibility(entity, in_view)
	# 清理：已 free 或换 group 的旧追踪记录
	var stale: Array = []
	for tracked in _hidden_entities.keys():
		if not seen_alive.has(tracked):
			stale.append(tracked)
	for t in stale:
		_hidden_entities.erase(t)


func _apply_visibility(entity: Node3D, now_visible: bool) -> void:
	if now_visible:
		if _hidden_entities.has(entity):
			entity.visible = true
			_hidden_entities.erase(entity)
	else:
		if not _hidden_entities.has(entity):
			_hidden_entities[entity] = true
		entity.visible = false


# ----- 可视化 -----

func _setup_visuals() -> void:
	# 沿用 .tscn 里的 VisionDisc 作为近距感知圆
	_close_disc = get_node_or_null("VisionDisc") as MeshInstance3D
	if _close_disc == null and draw_debug_visuals:
		_close_disc = MeshInstance3D.new()
		_close_disc.name = "VisionDisc"
		_close_disc.mesh = _make_disc_mesh()
		_close_disc.material_override = _make_translucent_material(
			Color(0.4, 0.9, 0.7, 0.18),
			Color(0.1, 0.7, 0.45, 1.0),
			0.12
		)
		add_child(_close_disc)
	if _close_disc != null:
		_close_disc.visible = draw_debug_visuals

	if draw_debug_visuals:
		_ensure_cone_visual()
	elif _cone_visual != null:
		_cone_visual.visible = false


func _ensure_cone_visual() -> void:
	if _cone_visual == null:
		_cone_visual = get_node_or_null("VisionCone") as MeshInstance3D
	if _cone_visual == null:
		_cone_visual = MeshInstance3D.new()
		_cone_visual.name = "VisionCone"
		_cone_visual.material_override = _make_translucent_material(
			Color(0.5, 0.95, 0.75, 0.12),
			Color(0.1, 0.8, 0.5, 1.0),
			0.08
		)
		add_child(_cone_visual)
	if _cone_visual.mesh == null or _cone_mesh_cache_segments != cone_segments:
		_cone_visual.mesh = _make_cone_fan_mesh(cone_segments)
		_cone_mesh_cache_segments = cone_segments


func _update_visuals() -> void:
	if not draw_debug_visuals or _player == null:
		return
	var ground := Vector3(_player.global_position.x, 0.04, _player.global_position.z)
	if _close_disc != null:
		_close_disc.global_position = ground
		_close_disc.scale = Vector3(_current_close_radius, 1.0, _current_close_radius)
	if _cone_visual != null:
		_cone_visual.global_position = Vector3(ground.x, 0.035, ground.z)
		var aim := _get_aim_direction(_player)
		_cone_visual.look_at(_cone_visual.global_position + aim, Vector3.UP)
		_cone_visual.scale = Vector3(_current_cone_range, 1.0, _current_cone_range)


func _make_disc_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.02
	mesh.radial_segments = 48
	return mesh


# 单位扇形（半径 1.0），中心在原点，开口朝 -Z（与 Godot look_at 朝向一致）
func _make_cone_fan_mesh(segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var normals := PackedVector3Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	var half_rad: float = deg_to_rad(cone_half_angle_deg)
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var ang: float = -half_rad + 2.0 * half_rad * t
		# x = sin(ang), z = -cos(ang) → 开口朝 -Z
		verts.append(Vector3(sin(ang), 0.0, -cos(ang)))
		normals.append(Vector3.UP)
	for i in segments:
		indices.append(0)
		indices.append(i + 2)
		indices.append(i + 1)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _make_translucent_material(
	albedo: Color,
	emission: Color,
	emission_energy: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.9
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = emission_energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	return material
