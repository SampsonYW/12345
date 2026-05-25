# warehouse_overlay.gd
# HUD 的仓库弹层视图，包含左侧背包和右侧仓库列表
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd
extends ColorRect

const STORAGE_DRAG_SLOT_SCRIPT := preload("res://scripts/ui/storage_drag_slot.gd")
const OverlayBuilder := preload("res://scripts/ui/overlay_builder.gd")

var _hud: Control = null
var _grid: GridContainer = null
var _stats_label: HBoxContainer = null
var _warehouse_list: VBoxContainer = null

func setup(hud: Control) -> void:
	_hud = hud
	name = "StorageOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.02, 0.025, 0.025, 0.58)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -550.0
	panel.offset_top = -350.0
	panel.offset_right = 550.0
	panel.offset_bottom = 350.0
	panel.add_theme_stylebox_override("panel", _hud._make_panel_style(Color(0.055, 0.065, 0.06, 0.88)))
	add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 160)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.set_script(STORAGE_DRAG_SLOT_SCRIPT)
	left.set("owner_hud", _hud)
	left.set("accept_target", "backpack_slot")
	left.custom_minimum_size = Vector2(390.0, 0.0)
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	left.add_child(_hud._make_overlay_title("背包"))
	
	_stats_label = _hud._make_backpack_stats()
	left.add_child(_stats_label)
	
	_grid = _hud._make_backpack_grid()
	left.add_child(_grid)

	var right := VBoxContainer.new()
	right.set_script(STORAGE_DRAG_SLOT_SCRIPT)
	right.set("owner_hud", _hud)
	right.set("accept_target", "warehouse_list")
	right.custom_minimum_size = Vector2(360.0, 0.0)
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_hud._make_overlay_title("仓库"))
	
	_warehouse_list = VBoxContainer.new()
	_warehouse_list.name = "WarehouseList"
	_warehouse_list.add_theme_constant_override("separation", 6)
	right.add_child(_warehouse_list)
	
	right.add_child(_hud._make_hint_label("右键物品可快速转移。拖拽或点击转移按钮也可操作。"))

func refresh_backpack() -> void:
	OverlayBuilder.populate_backpack_grid(_grid, _hud)
	OverlayBuilder.update_backpack_stats(_stats_label, _hud)

func refresh_warehouse() -> void:
	_hud._populate_warehouse_list(_warehouse_list)

func update_stats() -> void:
	OverlayBuilder.update_backpack_stats(_stats_label, _hud)

func get_grid() -> GridContainer:
	return _grid
