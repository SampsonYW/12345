# hud_input_interceptor.gd
# HUD 的输入拦截器，处理全局快捷键（背包、退出、物品使用、回车确认）
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd 以实现 MVC 架构解耦
extends Node

const START_KEYS := [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

var _hud: Control = null

func setup(hud: Control) -> void:
	_hud = hud

func _unhandled_input(event: InputEvent) -> void:
	if _hud == null:
		return
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
		
	if _hud._main_overlay != null and _hud._main_overlay.visible:
		if event.physical_keycode in START_KEYS:
			_mark_input_as_handled()
			if _hud._menu_controller != null:
				_hud._menu_controller.on_title_clicked()
		return
		
	if _hud._result_overlay != null and _hud._result_overlay.visible:
		if event.physical_keycode in START_KEYS:
			_mark_input_as_handled()
			if _hud._menu_controller != null:
				_hud._menu_controller.return_to_home_from_result()
		return
		
	if GameManager.current_location == GameManager.Location.TITLE:
		return
		
	if event.is_action_pressed("backpack"):
		_mark_input_as_handled()
		if _hud._active_blocking_overlay != null:
			_hud.close_blocking_overlay()
		else:
			_hud.open_backpack()
		return
		
	if event.keycode == KEY_ESCAPE and _hud._active_blocking_overlay != null:
		_mark_input_as_handled()
		_hud.close_blocking_overlay()
		return
		
	if _hud._active_blocking_overlay != null and _hud._inventory != null:
		for i in 8:
			if event.is_action_pressed("use_slot_%d" % (i + 1)):
				_mark_input_as_handled()
				_hud._inventory.use_slot(i)
				_hud._refresh_after_context_menu()
				return

func _mark_input_as_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
