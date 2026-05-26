# container_3d.gd
# 3D 容器节点：管理破解时间、被发现概率、随机物品掉落和开启状态。
# 3D 密封容器：玩家进入范围后长按 interact 破解，完成后生成 3D 拾取物。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写容器交互
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
# [AI-ASSISTED] 2026-05-26 — Sprite3D 接入美术 2D 立绘 + 按 loot_table 推断类型
extends StaticBody3D

signal cracked(container: StaticBody3D)

const ItemDataResource := preload("res://scripts/items/item_data.gd")

## 容器视觉类型（按 loot_table 自动推断，影响贴图）
enum ContainerKind { NORMAL, AMMO, MEDICAL }

## 容器各类型 × 各状态的贴图路径
const CONTAINER_TEXTURES := {
	ContainerKind.NORMAL: {
		"closed": "res://assets/sprites/containers/container_supply_closed.png",
		"hacking": "res://assets/sprites/containers/container_supply_hacking.png",
		"open": "res://assets/sprites/containers/container_supply_open.png",
	},
	ContainerKind.AMMO: {
		"closed": "res://assets/sprites/containers/container_ammo_closed.png",
		"hacking": "res://assets/sprites/containers/container_ammo_closed.png",
		"open": "res://assets/sprites/containers/container_ammo_open.png",
	},
	ContainerKind.MEDICAL: {
		"closed": "res://assets/sprites/containers/container_medical_closed.png",
		"hacking": "res://assets/sprites/containers/container_medical_closed.png",
		"open": "res://assets/sprites/containers/container_medical_open.png",
	},
}

## 容器的最大条目数（loot + 玩家放回的物品之和），跟 HUD 里 ContainerGrid 的格子数一致
const MAX_ENTRIES: int = 12

@export var loot_table: Array[ItemDataResource] = []
@export var risk: String = "low"
@export var base_crack_time: float = 2.0
@export var base_search_time: float = 1.0

var _is_cracked: bool = false
var _crack_progress: float = 0.0
var _is_cracking: bool = false
var _player_in_range: bool = false
var _search_entries: Array[Dictionary] = []
var _container_kind: int = ContainerKind.NORMAL


@onready var _visual: MeshInstance3D = $Visual
@onready var _interact_area: Area3D = $InteractArea
var _sprite: Sprite3D = null


func _ready() -> void:
	add_to_group("containers")
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	_container_kind = _infer_kind_from_loot()
	_sprite = get_node_or_null("Sprite") as Sprite3D
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite"
		# PNG ≈ 1910×1365；pixel_size 0.0008 → Sprite ≈ 1.53×1.09m，匹配 BoxMesh 1.2×1×1.2m
		_sprite.position = Vector3(0, 0.6, 0)
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.pixel_size = 0.0008
		_sprite.shaded = false
		_sprite.transparent = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		add_child(_sprite)
	if _visual != null:
		_visual.visible = false
	_apply_sprite_state("closed")


## Restore this container to its initial (unopened) state.
func reset() -> void:
	_is_cracked = false
	_crack_progress = 0.0
	_is_cracking = false
	_player_in_range = false
	_search_entries.clear()
	_apply_sprite_state("closed")



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
	_apply_sprite_state("hacking")

func is_cracking() -> bool:
	return _is_cracking

func get_crack_progress() -> float:
	return _crack_progress


func _complete_crack() -> void:
	if GameManager.ui_blocking_input:
		if _is_cracking:
			_interrupt()
		return
	_is_cracking = false
	_is_cracked = true
	_apply_sprite_state("open")
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


func get_revealed_item_icon(index: int) -> Texture2D:
	if not _is_valid_entry_index(index):
		return null
	if not bool(_search_entries[index].revealed):
		return null
	var item: ItemDataResource = _search_entries[index].item
	if item == null:
		return null
	return item.icon


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
	_apply_sprite_state("closed")


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


## 根据 loot_table 中物品类型推断容器视觉类型。
## - 全 AMMO → AMMO
## - 包含 BATTERY 或 PURIFIER → MEDICAL
## - 其他（COLLECTIBLE 等）→ NORMAL
func _infer_kind_from_loot() -> int:
	if loot_table.is_empty():
		return ContainerKind.NORMAL
	var has_ammo := false
	var has_medical := false
	var has_other := false
	for item in loot_table:
		if item == null:
			continue
		match item.type:
			ItemDataResource.Type.AMMO:
				has_ammo = true
			ItemDataResource.Type.BATTERY, ItemDataResource.Type.PURIFIER:
				has_medical = true
			_:
				has_other = true
	if has_medical:
		return ContainerKind.MEDICAL
	if has_ammo and not has_other:
		return ContainerKind.AMMO
	return ContainerKind.NORMAL


func _apply_sprite_state(state: String) -> void:
	if _sprite == null:
		return
	var paths: Dictionary = CONTAINER_TEXTURES.get(_container_kind, CONTAINER_TEXTURES[ContainerKind.NORMAL])
	var path: String = paths.get(state, "")
	if path != "" and ResourceLoader.exists(path):
		_sprite.texture = load(path)


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
