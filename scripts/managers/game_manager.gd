# game_manager.gd
# Autoload singleton for run state, erosion, elapsed time, and signal flare state.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node

signal state_changed(new_state: State)
signal erosion_changed(value: float)
signal erosion_tier_changed(tier: int)
signal signal_flare_fired(origin: Vector3)
signal run_finished(final_state: State)
signal location_changed(location: Location)
signal ui_blocking_changed(blocked: bool)

enum State { PREPARING, RUNNING, EXTRACTING, SUCCESS, DEAD }
enum Location { TITLE, AFTERGLOW, EXPEDITION }

const EROSION_RATE := 0.0167
const HIT_EROSION_AMOUNT := 2.5
const PURIFIER_REDUCTION := 17.5

const EROSION_STAT_MULTIPLIER := [1.0, 1.0, 1.1, 1.2, 1.35]
const EROSION_SPAWN_INTERVAL_MULTIPLIER := [1.0, 1.0, 0.85, 0.7, 0.5]
const EROSION_DORMANT_RATIO := [0.0, 0.0, 0.15, 0.3, 0.5]

var current_state: State = State.PREPARING
var elapsed_time: float = 0.0
var player_erosion: float = 0.0
var max_weight: float = 50.0
var max_erosion: float = 100.0
var player_position: Vector3 = Vector3.ZERO
var kill_count: int = 0
var signal_flare_used: bool = false
var signal_flare_position: Vector3 = Vector3.ZERO
var signal_flare_time: float = -1.0
var start_after_reload: bool = false
var current_location: Location = Location.TITLE
var ui_blocking_input: bool = false

var _last_tier: int = 0


func _process(delta: float) -> void:
	if current_state == State.RUNNING or current_state == State.EXTRACTING:
		elapsed_time += delta
		add_erosion(EROSION_RATE * delta)


func start_run() -> void:
	reset_run()
	set_location(Location.EXPEDITION)
	set_state(State.RUNNING)


func reset_run() -> void:
	var previous_state := current_state
	current_state = State.PREPARING
	elapsed_time = 0.0
	player_erosion = 0.0
	kill_count = 0
	signal_flare_used = false
	signal_flare_position = Vector3.ZERO
	signal_flare_time = -1.0
	_last_tier = 0
	set_ui_blocking_input(false)
	erosion_changed.emit(player_erosion)
	if previous_state != current_state:
		state_changed.emit(current_state)


func set_location(location: Location) -> void:
	if current_location == location:
		return
	current_location = location
	location_changed.emit(location)


func enter_afterglow() -> void:
	reset_run()
	set_location(Location.AFTERGLOW)


func begin_expedition() -> void:
	reset_run()
	set_location(Location.EXPEDITION)
	set_state(State.RUNNING)


func return_to_afterglow() -> void:
	reset_run()
	set_location(Location.AFTERGLOW)


func set_ui_blocking_input(blocked: bool) -> void:
	if ui_blocking_input == blocked:
		return
	ui_blocking_input = blocked
	ui_blocking_changed.emit(blocked)


func request_start_after_reload() -> void:
	start_after_reload = true


func consume_start_after_reload() -> bool:
	if not start_after_reload:
		return false
	start_after_reload = false
	return true


func set_state(new_state: State) -> void:
	if current_state == new_state:
		return
	if current_state == State.SUCCESS or current_state == State.DEAD:
		return
	current_state = new_state
	state_changed.emit(new_state)
	match new_state:
		State.SUCCESS, State.DEAD:
			run_finished.emit(new_state)


func fire_signal_flare(origin: Vector3) -> bool:
	if current_state != State.RUNNING:
		return false
	if signal_flare_used:
		return false
	signal_flare_used = true
	signal_flare_position = origin
	signal_flare_time = elapsed_time
	signal_flare_fired.emit(origin)
	set_state(State.EXTRACTING)
	return true


func add_erosion(amount: float) -> void:
	var prev := player_erosion
	player_erosion = clampf(player_erosion + amount, 0.0, max_erosion)
	if player_erosion != prev:
		erosion_changed.emit(player_erosion)
		_check_tier_change()


func reduce_erosion(amount: float) -> void:
	add_erosion(-amount)


func get_erosion_tier() -> int:
	if player_erosion < 25.0:
		return 0
	if player_erosion < 50.0:
		return 1
	if player_erosion < 75.0:
		return 2
	if player_erosion < 100.0:
		return 3
	return 4


func register_kill() -> void:
	kill_count += 1


func _check_tier_change() -> void:
	var tier := get_erosion_tier()
	if tier != _last_tier:
		_last_tier = tier
		erosion_tier_changed.emit(tier)
