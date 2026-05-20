# fog_of_war.gd
# Lightweight 3D MVP vision disc with explored ground trail.
# [AI-ASSISTED] 2026-05-20 - Day 4 P0 fog/vision pass.
extends Node3D

const EXPLORED_MARKER_SCENE := preload("res://scenes/explored_marker.tscn")

@export var base_radius: float = 8.0
@export var min_radius: float = 3.0
@export var trail_interval: float = 0.35
@export var trail_radius_scale: float = 0.72
@export var max_trail_markers: int = 28

var _current_radius: float = 8.0
var _trail_timer: float = 0.0
var _player: Node3D = null
var _vision_disc: MeshInstance3D = null
var _trail_parent: Node3D = null


func _ready() -> void:
	_current_radius = base_radius
	_build_nodes()


func _process(delta: float) -> void:
	_bind_player()
	if _player == null:
		return
	var erosion_ratio := clampf(GameManager.player_erosion / maxf(GameManager.max_erosion, 1.0), 0.0, 1.0)
	_current_radius = lerpf(base_radius, min_radius, erosion_ratio)
	_vision_disc.global_position = _ground_position(_player.global_position, 0.035)
	_vision_disc.scale = Vector3(_current_radius, 1.0, _current_radius)
	_trail_timer -= delta
	if _trail_timer <= 0.0:
		_trail_timer = trail_interval
		_add_trail_marker(_player.global_position)


func get_current_radius() -> float:
	return _current_radius


func get_explored_marker_count() -> int:
	return _trail_parent.get_child_count() if _trail_parent != null else 0


func clear_trail() -> void:
	if _trail_parent == null:
		return
	for child in _trail_parent.get_children():
		_trail_parent.remove_child(child)
		child.free()


func _build_nodes() -> void:
	_trail_parent = get_node_or_null("ExploredTrail") as Node3D
	if _trail_parent == null:
		_trail_parent = Node3D.new()
		_trail_parent.name = "ExploredTrail"
		add_child(_trail_parent)

	_vision_disc = get_node_or_null("VisionDisc") as MeshInstance3D
	if _vision_disc == null:
		_vision_disc = MeshInstance3D.new()
		_vision_disc.name = "VisionDisc"
		_vision_disc.mesh = _make_disc_mesh()
		_vision_disc.material_override = _make_material(Color(0.5, 0.95, 0.75, 0.20), Color(0.1, 0.8, 0.45, 1.0), 0.18)
		add_child(_vision_disc)


func _bind_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D


func _add_trail_marker(world_position: Vector3) -> void:
	if _trail_parent == null:
		return
	var marker := EXPLORED_MARKER_SCENE.instantiate() as MeshInstance3D
	var radius := maxf(_current_radius * trail_radius_scale, min_radius)
	marker.scale = Vector3(radius, 1.0, radius)
	_trail_parent.add_child(marker)
	marker.global_position = _ground_position(world_position, 0.025)
	while _trail_parent.get_child_count() > max_trail_markers:
		var oldest := _trail_parent.get_child(0)
		_trail_parent.remove_child(oldest)
		oldest.free()


func _ground_position(value: Vector3, y: float) -> Vector3:
	return Vector3(value.x, y, value.z)


func _make_disc_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.025
	mesh.radial_segments = 64
	return mesh


func _make_material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.9
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = emission_energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	return material
