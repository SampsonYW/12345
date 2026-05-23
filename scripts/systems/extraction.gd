# extraction.gd
# 撤离系统：信号弹发射后开启倒计时，时间结束母车到达，玩家靠近即成功撤离。
# Signal flare extraction flow: wait, arrival marker, boarding, and success.
# [AI-ASSISTED] 2026-05-20 - Day 4 P0 extraction loop.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node3D

@export var wait_time: float = 75.0
@export var boarding_range: float = 3.75
@export var arrival_offset: Vector3 = Vector3(0.0, 0.0, -3.0)

const MOTHERSHIP_MARKER_SCENE := preload("res://scenes/mothership_extraction_marker.tscn")
const SIGNAL_BEACON_SCENE := preload("res://scenes/extraction_signal_beacon.tscn")

var _timer: float = 0.0
var _waiting: bool = false
var _arrived: bool = false
var _landing_position: Vector3 = Vector3.ZERO
var _marker: Node3D = null


func _ready() -> void:
	if not GameManager.signal_flare_fired.is_connected(_on_signal_flare_fired):
		GameManager.signal_flare_fired.connect(_on_signal_flare_fired)
	if not GameManager.state_changed.is_connected(_on_state_changed):
		GameManager.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.State.EXTRACTING:
		return

	if _waiting:
		_timer -= delta
		if _timer <= 0.0:
			_waiting = false
			_arrived = true
			_clear_marker()
			_spawn_marker()

	if _arrived and not GameManager.ui_blocking_input and Input.is_action_just_pressed("interact"):
		try_board()


func get_remaining_time() -> float:
	return maxf(_timer, 0.0) if _waiting else 0.0


func has_arrived() -> bool:
	return _arrived


func get_landing_position() -> Vector3:
	return _landing_position


func try_board() -> bool:
	if GameManager.ui_blocking_input:
		return false
	if not _arrived:
		return false
	if not _player_in_boarding_range():
		return false
	GameManager.set_state(GameManager.State.SUCCESS)
	return true


func get_status_text() -> String:
	if _arrived:
		return "登船 [E]"
	if _waiting:
		return "到达倒计时 %d秒" % int(ceil(get_remaining_time()))
	return "就绪" if not GameManager.signal_flare_used else "已发射"


func get_extraction_direction(from_position: Vector3 = Vector3.ZERO) -> Vector3:
	var origin := from_position
	if origin == Vector3.ZERO:
		origin = GameManager.player_position
	var direction := _landing_position - origin
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.01 else Vector3.ZERO


func get_pressure_status() -> Dictionary:
	return {
		"status_text": get_status_text(),
		"remaining_time": get_remaining_time(),
		"landing_position": _landing_position,
		"direction": get_extraction_direction(),
		"waiting": _waiting,
		"arrived": _arrived,
	}


func _on_signal_flare_fired(origin: Vector3) -> void:
	if (
		GameManager.current_state != GameManager.State.RUNNING
		and GameManager.current_state != GameManager.State.EXTRACTING
	):
		return

	_landing_position = origin + arrival_offset
	_landing_position.y = 0.0
	_timer = maxf(wait_time, 0.0)
	_waiting = true
	_arrived = false
	_clear_marker()
	_notify_spawn_manager()
	_notify_enemies_of_signal(origin)
	_spawn_waiting_beacon()


func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.EXTRACTING:
		return
	_waiting = false
	_arrived = false
	_clear_marker()


func _player_in_boarding_range() -> bool:
	var player_position := GameManager.player_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		player_position = player.global_position
	return player_position.distance_to(_landing_position) <= boarding_range


func _spawn_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		return

	_marker = MOTHERSHIP_MARKER_SCENE.instantiate() as Node3D
	add_child(_marker)
	_marker.global_position = _landing_position


func _spawn_waiting_beacon() -> void:
	if _marker != null and is_instance_valid(_marker):
		return
	_marker = SIGNAL_BEACON_SCENE.instantiate() as Node3D
	add_child(_marker)
	_marker.global_position = _landing_position


func _notify_spawn_manager() -> void:
	var spawn_manager := get_parent().get_node_or_null("SpawnManager")
	if spawn_manager != null and spawn_manager.has_method("on_signal_flare"):
		spawn_manager.on_signal_flare()


func _notify_enemies_of_signal(origin: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy != null and enemy.has_method("react_to_signal_flare"):
			enemy.react_to_signal_flare(origin, _landing_position)


func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		if _marker.get_parent() != null:
			_marker.get_parent().remove_child(_marker)
		_marker.free()
	_marker = null
