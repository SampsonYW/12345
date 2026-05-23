# container_3d.gd
# 3D 容器节点：管理破解时间、被发现概率、随机物品掉落和开启状态。
# 3D 密封容器：玩家进入范围后长按 interact 破解，完成后生成 3D 拾取物。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写容器交互
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends StaticBody3D

signal cracked(container: StaticBody3D)

const ITEM_PICKUP_SCENE := preload("res://scenes/item_pickup_3d.tscn")
const ItemDataResource := preload("res://scripts/items/item_data.gd")

## 容器的最大条目数（loot + 玩家放回的物品之和），跟 HUD 里 ContainerGrid 的格子数一致
const MAX_ENTRIES: int = 12

@export var loot_table: Array[ItemDataResource] = []
@export var risk: String = "low"
@export var base_crack_time: float = 2.0
@export var base_search_time: float = 1.0
@export var pickup_spread_radius: float = 1.5

var _is_cracked: bool = false
var _crack_progress: float = 0.0
var _is_cracking: bool = false
var _player_in_range: bool = false
var _search_entries: Array[Dictionary] = []

@onready var _visual: MeshInstance3D = $Visual
@onready var _interact_area: Area3D = $InteractArea


func _ready() -> void:
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	if _visual.material_override != null:
		_visual.material_override = _visual.material_override.duplicate()
	_set_visual_color(Color(0.64, 0.52, 0.27, 1.0))


## Restore this container to its initial (unopened) state.
func reset() -> void:
	_is_cracked = false
	_crack_progress = 0.0
	_is_cracking = false
	_player_in_range = false
	_search_entries.clear()
	_set_visual_color(Color(0.64, 0.52, 0.27, 1.0))



func _process(delta: float) -> void:
	if _is_cracked:
		return
	if GameManager.ui_blocking_input:
		if _is_cracking:
			_interrupt()
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
	if GameManager.ui_blocking_input:
		if _is_cracking:
			_interrupt()
		return
	_is_cracking = false
	_is_cracked = true
	_set_visual_color(Color(0.34, 0.3, 0.2, 1.0))
	NoiseManager.emit_noise(global_position, NoiseManager.Level.LOW)
	open_container()
	cracked.emit(self)


func open_container() -> bool:
	if _search_entries.is_empty():
		for item in loot_table:
			_search_entries.append({
				"item": item,
				"revealed": false,
				"transferred": false,
				"search_progress": 0.0,
			})
	return not _search_entries.is_empty()


func get_search_entry_count() -> int:
	return _search_entries.size()


func is_opened() -> bool:
	return _is_cracked or not _search_entries.is_empty()


func is_entry_revealed(index: int) -> bool:
	if not _is_valid_entry_index(index):
		return false
	return _search_entries[index].revealed


func is_entry_transferred(index: int) -> bool:
	if not _is_valid_entry_index(index):
		return false
	return _search_entries[index].transferred


func get_search_duration_for_entry(index: int) -> float:
	if not _is_valid_entry_index(index):
		return 0.0
	var item: ItemDataResource = _search_entries[index].item
	if item == null:
		return base_search_time
	return base_search_time * _get_rarity_search_multiplier(item.rarity)


func get_search_progress_ratio(index: int) -> float:
	if not _is_valid_entry_index(index):
		return 0.0
	var duration := get_search_duration_for_entry(index)
	if duration <= 0.0:
		return 1.0
	return clampf(float(_search_entries[index].search_progress) / duration, 0.0, 1.0)


func get_revealed_item_name(index: int) -> String:
	if not _is_valid_entry_index(index):
		return ""
	if not bool(_search_entries[index].revealed):
		return ""
	var item: ItemDataResource = _search_entries[index].item
	return item.item_name if item != null else ""


func search_entry(index: int, duration: float) -> bool:
	if not _is_valid_entry_index(index):
		return false
	var entry := _search_entries[index]
	if entry.transferred:
		return false
	if entry.revealed:
		return true
	entry.search_progress = float(entry.search_progress) + maxf(duration, 0.0)
	if float(entry.search_progress) >= get_search_duration_for_entry(index):
		entry.revealed = true
		_search_entries[index] = entry
		return true
	_search_entries[index] = entry
	return false


func transfer_revealed_item_to_inventory(index: int, inventory: Node) -> bool:
	if not _is_valid_entry_index(index) or inventory == null:
		return false
	var entry := _search_entries[index]
	if not bool(entry.revealed) or bool(entry.transferred):
		return false
	if not inventory.has_method("add_item"):
		return false
	var item: ItemDataResource = entry.item
	if not inventory.add_item(item):
		return false
	entry.transferred = true
	_search_entries[index] = entry
	return true


## 把玩家背包里的物品放回容器。
## 优先复用之前被"转移走"的槽位（让 UI 中的空格能继续接收物品）；
## 没有可复用槽位时 append 到末尾，受 MAX_ENTRIES 上限约束。
## 返回 true 表示放入成功。
func add_item_to_container(item: ItemDataResource) -> bool:
	if item == null:
		return false
	# 先扫描已转移槽位复用（保留索引，让 UI"空格"复活成放回的物品）
	for i in _search_entries.size():
		if bool(_search_entries[i].transferred):
			_search_entries[i] = {
				"item": item,
				"revealed": true,
				"transferred": false,
				"search_progress": 0.0,
			}
			return true
	# 全部槽位都还在用 → 尝试 append
	if _search_entries.size() >= MAX_ENTRIES:
		return false
	_search_entries.append({
		"item": item,
		"revealed": true,
		"transferred": false,
		"search_progress": 0.0,
	})
	return true


## 容器槽位上限（HUD ContainerGrid 用来摆出固定数量的格子）
func get_capacity() -> int:
	return MAX_ENTRIES


func _interrupt() -> void:
	_is_cracking = false
	_crack_progress = 0.0
	_set_visual_color(Color(0.64, 0.52, 0.27, 1.0))


func _is_valid_entry_index(index: int) -> bool:
	return index >= 0 and index < _search_entries.size()


func _get_rarity_search_multiplier(rarity: int) -> float:
	match rarity:
		ItemDataResource.Rarity.UNCOMMON:
			return 1.5
		ItemDataResource.Rarity.RARE:
			return 2.25
		ItemDataResource.Rarity.EPIC:
			return 3.5
		_:
			return 1.0


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
	if _visual.material_override is StandardMaterial3D:
		_visual.material_override.albedo_color = color
	else:
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
