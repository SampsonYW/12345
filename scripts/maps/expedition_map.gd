# expedition_map.gd
# Self-contained expedition map script.
# 整图由 POI 驱动：_ready 时清空 .tscn 里手摆的 Obstacles/Containers/InitialSpawns/RiskZones 子节点，
# 然后从 POI_REGISTRY 注册的每个 POI 模块自包含构建。
#
# @tool: 在 Godot 编辑器中打开 expedition_map.tscn 时，_ready 也会触发，编辑器 3D 视图能直接预览整张地图。
# 编辑器中"保存场景"会把 .tscn 中残留的旧节点（24 障碍 + 30 容器 + 14 spawn + 6 zone marker）永久删除；
# POI 生成的节点（owner=null）不会被保存，保持代码驱动。
# [AI-ASSISTED] 2026-05-23 - 从 RISK_ZONE_DATA 常量 + tscn 手摆迁移到 POI 驱动
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
@tool
extends Node3D

const CoreWreckPOIScript := preload("res://scripts/maps/core_wreck_poi.gd")
const SouthApproachPOIScript := preload("res://scripts/maps/south_approach_poi.gd")
const FrozenDepotPOIScript := preload("res://scripts/maps/frozen_depot_poi.gd")
const SilentArrayPOIScript := preload("res://scripts/maps/silent_array_poi.gd")
const BlackYardPOIScript := preload("res://scripts/maps/black_yard_poi.gd")
const AshOutskirtsPOIScript := preload("res://scripts/maps/ash_outskirts_poi.gd")
const BrokenRailPOIScript := preload("res://scripts/maps/broken_rail_poi.gd")
const WastelandDecorationPOIScript := preload("res://scripts/maps/wasteland_decoration_poi.gd")

## 当前注册的所有 POI（按出现顺序 build）
const POI_REGISTRY: Array = [
	CoreWreckPOIScript,
	SouthApproachPOIScript,
	FrozenDepotPOIScript,
	SilentArrayPOIScript,
	BlackYardPOIScript,
	AshOutskirtsPOIScript,
	BrokenRailPOIScript,
	WastelandDecorationPOIScript,
]

@export var rebuild_pois_on_ready: bool = true

## 编辑器按钮：把当前 POI 节点位置/旋转写回各 *_poi.gd 文件（保留注释，原文件备份为 .bak）
@export_tool_button("Dump POI positions to .gd files") var _dump_poi_button: Callable = _dump_all_pois_to_files

const EXPEDITION_BOUNDS := Rect2(Vector2(-300.0, -175.0), Vector2(600.0, 350.0))
const FALLBACK_ZONE := {"name": "废土", "risk": "low"}

var _player: Node3D = null
var _hud: Node = null
var _world_prompt: Label3D = null
var _container_hint_shown: bool = false
var _pois_built: bool = false
var _risk_zones: Array = []   # 由 POI build 时填充，运行时唯一 zone 数据源


func _ready() -> void:
	if not rebuild_pois_on_ready:
		return
	# 编辑器内每次场景重载都重建（用户改 POI 数据后能立刻看到）
	# 运行时只建一次
	if Engine.is_editor_hint():
		_pois_built = false
	if _pois_built:
		return
	_clear_authored_content()
	_build_pois()
	_pois_built = true
	if Engine.is_editor_hint():
		push_warning("[expedition_map] @tool editor preview built. 保存场景 (Ctrl+S) 可把 .tscn 里旧节点的清理永久落盘；POI 生成节点不会被保存。")


## 清空 .tscn 手摆的 Obstacles/Containers/InitialSpawns/RiskZones 子节点
## 保留：Ground、根节点、这 4 个父容器节点本身
func _clear_authored_content() -> void:
	for parent_name in ["Obstacles", "Containers", "InitialSpawns", "RiskZones"]:
		var node := get_node_or_null(parent_name) as Node
		if node == null:
			continue
		for child in node.get_children():
			node.remove_child(child)
			child.queue_free()


func _build_pois() -> void:
	var parents := {
		"obstacles": get_node_or_null("Obstacles") as Node3D,
		"containers": get_node_or_null("Containers") as Node3D,
		"spawns": get_node_or_null("InitialSpawns") as Node3D,
		"risk_zones": get_node_or_null("RiskZones") as Node3D,
	}
	# 校验所有父容器存在
	for key in parents:
		if parents[key] == null:
			push_warning("[expedition_map] Missing parent node: %s" % key)
			return
	_risk_zones.clear()
	var total_obstacles := 0
	var total_containers := 0
	var total_spawns := 0
	for poi in POI_REGISTRY:
		var zone_def: Dictionary = poi.build_all(parents)
		if not zone_def.is_empty():
			_risk_zones.append(zone_def)
		# 顺便统计输出
		total_obstacles += poi.OBSTACLES.size()
		total_containers += poi.CONTAINERS.size()
		total_spawns += poi.SPAWNS.size()
	# 编辑器模式：把顶层 POI 节点（body / container / spawn marker / zone marker）的 owner 设为场景根，
	# 让它们在 Scene 树面板里显示 + 3D 视图可选中可拖动。
	# 注意：只设顶层节点 owner，不递归到内部 Mesh/Shape，否则用户在 viewport 会误选 Mesh 而非 body，
	# 导致拖动只移动局部子节点（body 不动），dump 也读不到真实变化。
	if Engine.is_editor_hint():
		_attach_owner_to_poi_roots()
	push_warning("[expedition_map] built %d POIs · %d obstacles · %d containers · %d spawns" % [
		POI_REGISTRY.size(), total_obstacles, total_containers, total_spawns
	])


# 只把 4 个父容器（Obstacles / Containers / InitialSpawns / RiskZones）的直接子节点的 owner
# 设为场景根；不递归进 body 内的 Mesh/Shape。这样：
#   - Scene 树展开 Obstacles 看到 N 个 body，body 不可展开（Mesh/Shape 隐藏）
#   - viewport 点击方块直接选中 body，拖动整体移动
func _attach_owner_to_poi_roots() -> void:
	for parent_name in ["Obstacles", "Containers", "InitialSpawns", "RiskZones"]:
		var parent_node := get_node_or_null(parent_name)
		if parent_node == null:
			continue
		for child in parent_node.get_children():
			if child.owner == null:
				child.owner = self


# 编辑器按钮回调：遍历 POI_REGISTRY，每个 POI 把自己的节点位置写回对应 *_poi.gd
func _dump_all_pois_to_files() -> void:
	var parents := {
		"obstacles": get_node_or_null("Obstacles") as Node3D,
		"containers": get_node_or_null("Containers") as Node3D,
		"spawns": get_node_or_null("InitialSpawns") as Node3D,
		"risk_zones": get_node_or_null("RiskZones") as Node3D,
	}
	for key in parents:
		if parents[key] == null:
			push_warning("[poi-dump] missing parent node: %s — abort" % key)
			return
	for poi in POI_REGISTRY:
		var result: Dictionary = poi.dump_current_state(parents)
		if not result.get("ok", false):
			push_error("[poi-dump] %s failed: %s" % [poi.POI_CLASS_NAME, result.get("error", "?")])
			continue
		push_warning("[poi-dump] %s → updated %d obstacles, %d containers, %d spawns" % [
			poi.POI_CLASS_NAME,
			result.get("obstacles", 0),
			result.get("containers", 0),
			result.get("spawns", 0),
		])
	push_warning("[poi-dump] done. 原文件已备份为 *.gd.bak。重新加载场景生效。")


func activate(player: Node3D, hud: Node, world_prompt: Label3D = null) -> void:
	_player = player
	_hud = hud
	_world_prompt = world_prompt
	_container_hint_shown = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_collision_active(true)
	_wire_containers()


func deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_set_collision_active(false)


## Reset all mutable map state (containers, hints) so a new expedition starts fresh.
func reset() -> void:
	_container_hint_shown = false
	var containers := get_node_or_null("Containers")
	if containers == null:
		return
	for child in containers.get_children():
		if child.has_method("reset"):
			child.reset()



func update(_delta: float) -> void:
	if _player == null:
		return
	_update_risk_label()
	_update_container_interactions()


# ---------------------------------------------------------------------------
# Public queries
# ---------------------------------------------------------------------------

func get_bounds() -> Rect2:
	return EXPEDITION_BOUNDS


## 重新烘焙 NavigationRegion3D 的 navmesh。在 POI 障碍物实例化完成后调用一次。
## 因为 POI 子节点是 NavRegion 的 sibling（不是 children），用 NavigationServer3D
## 显式传入 ExpeditionMap 根节点扫描整张地图的几何。
## on_thread=true 时异步烘焙，连接 bake_finished 信号通知完成；同步版本会卡帧 1-3 秒。
func bake_navmesh(on_thread: bool = true) -> void:
	var nav_region := get_node_or_null("NavRegion") as NavigationRegion3D
	if nav_region == null:
		push_warning("[expedition_map] NavRegion 节点缺失，无法烘焙 navmesh")
		return
	var nav_mesh: NavigationMesh = nav_region.navigation_mesh
	if nav_mesh == null:
		push_warning("[expedition_map] NavRegion 没有 navigation_mesh 资源")
		return
	# 手动 parse：从 ExpeditionMap 根节点扫描所有 sibling 子树
	var source_geom := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geom, self)
	if on_thread:
		NavigationServer3D.bake_from_source_geometry_data_async(
			nav_mesh, source_geom,
			func() -> void:
				nav_region.navigation_mesh = nav_mesh
				push_warning("[expedition_map] NavMesh bake 完成")
		)
	else:
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geom)
		nav_region.navigation_mesh = nav_mesh
		push_warning("[expedition_map] NavMesh bake 完成（同步）")


func get_risk_zones() -> Array:
	var zones: Array = []
	for data in _risk_zones:
		zones.append(data.duplicate(true))
	return zones


func get_zone_density_summary() -> Dictionary:
	var low_enemy := 0.0
	var low_container := 0.0
	var low_value := 0.0
	var low_count := 0.0
	var high_enemy := 0.0
	var high_container := 0.0
	var high_value := 0.0
	var high_count := 0.0
	for zone in _risk_zones:
		if zone.get("risk", "") == "high":
			high_enemy += float(zone.get("enemy_density", 0.0))
			high_container += float(zone.get("container_density", 0.0))
			high_value += float(zone.get("high_value_weight", 0.0))
			high_count += 1.0
		else:
			low_enemy += float(zone.get("enemy_density", 0.0))
			low_container += float(zone.get("container_density", 0.0))
			low_value += float(zone.get("high_value_weight", 0.0))
			low_count += 1.0
	return {
		"low_enemy_density": low_enemy / maxf(low_count, 1.0),
		"low_container_density": low_container / maxf(low_count, 1.0),
		"low_value_weight": low_value / maxf(low_count, 1.0),
		"high_enemy_density": high_enemy / maxf(high_count, 1.0),
		"high_container_density": high_container / maxf(high_count, 1.0),
		"high_value_weight": high_value / maxf(high_count, 1.0),
	}


func get_player_zone_info() -> Dictionary:
	var info := FALLBACK_ZONE.duplicate()
	if _player == null:
		return info
	var pos := Vector2(_player.global_position.x, _player.global_position.z)
	for zone in _risk_zones:
		if _zone_contains(zone, pos):
			info["name"] = zone.get("name", "")
			info["risk"] = zone.get("risk", "low")
	return info


func get_player_risk_label() -> String:
	var info := get_player_zone_info()
	return "高风险" if info["risk"] == "high" else "低风险"


func get_containers_node() -> Node:
	return get_node_or_null("Containers")


func collect_obstacle_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var obstacles := get_node_or_null("Obstacles")
	if obstacles == null:
		return positions
	for child in obstacles.get_children():
		if child is Node3D:
			var node := child as Node3D
			positions.append(Vector2(node.global_position.x, node.global_position.z))
	return positions


# ---------------------------------------------------------------------------
# Container wiring
# ---------------------------------------------------------------------------

func _wire_containers() -> void:
	var containers := get_node_or_null("Containers")
	if containers == null:
		return
	for child in containers.get_children():
		if child.has_signal("cracked") and not child.cracked.is_connected(_on_container_cracked):
			child.cracked.connect(_on_container_cracked)
		if "risk" in child:
			child.set_meta("risk", child.risk)


func _on_container_cracked(container: StaticBody3D) -> void:
	if _hud != null and _hud.has_method("open_container_search"):
		_hud.open_container_search(container)


# ---------------------------------------------------------------------------
# Container interactions
# ---------------------------------------------------------------------------

func _update_container_interactions() -> void:
	if GameManager.ui_blocking_input:
		return
	var container := _find_nearby_container()
	if container == null:
		_set_prompt_text("")
		return
	var prompt_pos := (
		(container as Node3D).global_position + Vector3(0.0, 0.0, 1.8)
		if container is Node3D
		else Vector3.INF
	)
	if container.has_method("is_opened") and container.is_opened():
		if not _container_hint_shown:
			_set_prompt_text("E 搜索", prompt_pos)
		else:
			_set_prompt_text("")
		var can_search := _hud != null and _hud.has_method("open_container_search")
		if Input.is_action_just_pressed("interact") and can_search:
			_container_hint_shown = true
			_set_prompt_text("")
			_hud.open_container_search(container)
	else:
		if not _container_hint_shown:
			_set_prompt_text("长按 E 开启", prompt_pos)
		else:
			_set_prompt_text("")


func _find_nearby_container() -> Node:
	if _player == null:
		return null
	var containers := get_node_or_null("Containers")
	if containers == null:
		return null
	var p_pos := _player.global_position
	for container in containers.get_children():
		if container is Node3D:
			var c_node := container as Node3D
			if p_pos.distance_to(c_node.global_position) <= 3.2:
				return container
	return null


# ---------------------------------------------------------------------------
# Risk zone label
# ---------------------------------------------------------------------------

func _update_risk_label() -> void:
	var info := get_player_zone_info()
	var risk: String = info.get("risk", "low")
	GameManager.zone_erosion_multiplier = 1.5 if risk == "high" else 1.0
	
	if _hud != null:
		if _hud.has_method("set_zone_info"):
			_hud.set_zone_info(info["name"], risk)
		if _hud.has_method("set_risk_label_text"):
			_hud.set_risk_label_text("风险  %s" % get_player_risk_label())


# ---------------------------------------------------------------------------
# Collision management
# ---------------------------------------------------------------------------

func _set_collision_active(active: bool) -> void:
	_toggle_collision_recursive(self, active)


func _toggle_collision_recursive(node: Node, active: bool) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		if active:
			body.collision_layer = int(body.get_meta("_saved_collision_layer", body.collision_layer))
		else:
			# Only save if not already deactivated (layer > 0), to avoid
			# overwriting the saved original value on repeated deactivate calls.
			if body.collision_layer > 0:
				body.set_meta("_saved_collision_layer", body.collision_layer)
			body.collision_layer = 0
	for child in node.get_children():
		_toggle_collision_recursive(child, active)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _zone_contains(zone: Dictionary, pos: Vector2) -> bool:
	var center: Vector2 = zone.get("center")
	var size: Vector2 = zone.get("size")
	var rect := Rect2(center - size * 0.5, size)
	return rect.has_point(pos)


func _set_prompt_text(text: String, world_position: Vector3 = Vector3.INF) -> void:
	if _hud != null and _hud.has_method("set_prompt_text"):
		_hud.set_prompt_text(text)
	if _world_prompt == null:
		return
	_world_prompt.text = text
	_world_prompt.visible = text.strip_edges() != ""
	if _world_prompt.visible:
		var target_pos := world_position
		if target_pos == Vector3.INF:
			target_pos = (
				_player.global_position + Vector3(0.0, 0.0, 2.8)
				if _player != null
				else Vector3.ZERO
			)
		var y := 0.09 if world_position == Vector3.INF else maxf(target_pos.y + 0.01, 0.09)
		_world_prompt.global_position = Vector3(target_pos.x, y, target_pos.z)
