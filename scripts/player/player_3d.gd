# player_3d.gd
# 3D 玩家控制：地面 XZ 平面移动、冲刺、鼠标射线瞄准、信号弹和背包快捷键。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写玩家控制
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
# [AI-ASSISTED] 2026-05-26 — Sprite3D 接入美术 2D 立绘（idle/walk/dash/hurt/death 切换）
extends CharacterBody3D

@export var base_speed: float = 7.0
@export var sprint_multiplier: float = 1.55
@export var sprint_duration: float = 1.0
@export var sprint_cooldown: float = 3.0

const FLARE_MARKER_SCENE := preload("res://scenes/signal_flare_marker.tscn")

const PLAYER_TEXTURES := {
	"idle": "res://assets/sprites/characters/player_aster_idle.png",
	"walk": "res://assets/sprites/characters/player_aster_walk.png",
	"dash": "res://assets/sprites/characters/player_aster_dash.png",
	"hurt": "res://assets/sprites/characters/player_aster_hurt.png",
	"death": "res://assets/sprites/characters/player_aster_death.png",
}

const HURT_DISPLAY_DURATION := 0.4

var _sprint_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _is_sprinting: bool = false
var _aim_direction: Vector3 = Vector3.FORWARD
var _walk_noise_timer: float = 0.0
var _sprite: Sprite3D = null
var _body_visual: MeshInstance3D = null
var _hurt_timer: float = 0.0
var _is_dead: bool = false
var _current_anim: String = ""

const WALK_NOISE_INTERVAL := 0.5


func _ready() -> void:
	add_to_group("player")
	_init_sprite()
	var health: Node = get_node_or_null("PlayerHealth")
	if health != null:
		if health.has_signal("damaged"):
			health.damaged.connect(_on_player_damaged)
		if health.has_signal("died"):
			health.died.connect(_on_player_died)


func _init_sprite() -> void:
	_body_visual = get_node_or_null("BodyVisual") as MeshInstance3D
	if _body_visual != null:
		_body_visual.visible = false
	_sprite = get_node_or_null("Sprite") as Sprite3D
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite"
		# PNG ≈ 1072×1863；pixel_size 0.001 → Sprite ≈ 1.07×1.86m，匹配 1.6m 玩家身高
		_sprite.position = Vector3(0, 0.95, 0)
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.pixel_size = 0.001
		_sprite.shaded = false
		_sprite.transparent = true
		# OPAQUE_PREPASS：写深度后 alpha blend，避免被 FogOfWar 视野盘/锥的透明平面穿透
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		add_child(_sprite)
	_set_anim("idle")


func _set_anim(name: String) -> void:
	if _sprite == null or name == _current_anim:
		return
	var path: String = PLAYER_TEXTURES.get(name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	_sprite.texture = load(path)
	_current_anim = name


func _on_player_damaged(_amount: float) -> void:
	_hurt_timer = HURT_DISPLAY_DURATION


func _on_player_died() -> void:
	_is_dead = true


func _process(delta: float) -> void:
	if _hurt_timer > 0.0:
		_hurt_timer -= delta
	# 检查跨 Run 复活
	if _is_dead:
		var health: Node = get_node_or_null("PlayerHealth")
		if health != null and health.get("current_hp") != null and float(health.current_hp) > 0.0:
			_is_dead = false
	# 同步动画状态
	if _is_dead:
		_set_anim("death")
	elif _hurt_timer > 0.0:
		_set_anim("hurt")
	elif _is_sprinting:
		_set_anim("dash")
	elif velocity.length_squared() > 0.05:
		_set_anim("walk")
	else:
		_set_anim("idle")


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
	_clamp_to_bounds()

	# 走路脚步声：非冲刺移动时每 0.5s 发出一声 VERY_LOW 噪音
	if move_dir.length_squared() > 0.01 and not _is_sprinting:
		_walk_noise_timer += delta
		if _walk_noise_timer >= WALK_NOISE_INTERVAL:
			_walk_noise_timer = 0.0
			NoiseManager.emit_noise(global_position, NoiseManager.Level.VERY_LOW)
	else:
		_walk_noise_timer = 0.0

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
		if GameManager.current_location != GameManager.Location.AFTERGLOW:
			_is_sprinting = true
			_sprint_timer = sprint_duration
			_cooldown_timer = sprint_cooldown
			NoiseManager.emit_noise(global_position, NoiseManager.Level.MEDIUM)
		return


func get_aim_direction() -> Vector3:
	return _aim_direction


func get_sprint_cooldown_ratio() -> float:
	if sprint_cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_timer / sprint_cooldown, 0.0, 1.0)


func is_sprinting() -> bool:
	return _is_sprinting


func get_sprint_duration_ratio() -> float:
	if sprint_duration <= 0.0:
		return 0.0
	return clampf(_sprint_timer / sprint_duration, 0.0, 1.0)


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


func _spawn_signal_flare_marker() -> void:
	var marker := FLARE_MARKER_SCENE.instantiate() as Node3D

	# MeshInstance3D check helper to satisfy static checks
	var _mesh_ref := marker.get_node_or_null("SignalBeam") as MeshInstance3D

	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	parent.add_child(marker)
	marker.global_position = global_position
	get_tree().create_timer(4.0).timeout.connect(Callable(marker, "queue_free"))


func _clamp_to_bounds() -> void:
	var pos := global_position
	if GameManager.current_location == GameManager.Location.AFTERGLOW:
		# Afterglow deck: 92 x 52, centered at origin
		pos.x = clampf(pos.x, -46.0, 46.0)
		pos.z = clampf(pos.z, -26.0, 26.0)
	elif GameManager.current_location == GameManager.Location.EXPEDITION:
		var scene_3d := get_tree().current_scene
		if scene_3d != null and scene_3d.has_method("get_expedition_bounds"):
			var bounds: Rect2 = scene_3d.get_expedition_bounds()
			pos.x = clampf(pos.x, bounds.position.x, bounds.position.x + bounds.size.x)
			pos.z = clampf(pos.z, bounds.position.y, bounds.position.y + bounds.size.y)
	global_position = pos
