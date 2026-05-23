# inventory.gd
# 背包系统：挂载于 Player 的数据组件，管理物品槽、负重、分数结算和物品消耗。
# Player inventory: eight slots, weight limits, pickups, item use, and scoring.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node

const SLOT_COUNT: int = 8
const ItemDataResource := preload("res://scripts/items/item_data.gd")

signal inventory_changed(slots: Array, current_weight: float, max_weight: float)
signal pickup_blocked(reason: String)
signal collectible_changed(count: int, score: int)
signal use_blocked(reason: String)

var slots: Array[ItemDataResource] = []


func _ready() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = null
	_emit_all()


func add_item(item: ItemDataResource) -> bool:
	if item == null:
		return false
	if GameManager.player_erosion >= GameManager.max_erosion:
		pickup_blocked.emit("侵蚀已达上限，无法拾取更多。")
		return false
	var empty_idx: int = _find_empty_slot()
	if empty_idx < 0:
		pickup_blocked.emit("背包已满")
		return false
	if get_current_weight() + item.weight > GameManager.max_weight:
		pickup_blocked.emit("负重超限")
		return false
	slots[empty_idx] = item
	_emit_all()
	return true


func transfer_revealed_item_from_container(container: Node, index: int) -> bool:
	if container == null or not container.has_method("transfer_revealed_item_to_inventory"):
		return false
	return container.transfer_revealed_item_to_inventory(index, self)


func get_slot_item(idx: int) -> ItemDataResource:
	if idx < 0 or idx >= SLOT_COUNT:
		return null
	return slots[idx]


func remove_slot_item(idx: int) -> ItemDataResource:
	if idx < 0 or idx >= SLOT_COUNT:
		return null
	var item: ItemDataResource = slots[idx]
	if item == null:
		return null
	slots[idx] = null
	_emit_all()
	return item


func use_slot(idx: int) -> bool:
	if idx < 0 or idx >= SLOT_COUNT:
		return false
	var item: ItemDataResource = slots[idx]
	if item == null:
		return false
	match item.type:
		ItemDataResource.Type.COLLECTIBLE:
			use_blocked.emit("残响碎片仅在撤离后结算分数。")
			return false
		ItemDataResource.Type.AMMO:
			var ps: Node = get_parent().get_node_or_null("PlayerShooting")
			if ps and ps.has_method("add_ammo"):
				ps.add_ammo(item.ammo_amount)
		ItemDataResource.Type.BATTERY:
			var ph: Node = get_parent().get_node_or_null("PlayerHealth")
			if ph and ph.has_method("heal"):
				ph.heal(item.heal_amount)
		ItemDataResource.Type.PURIFIER:
			GameManager.reduce_erosion(item.purify_amount)
	slots[idx] = null
	_emit_all()
	return true


func get_current_weight() -> float:
	var weight: float = 0.0
	for item in slots:
		if item != null:
			weight += item.weight
	return weight


func get_collectible_count() -> int:
	var count: int = 0
	for item in slots:
		if item != null and item.type == ItemDataResource.Type.COLLECTIBLE:
			count += 1
	return count


func calculate_score() -> int:
	var score: int = 0
	for item in slots:
		if item != null and item.type == ItemDataResource.Type.COLLECTIBLE:
			score += item.score_value
	return score


func clear_on_death() -> void:
	for i in SLOT_COUNT:
		slots[i] = null
	_emit_all()


func _find_empty_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


func _emit_all() -> void:
	inventory_changed.emit(slots, get_current_weight(), GameManager.max_weight)
	collectible_changed.emit(get_collectible_count(), calculate_score())
