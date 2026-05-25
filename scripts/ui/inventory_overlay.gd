# inventory_overlay.gd
# HUD 的背包弹层视图，显示 8 个槽位的物品
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd
extends ColorRect

const OverlayBuilder := preload("res://scripts/ui/overlay_builder.gd")

var _hud: Control = null
var _grid: GridContainer = null
var _stats_label: HBoxContainer = null

func setup(hud: Control) -> void:
	_hud = hud
	name = "BackpackOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.02, 0.025, 0.025, 0.58)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -350.0
	panel.offset_top = -300.0
	panel.offset_right = 350.0
	panel.offset_bottom = 300.0
	panel.add_theme_stylebox_override("panel", _hud._make_panel_style(Color(0.055, 0.065, 0.06, 0.88)))
	add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	content.add_child(_hud._make_overlay_title("背包"))
	
	_stats_label = _hud._make_backpack_stats()
	content.add_child(_stats_label)
	
	_grid = _hud._make_backpack_grid()
	content.add_child(_grid)
	
	content.add_child(_hud._make_hint_label("按 Esc 或 B 关闭。数字键 1-8 或右键可使用物品。"))

func refresh_backpack() -> void:
	OverlayBuilder.populate_backpack_grid(_grid, _hud)
	OverlayBuilder.update_backpack_stats(_stats_label, _hud)

func update_stats() -> void:
	OverlayBuilder.update_backpack_stats(_stats_label, _hud)

func get_grid() -> GridContainer:
	return _grid
