# hud.gd
# HUD UI 逻辑脚本：管理玩家状态条（HP、侵蚀、弹药）、背包拖拽、容器搜索和母车仓库，以及屏幕边缘敌人警示 wedges。
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Control

const EMPTY_SLOT_COLOR := Color(0.12, 0.12, 0.12, 0.72)
const START_KEYS := [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
const SHORTCUT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
const ItemDataResource := preload("res://scripts/items/item_data.gd")
const ITEM_RELIC := preload("res://resources/items/relic_small.tres")
const ITEM_AMMO := preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY := preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER := preload("res://resources/items/purifier.tres")
const STORAGE_DRAG_SLOT_SCRIPT := preload("res://scripts/ui/storage_drag_slot.gd")
const MINIMAP_SCRIPT := preload("res://scripts/ui/minimap.gd")

# ----- Alert indicator constants (polish_plan §3) -----
const ALERT_INDICATOR_SIZE := 32.0
const ALERT_PULSE_SPEED := 4.0
const ALERT_MAX_OPACITY := 0.9
const ALERT_DETECTION_RANGE := 25.0
const ALERT_EDGE_INSET := 8.0
const ALERT_MERGE_ANGLE_DEG := 15.0

# ----- Spawn pulse constants (polish_plan §4) -----
const SPAWN_PULSE_SIZE := 48.0
const SPAWN_PULSE_DURATION := 2.0
const SPAWN_PULSE_ENTER_TIME := 0.2
const SPAWN_PULSE_HOLD_TIME := 1.5
const SPAWN_PULSE_FADE_TIME := 0.3

const TYPE_COLORS := {
	ItemDataResource.Type.COLLECTIBLE: Color(0.95, 0.68, 0.25, 1.0),
	ItemDataResource.Type.AMMO: Color(0.38, 0.62, 0.95, 1.0),
	ItemDataResource.Type.BATTERY: Color(0.35, 0.86, 0.45, 1.0),
	ItemDataResource.Type.PURIFIER: Color(0.30, 0.82, 0.84, 1.0),
}

var _player_health: Node = null
var _player_shooting: Node = null
var _inventory: Node = null
var _extraction: Node = null
var _blocked_hide_timer: float = 0.0
var _slot_panels: Array[Panel] = []

var _state_label: Label = null
var _time_label: Label = null
var _signal_label: Label = null
var _main_overlay: Control = null
var _main_prompt_label: Label = null
var _main_summary_label: Label = null
var _result_overlay: Control = null
var _result_title_label: Label = null
var _result_stats_label: Label = null
var _prompt_label: Label = null
var _risk_label: Label = null
var _zone_name_label: Label = null
var _zone_risk_label: Label = null
var _zone_container: VBoxContainer = null
var _backpack_overlay: Control = null
var _storage_overlay: Control = null
var _search_overlay: Control = null
var _active_blocking_overlay: Control = null
var _search_container: Node = null
var _search_active_index: int = -1
var _search_feedback_label: Label = null
var _search_entry_snapshot: Array = []
var _minimap: Control = null
var _hold_progress_container: Control = null
var _hold_progress_fill: ColorRect = null
var _hold_progress_label: Label = null
var _spawn_manager: Node = null
var _alert_indicators: Array[Dictionary] = []  # [{screen_pos, opacity, direction}]
var _spawn_pulses: Array[Dictionary] = []  # [{screen_pos, remaining, max_time, direction}]
var _warehouse_stock := {
	"标准弹药": 12,
	"能量电池": 6,
	"净化剂": 2,
	"残响碎片": 1,
}
var _warehouse_order := ["标准弹药", "能量电池", "净化剂", "残响碎片"]
var _warehouse_items := {
	"标准弹药": ITEM_AMMO,
	"能量电池": ITEM_BATTERY,
	"净化剂": ITEM_PURIFIER,
	"残响碎片": ITEM_RELIC,
}

@onready var top_left: VBoxContainer = $TopLeft
@onready var top_right: VBoxContainer = $TopRight
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
	slots_container.visible = false
	_build_status_labels()
	_build_minimap()
	_build_slot_panels()
	_build_prompt_labels()
	_build_main_overlay()
	_build_result_overlay()
	_bind_player_refs()
	_bind_extraction_ref()

	GameManager.erosion_changed.connect(_on_erosion_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.signal_flare_fired.connect(_on_signal_flare_fired)
	GameManager.location_changed.connect(_on_location_changed)

	_on_erosion_changed(GameManager.player_erosion)
	_on_state_changed(GameManager.current_state)
	_update_time_label()
	_update_signal_label()
	call_deferred("_restore_launch_screen")


func _process(delta: float) -> void:
	if _player_shooting == null or _player_health == null or _inventory == null:
		_bind_player_refs()
	if _extraction == null:
		_bind_extraction_ref()
	_bind_spawn_manager_ref()
	if _blocked_hide_timer > 0.0:
		_blocked_hide_timer -= delta
		if _blocked_hide_timer <= 0.0:
			blocked_label.visible = false
	_process_container_search(delta)
	_update_time_label()
	_update_signal_label()
	_update_alert_indicators(delta)
	_update_spawn_pulses(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if _main_overlay != null and _main_overlay.visible:
		if event.physical_keycode in START_KEYS:
			_mark_input_as_handled()
			_on_title_clicked()
		return
	if _result_overlay != null and _result_overlay.visible:
		if event.physical_keycode in START_KEYS:
			_mark_input_as_handled()
			_return_to_home_from_result()
		return
	if GameManager.current_location == GameManager.Location.TITLE:
		return
	if event.is_action_pressed("backpack"):
		_mark_input_as_handled()
		if _active_blocking_overlay != null:
			close_blocking_overlay()
		else:
			open_backpack()
		return
	if event.keycode == KEY_ESCAPE and _active_blocking_overlay != null:
		_mark_input_as_handled()
		close_blocking_overlay()
		return
	if _active_blocking_overlay != null and _handle_overlay_shortcut(event):
		_mark_input_as_handled()
		return


func _restore_launch_screen() -> void:
	GameManager.reset_run()
	GameManager.set_location(GameManager.Location.TITLE)
	_show_main_overlay(true)
	if GameManager.consume_start_after_reload():
		_start_run_from_ui()


func _mark_input_as_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _build_status_labels() -> void:
	_state_label = _make_status_label("状态  准备中")
	_time_label = _make_status_label("时间  00:00")
	_signal_label = _make_status_label("信号  就绪")
	_risk_label = _make_status_label("风险  标题")
	top_right.add_child(_state_label)
	top_right.add_child(_time_label)
	top_right.add_child(_signal_label)
	top_right.add_child(_risk_label)

	# Zone info panel (top-left, below existing stats)
	var zone_spacer := Control.new()
	zone_spacer.custom_minimum_size = Vector2(0, 10)
	zone_spacer.name = "ZoneSpacer"
	top_left.add_child(zone_spacer)

	_zone_container = VBoxContainer.new()
	_zone_container.name = "ZoneInfo"
	_zone_container.visible = false
	top_left.add_child(_zone_container)

	_zone_name_label = Label.new()
	_zone_name_label.name = "ZoneNameLabel"
	_zone_name_label.layout_mode = 2
	_zone_name_label.text = ""
	_zone_name_label.add_theme_font_size_override("font_size", 18)
	_zone_container.add_child(_zone_name_label)

	_zone_risk_label = Label.new()
	_zone_risk_label.name = "ZoneRiskLabel"
	_zone_risk_label.layout_mode = 2
	_zone_risk_label.text = ""
	_zone_risk_label.add_theme_font_size_override("font_size", 15)
	_zone_container.add_child(_zone_risk_label)


func _build_prompt_labels() -> void:
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.layout_mode = 1
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -360.0
	_prompt_label.offset_top = -150.0
	_prompt_label.offset_right = 360.0
	_prompt_label.offset_bottom = -116.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.94, 1.0))
	add_child(_prompt_label)
	_build_hold_progress()


func _build_minimap() -> void:
	_minimap = Control.new()
	_minimap.name = "Minimap"
	_minimap.set_script(MINIMAP_SCRIPT)
	_minimap.layout_mode = 1
	_minimap.anchor_left = 0.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_right = 0.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = 20.0
	_minimap.offset_top = -150.0
	_minimap.offset_right = 260.0
	_minimap.offset_bottom = -30.0
	_minimap.visible = false
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimap)


func _build_hold_progress() -> void:
	# Container: centered bottom, above PromptLabel
	_hold_progress_container = Control.new()
	_hold_progress_container.name = "HoldProgress"
	_hold_progress_container.layout_mode = 1
	_hold_progress_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold_progress_container.anchor_left = 0.5
	_hold_progress_container.anchor_top = 1.0
	_hold_progress_container.anchor_right = 0.5
	_hold_progress_container.anchor_bottom = 1.0
	_hold_progress_container.offset_left = -140.0
	_hold_progress_container.offset_top = -100.0
	_hold_progress_container.offset_right = 140.0
	_hold_progress_container.offset_bottom = -68.0
	_hold_progress_container.visible = false
	_hold_progress_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hold_progress_container)

	# Background bar
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.08, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_progress_container.add_child(bg)

	# Fill bar
	_hold_progress_fill = ColorRect.new()
	_hold_progress_fill.name = "Fill"
	_hold_progress_fill.layout_mode = 1
	_hold_progress_fill.anchor_left = 0.0
	_hold_progress_fill.anchor_top = 0.0
	_hold_progress_fill.anchor_right = 0.0
	_hold_progress_fill.anchor_bottom = 1.0
	_hold_progress_fill.offset_left = 2.0
	_hold_progress_fill.offset_top = 2.0
	_hold_progress_fill.offset_right = 2.0
	_hold_progress_fill.offset_bottom = -2.0
	_hold_progress_fill.color = Color(0.38, 0.78, 1.0, 0.9)
	_hold_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_progress_container.add_child(_hold_progress_fill)

	# Label overlay
	_hold_progress_label = Label.new()
	_hold_progress_label.name = "Label"
	_hold_progress_label.layout_mode = 1
	_hold_progress_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hold_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hold_progress_label.add_theme_font_size_override("font_size", 16)
	_hold_progress_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96, 1.0))
	_hold_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_progress_container.add_child(_hold_progress_label)


func _build_slot_panels() -> void:
	for i in 8:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(60, 60)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		num.position = Vector2(6.0, 2.0)
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num)

		var name_label := Label.new()
		name_label.name = "ItemName"
		name_label.position = Vector2(6.0, 36.0)
		name_label.size = Vector2(48.0, 20.0)
		name_label.clip_text = true
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_label)

		slots_container.add_child(panel)
		_slot_panels.append(panel)


func _build_main_overlay() -> void:
	_main_overlay = ColorRect.new()
	_main_overlay.name = "MainOverlay"
	_main_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_overlay.color = Color(0.035, 0.045, 0.04, 0.94)
	_main_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_overlay.gui_input.connect(_on_main_overlay_gui_input)
	add_child(_main_overlay)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -240.0
	content.offset_top = -120.0
	content.offset_right = 240.0
	content.offset_bottom = 120.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	_main_overlay.add_child(content)

	var title := Label.new()
	title.text = "余晖号"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78, 1.0))
	content.add_child(title)

	_main_prompt_label = Label.new()
	_main_prompt_label.text = "点击任意位置开始"
	_main_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_prompt_label.add_theme_font_size_override("font_size", 18)
	_main_prompt_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.82, 1.0))
	content.add_child(_main_prompt_label)

	_main_summary_label = Label.new()
	_main_summary_label.visible = false
	_main_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_summary_label.add_theme_font_size_override("font_size", 16)
	_main_summary_label.add_theme_color_override("font_color", Color(0.90, 0.96, 0.92, 1.0))
	content.add_child(_main_summary_label)

	var button := Button.new()
	button.text = "开始"
	button.custom_minimum_size = Vector2(180.0, 42.0)
	button.pressed.connect(_on_title_clicked)
	content.add_child(button)


func _build_result_overlay() -> void:
	_result_overlay = ColorRect.new()
	_result_overlay.name = "ResultOverlay"
	_result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.color = Color(0.02, 0.025, 0.025, 0.88)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.visible = false
	add_child(_result_overlay)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -280.0
	content.offset_top = -150.0
	content.offset_right = 280.0
	content.offset_bottom = 150.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	_result_overlay.add_child(content)

	_result_title_label = Label.new()
	_result_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title_label.add_theme_font_size_override("font_size", 34)
	_result_title_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.74, 1.0))
	content.add_child(_result_title_label)

	_result_stats_label = Label.new()
	_result_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats_label.add_theme_font_size_override("font_size", 18)
	_result_stats_label.add_theme_color_override("font_color", Color(0.90, 0.96, 0.92, 1.0))
	content.add_child(_result_stats_label)

	var prompt := Label.new()
	prompt.text = "按回车或空格返回余晖号"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(0.76, 0.84, 0.80, 1.0))
	content.add_child(prompt)

	var button := Button.new()
	button.text = "返回余晖号"
	button.custom_minimum_size = Vector2(180.0, 42.0)
	button.pressed.connect(_return_to_home_from_result)
	content.add_child(button)


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
		if _player_health != null:
			_player_health.health_changed.connect(_on_health_changed)
			_on_health_changed(_player_health.current_hp, _player_health.max_hp)
	if _player_shooting == null:
		_player_shooting = player.get_node_or_null("PlayerShooting")
		if _player_shooting != null:
			_player_shooting.ammo_changed.connect(_on_ammo_changed)
			_on_ammo_changed(_player_shooting.current_ammo, _player_shooting.max_ammo)
	if _inventory == null:
		_inventory = player.get_node_or_null("Inventory")
		if _inventory != null:
			_inventory.inventory_changed.connect(_on_inventory_changed)
			_inventory.collectible_changed.connect(_on_collectible_changed)
			_inventory.pickup_blocked.connect(_on_pickup_blocked)
			_inventory.use_blocked.connect(_on_pickup_blocked)
			_on_inventory_changed(_inventory.slots, _inventory.get_current_weight(), GameManager.max_weight)
			_on_collectible_changed(_inventory.get_collectible_count(), _inventory.calculate_score())


func _bind_extraction_ref() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		_extraction = scene.get_node_or_null("Extraction")


func set_prompt_text(text: String) -> void:
	if _prompt_label != null:
		_prompt_label.text = text
		_prompt_label.visible = false


func get_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


func show_hold_progress(ratio: float, text: String = "") -> void:
	if _hold_progress_container == null:
		return
	_hold_progress_container.visible = true
	if _hold_progress_label != null:
		_hold_progress_label.text = text if text != "" else "%d%%" % int(round(ratio * 100.0))
	if _hold_progress_fill != null:
		var container_width := _hold_progress_container.size.x - 4.0
		_hold_progress_fill.offset_right = 2.0 + container_width * clampf(ratio, 0.0, 1.0)
		# Color gradient: blue → cyan → green
		var c := Color(0.38, 0.78, 1.0, 0.9).lerp(Color(0.35, 0.92, 0.45, 0.9), ratio)
		_hold_progress_fill.color = c


func hide_hold_progress() -> void:
	if _hold_progress_container != null:
		_hold_progress_container.visible = false


func set_risk_label_text(text: String) -> void:
	if _risk_label != null:
		_risk_label.text = text


func get_risk_label_text() -> String:
	return _risk_label.text if _risk_label != null else ""


func set_zone_info(zone_name: String, risk: String) -> void:
	if _zone_container != null:
		_zone_container.visible = zone_name != ""
	if _zone_name_label != null:
		_zone_name_label.text = zone_name
	if _zone_risk_label != null:
		var risk_display := "低风险" if risk == "low" else "高风险"
		_zone_risk_label.text = "危险等级: %s" % risk_display
		if risk == "high":
			_zone_risk_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
		else:
			_zone_risk_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55, 1.0))


func open_backpack() -> void:
	close_blocking_overlay()
	if _backpack_overlay == null or not is_instance_valid(_backpack_overlay):
		_backpack_overlay = _build_backpack_overlay()
		add_child(_backpack_overlay)
	_populate_backpack_grid(_backpack_overlay.get_node_or_null("BackpackGrid") as GridContainer)
	_show_blocking_overlay(_backpack_overlay)


func open_storage() -> void:
	close_blocking_overlay()
	if _storage_overlay == null or not is_instance_valid(_storage_overlay):
		_storage_overlay = _build_storage_overlay()
		add_child(_storage_overlay)
	_populate_backpack_grid(_storage_overlay.get_node_or_null("BackpackGrid") as GridContainer)
	_populate_warehouse_list(_storage_overlay.get_node_or_null("WarehouseList") as VBoxContainer)
	_show_blocking_overlay(_storage_overlay)


func open_container_search(container: Node) -> void:
	if container == null:
		return
	close_blocking_overlay()
	_search_container = container
	_search_active_index = -1
	if container.has_method("open_container"):
		container.open_container()
	if _search_overlay == null or not is_instance_valid(_search_overlay):
		_search_overlay = _build_search_overlay()
		add_child(_search_overlay)
	_populate_backpack_grid(_search_overlay.get_node_or_null("BackpackGrid") as GridContainer)
	_populate_container_list()
	_show_blocking_overlay(_search_overlay)


func close_blocking_overlay() -> void:
	if _active_blocking_overlay != null and is_instance_valid(_active_blocking_overlay):
		_active_blocking_overlay.visible = false
	_active_blocking_overlay = null
	_search_container = null
	_search_active_index = -1
	_search_entry_snapshot.clear()
	GameManager.set_ui_blocking_input(false)


func get_visible_backpack_item_names() -> Array[String]:
	var names: Array[String] = []
	var grid := _get_visible_backpack_grid()
	if grid == null:
		return names
	for child in grid.get_children():
		var label := child.find_child("ItemName", true, false) as Label
		if label != null and label.text.strip_edges() != "":
			names.append(label.text)
	return names


func _show_blocking_overlay(overlay: Control) -> void:
	_active_blocking_overlay = overlay
	overlay.visible = true
	GameManager.set_ui_blocking_input(true)


func _get_visible_backpack_grid() -> GridContainer:
	if _backpack_overlay != null and _backpack_overlay.visible:
		return _backpack_overlay.get_node_or_null("BackpackGrid") as GridContainer
	if _storage_overlay != null and _storage_overlay.visible:
		return _storage_overlay.get_node_or_null("BackpackGrid") as GridContainer
	if _search_overlay != null and _search_overlay.visible:
		return _search_overlay.get_node_or_null("BackpackGrid") as GridContainer
	return null


func _build_backpack_overlay() -> Control:
	var overlay := _make_overlay("BackpackOverlay", Vector2(520.0, 460.0))
	var panel := overlay.get_node("Panel") as PanelContainer
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	content.add_child(_make_overlay_title("背包"))
	var grid := _make_backpack_grid()
	content.add_child(grid)
	var direct_grid := _make_backpack_grid()
	direct_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_overlay_child(direct_grid, Vector2(-180.0, -130.0), Vector2(180.0, 90.0))
	overlay.add_child(direct_grid)
	content.add_child(_make_hint_label("按 Esc 或 B 关闭。关闭后快捷键仍可使用。"))
	return overlay


func _build_storage_overlay() -> Control:
	var overlay := _make_overlay("StorageOverlay", Vector2(860.0, 500.0))
	var panel := overlay.get_node("Panel") as PanelContainer
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(390.0, 0.0)
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	left.add_child(_make_overlay_title("背包"))
	left.add_child(_make_backpack_grid())
	var direct_grid := _make_backpack_grid()
	direct_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_overlay_child(direct_grid, Vector2(-390.0, -160.0), Vector2(-20.0, 120.0))
	overlay.add_child(direct_grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360.0, 0.0)
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_make_overlay_title("仓库"))
	var list := VBoxContainer.new()
	list.name = "WarehouseList"
	list.add_theme_constant_override("separation", 6)
	right.add_child(list)
	var direct_list := VBoxContainer.new()
	direct_list.name = "WarehouseList"
	direct_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direct_list.add_theme_constant_override("separation", 6)
	_position_overlay_child(direct_list, Vector2(40.0, -160.0), Vector2(390.0, 120.0))
	overlay.add_child(direct_list)
	right.add_child(_make_hint_label(
		"行显示库存。转移按钮共享相同的物品操作接口。"
	))
	return overlay


func _build_search_overlay() -> Control:
	var overlay := _make_overlay("SearchOverlay", Vector2(940.0, 540.0))
	var panel := overlay.get_node("Panel") as PanelContainer
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(390.0, 0.0)
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	left.add_child(_make_overlay_title("背包"))
	left.add_child(_make_backpack_grid())
	var direct_grid := _make_backpack_grid()
	direct_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_overlay_child(direct_grid, Vector2(-430.0, -170.0), Vector2(-50.0, 130.0))
	overlay.add_child(direct_grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430.0, 0.0)
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_make_overlay_title("容器"))
	var list := VBoxContainer.new()
	list.name = "ContainerList"
	list.add_theme_constant_override("separation", 6)
	right.add_child(list)
	var direct_list := VBoxContainer.new()
	direct_list.name = "ContainerList"
	direct_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direct_list.add_theme_constant_override("separation", 6)
	_position_overlay_child(direct_list, Vector2(20.0, -170.0), Vector2(430.0, 130.0))
	overlay.add_child(direct_list)
	_search_feedback_label = _make_hint_label("")
	_search_feedback_label.name = "SearchFeedback"
	right.add_child(_search_feedback_label)
	right.add_child(_make_hint_label(
		"搜索自动开始。请将发现的物品移入背包。"
	))
	return overlay


func _make_overlay(node_name: String, size: Vector2) -> Control:
	var overlay := ColorRect.new()
	overlay.name = node_name
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.025, 0.025, 0.58)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.055, 0.065, 0.06, 0.88)))
	overlay.add_child(panel)
	return overlay


func _position_overlay_child(
	control: Control,
	top_left_offset: Vector2,
	bottom_right_offset: Vector2
) -> void:
	control.set_anchors_preset(Control.PRESET_CENTER)
	control.offset_left = top_left_offset.x
	control.offset_top = top_left_offset.y
	control.offset_right = bottom_right_offset.x
	control.offset_bottom = bottom_right_offset.y


func _make_overlay_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72, 1.0))
	return label


func _make_hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.76, 1.0))
	return label


func _make_backpack_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "BackpackGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _populate_backpack_grid(grid: GridContainer) -> void:
	if grid == null:
		return
	_clear_ui_children(grid)
	var slots: Array = _inventory.slots if _inventory != null else []
	for i in 8:
		var slot := PanelContainer.new()
		slot.set_script(STORAGE_DRAG_SLOT_SCRIPT)
		slot.set("owner_hud", self)
		slot.set("accept_target", "backpack_slot")
		slot.custom_minimum_size = Vector2(86.0, 76.0)
		slot.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.09, 0.085, 0.82)))

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		slot.add_child(box)

		var title := Label.new()
		title.name = "ItemName"
		title.clip_text = true
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90, 1.0))
		var item: ItemDataResource = slots[i] if i < slots.size() else null
		title.text = item.item_name if item != null else ""
		if item != null:
			slot.set("drag_payload", {
				"source": "backpack",
				"slot_index": i,
				"label": item.item_name,
			})
		box.add_child(title)

		var detail := Label.new()
		detail.text = "栏位 %d" % (i + 1)
		detail.add_theme_font_size_override("font_size", 11)
		detail.add_theme_color_override("font_color", Color(0.62, 0.70, 0.66, 1.0))
		box.add_child(detail)
		grid.add_child(slot)


func _populate_warehouse_list(list: VBoxContainer) -> void:
	if list == null:
		return
	_clear_ui_children(list)
	for item_name in _warehouse_order:
		var row_panel := PanelContainer.new()
		row_panel.set_script(STORAGE_DRAG_SLOT_SCRIPT)
		row_panel.set("owner_hud", self)
		row_panel.set("accept_target", "warehouse_list")
		row_panel.set("drag_payload", {
			"source": "warehouse",
			"item_name": String(item_name),
			"label": String(item_name),
		})
		row_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.075, 0.72)))
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 34.0)
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row_panel.add_child(row)
		var label := Label.new()
		label.text = "%s x %d" % [String(item_name), int(_warehouse_stock.get(item_name, 0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.88, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		var button := Button.new()
		button.text = "转移"
		button.disabled = int(_warehouse_stock.get(item_name, 0)) <= 0
		button.custom_minimum_size = Vector2(72.0, 30.0)
		button.pressed.connect(Callable(self, "_transfer_warehouse_item").bind(String(item_name)))
		row.add_child(button)
		list.add_child(row_panel)


func _populate_container_list() -> void:
	if _search_overlay == null:
		return
	var list := _search_overlay.get_node_or_null("ContainerList") as VBoxContainer
	if list == null:
		return
	_clear_ui_children(list)
	if _search_container == null or not is_instance_valid(_search_container):
		return
	var count := 0
	if _search_container.has_method("get_search_entry_count"):
		count = _search_container.get_search_entry_count()
	for i in count:
		var row_panel := PanelContainer.new()
		row_panel.set_script(STORAGE_DRAG_SLOT_SCRIPT)
		row_panel.set("owner_hud", self)
		row_panel.set("accept_target", "container_list")
		row_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.075, 0.72)))
		if _can_transfer_container_entry(i):
			row_panel.set("drag_payload", {
				"source": "container",
				"entry_index": i,
				"label": _get_container_entry_label(i),
			})
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 38.0)
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row_panel.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.88, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.text = "%d  %s" % [i + 1, _get_container_entry_label(i)]
		row.add_child(label)
		var button := Button.new()
		button.text = "转移"
		button.disabled = not _can_transfer_container_entry(i)
		button.custom_minimum_size = Vector2(78.0, 30.0)
		button.pressed.connect(Callable(self, "_transfer_container_entry").bind(i))
		row.add_child(button)
		list.add_child(row_panel)
	_save_search_snapshot()


func _get_container_entry_label(index: int) -> String:
	if _search_container == null:
		return "未知"
	var container := _search_container
	if container.has_method("is_entry_transferred") and container.is_entry_transferred(index):
		return "已转移"
	if container.has_method("is_entry_revealed") and container.is_entry_revealed(index):
		if container.has_method("get_revealed_item_name"):
			return container.get_revealed_item_name(index)
		return "已发现物品"
	if index == _search_active_index and container.has_method("get_search_progress_ratio"):
		return "搜索中... %d%%" % int(round(container.get_search_progress_ratio(index) * 100.0))
	return "Unknown"


func _can_transfer_container_entry(index: int) -> bool:
	if _search_container == null:
		return false
	var container := _search_container
	if container.has_method("is_entry_transferred") and container.is_entry_transferred(index):
		return false
	return container.has_method("is_entry_revealed") and container.is_entry_revealed(index)


func _transfer_container_entry(index: int) -> bool:
	if _inventory == null or _search_container == null:
		return false
	var moved := false
	if _inventory.has_method("transfer_revealed_item_from_container"):
		moved = _inventory.transfer_revealed_item_from_container(_search_container, index)
	if moved:
		_set_search_feedback("已移至背包。")
	else:
		_set_search_feedback("无法转移物品。")
	_populate_backpack_grid(_search_overlay.get_node_or_null("BackpackGrid") as GridContainer)
	_populate_container_list()
	return moved


func transfer_storage_item_to_backpack(item_name: String) -> bool:
	return _transfer_warehouse_item(item_name)


func transfer_backpack_slot_to_storage(slot_index: int) -> bool:
	if _inventory == null or not _inventory.has_method("remove_slot_item"):
		return false
	var item: ItemDataResource = null
	if _inventory.has_method("get_slot_item"):
		item = _inventory.get_slot_item(slot_index)
	if item == null:
		return false
	var removed: ItemDataResource = _inventory.remove_slot_item(slot_index)
	if removed == null:
		return false
	var stock_name := _get_storage_name_for_item(removed)
	_warehouse_stock[stock_name] = int(_warehouse_stock.get(stock_name, 0)) + 1
	if _storage_overlay != null and _storage_overlay.visible:
		_populate_backpack_grid(_storage_overlay.get_node_or_null("BackpackGrid") as GridContainer)
		_populate_warehouse_list(_storage_overlay.get_node_or_null("WarehouseList") as VBoxContainer)
	return true


func can_accept_storage_drop(data: Variant, target: String) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	var source := String(payload.get("source", ""))
	if target == "backpack_slot":
		return source == "warehouse" or source == "container"
	if target == "warehouse_list":
		return source == "backpack"
	return false


func accept_storage_drop(data: Variant, target: String) -> bool:
	if not can_accept_storage_drop(data, target):
		return false
	var payload: Dictionary = data
	var source := String(payload.get("source", ""))
	if target == "backpack_slot" and source == "warehouse":
		return transfer_storage_item_to_backpack(String(payload.get("item_name", "")))
	if target == "backpack_slot" and source == "container":
		return _transfer_container_entry(int(payload.get("entry_index", -1)))
	if target == "warehouse_list" and source == "backpack":
		return transfer_backpack_slot_to_storage(int(payload.get("slot_index", -1)))
	return false


func _transfer_warehouse_item(item_name: String) -> bool:
	if _inventory == null:
		return false
	var stock := int(_warehouse_stock.get(item_name, 0))
	if stock <= 0:
		_on_pickup_blocked("仓库物品已耗尽。")
		return false
	var item: ItemDataResource = _warehouse_items.get(item_name, null)
	if item == null:
		return false
	if not _inventory.add_item(item):
		return false
	_warehouse_stock[item_name] = stock - 1
	_populate_backpack_grid(_storage_overlay.get_node_or_null("BackpackGrid") as GridContainer)
	_populate_warehouse_list(_storage_overlay.get_node_or_null("WarehouseList") as VBoxContainer)
	return true


func _get_storage_name_for_item(item: ItemDataResource) -> String:
	for item_name in _warehouse_items.keys():
		if _warehouse_items[item_name] == item:
			return String(item_name)
	return item.item_name


func _set_search_feedback(text: String) -> void:
	if _search_feedback_label != null:
		_search_feedback_label.text = text


func _make_panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.42, 0.48, 0.42, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


func _clear_ui_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()


func _process_container_search(delta: float) -> void:
	if _search_overlay == null or not _search_overlay.visible:
		return
	if _search_container == null or not is_instance_valid(_search_container):
		return
	var container := _search_container
	var has_count := container.has_method("get_search_entry_count")
	var has_search := container.has_method("search_entry")
	if not has_count or not has_search:
		return
	var count: int = container.get_search_entry_count()
	if _search_active_index < 0 or _entry_search_complete(_search_active_index):
		_search_active_index = _find_next_unsearched_entry(count)
	if _search_active_index >= 0:
		container.search_entry(_search_active_index, delta)
	# Only rebuild the list when structural state changes (entry revealed/transferred).
	# This prevents destroying buttons/drag-slots every frame, which was blocking
	# mouse clicks and drag-and-drop interactions.
	if _search_state_changed(count):
		_populate_container_list()
	else:
		_update_container_search_labels()


func _handle_overlay_shortcut(event: InputEventKey) -> bool:
	var shortcut_index := SHORTCUT_KEYS.find(event.physical_keycode)
	if shortcut_index < 0:
		shortcut_index = SHORTCUT_KEYS.find(event.keycode)
	if shortcut_index < 0:
		return false
	if _search_overlay != null and _search_overlay.visible:
		_transfer_container_entry(shortcut_index)
		return true
	if (_storage_overlay != null
			and _storage_overlay.visible
			and shortcut_index < _warehouse_order.size()):
		_transfer_warehouse_item(_warehouse_order[shortcut_index])
		return true
	return false


func _entry_search_complete(index: int) -> bool:
	if _search_container == null:
		return true
	var container := _search_container
	if container.has_method("is_entry_revealed") and container.is_entry_revealed(index):
		return true
	if container.has_method("is_entry_transferred") and container.is_entry_transferred(index):
		return true
	return false


func _find_next_unsearched_entry(count: int) -> int:
	var container := _search_container
	for i in count:
		if container.has_method("is_entry_revealed") and container.is_entry_revealed(i):
			continue
		if container.has_method("is_entry_transferred") and container.is_entry_transferred(i):
			continue
		return i
	return -1


func _search_state_changed(count: int) -> bool:
	if _search_container == null:
		return false
	if _search_entry_snapshot.size() != count:
		return true
	for i in count:
		var revealed := false
		var transferred := false
		if _search_container.has_method("is_entry_revealed"):
			revealed = _search_container.is_entry_revealed(i)
		if _search_container.has_method("is_entry_transferred"):
			transferred = _search_container.is_entry_transferred(i)
		var snap: Dictionary = _search_entry_snapshot[i]
		if snap.get("revealed", false) != revealed or snap.get("transferred", false) != transferred:
			return true
	return false


func _save_search_snapshot() -> void:
	_search_entry_snapshot.clear()
	if _search_container == null or not is_instance_valid(_search_container):
		return
	var count := 0
	if _search_container.has_method("get_search_entry_count"):
		count = _search_container.get_search_entry_count()
	for i in count:
		var revealed := false
		var transferred := false
		if _search_container.has_method("is_entry_revealed"):
			revealed = _search_container.is_entry_revealed(i)
		if _search_container.has_method("is_entry_transferred"):
			transferred = _search_container.is_entry_transferred(i)
		_search_entry_snapshot.append({"revealed": revealed, "transferred": transferred})


func _update_container_search_labels() -> void:
	if _search_overlay == null:
		return
	var list := _search_overlay.get_node_or_null("ContainerList") as VBoxContainer
	if list == null:
		return
	var children := list.get_children()
	for i in children.size():
		var row_panel: Control = children[i]
		var row := row_panel.get_child(0) if row_panel.get_child_count() > 0 else null
		if row == null:
			continue
		var label := row.get_child(0) if row.get_child_count() > 0 else null
		if label is Label:
			label.text = "%d  %s" % [i + 1, _get_container_entry_label(i)]


func _show_main_overlay(show: bool) -> void:
	if _main_overlay != null:
		_main_overlay.visible = show
	if show and _result_overlay != null:
		_result_overlay.visible = false
	if show:
		close_blocking_overlay()
	_set_run_hud_visible(not show)


func _set_run_hud_visible(show: bool) -> void:
	top_left.visible = show
	top_right.visible = show
	slots_container.visible = false
	if _prompt_label != null:
		_prompt_label.visible = false
	if _minimap != null:
		var is_expedition := GameManager.current_location == GameManager.Location.EXPEDITION
		_minimap.visible = show and is_expedition
	blocked_label.visible = show and blocked_label.visible


func _on_title_clicked() -> void:
	GameManager.enter_afterglow()
	_clear_main_summary()
	_show_main_overlay(false)


func _start_run_from_ui() -> void:
	var state := GameManager.current_state
	if state == GameManager.State.SUCCESS or state == GameManager.State.DEAD:
		GameManager.request_start_after_reload()
		get_tree().reload_current_scene()
		return
	GameManager.start_run()
	_clear_main_summary()
	_show_main_overlay(false)


func _return_to_home_from_result() -> void:
	_clear_main_summary()
	_show_main_overlay(true)
	GameManager.return_to_afterglow()
	_show_main_overlay(false)


func _on_main_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_title_clicked()


func _on_health_changed(current: float, maximum: float) -> void:
	var safe_maximum := maxf(maximum, 1.0)
	hp_bar.value = current / safe_maximum * 100.0
	hp_label.text = "生命  %d / %d" % [int(round(current)), int(round(maximum))]


func _on_erosion_changed(value: float) -> void:
	erosion_bar.value = value
	erosion_label.text = "侵蚀  %d%%" % int(round(value))


func _on_ammo_changed(current: int, max_value: int) -> void:
	ammo_label.text = "弹药  %d / %d" % [current, max_value]


func _on_collectible_changed(count: int, score: int) -> void:
	collectible_label.text = "收集品  %d" % count
	score_label.text = "分数  %d" % score


func _on_inventory_changed(slots: Array, current_weight: float, max_weight: float) -> void:
	weight_label.text = "负重  %d / %d" % [int(round(current_weight)), int(round(max_weight))]
	if _active_blocking_overlay != null:
		_populate_backpack_grid(_get_visible_backpack_grid())
	for i in _slot_panels.size():
		var panel: Panel = _slot_panels[i]
		var fill := panel.get_node_or_null("Fill") as ColorRect
		var name_label := panel.get_node_or_null("ItemName") as Label
		if fill == null or name_label == null:
			continue
		var item: ItemDataResource = slots[i] if i < slots.size() else null
		if item == null:
			fill.color = EMPTY_SLOT_COLOR
			name_label.text = ""
		else:
			fill.color = TYPE_COLORS.get(item.type, Color.WHITE)
			name_label.text = ""


func _on_pickup_blocked(reason: String) -> void:
	blocked_label.text = reason
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _on_state_changed(new_state: int) -> void:
	if _state_label != null:
		_state_label.text = "状态  %s" % _get_state_text(new_state)
	_update_signal_label()
	_update_end_flow(new_state)
	if new_state == GameManager.State.RUNNING or new_state == GameManager.State.EXTRACTING:
		_show_main_overlay(false)


func _on_signal_flare_fired(_origin: Vector3) -> void:
	_update_signal_label()
	blocked_label.text = "信号已发射。守住撤离区域。"
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _on_location_changed(location: int) -> void:
	if location == GameManager.Location.TITLE:
		set_risk_label_text("风险  标题")
		if _zone_container != null:
			_zone_container.visible = false
		if _minimap != null:
			_minimap.visible = false
	elif location == GameManager.Location.AFTERGLOW:
		set_risk_label_text("余晖号")
		if _zone_container != null:
			_zone_container.visible = false
		if _minimap != null:
			_minimap.visible = false
	elif location == GameManager.Location.EXPEDITION:
		set_risk_label_text("风险  低风险")
		if _zone_container != null:
			_zone_container.visible = true
		if _minimap != null:
			_minimap.visible = true


func _update_time_label() -> void:
	if _time_label == null:
		return
	var total_seconds: int = int(floor(GameManager.elapsed_time))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	_time_label.text = "时间  %02d:%02d" % [minutes, seconds]


func _update_signal_label() -> void:
	if _signal_label == null:
		return
	if not GameManager.signal_flare_used:
		_signal_label.text = "信号  就绪"
		return
	if _extraction != null and _extraction.has_method("get_status_text"):
		_signal_label.text = "信号  %s" % _extraction.get_status_text()
	else:
		_signal_label.text = "信号  已发射"


func _update_end_flow(state: int) -> void:
	if state != GameManager.State.SUCCESS and state != GameManager.State.DEAD:
		if _result_overlay != null:
			_result_overlay.visible = false
		return

	var success := state == GameManager.State.SUCCESS
	var score := _get_run_score() if success else 0
	_result_title_label.text = "撤离成功" if success else "行动失败"
	_result_stats_label.text = "分数  %d\n击杀  %d\n侵蚀  %d%%\n时间  %s" % [
		score,
		GameManager.kill_count,
		int(round(GameManager.player_erosion)),
		_format_elapsed_time(),
	]
	if _main_overlay != null:
		_main_overlay.visible = false
	_set_run_hud_visible(false)
	GameManager.set_ui_blocking_input(true)
	_result_overlay.visible = true


func _set_main_summary(title: String, stats: String) -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "上次行动: %s" % title
	if _main_summary_label != null:
		_main_summary_label.text = "%s\n\n按回车、空格或点击开始进行新一轮行动。" % stats
		_main_summary_label.visible = true


func _clear_main_summary() -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "点击任意位置开始"
	if _main_summary_label != null:
		_main_summary_label.text = ""
		_main_summary_label.visible = false


func _get_run_score() -> int:
	if _inventory != null and _inventory.has_method("calculate_score"):
		return _inventory.calculate_score()
	return 0


func _format_elapsed_time() -> String:
	var total_seconds: int = int(floor(GameManager.elapsed_time))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _get_state_text(state: int) -> String:
	match state:
		GameManager.State.PREPARING:
			return "准备中"
		GameManager.State.RUNNING:
			return "行动中"
		GameManager.State.EXTRACTING:
			return "撤离中"
		GameManager.State.SUCCESS:
			return "成功"
		GameManager.State.DEAD:
			return "阵亡"
		_:
			return "未知"


# ----- Plan 3: Enemy Alert UI (polish_plan §3) -----
# [AI-ASSISTED] 2026-05-22 — screen-edge red wedge indicators for chasing/attacking enemies

func _bind_spawn_manager_ref() -> void:
	if _spawn_manager != null and is_instance_valid(_spawn_manager):
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_spawn_manager = scene.get_node_or_null("SpawnManager")
	if _spawn_manager != null and _spawn_manager.has_signal("spawn_occurred"):
		if not _spawn_manager.spawn_occurred.is_connected(_on_spawn_occurred):
			_spawn_manager.spawn_occurred.connect(_on_spawn_occurred)


func _update_alert_indicators(_delta: float) -> void:
	_alert_indicators.clear()
	var state := GameManager.current_state
	if state != GameManager.State.RUNNING and state != GameManager.State.EXTRACTING:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size := get_viewport_rect().size
	var enemies := get_tree().get_nodes_in_group("enemies")
	# Collect raw directions for active enemies within range
	var raw_entries: Array[Dictionary] = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy.has_method("is_awake") or not enemy.is_awake():
			continue
		if not enemy.has_method("get_ai_state_name"):
			continue
		var ai_state: String = enemy.get_ai_state_name()
		if ai_state != "CHASE" and ai_state != "ATTACK":
			continue
		var dist: float = enemy.global_position.distance_to(GameManager.player_position)
		if dist > ALERT_DETECTION_RANGE:
			continue
		# World direction from player to enemy (XZ plane)
		var to_enemy: Vector3 = enemy.global_position - GameManager.player_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.01:
			continue
		var dir_3d := to_enemy.normalized()
		# Check if enemy is off-screen or very close to edge
		var screen_pos := camera.unproject_position(enemy.global_position)
		var on_x := screen_pos.x >= 0.0 and screen_pos.x <= viewport_size.x
		var on_y := screen_pos.y >= 0.0 and screen_pos.y <= viewport_size.y
		var on_screen := on_x and on_y
		if camera.is_position_behind(enemy.global_position):
			on_screen = false
		# Range factor: closer enemies = stronger indicator
		var range_factor := 1.0 - clampf(dist / ALERT_DETECTION_RANGE, 0.0, 1.0)
		var pulse_sin := absf(sin(Time.get_ticks_msec() * 0.001 * ALERT_PULSE_SPEED))
		var pulse_alpha := (0.4 + 0.6 * pulse_sin) * range_factor
		pulse_alpha = clampf(pulse_alpha, 0.0, ALERT_MAX_OPACITY)
		var edge_pos := _direction_to_screen_edge(dir_3d, viewport_size, ALERT_EDGE_INSET)
		raw_entries.append({
			"screen_pos": edge_pos,
			"opacity": pulse_alpha,
			"direction": dir_3d,
			"on_screen": on_screen,
		})
	# Merge nearby indicators by angle
	var merged: Array[Dictionary] = []
	for entry in raw_entries:
		var found_merge := false
		for m in merged:
			var angle_diff := rad_to_deg(entry["direction"].angle_to(m["direction"]))
			if angle_diff < ALERT_MERGE_ANGLE_DEG:
				m["opacity"] = clampf(m["opacity"] + entry["opacity"] * 0.3, 0.0, ALERT_MAX_OPACITY)
				found_merge = true
				break
		if not found_merge:
			merged.append(entry.duplicate())
	_alert_indicators = merged


func _draw() -> void:
	_draw_alert_indicators()
	_draw_spawn_pulses()


func _draw_alert_indicators() -> void:
	for indicator in _alert_indicators:
		var pos: Vector2 = indicator["screen_pos"]
		var alpha: float = indicator["opacity"]
		var dir_3d: Vector3 = indicator["direction"]
		var color := Color(1.0, 0.25, 0.15, alpha)
		_draw_edge_wedge(pos, dir_3d, ALERT_INDICATOR_SIZE, color)


# ----- Plan 4: Spawn Pulse (polish_plan §4) -----
# [AI-ASSISTED] 2026-05-22 — screen-edge orange pulse when enemies spawn

func _on_spawn_occurred(pos: Vector3, _kind: String) -> void:
	var to_spawn: Vector3 = pos - GameManager.player_position
	to_spawn.y = 0.0
	if to_spawn.length_squared() < 0.01:
		return
	var dir := to_spawn.normalized()
	var viewport_size := get_viewport_rect().size
	var edge_pos := _direction_to_screen_edge(dir, viewport_size, ALERT_EDGE_INSET)
	_spawn_pulses.append({
		"screen_pos": edge_pos,
		"remaining": SPAWN_PULSE_DURATION,
		"max_time": SPAWN_PULSE_DURATION,
		"direction": dir,
	})
	# Future: _play_directional_audio("spawn_pulse", dir)


func _update_spawn_pulses(delta: float) -> void:
	var i := _spawn_pulses.size() - 1
	while i >= 0:
		_spawn_pulses[i]["remaining"] -= delta
		if _spawn_pulses[i]["remaining"] <= 0.0:
			_spawn_pulses.remove_at(i)
		else:
			# Recalculate screen position each frame (player may have moved)
			var dir: Vector3 = _spawn_pulses[i]["direction"]
			var viewport_size := get_viewport_rect().size
			_spawn_pulses[i]["screen_pos"] = _direction_to_screen_edge(dir, viewport_size, ALERT_EDGE_INSET)
		i -= 1


func _draw_spawn_pulses() -> void:
	for pulse in _spawn_pulses:
		var remaining: float = pulse["remaining"]
		var max_time: float = pulse["max_time"]
		var elapsed: float = max_time - remaining
		var alpha := 0.0
		if elapsed < SPAWN_PULSE_ENTER_TIME:
			# Fade in
			alpha = clampf(elapsed / SPAWN_PULSE_ENTER_TIME, 0.0, 1.0)
		elif remaining > SPAWN_PULSE_FADE_TIME:
			# Hold
			alpha = 1.0
		else:
			# Fade out
			alpha = clampf(remaining / SPAWN_PULSE_FADE_TIME, 0.0, 1.0)
		alpha *= 0.85
		var pos: Vector2 = pulse["screen_pos"]
		var dir_3d: Vector3 = pulse["direction"]
		var color := Color(1.0, 0.7, 0.15, alpha)
		_draw_edge_wedge(pos, dir_3d, SPAWN_PULSE_SIZE, color)


# ----- Shared helpers for edge indicators -----

func _direction_to_screen_edge(dir_3d: Vector3, viewport_size: Vector2, inset: float) -> Vector2:
	# Map 3D XZ direction to 2D screen-edge position
	# dir_3d.x → screen horizontal, dir_3d.z → screen vertical (inverted: -z is up on screen)
	var dir_2d := Vector2(dir_3d.x, -dir_3d.z).normalized()
	if dir_2d.length_squared() < 0.001:
		return Vector2(viewport_size.x * 0.5, inset)
	var center := viewport_size * 0.5
	var half := center - Vector2(inset, inset)
	# Find intersection with screen edge rectangle
	var t_x := absf(half.x / dir_2d.x) if absf(dir_2d.x) > 0.001 else 1e6
	var t_y := absf(half.y / dir_2d.y) if absf(dir_2d.y) > 0.001 else 1e6
	var t := minf(t_x, t_y)
	return center + dir_2d * t


func _draw_edge_wedge(pos: Vector2, dir_3d: Vector3, wedge_size: float, color: Color) -> void:
	# Draw a wedge/triangle pointing from screen edge toward center
	var dir_2d := Vector2(dir_3d.x, -dir_3d.z).normalized()
	if dir_2d.length_squared() < 0.001:
		dir_2d = Vector2.UP
	# Inward direction (toward center)
	var inward := -dir_2d
	# Perpendicular for triangle width
	var perp := Vector2(-dir_2d.y, dir_2d.x)
	var half_width := wedge_size * 0.35
	var tip := pos + inward * wedge_size * 0.6
	var base_a := pos + perp * half_width
	var base_b := pos - perp * half_width
	var points := PackedVector2Array([tip, base_a, base_b])
	var colors := PackedColorArray([color, color, color])
	draw_polygon(points, colors)
