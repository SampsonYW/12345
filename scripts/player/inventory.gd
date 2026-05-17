# inventory.gd
# 玩家背包：8 槽位 + 负重双约束。地上 ItemPickup 触发 add_item；按 1-8 触发 use_slot
# 硬门槛：侵蚀 100% 禁止任何拾取；负重超上限禁止；槽满禁止
# COLLECTIBLE 类型只能携带至撤离结算，不可主动使用
# 挂在 Player 下的 Inventory Node 上
extends Node

const SLOT_COUNT: int = 8

signal inventory_changed(slots: Array, current_weight: float, max_weight: float)
signal pickup_blocked(reason: String)
signal collectible_changed(count: int, score: int)
signal use_blocked(reason: String)

var slots: Array[ItemData] = []


func _ready() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = null
	_emit_all()


# 尝试把 item 放进空槽。成功返回 true
func add_item(item: ItemData) -> bool:
	if item == null:
		return false
	if GameManager.player_erosion >= GameManager.max_erosion:
		pickup_blocked.emit("侵蚀已满，无法拾取")
		return false
	var empty_idx: int = _find_empty_slot()
	if empty_idx < 0:
		pickup_blocked.emit("背包已满")
		return false
	if get_current_weight() + item.weight > GameManager.max_weight:
		pickup_blocked.emit("超过负重上限")
		return false
	slots[empty_idx] = item
	_emit_all()
	return true


# 主动使用 idx 槽位的物品。成功返回 true
func use_slot(idx: int) -> bool:
	if idx < 0 or idx >= SLOT_COUNT:
		return false
	var item: ItemData = slots[idx]
	if item == null:
		return false
	match item.type:
		ItemData.Type.COLLECTIBLE:
			use_blocked.emit("残响碎片仅在撤离时计分")
			return false
		ItemData.Type.AMMO:
			var ps: Node = get_parent().get_node_or_null("PlayerShooting")
			if ps and ps.has_method("add_ammo"):
				ps.add_ammo(item.ammo_amount)
		ItemData.Type.BATTERY:
			var ph: Node = get_parent().get_node_or_null("PlayerHealth")
			if ph and ph.has_method("heal"):
				ph.heal(item.heal_amount)
		ItemData.Type.PURIFIER:
			GameManager.reduce_erosion(item.purify_amount)
	slots[idx] = null
	_emit_all()
	return true


func get_current_weight() -> float:
	var w: float = 0.0
	for item in slots:
		if item != null:
			w += item.weight
	return w


func get_collectible_count() -> int:
	var n: int = 0
	for item in slots:
		if item != null and item.type == ItemData.Type.COLLECTIBLE:
			n += 1
	return n


func calculate_score() -> int:
	var s: int = 0
	for item in slots:
		if item != null and item.type == ItemData.Type.COLLECTIBLE:
			s += item.score_value
	return s


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
