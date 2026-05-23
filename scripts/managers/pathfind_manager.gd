# pathfind_manager.gd
# A* 网格寻路管理器：为敌人 AI 提供绕墙寻路能力。
# 在探险地图加载后调用 build_grid() 构建一次，敌人通过 find_path() 查询路径。
# [AI-ASSISTED] 2026-05-23 — 新增 A* 寻路系统
extends Node

const OBSTACLE_MASK := 4  # Layer 3: Obstacles (per rules.md §3.2)
const DEFAULT_CELL_SIZE := 2.0

var _astar := AStar3D.new()
var _cell_size: float = DEFAULT_CELL_SIZE
var _grid_origin: Vector2 = Vector2.ZERO
var _grid_cols: int = 0
var _grid_rows: int = 0
var _built: bool = false
var _pending_build: Dictionary = {}


func _physics_process(_delta: float) -> void:
	if _pending_build.is_empty():
		return
	var bounds: Rect2 = _pending_build["bounds"]
	var cs: float = _pending_build["cell_size"]
	_pending_build = {}
	_build_grid_internal(bounds, cs)


func is_ready() -> bool:
	return _built


func get_cell_size() -> float:
	return _cell_size


## 请求构建寻路网格（延迟到下一个物理帧执行，确保障碍物已注册）
func build_grid(bounds: Rect2, cell_size: float = DEFAULT_CELL_SIZE) -> void:
	_pending_build = {"bounds": bounds, "cell_size": cell_size}


## 查询从 from 到 to 的路径（世界坐标）
func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	if not _built:
		return []
	var from_id := _nearest_walkable_id(from)
	var to_id := _nearest_walkable_id(to)
	if from_id < 0 or to_id < 0 or from_id == to_id:
		return []
	var raw_path := _astar.get_point_path(from_id, to_id)
	var path: Array[Vector3] = []
	for p in raw_path:
		path.append(p)
	return path


# ----- 私有函数 -----

func _build_grid_internal(bounds: Rect2, cell_size: float) -> void:
	_cell_size = cell_size
	_grid_origin = bounds.position
	_grid_cols = int(ceil(bounds.size.x / _cell_size))
	_grid_rows = int(ceil(bounds.size.y / _cell_size))

	_astar.clear()
	_astar.reserve_space(_grid_cols * _grid_rows)

	var space_state := _get_space_state()
	if space_state == null:
		push_warning("[PathfindManager] No physics space available, grid not built")
		return

	# Phase 1: 添加可行走节点
	for ix in _grid_cols:
		for iz in _grid_rows:
			var world_pos := _cell_to_world(ix, iz)
			var id := _cell_id(ix, iz)
			if not _is_cell_blocked(space_state, world_pos):
				_astar.add_point(id, world_pos)

	# Phase 2: 连接相邻可行走节点（8 方向，只连右/下/右下/右上避免重复）
	for ix in _grid_cols:
		for iz in _grid_rows:
			var id := _cell_id(ix, iz)
			if not _astar.has_point(id):
				continue
			var neighbors := [[ix + 1, iz], [ix, iz + 1], [ix + 1, iz + 1], [ix + 1, iz - 1]]
			for n in neighbors:
				var nx: int = n[0]
				var nz: int = n[1]
				if nx < 0 or nx >= _grid_cols or nz < 0 or nz >= _grid_rows:
					continue
				var nid := _cell_id(nx, nz)
				if _astar.has_point(nid):
					_astar.connect_points(id, nid)

	_built = true
	print("[PathfindManager] Grid built: %d×%d cells (%.1fm), %d walkable points" % [
		_grid_cols, _grid_rows, _cell_size, _astar.get_point_count()
	])


func _cell_to_world(ix: int, iz: int) -> Vector3:
	var x := _grid_origin.x + (ix + 0.5) * _cell_size
	var z := _grid_origin.y + (iz + 0.5) * _cell_size
	return Vector3(x, 0.0, z)


func _world_to_cell(world_pos: Vector3) -> Vector2i:
	var ix := int(floor((world_pos.x - _grid_origin.x) / _cell_size))
	var iz := int(floor((world_pos.z - _grid_origin.y) / _cell_size))
	return Vector2i(clampi(ix, 0, _grid_cols - 1), clampi(iz, 0, _grid_rows - 1))


func _cell_id(ix: int, iz: int) -> int:
	return ix * _grid_rows + iz


func _nearest_walkable_id(world_pos: Vector3) -> int:
	var cell := _world_to_cell(world_pos)
	var id := _cell_id(cell.x, cell.y)
	if _astar.has_point(id):
		return id
	# 当前格子被阻挡，用 AStar3D 内置方法找最近可行走点
	if _astar.get_point_count() == 0:
		return -1
	return _astar.get_closest_point(world_pos)


func _is_cell_blocked(space_state: PhysicsDirectSpaceState3D, world_pos: Vector3) -> bool:
	# 从上方向下投射射线检测障碍物（与 spawn_manager 同方法）
	var ray_origin := Vector3(world_pos.x, 10.0, world_pos.z)
	var ray_end := Vector3(world_pos.x, -1.0, world_pos.z)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, OBSTACLE_MASK)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var hit_pos: Vector3 = result["position"]
	return hit_pos.y > 0.05


func _get_space_state() -> PhysicsDirectSpaceState3D:
	var tree := get_tree()
	if tree == null:
		return null
	var world := tree.root.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state
