# hud.gd
# 局内 UI：HP / 弹药 / 侵蚀 / 负重 / 收集品 / 8 槽背包栏 / 提示
extends Control

@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_label: Label = %HPLabel
@onready var erosion_bar: ProgressBar = %ErosionBar
@onready var erosion_label: Label = %ErosionLabel
@onready var weight_label: Label = %WeightLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var score_label: Label = %ScoreLabel
@onready var collectible_label: Label = %CollectibleLabel
@onready var blocked_label: Label = %BlockedLabel
@onready var slots_container: HBoxContainer = %BottomBar

const EMPTY_SLOT_COLOR := Color(0.12, 0.12, 0.12, 0.7)
const TYPE_COLORS := {
	ItemData.Type.COLLECTIBLE: Color(0.95, 0.65, 0.25, 1),
	ItemData.Type.AMMO: Color(0.4, 0.6, 0.95, 1),
	ItemData.Type.BATTERY: Color(0.35, 0.85, 0.45, 1),
	ItemData.Type.PURIFIER: Color(0.35, 0.85, 0.85, 1),
}

var _player_health: Node = null
var _player_shooting: Node = null
var _inventory: Node = null
var _blocked_hide_timer: float = 0.0
var _slot_panels: Array = []


func _ready() -> void:
	blocked_label.visible = false
	_build_slot_panels()

	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		_player_health = player.get_node_or_null("PlayerHealth")
		_player_shooting = player.get_node_or_null("PlayerShooting")
		_inventory = player.get_node_or_null("Inventory")

	if _player_health:
		_player_health.health_changed.connect(_on_health_changed)
		_on_health_changed(_player_health.current_hp, _player_health.max_hp)
	if _player_shooting:
		_player_shooting.ammo_changed.connect(_on_ammo_changed)
		_on_ammo_changed(_player_shooting.current_ammo, _player_shooting.max_ammo)
	if _inventory:
		_inventory.inventory_changed.connect(_on_inventory_changed)
		_inventory.collectible_changed.connect(_on_collectible_changed)
		_inventory.pickup_blocked.connect(_on_pickup_blocked)
		_inventory.use_blocked.connect(_on_pickup_blocked)
		_on_collectible_changed(0, 0)
		_on_inventory_changed(_inventory.slots, 0.0, GameManager.max_weight)

	GameManager.erosion_changed.connect(_on_erosion_changed)
	_on_erosion_changed(GameManager.player_erosion)


func _process(delta: float) -> void:
	if _blocked_hide_timer > 0.0:
		_blocked_hide_timer -= delta
		if _blocked_hide_timer <= 0.0:
			blocked_label.visible = false


# 在 BottomBar 下程序化生成 8 个槽位面板
func _build_slot_panels() -> void:
	for i in 8:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(60, 60)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.anchor_right = 1.0
		fill.anchor_bottom = 1.0
		fill.offset_left = 4.0
		fill.offset_top = 4.0
		fill.offset_right = -4.0
		fill.offset_bottom = -4.0
		fill.color = EMPTY_SLOT_COLOR
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(fill)

		var num := Label.new()
		num.name = "Num"
		num.text = str(i + 1)
		num.position = Vector2(6, 2)
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num)

		var name_lbl := Label.new()
		name_lbl.name = "ItemName"
		name_lbl.position = Vector2(6, 36)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_lbl)

		slots_container.add_child(panel)
		_slot_panels.append(panel)


func _on_health_changed(current: float, maximum: float) -> void:
	hp_bar.value = current / maximum * 100.0
	hp_label.text = "HP  %d / %d" % [int(current), int(maximum)]


func _on_erosion_changed(value: float) -> void:
	erosion_bar.value = value
	erosion_label.text = "侵蚀  %d%%" % int(value)


func _on_ammo_changed(current: int, max_value: int) -> void:
	ammo_label.text = "弹药  %d / %d" % [current, max_value]


func _on_collectible_changed(count: int, score: int) -> void:
	collectible_label.text = "残响  %d" % count
	score_label.text = "分数  %d" % score


func _on_inventory_changed(slots: Array, current_weight: float, max_weight: float) -> void:
	weight_label.text = "负重  %d / %d" % [int(round(current_weight)), int(max_weight)]
	for i in _slot_panels.size():
		var panel: Panel = _slot_panels[i]
		var fill: ColorRect = panel.get_node("Fill")
		var name_lbl: Label = panel.get_node("ItemName")
		var item: ItemData = slots[i] if i < slots.size() else null
		if item == null:
			fill.color = EMPTY_SLOT_COLOR
			name_lbl.text = ""
		else:
			fill.color = TYPE_COLORS.get(item.type, Color.WHITE)
			name_lbl.text = item.item_name


func _on_pickup_blocked(reason: String) -> void:
	blocked_label.text = reason
	blocked_label.visible = true
	_blocked_hide_timer = 2.0
