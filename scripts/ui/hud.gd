# hud.gd
# 局内 UI：HP / 弹药 / 侵蚀 / 负重 / 收集品 / 8 槽背包栏 / 提示
# [AI-ASSISTED] 2026-05-19 - 按 docs/rules.md 规范化脚本结构和安全引用
extends Control

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
var _slot_panels: Array[Panel] = []
var _state_label: Label = null
var _time_label: Label = null
var _flare_label: Label = null
var _result_label: Label = null

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


func _ready() -> void:
	blocked_label.visible = false
	_build_status_labels()
	_build_result_label()
	_build_slot_panels()
	_bind_player_refs()

	GameManager.erosion_changed.connect(_on_erosion_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.signal_flare_fired.connect(_on_signal_flare_fired)
	_on_erosion_changed(GameManager.player_erosion)
	_on_state_changed(GameManager.current_state)
	_update_time_label()
	_update_flare_label()


func _process(delta: float) -> void:
	if _player_shooting == null or _player_health == null or _inventory == null:
		_bind_player_refs()
	if _blocked_hide_timer > 0.0:
		_blocked_hide_timer -= delta
		if _blocked_hide_timer <= 0.0:
			blocked_label.visible = false
	_update_time_label()


func _unhandled_input(event: InputEvent) -> void:
	if (
		_result_label != null
		and _result_label.visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		get_tree().reload_current_scene()


func _build_status_labels() -> void:
	var top_right := get_node_or_null("TopRight") as VBoxContainer
	if top_right == null:
		return
	_state_label = _make_status_label("状态  准备")
	_time_label = _make_status_label("时间  00:00")
	_flare_label = _make_status_label("信号弹  READY")
	top_right.add_child(_state_label)
	top_right.add_child(_time_label)
	top_right.add_child(_flare_label)


func _build_result_label() -> void:
	_result_label = Label.new()
	_result_label.visible = false
	_result_label.layout_mode = 1
	_result_label.anchors_preset = PRESET_CENTER
	_result_label.anchor_left = 0.5
	_result_label.anchor_top = 0.5
	_result_label.anchor_right = 0.5
	_result_label.anchor_bottom = 0.5
	_result_label.offset_left = -240.0
	_result_label.offset_top = -70.0
	_result_label.offset_right = 240.0
	_result_label.offset_bottom = 70.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 24)
	_result_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	add_child(_result_label)


func _make_status_label(text: String) -> Label:
	var label := Label.new()
	label.layout_mode = 2
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _bind_player_refs() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if _player_health == null:
		_player_health = player.get_node_or_null("PlayerHealth")
		if _player_health:
			_player_health.health_changed.connect(_on_health_changed)
			_on_health_changed(_player_health.current_hp, _player_health.max_hp)
	if _player_shooting == null:
		_player_shooting = player.get_node_or_null("PlayerShooting")
		if _player_shooting:
			_player_shooting.ammo_changed.connect(_on_ammo_changed)
			_on_ammo_changed(_player_shooting.current_ammo, _player_shooting.max_ammo)
	if _inventory == null:
		_inventory = player.get_node_or_null("Inventory")
		if _inventory:
			_inventory.inventory_changed.connect(_on_inventory_changed)
			_inventory.collectible_changed.connect(_on_collectible_changed)
			_inventory.pickup_blocked.connect(_on_pickup_blocked)
			_inventory.use_blocked.connect(_on_pickup_blocked)
			_on_collectible_changed(0, 0)
			_on_inventory_changed(_inventory.slots, 0.0, GameManager.max_weight)


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
		var fill := panel.get_node_or_null("Fill") as ColorRect
		var name_lbl := panel.get_node_or_null("ItemName") as Label
		if fill == null or name_lbl == null:
			continue
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


func _on_state_changed(new_state: int) -> void:
	if _state_label != null:
		_state_label.text = "状态  %s" % _get_state_text(new_state)
	_update_flare_label()
	_update_result_label(new_state)


func _on_signal_flare_fired(_origin: Vector3) -> void:
	_update_flare_label()
	blocked_label.text = "信号弹已发射，坚守撤离点"
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _update_time_label() -> void:
	if _time_label == null:
		return
	var total_seconds: int = int(floor(GameManager.elapsed_time))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	_time_label.text = "时间  %02d:%02d" % [minutes, seconds]


func _update_flare_label() -> void:
	if _flare_label == null:
		return
	if GameManager.signal_flare_used:
		_flare_label.text = "信号弹  FIRED"
	else:
		_flare_label.text = "信号弹  READY"


func _update_result_label(state: int) -> void:
	if _result_label == null:
		return
	if state != GameManager.State.SUCCESS and state != GameManager.State.DEAD:
		_result_label.visible = false
		return
	var score := 0
	if state == GameManager.State.SUCCESS and _inventory and _inventory.has_method("calculate_score"):
		score = _inventory.calculate_score()
	var title := "撤离成功" if state == GameManager.State.SUCCESS else "行动失败"
	_result_label.text = "%s\n分数 %d  击杀 %d  侵蚀 %d%%\n按 R 重新开始" % [
		title,
		score,
		GameManager.kill_count,
		int(GameManager.player_erosion),
	]
	_result_label.visible = true


func _get_state_text(state: int) -> String:
	match state:
		GameManager.State.PREPARING:
			return "准备"
		GameManager.State.RUNNING:
			return "搜索"
		GameManager.State.EXTRACTING:
			return "撤离"
		GameManager.State.SUCCESS:
			return "成功"
		GameManager.State.DEAD:
			return "死亡"
		_:
			return "未知"
