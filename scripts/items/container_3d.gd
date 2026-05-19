# container_3d.gd
# 3D 密封容器：玩家进入范围后长按 interact 破解，完成后生成 3D 拾取物。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写容器交互
extends StaticBody3D

signal cracked(container: StaticBody3D)

const ITEM_PICKUP_SCENE := preload("res://scenes/item_pickup_3d.tscn")

@export var loot_table: Array[ItemData] = []
@export var base_crack_time: float = 2.0
@export var pickup_spread_radius: float = 1.5

var _is_cracked: bool = false
var _crack_progress: float = 0.0
var _is_cracking: bool = false
var _player_in_range: bool = false

@onready var _visual: MeshInstance3D = $Visual
@onready var _interact_area: Area3D = $InteractArea


func _ready() -> void:
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	_set_visual_color(Color(0.64, 0.52, 0.27, 1.0))


func _process(delta: float) -> void:
	if _is_cracked:
		return
	if not _player_in_range:
		if _is_cracking:
			_interrupt()
		return
	if Input.is_action_pressed("interact"):
		if not _is_cracking:
			_start_crack()
		_crack_progress += delta / get_crack_duration()
		_set_visual_color(Color(0.75, 0.62, 0.32, 1.0).lerp(Color(1.0, 0.9, 0.45, 1.0), _crack_progress))
		if _crack_progress >= 1.0:
			_complete_crack()
	else:
		if _is_cracking:
			_interrupt()


func get_crack_duration() -> float:
	var erosion_ratio: float = GameManager.player_erosion / 100.0
	return base_crack_time * (1.0 + erosion_ratio * 1.5)


func _start_crack() -> void:
	_is_cracking = true
	_crack_progress = 0.0


func _complete_crack() -> void:
	_is_cracking = false
	_is_cracked = true
	_set_visual_color(Color(0.34, 0.3, 0.2, 1.0))
	NoiseManager.emit_noise(global_position, NoiseManager.Level.LOW)
	cracked.emit(self)
	_spawn_pickups()


func _interrupt() -> void:
	_is_cracking = false
	_crack_progress = 0.0
	_set_visual_color(Color(0.64, 0.52, 0.27, 1.0))


func _spawn_pickups() -> void:
	if loot_table.is_empty():
		return
	var n: int = loot_table.size()
	var pickup_parent := _find_pickup_parent()
	for i in n:
		var angle: float = TAU * float(i) / float(n)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * pickup_spread_radius
		var pickup: Area3D = ITEM_PICKUP_SCENE.instantiate()
		pickup.item_data = loot_table[i]
		pickup_parent.add_child(pickup)
		pickup.global_position = global_position + offset


func _find_pickup_parent() -> Node:
	var scene: Node = get_tree().current_scene
	var entities: Node = scene.get_node_or_null("Entities")
	if entities:
		var pickups: Node = entities.get_node_or_null("Pickups")
		if pickups:
			return pickups
		return entities
	return scene


func _set_visual_color(color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.84
	_visual.material_override = material


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		var ph: Node = body.get_node_or_null("PlayerHealth")
		if ph and ph.has_signal("damaged") and not ph.damaged.is_connected(_on_player_damaged):
			ph.damaged.connect(_on_player_damaged)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _is_cracking:
			_interrupt()


func _on_player_damaged() -> void:
	if _is_cracking and not _is_cracked:
		_interrupt()
