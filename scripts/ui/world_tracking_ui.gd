extends Control
# world_tracking_ui.gd
# HUD 子系统：负责将 3D 世界中的实体（敌人、容器）状态以 2D UI 形式投影到屏幕上。
# 替代原有的 3D Mesh 状态条，彻底解决深度遮挡、光照影响和背对相机等问题。

var _pool: Array[VBoxContainer] = []
var _active_widgets: Dictionary = {}

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		visible = false
		return
	visible = true

	var current_frame_ids := {}

	# 追踪敌人
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var eid := enemy.get_instance_id()
		var widget := _get_or_create_widget(eid)
		current_frame_ids[eid] = true
		
		var screen_pos := _get_screen_pos(cam, enemy.global_position + Vector3(0, 1.8, 0))
		if not enemy.visible or screen_pos == Vector2.INF:
			widget.visible = false
			continue
		
		widget.visible = true
		widget.position = screen_pos - Vector2(widget.size.x * 0.5, widget.size.y)
		
		var hp_bar := widget.get_node("HpBar") as ProgressBar
		var alert_bar := widget.get_node("AlertBar") as ProgressBar
		
		if enemy.has_method("get_hp_ratio"):
			var hp_ratio: float = enemy.get_hp_ratio()
			hp_bar.value = hp_ratio
			hp_bar.visible = hp_ratio > 0.0
		
		if enemy.has_method("get_alert_ratio"):
			var alert_ratio: float = enemy.get_alert_ratio()
			alert_bar.value = alert_ratio
			# 在未觉醒时，如果有警觉值就显示；如果是刚被觉醒或者完全觉醒也可以显示，因为现在我们修改了 get_alert_ratio() 使得觉醒时必定返回 1.0
			# 我们这里只需处理，如果未被警觉即 alert_ratio == 0 时，不显示
			alert_bar.visible = alert_ratio > 0.0

	# 追踪容器
	var containers := get_tree().get_nodes_in_group("containers")
	for container in containers:
		if not is_instance_valid(container):
			continue
		var cid := container.get_instance_id()
		if not container.has_method("is_cracking") or not container.is_cracking():
			continue
			
		var widget := _get_or_create_widget(cid)
		current_frame_ids[cid] = true
		
		var screen_pos := _get_screen_pos(cam, container.global_position + Vector3(0, 1.3, 0))
		if not container.visible or screen_pos == Vector2.INF:
			widget.visible = false
			continue
		
		widget.visible = true
		widget.position = screen_pos - Vector2(widget.size.x * 0.5, widget.size.y)
		
		var alert_bar := widget.get_node("AlertBar") as ProgressBar
		alert_bar.visible = false # 容器不用这个
		
		var hp_bar := widget.get_node("HpBar") as ProgressBar
		if container.has_method("get_crack_progress"):
			var crack_progress: float = container.get_crack_progress()
			hp_bar.value = crack_progress
			hp_bar.visible = crack_progress > 0.0
			# 对于容器，我们临时复用 HpBar 并改颜色？
			# 为简单起见，我们直接修改 HpBar 的 fill 颜色
			var sb := hp_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
			sb.bg_color = Color(1.0, 0.9, 0.45, 1.0)
			hp_bar.add_theme_stylebox_override("fill", sb)
		else:
			hp_bar.visible = false

	# 释放未使用的 widget
	var keys_to_remove := []
	for id in _active_widgets.keys():
		if not current_frame_ids.has(id):
			var w: VBoxContainer = _active_widgets[id]
			w.visible = false
			_pool.append(w)
			keys_to_remove.append(id)
			
	for id in keys_to_remove:
		_active_widgets.erase(id)


func _get_screen_pos(cam: Camera3D, pos3d: Vector3) -> Vector2:
	if cam.is_position_behind(pos3d):
		return Vector2.INF
	return cam.unproject_position(pos3d)


func _get_or_create_widget(id: int) -> VBoxContainer:
	if _active_widgets.has(id):
		var w: VBoxContainer = _active_widgets[id]
		# 重置样式（避免容器改变了敌人的颜色）
		var hp_bar := w.get_node("HpBar") as ProgressBar
		hp_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.95, 0.08, 0.05, 1.0)))
		return w
	
	var w: VBoxContainer
	if _pool.size() > 0:
		w = _pool.pop_back()
	else:
		w = _create_new_widget()
		add_child(w)
	
	w.visible = true
	_active_widgets[id] = w
	return w


func _create_new_widget() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(80, 20)
	vbox.add_theme_constant_override("separation", 2)
	
	var hp_bar := ProgressBar.new()
	hp_bar.name = "HpBar"
	hp_bar.custom_minimum_size = Vector2(80, 8)
	hp_bar.show_percentage = false
	hp_bar.max_value = 1.0
	hp_bar.add_theme_stylebox_override("background", _make_stylebox(Color(0.04, 0.04, 0.04, 0.9)))
	hp_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.95, 0.08, 0.05, 1.0)))
	vbox.add_child(hp_bar)
	
	var alert_bar := ProgressBar.new()
	alert_bar.name = "AlertBar"
	alert_bar.custom_minimum_size = Vector2(80, 6)
	alert_bar.show_percentage = false
	alert_bar.max_value = 1.0
	alert_bar.add_theme_stylebox_override("background", _make_stylebox(Color(0.04, 0.05, 0.05, 0.9)))
	alert_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(1.0, 0.65, 0.12, 1.0)))
	vbox.add_child(alert_bar)
	
	return vbox


func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	# 添加边框提升对比度
	sb.border_color = Color(0, 0, 0, 0.8)
	sb.set_border_width_all(1)
	return sb
