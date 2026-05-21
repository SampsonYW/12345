# afterglow_map.gd
# Self-contained Afterglow Express (母车) map script.
# Owns: warehouse/departure interactions, collision management.
extends Node3D

const INTERACTION_RANGE := 3.25
const DEPARTURE_HOLD_TIME := 1.4

var _player: Node3D = null
var _hud: Node = null
var _world_prompt: Label3D = null
var _departure_hold: float = 0.0
var _active_point: String = ""


func activate(player: Node3D, hud: Node, world_prompt: Label3D = null) -> void:
	_player = player
	_hud = hud
	_world_prompt = world_prompt
	_departure_hold = 0.0
	_active_point = ""
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_collision_active(true)


func deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_set_collision_active(false)
	_hide_progress()
	_departure_hold = 0.0
	_active_point = ""


func update(delta: float) -> void:
	if _player == null:
		return
	_update_interactions(delta)


## Test helper: place the player near a named interaction point.
func set_player_near_point(point_name: String) -> void:
	var point := _get_point(point_name)
	if point == null or _player == null:
		return
	_player.global_position = point.global_position + Vector3(0.0, 0.0, 1.25)
	GameManager.player_position = _player.global_position
	_update_interactions(0.0)


## Test helper: immediately complete the departure hold.
func complete_departure_for_test() -> void:
	_begin_expedition()


func get_active_point() -> String:
	return _active_point


# ---------------------------------------------------------------------------
# Interactions
# ---------------------------------------------------------------------------

func _update_interactions(delta: float) -> void:
	if _player == null:
		return
	var nearby := _find_nearby_point()
	_active_point = nearby
	if nearby == "warehouse":
		_departure_hold = 0.0
		_set_prompt_text("E Open Storage")
		if Input.is_action_pressed("interact") and not GameManager.ui_blocking_input:
			if _hud != null and _hud.has_method("open_storage"):
				_hud.open_storage()
	elif nearby == "departure":
		var departure_point := _get_point("departure")
		var prompt_pos := departure_point.global_position + Vector3(0.0, 0.6, -2.5) if departure_point != null else Vector3(32.0, 0.8, 10.5)
		if GameManager.ui_blocking_input:
			_departure_hold = 0.0
			_set_prompt_text("")
			_hide_progress()
			return
		if Input.is_action_pressed("interact"):
			_departure_hold += delta
			var ratio := clampf(_departure_hold / DEPARTURE_HOLD_TIME, 0.0, 1.0)
			_set_prompt_text("Hold E  Depart", prompt_pos)
			_show_progress(ratio, "Departing  %d%%" % int(round(ratio * 100.0)))
			if ratio >= 1.0:
				_hide_progress()
				_begin_expedition()
		else:
			_departure_hold = 0.0
			_set_prompt_text("")
			_hide_progress()
	else:
		_departure_hold = 0.0
		_set_prompt_text("")


func _find_nearby_point() -> String:
	if _player == null:
		return ""
	var warehouse := _get_point("warehouse")
	var departure := _get_point("departure")
	if warehouse != null and _player.global_position.distance_to(warehouse.global_position) <= INTERACTION_RANGE:
		return "warehouse"
	if departure != null and _player.global_position.distance_to(departure.global_position) <= INTERACTION_RANGE:
		return "departure"
	return ""


func _get_point(point_name: String) -> Node3D:
	match point_name:
		"warehouse":
			return get_node_or_null("WarehousePoint") as Node3D
		"departure":
			return get_node_or_null("DeparturePoint") as Node3D
	return null


func _begin_expedition() -> void:
	_departure_hold = 0.0
	_set_prompt_text("")
	GameManager.begin_expedition()


# ---------------------------------------------------------------------------
# Collision management
# ---------------------------------------------------------------------------

func _set_collision_active(active: bool) -> void:
	for child in get_children():
		if child is CollisionObject3D:
			var body := child as CollisionObject3D
			if active:
				body.collision_layer = int(body.get_meta("_saved_collision_layer", body.collision_layer))
			else:
				if body.collision_layer > 0:
					body.set_meta("_saved_collision_layer", body.collision_layer)
				body.collision_layer = 0


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _set_prompt_text(text: String, world_position: Vector3 = Vector3.INF) -> void:
	if _hud != null and _hud.has_method("set_prompt_text"):
		_hud.set_prompt_text(text)
	if _world_prompt == null:
		return
	_world_prompt.text = text
	_world_prompt.visible = text.strip_edges() != ""
	if _world_prompt.visible:
		var target_pos := world_position
		if target_pos == Vector3.INF:
			target_pos = _player.global_position + Vector3(0.0, 0.0, 2.8) if _player != null else Vector3.ZERO
		var y := 0.09 if world_position == Vector3.INF else maxf(target_pos.y + 0.01, 0.09)
		_world_prompt.global_position = Vector3(target_pos.x, y, target_pos.z)


func _show_progress(ratio: float, text: String = "") -> void:
	if _hud != null and _hud.has_method("show_hold_progress"):
		_hud.show_hold_progress(ratio, text)


func _hide_progress() -> void:
	if _hud != null and _hud.has_method("hide_hold_progress"):
		_hud.hide_hold_progress()
