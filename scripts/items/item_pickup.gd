# item_pickup.gd
# 地上的可拾取物品。玩家走过去 → 自动尝试加入背包；背包满则停留在原地
extends Area2D

@export var item_data: ItemData

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	_update_visual()


func set_item(item: ItemData) -> void:
	item_data = item
	if is_node_ready():
		_update_visual()


func _update_visual() -> void:
	if item_data == null:
		return
	match item_data.type:
		ItemData.Type.COLLECTIBLE:
			visual.color = Color(0.95, 0.65, 0.25, 1)  # 橙色
		ItemData.Type.AMMO:
			visual.color = Color(0.4, 0.6, 0.95, 1)    # 蓝色
		ItemData.Type.BATTERY:
			visual.color = Color(0.35, 0.85, 0.45, 1)  # 绿色
		ItemData.Type.PURIFIER:
			visual.color = Color(0.35, 0.85, 0.85, 1)  # 青色


func _physics_process(_delta: float) -> void:
	# 每帧检查与玩家的重叠 — 这样玩家走过来 / 背包腾出空间后都能立刻被捡
	for body in get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		var inv: Node = body.get_node_or_null("Inventory")
		if inv == null:
			continue
		if inv.has_method("add_item") and inv.add_item(item_data):
			queue_free()
			return
