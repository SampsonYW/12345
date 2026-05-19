extends Control

const EMPTY_SLOT_COLOR := Color(0.12, 0.12, 0.12, 0.72)
const START_KEYS := [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

const TYPE_COLORS := {
	ItemData.Type.COLLECTIBLE: Color(0.95, 0.68, 0.25, 1.0),
	ItemData.Type.AMMO: Color(0.38, 0.62, 0.95, 1.0),
	ItemData.Type.BATTERY: Color(0.35, 0.86, 0.45, 1.0),
	ItemData.Type.PURIFIER: Color(0.30, 0.82, 0.84, 1.0),
}

var _player_health: Node = null
var _player_shooting: Node = null
var _inventory: Node = null
var _blocked_hide_timer: float = 0.0
var _slot_panels: Array[Panel] = []

var _state_label: Label = null
var _time_label: Label = null
var _signal_label: Label = null
var _main_overlay: Control = null
var _main_prompt_label: Label = null
var _main_summary_label: Label = null
var _result_overlay: Control = null
var _result_title_label: Label = null
var _result_stats_label: Label = null

@onready var top_left: VBoxContainer = $TopLeft
@onready var top_right: VBoxContainer = $TopRight
@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_label: Label = %HPLabel
@onready var erosion_bar: ProgressBar = %ErosionBar
@onready var erosion_label: Label = %ErosionLabel
@onready var weight_label: Label = %WeightLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var score_label: Label = %ScoreLabel
@onready var collectible_label: Label = %CollectibleLabel
@onready var blocked_label: Label = %BlockedLabel
@onready var slots_container: HBoxContainer = %BottomBar


func _ready() -> void:
	blocked_label.visible = false
	_build_status_labels()
	_build_slot_panels()
	_build_main_overlay()
	_build_result_overlay()
	_bind_player_refs()

	GameManager.erosion_changed.connect(_on_erosion_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.signal_flare_fired.connect(_on_signal_flare_fired)

	_on_erosion_changed(GameManager.player_erosion)
	_on_state_changed(GameManager.current_state)
	_update_time_label()
	_update_signal_label()
	call_deferred("_restore_launch_screen")


func _process(delta: float) -> void:
	if _player_shooting == null or _player_health == null or _inventory == null:
		_bind_player_refs()
	if _blocked_hide_timer > 0.0:
		_blocked_hide_timer -= delta
		if _blocked_hide_timer <= 0.0:
			blocked_label.visible = false
	_update_time_label()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if _main_overlay != null and _main_overlay.visible and event.physical_keycode in START_KEYS:
		_start_run_from_ui()
		get_viewport().set_input_as_handled()
	elif _result_overlay != null and _result_overlay.visible and event.physical_keycode in START_KEYS:
		_return_to_home_from_result()
		get_viewport().set_input_as_handled()


func _restore_launch_screen() -> void:
	GameManager.reset_run()
	_show_main_overlay(true)
	if GameManager.consume_start_after_reload():
		_start_run_from_ui()


func _build_status_labels() -> void:
	_state_label = _make_status_label("State  Preparing")
	_time_label = _make_status_label("Time  00:00")
	_signal_label = _make_status_label("Signal  Ready")
	top_right.add_child(_state_label)
	top_right.add_child(_time_label)
	top_right.add_child(_signal_label)


func _build_slot_panels() -> void:
	for i in 8:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(60, 60)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.offset_left = 4.0
		fill.offset_top = 4.0
		fill.offset_right = -4.0
		fill.offset_bottom = -4.0
		fill.color = EMPTY_SLOT_COLOR
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(fill)

		var num := Label.new()
		num.name = "Num"
		num.text = str(i + 1)
		num.position = Vector2(6.0, 2.0)
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num)

		var name_label := Label.new()
		name_label.name = "ItemName"
		name_label.position = Vector2(6.0, 36.0)
		name_label.size = Vector2(48.0, 20.0)
		name_label.clip_text = true
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_label)

		slots_container.add_child(panel)
		_slot_panels.append(panel)


func _build_main_overlay() -> void:
	_main_overlay = ColorRect.new()
	_main_overlay.name = "MainOverlay"
	_main_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_overlay.color = Color(0.035, 0.045, 0.04, 0.94)
	_main_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_overlay.gui_input.connect(_on_main_overlay_gui_input)
	add_child(_main_overlay)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -240.0
	content.offset_top = -120.0
	content.offset_right = 240.0
	content.offset_bottom = 120.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	_main_overlay.add_child(content)

	var title := Label.new()
	title.text = "Afterglow Express"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78, 1.0))
	content.add_child(title)

	_main_prompt_label = Label.new()
	_main_prompt_label.text = "Press Enter or Space to start"
	_main_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_prompt_label.add_theme_font_size_override("font_size", 18)
	_main_prompt_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.82, 1.0))
	content.add_child(_main_prompt_label)

	_main_summary_label = Label.new()
	_main_summary_label.visible = false
	_main_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_summary_label.add_theme_font_size_override("font_size", 16)
	_main_summary_label.add_theme_color_override("font_color", Color(0.90, 0.96, 0.92, 1.0))
	content.add_child(_main_summary_label)

	var button := Button.new()
	button.text = "Start Run"
	button.custom_minimum_size = Vector2(180.0, 42.0)
	button.pressed.connect(_start_run_from_ui)
	content.add_child(button)


func _build_result_overlay() -> void:
	_result_overlay = ColorRect.new()
	_result_overlay.name = "ResultOverlay"
	_result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.color = Color(0.02, 0.025, 0.025, 0.88)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.visible = false
	add_child(_result_overlay)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -280.0
	content.offset_top = -150.0
	content.offset_right = 280.0
	content.offset_bottom = 150.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	_result_overlay.add_child(content)

	_result_title_label = Label.new()
	_result_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title_label.add_theme_font_size_override("font_size", 34)
	_result_title_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.74, 1.0))
	content.add_child(_result_title_label)

	_result_stats_label = Label.new()
	_result_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats_label.add_theme_font_size_override("font_size", 18)
	_result_stats_label.add_theme_color_override("font_color", Color(0.90, 0.96, 0.92, 1.0))
	content.add_child(_result_stats_label)

	var prompt := Label.new()
	prompt.text = "Press Enter or Space to return home"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(0.76, 0.84, 0.80, 1.0))
	content.add_child(prompt)

	var button := Button.new()
	button.text = "Back to Home"
	button.custom_minimum_size = Vector2(180.0, 42.0)
	button.pressed.connect(_return_to_home_from_result)
	content.add_child(button)


func _make_status_label(text: String) -> Label:
	var label := Label.new()
	label.layout_mode = 2
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _bind_player_refs() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if _player_health == null:
		_player_health = player.get_node_or_null("PlayerHealth")
		if _player_health != null:
			_player_health.health_changed.connect(_on_health_changed)
			_on_health_changed(_player_health.current_hp, _player_health.max_hp)
	if _player_shooting == null:
		_player_shooting = player.get_node_or_null("PlayerShooting")
		if _player_shooting != null:
			_player_shooting.ammo_changed.connect(_on_ammo_changed)
			_on_ammo_changed(_player_shooting.current_ammo, _player_shooting.max_ammo)
	if _inventory == null:
		_inventory = player.get_node_or_null("Inventory")
		if _inventory != null:
			_inventory.inventory_changed.connect(_on_inventory_changed)
			_inventory.collectible_changed.connect(_on_collectible_changed)
			_inventory.pickup_blocked.connect(_on_pickup_blocked)
			_inventory.use_blocked.connect(_on_pickup_blocked)
			_on_inventory_changed(_inventory.slots, _inventory.get_current_weight(), GameManager.max_weight)
			_on_collectible_changed(_inventory.get_collectible_count(), _inventory.calculate_score())


func _show_main_overlay(show: bool) -> void:
	if _main_overlay != null:
		_main_overlay.visible = show
	if show and _result_overlay != null:
		_result_overlay.visible = false
	_set_run_hud_visible(not show)


func _set_run_hud_visible(show: bool) -> void:
	top_left.visible = show
	top_right.visible = show
	slots_container.visible = show
	blocked_label.visible = show and blocked_label.visible


func _start_run_from_ui() -> void:
	if GameManager.current_state == GameManager.State.SUCCESS or GameManager.current_state == GameManager.State.DEAD:
		GameManager.request_start_after_reload()
		get_tree().reload_current_scene()
		return
	GameManager.start_run()
	_clear_main_summary()
	_show_main_overlay(false)


func _return_to_home_from_result() -> void:
	_clear_main_summary()
	_show_main_overlay(true)


func _on_main_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_run_from_ui()


func _on_health_changed(current: float, maximum: float) -> void:
	var safe_maximum := maxf(maximum, 1.0)
	hp_bar.value = current / safe_maximum * 100.0
	hp_label.text = "HP  %d / %d" % [int(round(current)), int(round(maximum))]


func _on_erosion_changed(value: float) -> void:
	erosion_bar.value = value
	erosion_label.text = "Erosion  %d%%" % int(round(value))


func _on_ammo_changed(current: int, max_value: int) -> void:
	ammo_label.text = "Ammo  %d / %d" % [current, max_value]


func _on_collectible_changed(count: int, score: int) -> void:
	collectible_label.text = "Collectibles  %d" % count
	score_label.text = "Score  %d" % score


func _on_inventory_changed(slots: Array, current_weight: float, max_weight: float) -> void:
	weight_label.text = "Weight  %d / %d" % [int(round(current_weight)), int(round(max_weight))]
	for i in _slot_panels.size():
		var panel: Panel = _slot_panels[i]
		var fill := panel.get_node_or_null("Fill") as ColorRect
		var name_label := panel.get_node_or_null("ItemName") as Label
		if fill == null or name_label == null:
			continue
		var item: ItemData = slots[i] if i < slots.size() else null
		if item == null:
			fill.color = EMPTY_SLOT_COLOR
			name_label.text = ""
		else:
			fill.color = TYPE_COLORS.get(item.type, Color.WHITE)
			name_label.text = item.item_name


func _on_pickup_blocked(reason: String) -> void:
	blocked_label.text = reason
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _on_state_changed(new_state: int) -> void:
	if _state_label != null:
		_state_label.text = "State  %s" % _get_state_text(new_state)
	_update_signal_label()
	_update_end_flow(new_state)
	if new_state == GameManager.State.RUNNING or new_state == GameManager.State.EXTRACTING:
		_show_main_overlay(false)


func _on_signal_flare_fired(_origin: Vector3) -> void:
	_update_signal_label()
	blocked_label.text = "Signal fired. Hold the extraction zone."
	blocked_label.visible = true
	_blocked_hide_timer = 2.0


func _update_time_label() -> void:
	if _time_label == null:
		return
	var total_seconds: int = int(floor(GameManager.elapsed_time))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	_time_label.text = "Time  %02d:%02d" % [minutes, seconds]


func _update_signal_label() -> void:
	if _signal_label == null:
		return
	_signal_label.text = "Signal  Fired" if GameManager.signal_flare_used else "Signal  Ready"


func _update_end_flow(state: int) -> void:
	if state != GameManager.State.SUCCESS and state != GameManager.State.DEAD:
		if _result_overlay != null:
			_result_overlay.visible = false
		return

	var success := state == GameManager.State.SUCCESS
	var score := _get_run_score() if success else 0
	_result_title_label.text = "Extraction Complete" if success else "Run Failed"
	_result_stats_label.text = "Score  %d\nKills  %d\nErosion  %d%%\nTime  %s" % [
		score,
		GameManager.kill_count,
		int(round(GameManager.player_erosion)),
		_format_elapsed_time(),
	]
	if _main_overlay != null:
		_main_overlay.visible = false
	_set_run_hud_visible(false)
	_result_overlay.visible = true


func _set_main_summary(title: String, stats: String) -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "Last run: %s" % title
	if _main_summary_label != null:
		_main_summary_label.text = "%s\n\nPress Enter, Space, or Start Run for a new run." % stats
		_main_summary_label.visible = true


func _clear_main_summary() -> void:
	if _main_prompt_label != null:
		_main_prompt_label.text = "Press Enter or Space to start"
	if _main_summary_label != null:
		_main_summary_label.text = ""
		_main_summary_label.visible = false


func _get_run_score() -> int:
	if _inventory != null and _inventory.has_method("calculate_score"):
		return _inventory.calculate_score()
	return 0


func _format_elapsed_time() -> String:
	var total_seconds: int = int(floor(GameManager.elapsed_time))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _get_state_text(state: int) -> String:
	match state:
		GameManager.State.PREPARING:
			return "Preparing"
		GameManager.State.RUNNING:
			return "Running"
		GameManager.State.EXTRACTING:
			return "Extracting"
		GameManager.State.SUCCESS:
			return "Success"
		GameManager.State.DEAD:
			return "Dead"
		_:
			return "Unknown"
