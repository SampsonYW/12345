# fog_of_war.gd
# View distance system: erosion reduces how far the player can see.
# Areas beyond view distance are covered by a semi-transparent fog mask.
# Erosion 0% = 100% view distance, Erosion 100% = 50% view distance.
extends Node3D

## Base view distance at 0% erosion (100% view distance).
@export var base_radius: float = 8.0
## Minimum view distance ratio at 100% erosion. 0.5 = 50% of base_radius.
@export var min_radius_ratio: float = 0.5
## Height of the fog mask plane above ground.
@export var fog_height: float = 0.15

var _current_radius: float = 8.0
var _player: Node3D = null
var _fog_mask: MeshInstance3D = null


func _ready() -> void:
	_current_radius = base_radius
	_build_fog_mask()


func _process(_delta: float) -> void:
	_bind_player()
	if _player == null:
		return
	var erosion_ratio := clampf(GameManager.player_erosion / maxf(GameManager.max_erosion, 1.0), 0.0, 1.0)
	# Erosion 0% → base_radius (100%), Erosion 100% → base_radius * min_radius_ratio (50%)
	_current_radius = lerpf(base_radius, base_radius * min_radius_ratio, erosion_ratio)

	if _fog_mask != null:
		_fog_mask.global_position = Vector3(_player.global_position.x, fog_height, _player.global_position.z)
		var mat := _fog_mask.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("player_position", _player.global_position)
			mat.set_shader_parameter("vision_radius", _current_radius)


## Returns the current view distance radius.
func get_current_radius() -> float:
	return _current_radius


func _build_fog_mask() -> void:
	if DisplayServer.get_name() == "headless":
		return

	_fog_mask = get_node_or_null("FogMask") as MeshInstance3D
	if _fog_mask == null:
		_fog_mask = MeshInstance3D.new()
		_fog_mask.name = "FogMask"
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(1000.0, 1000.0)
		_fog_mask.mesh = mesh
		_fog_mask.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Load shader for distance-based fog
		var shader = load("res://shaders/fog_mask.gdshader") as Shader
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("player_position", Vector3.ZERO)
			mat.set_shader_parameter("vision_radius", base_radius)
			mat.set_shader_parameter("fog_opacity", 0.65)
			mat.set_shader_parameter("fog_color", Color(0.05, 0.06, 0.08, 1.0))
			_fog_mask.material_override = mat
		add_child(_fog_mask)


func _bind_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
