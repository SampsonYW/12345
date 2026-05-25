# camera_occlusion.gd
# 动态检测摄像机与玩家之间的遮挡物，通过 Shader 局部变透明。
# [AI-ASSISTED] 2026-05-24 — 升级为局部 Shader 镂空，避免整墙透明
extends Node3D

const SCAN_RADIUS := 2.6
const SHADER_RES := preload("res://resources/shaders/wall_occlusion.gdshader")

var _shape_cast: ShapeCast3D = null
# MeshInstance3D -> 原始 StandardMaterial3D
var _original_materials: Dictionary = {}
# MeshInstance3D -> 缓存的 ShaderMaterial
var _shader_materials: Dictionary = {}


func _ready() -> void:
	_shape_cast = ShapeCast3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = SCAN_RADIUS
	_shape_cast.shape = sphere
	# 4 (Obstacles). 不检测 64 (LowObstacle) 因为矮墙并不会遮挡玩家的视线，镂空反而像染色错误
	_shape_cast.collision_mask = 4
	_shape_cast.collide_with_areas = false
	_shape_cast.collide_with_bodies = true
	_shape_cast.max_results = 32
	add_child(_shape_cast)
	_precompile_shader()


func _precompile_shader() -> void:
	# 强制在游戏加载第一帧渲染一次 Shader，提前触发管线编译（解决首次渲染卡顿）
	var dummy = MeshInstance3D.new()
	dummy.mesh = QuadMesh.new()
	dummy.mesh.size = Vector2(0.001, 0.001)
	var sm = ShaderMaterial.new()
	sm.shader = SHADER_RES
	dummy.material_override = sm
	add_child(dummy)
	call_deferred("_place_dummy", dummy)


func _place_dummy(dummy: Node3D) -> void:
	if not dummy or not is_instance_valid(dummy): return
	var game = get_parent()
	if game and ("_camera" in game) and is_instance_valid(game._camera):
		var cam: Camera3D = game._camera
		# 放在摄像机视野正前方极近处
		dummy.global_position = cam.global_position - cam.global_transform.basis.z * 1.0
		var timer = get_tree().create_timer(0.5)
		timer.timeout.connect(dummy.queue_free)
	else:
		dummy.queue_free()


func _physics_process(_delta: float) -> void:
	var game: Node = get_parent()
	if not game or not ("_player" in game) or not ("_camera" in game):
		return
	var player: Node3D = game._player
	var camera: Camera3D = game._camera
	
	if not player or not is_instance_valid(player) or not camera or not is_instance_valid(camera):
		_restore_all()
		return
		
	if GameManager.current_location != GameManager.Location.EXPEDITION and GameManager.current_location != GameManager.Location.AFTERGLOW:
		_restore_all()
		return
	
	_shape_cast.global_position = camera.global_position
	var target_global = player.global_position + Vector3(0.0, 1.0, 0.0)
	_shape_cast.target_position = _shape_cast.to_local(target_global)
	
	_shape_cast.force_shapecast_update()
	
	var active_meshes: Dictionary = {}
	
	var hit_count := _shape_cast.get_collision_count()
	for i in range(hit_count):
		var collider = _shape_cast.get_collider(i)
		if collider == player:
			continue
			
		for child in collider.get_children():
			if child is MeshInstance3D:
				active_meshes[child] = true
				if not _original_materials.has(child):
					_apply_shader(child)
				else:
					_update_shader(child, player.global_position, camera.global_position)
	
	# 恢复不再受遮挡的墙体材质
	var to_remove: Array = []
	for mesh in _original_materials.keys():
		if not active_meshes.has(mesh):
			_restore_material(mesh)
			to_remove.append(mesh)
			
	for m in to_remove:
		_original_materials.erase(m)


func _apply_shader(mesh: MeshInstance3D) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	var original = mesh.material_override as StandardMaterial3D
	if original == null:
		return
		
	_original_materials[mesh] = original
	
	if _shader_materials.has(mesh):
		mesh.material_override = _shader_materials[mesh]
	else:
		var sm = ShaderMaterial.new()
		sm.shader = SHADER_RES
		sm.set_shader_parameter("albedo", original.albedo_color)
		sm.set_shader_parameter("metallic", original.metallic)
		sm.set_shader_parameter("roughness", original.roughness)
		_shader_materials[mesh] = sm
		mesh.material_override = sm


func _update_shader(mesh: MeshInstance3D, player_pos: Vector3, camera_pos: Vector3) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	var sm = mesh.material_override as ShaderMaterial
	if sm:
		sm.set_shader_parameter("player_pos", player_pos)
		sm.set_shader_parameter("camera_pos", camera_pos)


func _restore_material(mesh: MeshInstance3D) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	var original = _original_materials[mesh]
	if original and is_instance_valid(original):
		mesh.material_override = original


func _restore_all() -> void:
	if _original_materials.is_empty():
		return
	for mesh in _original_materials.keys():
		_restore_material(mesh)
	_original_materials.clear()
