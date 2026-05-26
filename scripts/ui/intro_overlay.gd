# intro_overlay.gd
# 开场动画 overlay：全屏播放 VideoStreamPlayer + 右上角透明 Skip 按钮。
# 播放完毕或玩家点 Skip 时发出 finished 信号并销毁自己。
# game_3d.gd 在 _ready() 创建挂载，期间设 ui_blocking_input 屏蔽玩家输入。
# [AI-ASSISTED] 2026-05-26 — 开场动画接入
extends Control

signal finished

const INTRO_VIDEO := preload("res://assets/video/intro_2k.ogv")

var _video_player: VideoStreamPlayer = null
var _skip_button: Button = null
var _finished: bool = false


func _ready() -> void:
	name = "IntroOverlay"
	# anchors + offsets 都设：程序化创建的 Control size 默认 0，单设 anchors 不够
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 视频期间暂停整个 SceneTree，自己用 ALWAYS 继续运行
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	# 黑色背景填满 letterbox 区
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 全屏视频
	_video_player = VideoStreamPlayer.new()
	_video_player.name = "IntroVideo"
	_video_player.stream = INTRO_VIDEO
	_video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.autoplay = false
	_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_player.finished.connect(_on_video_finished)
	add_child(_video_player)
	# 右上角透明 Skip 按钮（anchor 在 viewport 右上角）
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "跳过 ›"
	_skip_button.custom_minimum_size = Vector2(120.0, 40.0)
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	_skip_button.offset_left = -160.0
	_skip_button.offset_top = 24.0
	_skip_button.offset_right = -24.0
	_skip_button.offset_bottom = 64.0
	_skip_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_button.add_theme_stylebox_override("normal", _make_skip_style(Color(0.05, 0.05, 0.06, 0.35)))
	_skip_button.add_theme_stylebox_override("hover", _make_skip_style(Color(0.10, 0.12, 0.14, 0.65)))
	_skip_button.add_theme_stylebox_override("pressed", _make_skip_style(Color(0.06, 0.08, 0.10, 0.85)))
	_skip_button.add_theme_color_override("font_color", Color(0.92, 0.96, 0.94, 0.86))
	_skip_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	_skip_button.add_theme_font_size_override("font_size", 18)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(_on_skip_pressed)
	add_child(_skip_button)
	# 启动时 ui_blocking 让玩家移动/射击停下来
	GameManager.set_ui_blocking_input(true)
	_video_player.play()


func _unhandled_input(event: InputEvent) -> void:
	# ESC / 空格 / 回车 也能跳过
	if _finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_skip_pressed()
			get_viewport().set_input_as_handled()


func _on_video_finished() -> void:
	_finish()


func _on_skip_pressed() -> void:
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _video_player != null and _video_player.is_playing():
		_video_player.stop()
	get_tree().paused = false
	GameManager.set_ui_blocking_input(false)
	finished.emit()
	queue_free()


func _make_skip_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.45, 0.62, 0.75, 0.5)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style
