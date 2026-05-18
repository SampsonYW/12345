# container.gd
# 密封容器：长按 interact 读条破解，受侵蚀影响速度
# 破解完成 → loot_table 中每件物品都 spawn 成 ItemPickup 散落在容器周围
# 读条期间走出范围 / 被攻击 都会中断
# [AI-ASSISTED] 2026-05-19 - 按 docs/rules.md 规范化信号类型和内部状态
extends StaticBody2D

signal cracked(container: StaticBody2D)

const ITEM_PICKUP_SCENE := preload("res://scenes/item_pickup.tscn")

# ----- 参数 -----
@export var loot_table: Array[ItemData] = []
@export var base_crack_time: float = 2.0  # design.md §5.2 / implementation.md §13
@export var pickup_spread_radius: float = 65.0

# ----- 内部状态 -----
var _is_cracked: bool = false
var _crack_progress: float = 0.0  # 0.0 ~ 1.0
var _is_cracking: bool = false
var _player_in_range: bool = false

@onready var crack_bar: ProgressBar = $CrackProgressBar
@onready var visual: Polygon2D = $Visual
@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	crack_bar.value = 0.0
	crack_bar.visible = false
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


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
		crack_bar.value = _crack_progress
		if _crack_progress >= 1.0:
			_complete_crack()
	else:
		if _is_cracking:
			_interrupt()


func get_crack_duration() -> float:
	var erosion_ratio: float = GameManager.player_erosion / 100.0
	return base_crack_time * (1.0 + erosion_ratio * 1.5)


func _start_crack() -> void:
	if _is_cracked:
		return
	_is_cracking = true
	_crack_progress = 0.0
	crack_bar.visible = true


func _complete_crack() -> void:
	_is_cracking = false
	_is_cracked = true
	crack_bar.visible = false
	visual.color = Color(0.4, 0.35, 0.25, 1)
	NoiseManager.emit_noise(global_position, NoiseManager.Level.LOW)
	cracked.emit(self)
	_spawn_pickups()


func _interrupt() -> void:
	_is_cracking = false
	_crack_progress = 0.0
	crack_bar.value = 0.0
	crack_bar.visible = false


# 把 loot_table 里每件物品 spawn 成地上 ItemPickup，环绕容器分布
func _spawn_pickups() -> void:
	if loot_table.is_empty():
		return
	var n: int = loot_table.size()
	var pickup_parent: Node = _find_pickup_parent()
	for i in n:
		var angle: float = TAU * float(i) / float(n) + randf_range(-0.15, 0.15)
		var offset := Vector2(cos(angle), sin(angle)) * pickup_spread_radius
		var pickup: Area2D = ITEM_PICKUP_SCENE.instantiate()
		pickup.item_data = loot_table[i]
		pickup_parent.add_child(pickup)
		pickup.global_position = global_position + offset


# 优先放在 Entities/Pickups 下，没有就放 Entities 下，再没有就放 current_scene
func _find_pickup_parent() -> Node:
	var scene: Node = get_tree().current_scene
	var entities: Node = scene.get_node_or_null("Entities")
	if entities:
		var pickups: Node = entities.get_node_or_null("Pickups")
		if pickups:
			return pickups
		return entities
	return scene


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
