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
var _backpack_overlay: Control = null
var _storage_overlay: Control = null
var _search_overlay: Control = null
var _active_blocking_overlay: Control = null
var _search_container: Node = null
var _search_active_index: int = -1
var _search_feedback_label: Label = null
var _warehouse_stock := {
	"Standard Ammo": 12,
	"Small Battery": 6,
	"Purifier": 2,
	"Small Relic": 1,
}
var _warehouse_order := ["Standard Ammo", "Small Battery", "Purifier", "Small Relic"]
var _warehouse_items := {
	"Standard Ammo": ITEM_AMMO,
	"Small Battery": ITEM_BATTERY,
	"Purifier": ITEM_PURIFIER,
	"Small Relic": ITEM_RELIC,
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
	if _blocked_hide_timer > 0.0:
		_blocked_hide_timer -= delta
		if _blocked_hide_timer <= 0.0:
			blocked_label.visible = false
	_process_container_search(delta)
	_update_time_label()
	_update_signal_label()


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
	_state_label = _make_status_label("State  Preparing")
	_time_label = _make_status_label("Time  00:00")
	_signal_label = _make_status_label("Signal  Ready")
	_risk_label = _make_status_label("Risk  Title")
	top_right.add_child(_state_label)
	top_right.add_child(_time_label)
	top_right.add_child(_signal_label)
	top_right.add_child(_risk_label)


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
	title.text = "Afterglow Express"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78, 1.0))
	content.add_child(title)

	_main_prompt_label = Label.new()
	_main_prompt_label.text = "Click anywhere to start"
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
	button.text = "Start"
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
	prompt.text = "Press Enter or Space to return to Afterglow"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(0.76, 0.84, 0.80, 1.0))
	content.add_child(prompt)

	var button := Button.new()
	button.text = "Back to Afterglow"
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


func set_risk_label_text(text: String) -> void:
	if _risk_label != null:
		_risk_label.text = text


func get_risk_label_text() -> String:
	return _risk_label.text if _risk_label != null else ""


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
	content.add_child(_make_overlay_title("Backpack"))
	var grid := _make_backpack_grid()
	content.add_child(grid)
	var direct_grid := _make_backpack_grid()
	_position_overlay_child(direct_grid, Vector2(-180.0, -130.0), Vector2(180.0, 90.0))
	overlay.add_child(direct_grid)
	content.add_child(_make_hint_label("Esc or B closes. Quick-use keys still work after closing."))
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
	left.add_child(_make_overlay_title("Backpack"))
	left.add_child(_make_backpack_grid())
	var direct_grid := _make_backpack_grid()
	_position_overlay_child(direct_grid, Vector2(-390.0, -160.0), Vector2(-20.0, 120.0))
	overlay.add_child(direct_grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360.0, 0.0)
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_make_overlay_title("Warehouse"))
	var list := VBoxContainer.new()
	list.name = "WarehouseList"
	list.add_theme_constant_override("separation", 6)
	right.add_child(list)
	var direct_list := VBoxContainer.new()
	direct_list.name = "WarehouseList"
	direct_list.add_theme_constant_override("separation", 6)
	_position_overlay_child(direct_list, Vector2(40.0, -160.0), Vector2(390.0, 120.0))
	overlay.add_child(direct_list)
	right.add_child(_make_hint_label("Rows show storage stock. Transfer buttons share the same inventory API."))
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
	left.add_child(_make_overlay_title("Backpack"))
	left.add_child(_make_backpack_grid())
	var direct_grid := _make_backpack_grid()
	_position_overlay_child(direct_grid, Vector2(-430.0, -170.0), Vector2(-50.0, 130.0))
	overlay.add_child(direct_grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430.0, 0.0)
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_make_overlay_title("Container"))
	var list := VBoxContainer.new()
	list.name = "ContainerList"
	list.add_theme_constant_override("separation", 6)
	right.add_child(list)
	var direct_list := VBoxContainer.new()
	direct_list.name = "ContainerList"
	direct_list.add_theme_constant_override("separation", 6)
	_position_overlay_child(direct_list, Vector2(20.0, -170.0), Vector2(430.0, 130.0))
	overlay.add_child(direct_list)
	_search_feedback_label = _make_hint_label("")
	_search_feedback_label.name = "SearchFeedback"
	right.add_child(_search_feedback_label)
	right.add_child(_make_hint_label("Search starts automatically. Move revealed items into the backpack explicitly."))
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


func _position_overlay_child(control: Control, top_left_offset: Vector2, bottom_right_offset: Vector2) -> void:
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
		title.text = item.item_name if item != null else "Empty"
		if item != null:
			slot.set("drag_payload", {
				"source": "backpack",
				"slot_index": i,
				"label": item.item_name,
			})
		box.add_child(title)

		var detail := Label.new()
		detail.text = "Slot %d" % (i + 1)
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
		row_panel.add_child(row)
		var label := Label.new()
		label.text = "%s x %d" % [String(item_name), int(_warehouse_stock.get(item_name, 0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.88, 1.0))
		row.add_child(label)
		var button := Button.new()
		button.text = "Move"
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
		row_panel.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.88, 1.0))
		label.text = "%d  %s" % [i + 1, _get_container_entry_label(i)]
		row.add_child(label)
		var button := Button.new()
		button.text = "Move"
		button.disabled = not _can_transfer_container_entry(i)
		button.custom_minimum_size = Vector2(78.0, 30.0)
		button.pressed.connect(Callable(self, "_transfer_container_entry").bind(i))
		row.add_child(button)
		list.add_child(row_panel)


func _get_container_entry_label(index: int) -> String:
	if _search_container == null:
		return "Unknown"
	if _search_container.has_method("is_entry_transferred") and _search_container.is_entry_transferred(index):
		return "Transferred"
	if _search_container.has_method("is_entry_revealed") and _search_container.is_entry_revealed(index):
		if _search_container.has_method("get_revealed_item_name"):
			return _search_container.get_revealed_item_name(index)
		return "Revealed Item"
	if index == _search_active_index and _search_container.has_method("get_search_progress_ratio"):
		return "Searching... %d%%" % int(round(_search_container.get_search_progress_ratio(index) * 100.0))
	return "Unknown"


func _can_transfer_container_entry(index: int) -> bool:
	if _search_container == null:
		return false
	if _search_container.has_method("is_entry_transferred") and _search_container.is_entry_transferred(index):
		return false
	return _search_container.has_method("is_entry_revealed") and _search_container.is_entry_revealed(index)


func _transfer_container_entry(index: int) -> bool:
	if _inventory == null or _search_container == null:
		return false
	var moved := false
	if _inventory.has_method("transfer_revealed_item_from_container"):
		moved = _inventory.transfer_revealed_item_from_container(_search_container, index)
	if moved:
		_set_search_feedback("Moved to backpack.")
	else:
		_set_search_feedback("Cannot move item.")
	_populate_backpack_grid(_search_overlay.get_node_or_null("BackpackGrid") as GridContainer)
	_populate_container_list()
	return moved


func transfer_storage_item_to_backpack(item_name: String) -> bool:
	return _transfer_warehouse_item(item_name)


func transfer_backpack_slot_to_storage(slot_index: int) -> bool:
	if _inventory == null or not _inventory.has_method("remove_slot_item"):
		return false
	var item: ItemDataResource = _inventory.get_slot_item(slot_index) if _inventory.has_method("get_slot_item") else null
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
		_on_pickup_blocked("Warehouse item depleted.")
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
	if not _search_container.has_method("get_search_entry_count") or not _search_container.has_method("search_entry"):
		return
	var count: int = _search_container.get_search_entry_count()
	if _search_active_index < 0 or _entry_search_complete(_search_active_index):
		_search_active_index = _find_next_unsearched_entry(count)
	if _search_active_index >= 0:
		_search_container.search_entry(_search_active_index, delta)
	_populate_container_list()


func _handle_overlay_shortcut(event: InputEventKey) -> bool:
	var shortcut_index := SHORTCUT_KEYS.find(event.physical_keycode)
	if shortcut_index < 0:
		shortcut_index = SHORTCUT_KEYS.find(event.keycode)
	if shortcut_index < 0:
		return false
	if _search_overlay != null and _search_overlay.visible:
		_transfer_container_entry(shortcut_index)
		return true
	if _storage_overlay != null and _storage_overlay.visible and shortcut_index < _warehouse_order.size():
		_transfer_warehouse_item(_warehouse_order[shortcut_index])
		return true
	return false


func _entry_search_complete(index: int) -> bool:
	if _search_container == null:
		return true
	if _search_container.has_method("is_entry_revealed") and _search_container.is_entry_revealed(index):
		return true
	if _search_container.has_method("is_entry_transferred") and _search_container.is_entry_transferred(index):
		return true
	return false


func _find_next_unsearched_entry(count: int) -> int:
	for i in count:
		if _search_container.has_method("is_entry_revealed") and _search_container.is_entry_revealed(i):
			continue
		if _search_container.has_method("is_entry_transferred") and _search_container.is_entry_transferred(i):
			continue
		return i
	return -1


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
	blocked_label.visible = show and blocked_label.visible


func _on_title_clicked() -> void:
	GameManager.enter_afterglow()
	_clear_main_summary()
	_show_main_overlay(false)


func _start_run_from_ui() -> void:
	if GameManager.current_state == GameManager.State.SUCCESS or GameManager.current_state == GameManager.State.DEAD:
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
	hp_label.text = "HP  %d / %d" % [int(round(current)), int(round(maximum))]


func _on_erosion_changed(value: float) -> void:
	erosion_bar.value = value
	erosion_label.text = "Erosion  %d%%" % int(round(value))


func _on_ammo_changed(current: int, max_value: int) -> void:
	ammo_label.text = "Ammo  %d / %d" % [current, max_value]


func _on_collectible_changed(count: int, score: int) -> void:
	collectible_label.text = "Collectibles  %d" % count
	score_label.text = "Score  %d" % score


func _on_inventory_changed(slots: Array, current_weight: float, max_weight: float) -> void:
	weight_label.text = "Weight  %d / %d" % [int(round(current_weight)), int(round(max_weight))]
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
		_state_label.text = "State  %s" % _get_state_text(new_state)
	_update_signal_label()
	_update_end_flow(new_state)
	if new_state == GameManager.State.RUNNING or new_state == GameManager.State.EXTRACTING:
		_show_main_overlay(false)


func _on_signal_flare_fired(_origin: Vector3) -> void:
	_update_signal_label()
	blocked_label.text = "Signal fired. Hold the extraction zone."
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _on_location_changed(location: int) -> void:
	if location == GameManager.Location.TITLE:
		set_risk_label_text("Risk  Title")
	elif location == GameManager.Location.AFTERGLOW:
		set_risk_label_text("Afterglow Express")
	elif location == GameManager.Location.EXPEDITION:
		set_risk_label_text("Risk  Low Risk")


func _update_time_label() -> void:
	if _time_label == null:
		return
	var total_seconds: int = int(floor(GameManager.elapsed_time))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	_time_label.text = "Time  %02d:%02d" % [minutes, seconds]


func _update_signal_label() -> void:
	if _signal_label == null:
		return
	if not GameManager.signal_flare_used:
		_signal_label.text = "Signal  Ready"
		return
	if _extraction != null and _extraction.has_method("get_status_text"):
		_signal_label.text = "Signal  %s" % _extraction.get_status_text()
	else:
		_signal_label.text = "Signal  Fired"


func _update_end_flow(state: int) -> void:
	if state != GameManager.State.SUCCESS and state != GameManager.State.DEAD:
		if _result_overlay != null:
			_result_overlay.visible = false
		return

	var success := state == GameManager.State.SUCCESS
	var score := _get_run_score() if success else 0
	_result_title_label.text = "Extraction Complete" if success else "Run Failed"
	_result_stats_label.text = "Score  %d\nKills  %d\nErosion  %d%%\nTime  %s" % [
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
		_main_prompt_label.text = "Last run: %s" % title
	if _main_summary_label != null:
		_main_summary_label.text = "%s\n\nPress Enter, Space, or Start Run for a new run." % stats
		_main_summary_label.visible = true


func _clear_main_summary() -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "Click anywhere to start"
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
			return "Preparing"
		GameManager.State.RUNNING:
			return "Running"
		GameManager.State.EXTRACTING:
			return "Extracting"
		GameManager.State.SUCCESS:
			return "Success"
		GameManager.State.DEAD:
			return "Dead"
		_:
			return "Unknown"
