# extraction.gd
# Signal flare extraction flow: wait, arrival marker, boarding, and success.
# [AI-ASSISTED] 2026-05-20 - Day 4 P0 extraction loop.
extends Node3D

@export var wait_time: float = 75.0
@export var boarding_range: float = 3.75
@export var arrival_offset: Vector3 = Vector3(0.0, 0.0, -3.0)

var _timer: float = 0.0
var _waiting: bool = false
var _arrived: bool = false
var _landing_position: Vector3 = Vector3.ZERO
var _marker: Node3D = null


func _ready() -> void:
	if not GameManager.signal_flare_fired.is_connected(_on_signal_flare_fired):
		GameManager.signal_flare_fired.connect(_on_signal_flare_fired)
	if not GameManager.state_changed.is_connected(_on_state_changed):
		GameManager.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.State.EXTRACTING:
		return

	if _waiting:
		_timer -= delta
		if _timer <= 0.0:
			_waiting = false
			_arrived = true
			_clear_marker()
			_spawn_marker()

	if _arrived and not GameManager.ui_blocking_input and Input.is_action_just_pressed("interact"):
		try_board()


func get_remaining_time() -> float:
	return maxf(_timer, 0.0) if _waiting else 0.0


func has_arrived() -> bool:
	return _arrived


func get_landing_position() -> Vector3:
	return _landing_position


func try_board() -> bool:
	if GameManager.ui_blocking_input:
		return false
	if not _arrived:
		return false
	if not _player_in_boarding_range():
		return false
	GameManager.set_state(GameManager.State.SUCCESS)
	return true


func get_status_text() -> String:
	if _arrived:
		return "Board [E]"
	if _waiting:
		return "Arrives %ds" % int(ceil(get_remaining_time()))
	return "Ready" if not GameManager.signal_flare_used else "Fired"


func get_extraction_direction(from_position: Vector3 = Vector3.ZERO) -> Vector3:
	var origin := from_position
	if origin == Vector3.ZERO:
		origin = GameManager.player_position
	var direction := _landing_position - origin
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.01 else Vector3.ZERO


func get_pressure_status() -> Dictionary:
	return {
		"status_text": get_status_text(),
		"remaining_time": get_remaining_time(),
		"landing_position": _landing_position,
		"direction": get_extraction_direction(),
		"waiting": _waiting,
		"arrived": _arrived,
	}


func _on_signal_flare_fired(origin: Vector3) -> void:
	if (
		GameManager.current_state != GameManager.State.RUNNING
		and GameManager.current_state != GameManager.State.EXTRACTING
	):
		return

	_landing_position = origin + arrival_offset
	_landing_position.y = 0.0
	_timer = maxf(wait_time, 0.0)
	_waiting = true
	_arrived = false
	_clear_marker()
	_notify_spawn_manager()
	_notify_enemies_of_signal(origin)
	_spawn_waiting_beacon()


func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.EXTRACTING:
		return
	_waiting = false
	_arrived = false
	_clear_marker()


func _player_in_boarding_range() -> bool:
	var player_position := GameManager.player_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		player_position = player.global_position
	return player_position.distance_to(_landing_position) <= boarding_range


func _spawn_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		return

	_marker = Node3D.new()
	_marker.name = "MothershipExtractionMarker"
	add_child(_marker)
	_marker.global_position = _landing_position

	_add_cylinder(_marker, "LandingPad", Vector3(0.0, 0.06, 0.0), 3.5, 0.12, _make_material(Color(0.1, 0.55, 0.5, 1.0), Color(0.0, 0.9, 0.8, 1.0), 0.35))
	_add_cylinder(_marker, "SignalBeam", Vector3(0.0, 2.1, 0.0), 0.32, 4.2, _make_material(Color(0.1, 0.85, 0.78, 0.45), Color(0.0, 1.0, 0.85, 1.0), 1.6))
	_add_box(_marker, "MothershipHull", Vector3(0.0, 4.8, 0.0), Vector3(5.8, 0.75, 2.4), _make_material(Color(0.54, 0.58, 0.62, 1.0), Color(0.2, 0.9, 0.85, 1.0), 0.25))
	_add_box(_marker, "BoardingRamp", Vector3(0.0, 1.05, 1.85), Vector3(2.0, 0.2, 2.8), _make_material(Color(0.24, 0.32, 0.34, 1.0), Color(0.0, 0.75, 0.7, 1.0), 0.2))

	var light := OmniLight3D.new()
	light.name = "ExtractionLight"
	light.position = Vector3(0.0, 2.5, 0.0)
	light.light_color = Color(0.0, 1.0, 0.85, 1.0)
	light.light_energy = 4.0
	light.omni_range = 9.0
	_marker.add_child(light)


func _spawn_waiting_beacon() -> void:
	if _marker != null and is_instance_valid(_marker):
		return
	_marker = Node3D.new()
	_marker.name = "ExtractionSignalBeacon"
	add_child(_marker)
	_marker.global_position = _landing_position
	_add_cylinder(_marker, "PendingLandingPad", Vector3(0.0, 0.04, 0.0), 2.4, 0.08, _make_material(Color(0.08, 0.35, 0.32, 0.8), Color(0.0, 0.7, 0.62, 1.0), 0.25))
	_add_cylinder(_marker, "PendingSignalBeam", Vector3(0.0, 1.4, 0.0), 0.18, 2.8, _make_material(Color(0.1, 0.85, 0.78, 0.30), Color(0.0, 1.0, 0.85, 1.0), 1.0))


func _notify_spawn_manager() -> void:
	var spawn_manager := get_parent().get_node_or_null("SpawnManager")
	if spawn_manager != null and spawn_manager.has_method("on_signal_flare"):
		spawn_manager.on_signal_flare()


func _notify_enemies_of_signal(origin: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy != null and enemy.has_method("react_to_signal_flare"):
			enemy.react_to_signal_flare(origin, _landing_position)


func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		if _marker.get_parent() != null:
			_marker.get_parent().remove_child(_marker)
		_marker.free()
	_marker = null


func _add_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_cylinder(parent: Node3D, node_name: String, position: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _make_material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = emission_energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	material.roughness = 0.65
	if albedo.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
