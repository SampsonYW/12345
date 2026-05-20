# player_3d.gd
# 3D 玩家控制：地面 XZ 平面移动、冲刺、鼠标射线瞄准、信号弹和背包快捷键。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写玩家控制
extends CharacterBody3D

@export var base_speed: float = 7.0
@export var sprint_multiplier: float = 1.55
@export var sprint_duration: float = 1.0
@export var sprint_cooldown: float = 3.0

var _sprint_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _is_sprinting: bool = false
var _aim_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	if is_input_locked() or not _can_move_in_current_location():
		velocity = Vector3.ZERO
		return

	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_dir := Vector3(input.x, 0.0, input.y)
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()
	var speed: float = base_speed * (sprint_multiplier if _is_sprinting else 1.0)
	velocity = move_dir * speed
	move_and_slide()

	GameManager.player_position = global_position
	_update_aim_direction(move_dir)
	_update_sprint_timers(delta)


func _unhandled_input(event: InputEvent) -> void:
	if is_input_locked():
		return
	if event.is_action_pressed("signal_flare"):
		_fire_signal_flare()
		return

	if event.is_action_pressed("sprint") and _cooldown_timer <= 0.0 and not _is_sprinting:
		_is_sprinting = true
		_sprint_timer = sprint_duration
		_cooldown_timer = sprint_cooldown
		NoiseManager.emit_noise(global_position, NoiseManager.Level.MEDIUM)
		return

	for i in 8:
		if event.is_action_pressed("use_slot_%d" % (i + 1)):
			_use_inventory_slot(i)
			return


func get_aim_direction() -> Vector3:
	return _aim_direction


func get_sprint_cooldown_ratio() -> float:
	if sprint_cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_timer / sprint_cooldown, 0.0, 1.0)


func is_input_locked() -> bool:
	return GameManager.ui_blocking_input


func _update_aim_direction(move_dir: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	var aimed := false
	if camera != null:
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_origin := camera.project_ray_origin(mouse_pos)
		var ray_direction := camera.project_ray_normal(mouse_pos)
		var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(
			ray_origin,
			ray_direction
		)
		if hit is Vector3:
			var to_hit: Vector3 = hit - global_position
			to_hit.y = 0.0
			if to_hit.length_squared() > 0.01:
				_aim_direction = to_hit.normalized()
				aimed = true
	if not aimed and move_dir.length_squared() > 0.01:
		_aim_direction = move_dir.normalized()
	look_at(global_position + _aim_direction, Vector3.UP)


func _update_sprint_timers(delta: float) -> void:
	if _is_sprinting:
		_sprint_timer -= delta
		if _sprint_timer <= 0.0:
			_is_sprinting = false
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _use_inventory_slot(idx: int) -> void:
	var inv: Node = get_node_or_null("Inventory")
	if inv != null and inv.has_method("use_slot"):
		inv.use_slot(idx)


func _can_move_in_current_location() -> bool:
	if GameManager.current_location == GameManager.Location.AFTERGLOW:
		return true
	return (
		GameManager.current_state == GameManager.State.RUNNING
		or GameManager.current_state == GameManager.State.EXTRACTING
	)


func _fire_signal_flare() -> void:
	if GameManager.fire_signal_flare(global_position):
		NoiseManager.emit_noise(global_position, NoiseManager.Level.GLOBAL)
		_spawn_signal_flare_marker()


const FLARE_MARKER_SCENE := preload("res://scenes/signal_flare_marker.tscn")


func _spawn_signal_flare_marker() -> void:
	var marker := FLARE_MARKER_SCENE.instantiate() as Node3D
	marker.global_position = global_position

	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	parent.add_child(marker)
	get_tree().create_timer(4.0).timeout.connect(Callable(marker, "queue_free"))

