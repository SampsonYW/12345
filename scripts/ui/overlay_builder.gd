# overlay_builder.gd
# 提供 HUD 弹层相关的 UI 构建和列表填充的静态工具方法
# [AI-ASSISTED] 2026-05-25 — 从 hud.gd 剥离，作为 View 层的复用工具
extends RefCounted

const STORAGE_DRAG_SLOT_SCRIPT := preload("res://scripts/ui/storage_drag_slot.gd")

static func populate_backpack_grid(grid: GridContainer, hud: Control) -> void:
	if grid == null or hud == null or hud._inventory == null:
		return
	hud._clear_ui_children(grid)
	var slots: Array = hud._inventory.slots
	for i in 8:
		var slot := PanelContainer.new()
		slot.set_script(STORAGE_DRAG_SLOT_SCRIPT)
		slot.set("owner_hud", hud)
		slot.set("accept_target", "backpack_slot")
		slot.custom_minimum_size = Vector2(120.0, 106.0)
		slot.add_theme_stylebox_override("panel", hud._make_panel_style(Color(0.08, 0.09, 0.085, 0.82)))

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		slot.add_child(box)

		var title := Label.new()
		title.name = "ItemName"
		title.clip_text = true
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90, 1.0))
		var item = slots[i] if i < slots.size() else null
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
		detail.add_theme_font_size_override("font_size", 15)
		detail.add_theme_color_override("font_color", Color(0.62, 0.70, 0.66, 1.0))
		box.add_child(detail)

		slot.gui_input.connect(hud._on_backpack_slot_gui_input.bind(i))
		grid.add_child(slot)

static func update_backpack_stats(stats_label: HBoxContainer, hud: Control) -> void:
	if stats_label == null or hud == null or hud._inventory == null:
		return
	var current_weight = hud._inventory.get_current_weight()
	var max_weight = GameManager.max_weight
	var count = hud._inventory.get_collectible_count()
	var score = hud._inventory.calculate_score()
	stats_label.get_node("Weight").text = "负重  %d / %d" % [int(round(current_weight)), int(round(max_weight))]
	stats_label.get_node("Score").text = "分数  %d" % score
	stats_label.get_node("Collectibles").text = "收集品  %d" % count
