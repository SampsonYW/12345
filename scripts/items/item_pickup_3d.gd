# item_pickup_3d.gd
# 3D ground pickup that hands items to the player's Inventory.
# [AI-ASSISTED] 2026-05-19 - 3D pickup logic.
extends Area3D

const ItemDataResource := preload("res://scripts/items/item_data.gd")

@export var item_data: ItemDataResource

@onready var _visual: MeshInstance3D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _visual.material_override != null:
		_visual.material_override = _visual.material_override.duplicate()
	_update_visual()


func set_item(item: ItemDataResource) -> void:
	item_data = item
	if is_node_ready():
		_update_visual()


func _update_visual() -> void:
	if item_data == null:
		return
	var color := Color(0.9, 0.9, 0.9, 1.0)
	match item_data.type:
		ItemDataResource.Type.COLLECTIBLE:
			color = Color(0.95, 0.65, 0.25, 1.0)
		ItemDataResource.Type.AMMO:
			color = Color(0.4, 0.6, 0.95, 1.0)
		ItemDataResource.Type.BATTERY:
			color = Color(0.35, 0.85, 0.45, 1.0)
		ItemDataResource.Type.PURIFIER:
			color = Color(0.35, 0.85, 0.85, 1.0)
	if _visual.material_override is StandardMaterial3D:
		_visual.material_override.albedo_color = color
		_visual.material_override.emission_enabled = true
		_visual.material_override.emission = color * 0.2
	else:
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
