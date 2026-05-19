# item_pickup_3d.gd
# 3D 地面拾取物：玩家碰到后尝试加入 Inventory，失败时保留在地面。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写拾取物
extends Area3D

@export var item_data: ItemData

@onready var _visual: MeshInstance3D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_visual()


func set_item(item: ItemData) -> void:
	item_data = item
	if is_node_ready():
		_update_visual()


func _update_visual() -> void:
	if item_data == null:
		return
	var color := Color(0.9, 0.9, 0.9, 1.0)
	match item_data.type:
		ItemData.Type.COLLECTIBLE:
			color = Color(0.95, 0.65, 0.25, 1.0)
		ItemData.Type.AMMO:
			color = Color(0.4, 0.6, 0.95, 1.0)
		ItemData.Type.BATTERY:
			color = Color(0.35, 0.85, 0.45, 1.0)
		ItemData.Type.PURIFIER:
			color = Color(0.35, 0.85, 0.85, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.2
	_visual.material_override = material


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var inv: Node = body.get_node_or_null("Inventory")
	if inv == null:
		return
	if inv.has_method("add_item") and inv.add_item(item_data):
		queue_free()
