# hud.gd
# HUD UI 逻辑脚本：管理玩家状态条（HP、侵蚀、弹药）、背包拖拽、容器搜索和母车仓库，以及屏幕边缘敌人警示 wedges。
# [AI-ASSISTED] 2026-05-22 — Applied Cyber-Tactical aesthetic overhaul
extends Control

const EMPTY_SLOT_COLOR := Color(0.1, 0.1, 0.12, 0.6)
const SLOT_BORDER_COLOR := Color(0.3, 0.4, 0.5, 0.3)
const ACCENT_COLOR := Color(0.4, 0.7, 0.9, 1.0)
const SPRINT_COLOR_READY := Color(0.4, 0.7, 0.9, 1.0)
const SPRINT_COLOR_ACTIVE := Color(0.9, 0.9, 0.95, 1.0)
const SPRINT_COLOR_COOLDOWN := Color(0.4, 0.5, 0.6, 1.0)
const ItemDataResource := preload("res://scripts/items/item_data.gd")
const STORAGE_DRAG_SLOT_SCRIPT := preload("res://scripts/ui/storage_drag_slot.gd")

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
var _player: Node = null
var _blocked_hide_timer: float = 0.0
var _slot_panels: Array[Panel] = []

@warning_ignore("unused_private_class_variable")
@onready var _signal_label: Label = %SignalLabel
@warning_ignore("unused_private_class_variable")
@onready var _zone_name_label: Label = %ZoneNameLabel
@warning_ignore("unused_private_class_variable")
@onready var _zone_risk_label: Label = %ZoneRiskLabel
@onready var _zone_container: VBoxContainer = %ZoneInfo
@onready var _minimap: Control = %Minimap
@onready var _sprint_container: Control = %SprintUI
@onready var _sprint_bar: ProgressBar = %SprintBar
@warning_ignore("unused_private_class_variable")
@onready var _sprint_label: Label = %SprintLabel
@warning_ignore("unused_private_class_variable")
@onready var _sprint_status_label: Label = %SprintStatus
@onready var _prompt_label: Label = %PromptLabel
@onready var _hold_progress_container: Control = %HoldProgress
@onready var _hold_progress_fill: ColorRect = %HoldProgress/Fill
@onready var _hold_progress_label: Label = %HoldProgress/Label
@onready var _main_overlay: Control = %MainOverlay
@onready var _main_prompt_label: Label = %MainPromptLabel
@onready var _main_summary_label: Label = %MainSummaryLabel
@onready var _result_overlay: Control = %ResultOverlay
@onready var _result_title_label: Label = %ResultTitleLabel
@onready var _result_stats_label: Label = %ResultStatsLabel
var _menu_controller: RefCounted = null
var _backpack_overlay: Control = null
var _storage_overlay: Control = null
var _search_overlay: Control = null
var _active_blocking_overlay: Control = null
var _search_container: Node = null
var _search_active_index: int = -1
var _search_feedback_label: Label = null
var _search_entry_snapshot: Array = []
var _spawn_manager: Node = null
var _alert_indicators: Array[Dictionary] = []  # [{screen_pos, opacity, direction}]
var _spawn_pulses: Array[Dictionary] = []  # [{screen_pos, remaining, max_time, direction}]
var _context_menu_controller: Node = null
var _drag_drop_controller: Node = null
var _input_interceptor: Node = null
var _player_status_ui: Node = null
var _world_tracking_ui: Control = null
var _damage_vignette: ColorRect = null
var _vignette_timer: float = 0.0

@onready var top_left: VBoxContainer = %TopLeft
@onready var top_right: VBoxContainer = %TopRight
@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_label: Label = %HPLabel
@onready var erosion_bar: ProgressBar = %ErosionBar
@onready var erosion_label: Label = %ErosionLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var blocked_label: Label = %BlockedLabel
@onready var slots_container: HBoxContainer = %BottomBar


func _ready() -> void:
	blocked_label.visible = false
	slots_container.visible = false
	# 受击红屏暗角
	_damage_vignette = ColorRect.new()
	_damage_vignette.name = "DamageVignette"
	_damage_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_vignette.color = Color(0.8, 0.05, 0.05, 0.0)
	add_child(_damage_vignette)
	_bind_player_refs()
	_bind_extraction_ref()

	GameManager.erosion_changed.connect(_on_erosion_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.signal_flare_fired.connect(_on_signal_flare_fired)
	GameManager.location_changed.connect(_on_location_changed)
	
	_context_menu_controller = preload("res://scripts/ui/context_menu_controller.gd").new()
	_context_menu_controller.setup(self)
	_context_menu_controller.item_use_requested.connect(_on_context_menu_use_requested)
	_context_menu_controller.item_discard_requested.connect(_on_context_menu_discard_requested)
	_context_menu_controller.transfer_to_warehouse_requested.connect(_on_context_menu_to_warehouse)
	_context_menu_controller.transfer_to_backpack_from_warehouse_requested.connect(_on_context_menu_to_backpack_from_warehouse)
	_context_menu_controller.transfer_to_backpack_from_container_requested.connect(_on_context_menu_to_backpack_from_container)
	_context_menu_controller.transfer_to_container_requested.connect(_on_context_menu_to_container)
	add_child(_context_menu_controller)
	
	_drag_drop_controller = preload("res://scripts/ui/drag_drop_controller.gd").new()
	_drag_drop_controller.transfer_warehouse_to_backpack_requested.connect(_on_drag_warehouse_to_backpack)
	_drag_drop_controller.transfer_container_to_backpack_requested.connect(_on_drag_container_to_backpack)
	_drag_drop_controller.transfer_backpack_to_warehouse_requested.connect(_on_drag_backpack_to_warehouse)
	_drag_drop_controller.transfer_backpack_to_container_requested.connect(_on_drag_backpack_to_container)
	add_child(_drag_drop_controller)
	
	_input_interceptor = preload("res://scripts/ui/hud_input_interceptor.gd").new()
	_input_interceptor.setup(self)
	add_child(_input_interceptor)
	
	_player_status_ui = preload("res://scripts/ui/player_status_ui.gd").new()
	_player_status_ui.setup(self)
	add_child(_player_status_ui)
	_player_status_ui.apply_theme()

	_world_tracking_ui = preload("res://scripts/ui/world_tracking_ui.gd").new()
	_world_tracking_ui.name = "WorldTrackingUI"
	add_child(_world_tracking_ui)

	_menu_controller = preload("res://scripts/ui/menu_overlay_controller.gd").new(
		self, _main_overlay, _main_prompt_label, _main_summary_label,
		_result_overlay, _result_title_label, _result_stats_label
	)
	
	_on_erosion_changed(GameManager.player_erosion)
	_on_state_changed(GameManager.current_state)

	if _player_status_ui != null:
		_player_status_ui.update_signal_label(_extraction)
	_style_sprint_bar()
	call_deferred("_restore_launch_screen")

	# Collect slot panels from BottomBar children
	_slot_panels = []
	for child in slots_container.get_children():
		if child is Panel:
			_slot_panels.append(child)


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
	# 受击红屏淡出
	if _vignette_timer > 0.0 and _damage_vignette != null:
		_vignette_timer -= delta
		var a := clampf(_vignette_timer / 0.5, 0.0, 1.0)
		_damage_vignette.color = Color(0.8, 0.05, 0.05, a * 0.35)
	_process_container_search(delta)

	if _player_status_ui != null:
		_player_status_ui.update_sprint_ui()
		_player_status_ui.update_signal_label(_extraction)
	_update_alert_indicators(delta)
	_update_spawn_pulses(delta)
	queue_redraw()


func _restore_launch_screen() -> void:
	GameManager.reset_run()
	GameManager.set_location(GameManager.Location.TITLE)
	if _menu_controller != null:
		_menu_controller.show_main_overlay(true)
	if GameManager.consume_start_after_reload():
		if _menu_controller != null:
			_menu_controller.start_run_from_ui()


func _style_sprint_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.12, 0.6)
	bg.set_corner_radius_all(6)
	_sprint_bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = SPRINT_COLOR_READY
	fg.set_corner_radius_all(6)
	fg.shadow_color = SPRINT_COLOR_READY * Color(1.0, 1.0, 1.0, 0.2)
	fg.shadow_size = 6
	_sprint_bar.add_theme_stylebox_override("fill", fg)





func _bind_player_refs() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_player = player
	if _player_health == null:
		_player_health = player.get_node_or_null("PlayerHealth")
		if _player_health != null:
			_player_health.health_changed.connect(_on_health_changed)
			_player_health.damaged.connect(_on_player_damaged)
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





func set_zone_info(zone_name: String, risk: String) -> void:
	if _player_status_ui != null:
		_player_status_ui.set_zone_info(zone_name, risk)


func open_backpack() -> void:
	close_blocking_overlay()
	if _backpack_overlay == null or not is_instance_valid(_backpack_overlay):
		_backpack_overlay = preload("res://scripts/ui/inventory_overlay.gd").new()
		_backpack_overlay.setup(self)
		add_child(_backpack_overlay)
	_backpack_overlay.refresh_backpack()
	_show_blocking_overlay(_backpack_overlay)


func open_storage() -> void:
	close_blocking_overlay()
	if _storage_overlay == null or not is_instance_valid(_storage_overlay):
		_storage_overlay = preload("res://scripts/ui/warehouse_overlay.gd").new()
		_storage_overlay.setup(self)
		add_child(_storage_overlay)
	_storage_overlay.refresh_backpack()
	_storage_overlay.refresh_warehouse()
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
		_search_overlay = preload("res://scripts/ui/container_search_overlay.gd").new()
		_search_overlay.setup(self)
		add_child(_search_overlay)
	_search_overlay.refresh_backpack()
	_search_overlay.refresh_container()
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
		return _backpack_overlay.get_grid()
	if _storage_overlay != null and _storage_overlay.visible:
		return _storage_overlay.get_grid()
	if _search_overlay != null and _search_overlay.visible:
		return _search_overlay.get_grid()
	return null


func _make_overlay_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _make_hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.76, 1.0))
	return label


func _make_backpack_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "BackpackGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _make_backpack_stats() -> HBoxContainer:
	var stats := HBoxContainer.new()
	stats.name = "BackpackStats"
	stats.add_theme_constant_override("separation", 24)
	var weight_lbl := Label.new()
	weight_lbl.name = "Weight"
	weight_lbl.add_theme_font_size_override("font_size", 18)
	weight_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 1.0))
	stats.add_child(weight_lbl)
	var score_lbl := Label.new()
	score_lbl.name = "Score"
	score_lbl.add_theme_font_size_override("font_size", 18)
	score_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4, 1.0))
	stats.add_child(score_lbl)
	var coll_lbl := Label.new()
	coll_lbl.name = "Collectibles"
	coll_lbl.add_theme_font_size_override("font_size", 18)
	coll_lbl.add_theme_color_override("font_color", Color(0.8, 0.95, 0.6, 1.0))
	stats.add_child(coll_lbl)
	return stats


func _on_backpack_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var loc := GameManager.current_location
	if loc != GameManager.Location.EXPEDITION and loc != GameManager.Location.AFTERGLOW:
		return
	var item: ItemDataResource = null
	if _inventory != null and _inventory.has_method("get_slot_item"):
		item = _inventory.get_slot_item(slot_index)
	if item == null:
		return
	var is_search_active := _search_overlay != null and _search_overlay.visible and _search_container != null
	_context_menu_controller.show_for_backpack(event.global_position, item, slot_index, loc, is_search_active)


func _on_warehouse_row_gui_input(event: InputEvent, item_name: String) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if WarehouseManager.get_stock(item_name) <= 0:
		return
	_context_menu_controller.show_for_warehouse(event.global_position, item_name, WarehouseManager.get_stock(item_name))


func _on_container_row_gui_input(event: InputEvent, entry_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not _can_transfer_container_entry(entry_index):
		return
	var label_text := _get_container_entry_label(entry_index)
	_context_menu_controller.show_for_container(event.global_position, entry_index, label_text)


func _on_context_menu_use_requested(slot_index: int) -> void:
	if _inventory != null and _inventory.has_method("use_slot"):
		_inventory.use_slot(slot_index)
	_refresh_after_context_menu()

func _on_context_menu_discard_requested(slot_index: int) -> void:
	if _inventory != null and _inventory.has_method("remove_slot_item"):
		var removed: ItemDataResource = _inventory.remove_slot_item(slot_index)
		if removed != null:
			_on_pickup_blocked("已丢弃: %s" % removed.item_name)
	_refresh_after_context_menu()

func _on_context_menu_to_warehouse(slot_index: int) -> void:
	transfer_backpack_slot_to_storage(slot_index)
	_refresh_after_context_menu()

func _on_context_menu_to_backpack_from_warehouse(item_name: String) -> void:
	_transfer_warehouse_item(item_name)
	_refresh_after_context_menu()

func _on_context_menu_to_backpack_from_container(entry_index: int) -> void:
	_transfer_container_entry(entry_index)
	_refresh_after_context_menu()

func _on_context_menu_to_container(slot_index: int) -> void:
	transfer_backpack_slot_to_container(slot_index)
	_refresh_after_context_menu()

func _on_drag_warehouse_to_backpack(item_name: String) -> void:
	transfer_storage_item_to_backpack(item_name)

func _on_drag_container_to_backpack(entry_index: int) -> void:
	_transfer_container_entry(entry_index)
	_refresh_after_context_menu()

func _on_drag_backpack_to_warehouse(slot_index: int) -> void:
	transfer_backpack_slot_to_storage(slot_index)
	_refresh_after_context_menu()

func _on_drag_backpack_to_container(slot_index: int) -> void:
	transfer_backpack_slot_to_container(slot_index)
	_refresh_after_context_menu()

func _refresh_after_context_menu() -> void:
	if _backpack_overlay != null and _backpack_overlay.visible:
		_backpack_overlay.refresh_backpack()
	if _storage_overlay != null and _storage_overlay.visible:
		_storage_overlay.refresh_backpack()
		_storage_overlay.refresh_warehouse()
	if _search_overlay != null and _search_overlay.visible:
		_search_overlay.refresh_backpack()
		_search_overlay.refresh_container()


func _populate_warehouse_list(list: VBoxContainer) -> void:
	if list == null:
		return
	_clear_ui_children(list)
	for item_name in WarehouseManager.order:
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
		label.text = "%s x %d" % [String(item_name), WarehouseManager.get_stock(String(item_name))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.88, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		var button := Button.new()
		button.text = "转移"
		button.disabled = WarehouseManager.get_stock(String(item_name)) <= 0
		button.custom_minimum_size = Vector2(72.0, 30.0)
		button.pressed.connect(Callable(self, "_transfer_warehouse_item").bind(String(item_name)))
		row.add_child(button)
		# Right-click context menu support
		row_panel.gui_input.connect(_on_warehouse_row_gui_input.bind(String(item_name)))
		list.add_child(row_panel)


func _populate_container_list() -> void:
	if _search_overlay == null:
		return
	var grid := _search_overlay.find_child("ContainerList", true, false) as GridContainer
	if grid == null:
		return
	_clear_ui_children(grid)
	if _search_container == null or not is_instance_valid(_search_container):
		return
	var capacity: int = 12
	if _search_container.has_method("get_capacity"):
		capacity = int(_search_container.get_capacity())
	for i in capacity:
		var text := _container_slot_text(i)
		var is_empty := text == ""
		var slot := PanelContainer.new()
		slot.name = "ContainerSlot%d" % i
		slot.custom_minimum_size = Vector2(120.0, 106.0)
		var bg: Color = Color(0.05, 0.055, 0.05, 0.55) if is_empty else Color(0.08, 0.09, 0.085, 0.82)
		slot.add_theme_stylebox_override("panel", _make_panel_style(bg))
		# 所有槽都接受 backpack drop；add_item_to_container 会优先复用 transferred 槽位
		slot.set_script(STORAGE_DRAG_SLOT_SCRIPT)
		slot.set("owner_hud", self)
		slot.set("accept_target", "container_list")
		# 仅可转移条目能被拖出 + 右键
		if not is_empty and _can_transfer_container_entry(i):
			slot.set("drag_payload", {
				"source": "container",
				"entry_index": i,
				"label": text,
			})
			slot.gui_input.connect(_on_container_row_gui_input.bind(i))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		slot.add_child(box)
		# 已发现物品显示图标（来自 ItemData.icon）
		var icon_tex: Texture2D = null
		if not is_empty and _search_container.has_method("get_revealed_item_icon"):
			icon_tex = _search_container.get_revealed_item_icon(i)
		if icon_tex != null:
			var icon := TextureRect.new()
			icon.texture = icon_tex
			icon.custom_minimum_size = Vector2(48.0, 48.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(icon)
		var title := Label.new()
		title.name = "ItemName"
		title.clip_text = true
		title.add_theme_font_size_override("font_size", 18)
		var color: Color = Color(0.45, 0.48, 0.45, 0.7) if is_empty else Color(0.92, 0.96, 0.90, 1.0)
		title.add_theme_color_override("font_color", color)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text = text
		box.add_child(title)
		grid.add_child(slot)
	_save_search_snapshot()


## 容器槽位显示文本（统一在 _populate_container_list 和 _update_container_search_labels 用）
## 空槽位和已转移槽位都返回 ""（视觉上一致，可被复用接收新物品）
func _container_slot_text(index: int) -> String:
	if _search_container == null or not _search_container.has_method("get_search_entry_count"):
		return ""
	if index >= _search_container.get_search_entry_count():
		return ""
	if _search_container.has_method("is_entry_transferred") and _search_container.is_entry_transferred(index):
		return ""
	return _get_container_entry_label(index)


func _get_container_entry_label(index: int) -> String:
	if _search_container == null:
		return "未知"
	var container := _search_container
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
	if _search_overlay != null and _search_overlay.visible:
		_search_overlay.refresh_backpack()
		_search_overlay.refresh_container()
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
	WarehouseManager.add_item(removed)
	if _storage_overlay != null and _storage_overlay.visible:
		_storage_overlay.refresh_backpack()
		_storage_overlay.refresh_warehouse()
	return true


## 把背包某槽位的物品存入当前打开的容器（双向 loot 转移的反向）。
## 返回 true 表示成功。
func transfer_backpack_slot_to_container(slot_index: int) -> bool:
	if _search_container == null or not is_instance_valid(_search_container):
		return false
	if _inventory == null or not _inventory.has_method("get_slot_item"):
		return false
	var item: ItemDataResource = _inventory.get_slot_item(slot_index)
	if item == null:
		return false
	if not _search_container.has_method("add_item_to_container"):
		return false
	var removed: ItemDataResource = _inventory.remove_slot_item(slot_index)
	if removed == null:
		return false
	if not _search_container.add_item_to_container(removed):
		# 回滚到背包
		_inventory.add_item(removed)
		_set_search_feedback("无法存入容器。")
		return false
	_set_search_feedback("已存入容器。")
	if _search_overlay != null and _search_overlay.visible:
		_search_overlay.refresh_backpack()
		_search_overlay.refresh_container()
	return true


func can_accept_storage_drop(data: Variant, target: String) -> bool:
	if _drag_drop_controller == null:
		return false
	return _drag_drop_controller.can_accept_drop(data, target)


func accept_storage_drop(data: Variant, target: String) -> bool:
	if _drag_drop_controller == null:
		return false
	return _drag_drop_controller.accept_drop(data, target)


func _transfer_warehouse_item(item_name: String) -> bool:
	if _inventory == null:
		return false
	var item: ItemDataResource = WarehouseManager.remove_item(item_name)
	if item == null:
		_on_pickup_blocked("仓库物品已耗尽。")
		return false
	if not _inventory.add_item(item):
		WarehouseManager.add_item(item)
		return false
	if _storage_overlay != null and _storage_overlay.visible:
		_storage_overlay.refresh_backpack()
		_storage_overlay.refresh_warehouse()
	return true


func _set_search_feedback(text: String) -> void:
	if _search_feedback_label != null:
		_search_feedback_label.text = text


func _make_panel_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(0.3, 0.4, 0.5, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	return style


func _clear_ui_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


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
	var grid := _search_overlay.find_child("ContainerList", true, false) as GridContainer
	if grid == null:
		return
	var children := grid.get_children()
	for i in children.size():
		var slot := children[i] as PanelContainer
		if slot == null:
			continue
		var label := slot.find_child("ItemName", true, false) as Label
		if label != null:
			label.text = _container_slot_text(i)


# HUD toggle helper - kept for menu_controller to use
func _set_run_hud_visible(is_show: bool) -> void:
	if top_left.get_parent() is PanelContainer:
		top_left.get_parent().visible = is_show
	else:
		top_left.visible = is_show

	if top_right.get_parent() is PanelContainer:
		top_right.get_parent().visible = is_show
	else:
		top_right.visible = is_show
	slots_container.visible = false
	if _prompt_label != null:
		_prompt_label.visible = false
	var show_expedition_ui := is_show and GameManager.current_location == GameManager.Location.EXPEDITION
	if _minimap != null:
		_minimap.visible = show_expedition_ui
	if _sprint_container != null:
		_sprint_container.visible = show_expedition_ui
	blocked_label.visible = is_show and blocked_label.visible


func _on_health_changed(current: float, maximum: float) -> void:
	if _player_status_ui != null:
		_player_status_ui.on_health_changed(current, maximum)


func _on_player_damaged(_amount: float) -> void:
	if _damage_vignette != null:
		_vignette_timer = 0.5
		_damage_vignette.color = Color(0.8, 0.05, 0.05, 0.35)


func _on_erosion_changed(value: float) -> void:
	if _player_status_ui != null:
		_player_status_ui.on_erosion_changed(value)


func _on_ammo_changed(current: int, max_value: int) -> void:
	if _player_status_ui != null:
		_player_status_ui.on_ammo_changed(current, max_value)


func _on_collectible_changed(_count: int, _score: int) -> void:
	if _backpack_overlay != null and _backpack_overlay.visible: _backpack_overlay.update_stats()
	if _storage_overlay != null and _storage_overlay.visible: _storage_overlay.update_stats()
	if _search_overlay != null and _search_overlay.visible: _search_overlay.update_stats()

func _on_inventory_changed(slots: Array, _current_weight: float, _max_weight: float) -> void:

	if _active_blocking_overlay != null:
		if _backpack_overlay != null and _backpack_overlay.visible: _backpack_overlay.refresh_backpack()
		if _storage_overlay != null and _storage_overlay.visible: _storage_overlay.refresh_backpack()
		if _search_overlay != null and _search_overlay.visible: _search_overlay.refresh_backpack()
	for i in _slot_panels.size():
		var panel: Panel = _slot_panels[i]
		var fill := panel.get_node_or_null("Fill") as ColorRect
		var name_label := panel.get_node_or_null("ItemName") as Label
		if fill == null or name_label == null:
			continue
		var icon_rect := panel.get_node_or_null("Icon") as TextureRect
		if icon_rect == null:
			icon_rect = TextureRect.new()
			icon_rect.name = "Icon"
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.offset_left = 8.0
			icon_rect.offset_top = 8.0
			icon_rect.offset_right = -8.0
			icon_rect.offset_bottom = -8.0
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(icon_rect)
			panel.move_child(icon_rect, 1)
		var item: ItemDataResource = slots[i] if i < slots.size() else null
		if item == null:
			fill.color = EMPTY_SLOT_COLOR
			icon_rect.texture = null
			name_label.text = ""
		else:
			if item.icon != null:
				fill.color = Color(0.06, 0.07, 0.09, 0.85)
				icon_rect.texture = item.icon
			else:
				fill.color = TYPE_COLORS.get(item.type, Color.WHITE)
				icon_rect.texture = null
			name_label.text = ""


func _on_pickup_blocked(reason: String) -> void:
	blocked_label.text = reason
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _on_state_changed(new_state: int) -> void:

	if _player_status_ui != null:
		_player_status_ui.update_signal_label(_extraction)
	if _menu_controller != null:
		_menu_controller.on_state_changed(new_state)


func _on_signal_flare_fired(_origin: Vector3) -> void:
	if _player_status_ui != null:
		_player_status_ui.update_signal_label(_extraction)
	blocked_label.text = "信号已发射。守住撤离区域。"
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _on_location_changed(location: int) -> void:
	if location == GameManager.Location.TITLE:

		if _zone_container != null:
			_zone_container.visible = false
		if _minimap != null:
			_minimap.visible = false
		if _sprint_container != null:
			_sprint_container.visible = false
	elif location == GameManager.Location.AFTERGLOW:

		if _zone_container != null:
			_zone_container.visible = false
		if _minimap != null:
			_minimap.visible = false
		if _sprint_container != null:
			_sprint_container.visible = false
	elif location == GameManager.Location.EXPEDITION:

		if _zone_container != null:
			_zone_container.visible = true
		if _minimap != null:
			_minimap.visible = true
		if _sprint_container != null:
			_sprint_container.visible = true

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
