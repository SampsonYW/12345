# storage_drag_slot.gd
# UI 拖拽槽包装器：使 HUD 的背包、容器、仓库列表支持 Godot 拖拽（Drag & Drop）交互。
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Control

var owner_hud: Node = null
var drag_payload: Dictionary = {}
var accept_target: String = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty():
		return null
	var preview := Label.new()
	preview.text = String(drag_payload.get("label", "物品"))
	preview.add_theme_color_override("font_color", Color(0.96, 0.92, 0.72, 1.0))
	set_drag_preview(preview)
	return drag_payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if owner_hud == null or not owner_hud.has_method("can_accept_storage_drop"):
		return false
	return owner_hud.can_accept_storage_drop(data, accept_target)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if owner_hud != null and owner_hud.has_method("accept_storage_drop"):
		owner_hud.accept_storage_drop(data, accept_target)
