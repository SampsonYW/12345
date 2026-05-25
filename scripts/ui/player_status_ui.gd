# player_status_ui.gd
# HUD 的左下角/右上角玩家状态视图，负责管理血条、侵蚀、弹药、小地图和地区危险指示
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd 以实现 MVC 解耦
extends Node

const SPRINT_COLOR_READY := Color(0.4, 0.7, 0.9, 1.0)
const SPRINT_COLOR_ACTIVE := Color(0.9, 0.9, 0.95, 1.0)
const SPRINT_COLOR_COOLDOWN := Color(0.4, 0.5, 0.6, 1.0)

var _hud: Control = null

func setup(hud: Control) -> void:
	_hud = hud

func apply_theme() -> void:
	if _hud == null: return
	_style_progress_bar(_hud.hp_bar, Color(0.4, 0.8, 0.5, 1.0))
	_style_progress_bar(_hud.erosion_bar, Color(0.7, 0.5, 0.8, 1.0))
	
	for panel: Control in [_hud.top_left, _hud.top_right]:
		_apply_label_shadow_recursive(panel)

func on_health_changed(current: float, maximum: float) -> void:
	if _hud == null or _hud.hp_bar == null or _hud.hp_label == null: return
	var safe_maximum := maxf(maximum, 1.0)
	_hud.hp_bar.value = current / safe_maximum * 100.0
	_hud.hp_label.text = "%d / %d" % [int(round(current)), int(round(maximum))]

func on_erosion_changed(value: float) -> void:
	if _hud == null or _hud.erosion_bar == null or _hud.erosion_label == null: return
	_hud.erosion_bar.value = value
	_hud.erosion_label.text = "%d%%" % int(round(value))
	
	var container = _hud.erosion_bar.get_parent()
	if container is Control:
		container.visible = value > 0.01

func on_ammo_changed(current: int, max_value: int) -> void:
	if _hud == null or _hud.ammo_label == null: return
	_hud.ammo_label.text = "弹药 %d/%d" % [current, max_value]

func set_zone_info(zone_name: String, risk: String) -> void:
	if _hud == null: return
	if _hud._zone_container != null:
		_hud._zone_container.visible = zone_name != ""
	if _hud._zone_name_label != null and _hud._zone_name_label.text != zone_name:
		_hud._zone_name_label.text = zone_name
	if _hud._zone_risk_label != null:
		var risk_display := "低风险" if risk == "low" else "高风险"
		var full_text := "危险等级: %s" % risk_display
		if _hud._zone_risk_label.text != full_text:
			_hud._zone_risk_label.text = full_text
			if risk == "high":
				_hud._zone_risk_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
			else:
				_hud._zone_risk_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55, 1.0))

func update_signal_label(extraction: Node) -> void:
	if _hud == null or _hud._signal_label == null: return
	if not GameManager.signal_flare_used:
		_hud._signal_label.visible = false
		return
		
	_hud._signal_label.visible = true
	if extraction != null and extraction.has_method("get_status_text"):
		_hud._signal_label.text = "飞船到达 %s" % extraction.get_status_text()
	else:
		_hud._signal_label.text = "飞船已到达"

func update_sprint_ui() -> void:
	if _hud == null or _hud._sprint_bar == null or _hud._sprint_status_label == null: return
	if _hud._player == null or not is_instance_valid(_hud._player):
		_hud._player = get_tree().get_first_node_in_group("player")
	if _hud._player == null: return
	if not _hud._player.has_method("is_sprinting") or not _hud._player.has_method("get_sprint_cooldown_ratio"): return

	var is_sprinting: bool = _hud._player.is_sprinting()
	var cooldown_ratio: float = _hud._player.get_sprint_cooldown_ratio()
	var duration_ratio: float = 0.0
	if _hud._player.has_method("get_sprint_duration_ratio"):
		duration_ratio = _hud._player.get_sprint_duration_ratio()

	var fg := _hud._sprint_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fg == null:
		fg = StyleBoxFlat.new()
		fg.set_corner_radius_all(6)
		_hud._sprint_bar.add_theme_stylebox_override("fill", fg)

	if is_sprinting:
		_hud._sprint_bar.value = duration_ratio * 100.0
		_hud._sprint_status_label.text = "激活"
		_hud._sprint_status_label.add_theme_color_override("font_color", SPRINT_COLOR_ACTIVE)
		fg.bg_color = SPRINT_COLOR_ACTIVE
		fg.shadow_color = SPRINT_COLOR_ACTIVE * Color(1.0, 1.0, 1.0, 0.2)
	elif cooldown_ratio > 0.0:
		var fill_ratio := 1.0 - cooldown_ratio
		_hud._sprint_bar.value = fill_ratio * 100.0
		_hud._sprint_status_label.text = "恢复中 %d%%" % int(round(fill_ratio * 100.0))
		_hud._sprint_status_label.add_theme_color_override("font_color", SPRINT_COLOR_COOLDOWN)
		fg.bg_color = SPRINT_COLOR_COOLDOWN
		fg.shadow_color = Color(0, 0, 0, 0)
	else:
		_hud._sprint_bar.value = 100.0
		_hud._sprint_status_label.text = "就绪"
		_hud._sprint_status_label.add_theme_color_override("font_color", SPRINT_COLOR_READY)
		fg.bg_color = SPRINT_COLOR_READY
		fg.shadow_color = SPRINT_COLOR_READY * Color(1.0, 1.0, 1.0, 0.2)

func _apply_label_shadow_recursive(parent: Control) -> void:
	for child in parent.get_children():
		if child is Label:
			child.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))
			child.add_theme_constant_override("shadow_offset_x", 1)
			child.add_theme_constant_override("shadow_offset_y", 1)
		elif child is Control:
			_apply_label_shadow_recursive(child)

func _style_progress_bar(bar: ProgressBar, fill_color: Color) -> void:
	if bar == null: return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.12, 0.5)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fg)
