# item_pickup_3d.gd
# 3D 可捡拾物品：放置于场景中的实体，玩家靠近触发自动拾取。
# 3D ground pickup that hands items to the player's Inventory.
# [AI-ASSISTED] 2026-05-19 - 3D pickup logic.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
# [AI-ASSISTED] 2026-05-26 — 用 Sprite3D 接入美术 2D 立绘
extends Area3D

const ItemDataResource := preload("res://scripts/items/item_data.gd")

const PICKUP_TEXTURES := {
	ItemDataResource.Type.COLLECTIBLE: "res://assets/sprites/pickups/pickup_resonance_world.png",
	ItemDataResource.Type.AMMO: "res://assets/sprites/pickups/pickup_ammo_world.png",
	ItemDataResource.Type.BATTERY: "res://assets/sprites/pickups/pickup_battery_world.png",
	ItemDataResource.Type.PURIFIER: "res://assets/sprites/pickups/pickup_purifier_world.png",
}

@export var item_data: ItemDataResource

@onready var _visual: MeshInstance3D = $Visual
var _sprite: Sprite3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_sprite = get_node_or_null("Sprite") as Sprite3D
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite"
		# PNG ≈ 1500×1375；pixel_size 0.0005 → Sprite ≈ 0.75×0.69m，匹配 0.56m SphereMesh
		_sprite.position = Vector3(0, 0.45, 0)
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.pixel_size = 0.0005
		_sprite.shaded = false
		_sprite.transparent = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		add_child(_sprite)
	if _visual != null:
		_visual.visible = false
	_update_visual()


func set_item(item: ItemDataResource) -> void:
	item_data = item
	if is_node_ready():
		_update_visual()


func _update_visual() -> void:
	if item_data == null or _sprite == null:
		return
	var texture_path: String = PICKUP_TEXTURES.get(item_data.type, "")
	if texture_path != "" and ResourceLoader.exists(texture_path):
		_sprite.texture = load(texture_path)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var inv: Node = body.get_node_or_null("Inventory")
	if inv == null:
		return
	if inv.has_method("add_item") and inv.add_item(item_data):
		queue_free()
