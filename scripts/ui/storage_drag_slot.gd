extends PanelContainer

var owner_hud: Node = null
var drag_payload: Dictionary = {}
var accept_target: String = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty():
		return null
	var preview := Label.new()
	preview.text = String(drag_payload.get("label", "Item"))
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
