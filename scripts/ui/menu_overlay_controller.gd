# menu_overlay_controller.gd
# 处理游戏开始主界面 (MainOverlay) 与结果结算界面 (ResultOverlay) 的状态与交互
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd
extends RefCounted

var _hud: Control = null
var _main_overlay: Control = null
var _main_prompt_label: Label = null
var _main_summary_label: Label = null
var _result_overlay: Control = null
var _result_title_label: Label = null
var _result_stats_label: Label = null

func _init(
	hud: Control,
	main_overlay: Control,
	main_prompt: Label,
	main_summary: Label,
	result_overlay: Control,
	result_title: Label,
	result_stats: Label
) -> void:
	_hud = hud
	_main_overlay = main_overlay
	_main_prompt_label = main_prompt
	_main_summary_label = main_summary
	_result_overlay = result_overlay
	_result_title_label = result_title
	_result_stats_label = result_stats
	
	_main_overlay.gui_input.connect(_on_main_overlay_gui_input)
	
	var start_btn = _main_overlay.get_node_or_null("Content/StartButton")
	if start_btn: start_btn.pressed.connect(on_title_clicked)
	
	var return_btn = _result_overlay.get_node_or_null("Content/ReturnButton")
	if return_btn: return_btn.pressed.connect(return_to_home_from_result)

func show_main_overlay(is_show: bool) -> void:
	if _main_overlay != null:
		_main_overlay.visible = is_show
	if is_show and _result_overlay != null:
		_result_overlay.visible = false
	if is_show:
		_hud.close_blocking_overlay()
	_hud._set_run_hud_visible(not is_show)

func on_title_clicked() -> void:
	GameManager.enter_afterglow()
	clear_main_summary()
	show_main_overlay(false)

func start_run_from_ui() -> void:
	var state := GameManager.current_state
	if state == GameManager.State.SUCCESS or state == GameManager.State.DEAD:
		GameManager.request_start_after_reload()
		_hud.get_tree().reload_current_scene()
		return
	GameManager.start_run()
	clear_main_summary()
	show_main_overlay(false)

func return_to_home_from_result() -> void:
	clear_main_summary()
	show_main_overlay(true)
	GameManager.return_to_afterglow()
	show_main_overlay(false)

func update_end_flow(state: int) -> void:
	if state != GameManager.State.SUCCESS and state != GameManager.State.DEAD:
		if _result_overlay != null:
			_result_overlay.visible = false
		return

	if _hud._active_blocking_overlay != null:
		_hud.close_blocking_overlay()

	var success := state == GameManager.State.SUCCESS
	var score: int = _hud._get_run_score() if success else 0
	_result_title_label.text = "撤离成功" if success else "行动失败"
	_result_stats_label.text = "分数  %d\n击杀  %d\n侵蚀  %d%%\n时间  %s" % [
		score,
		GameManager.kill_count,
		int(round(GameManager.player_erosion)),
		_hud._format_elapsed_time(),
	]
	if _main_overlay != null:
		_main_overlay.visible = false
	_hud._set_run_hud_visible(false)
	GameManager.set_ui_blocking_input(true)
	_result_overlay.visible = true

func set_main_summary(title: String, stats: String) -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "上次行动: %s" % title
	if _main_summary_label != null:
		_main_summary_label.text = "%s\n\n按回车、空格或点击开始进行新一轮行动。" % stats
		_main_summary_label.visible = true

func clear_main_summary() -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "点击任意位置开始"
	if _main_summary_label != null:
		_main_summary_label.text = ""
		_main_summary_label.visible = false

func on_state_changed(new_state: int) -> void:
	update_end_flow(new_state)
	if new_state == GameManager.State.RUNNING or new_state == GameManager.State.EXTRACTING:
		show_main_overlay(false)

func _on_main_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on_title_clicked()
