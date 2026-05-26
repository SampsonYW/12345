# enemy_3d.gd
# 3D 敌人基类：巡逻型主动游走追击，休眠型靠噪音/受击唤醒，近身攻击 PlayerHealth。
# [AI-ASSISTED] 2026-05-19 - 全 3D 重写敌人占位逻辑
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
# [AI-ASSISTED] 2026-05-23 — 追击/信号弹寻路升级为 A* 网格寻路（绕墙/拐角）
# [AI-ASSISTED] 2026-05-24 — 寻路迁移到 Godot NavigationServer3D + NavigationAgent3D，删除自建 A*
# [AI-ASSISTED] 2026-05-24 — 敌人AI性能优化：寻路/视线/billboard 节流
# [AI-ASSISTED] 2026-05-24 — 巡逻寻路改用 NavigationAgent3D，修复撞墙/摩擦
# [AI-ASSISTED] 2026-05-26 — Sprite3D 接入美术 2D 立绘（巡逻型/休眠型按 enemy_type 选贴图）
extends CharacterBody3D

signal died(enemy: CharacterBody3D)

enum EnemyType { PATROL, DORMANT }
enum State { PATROL, SLEEP, CHASE, ATTACK }

const GAME_STATE_RUNNING := 1
const GAME_STATE_EXTRACTING := 2
const FALLBACK_EROSION_STAT_MULTIPLIER := [1.0, 1.0, 1.1, 1.2, 1.35]
const ALERT_BAR_WIDTH := 1.0
const ALERT_BAR_HEIGHT := 0.08
const ALERT_BAR_DEPTH := 0.04
const HP_BAR_WIDTH := 1.0
const HP_BAR_HEIGHT := 0.08
const HP_BAR_DEPTH := 0.04
const NAV_UPDATE_INTERVAL := 0.2
const VISION_CHECK_INTERVAL := 0.15

const ENEMY_TEXTURES := {
	EnemyType.PATROL: "res://assets/sprites/enemies/enemy_patrol_base.png",
	EnemyType.DORMANT: "res://assets/sprites/enemies/enemy_sleeper_base.png",
}

@export var alert_threshold: float = 100.0
@export var decay_rate: float = 5.0
@export var base_hp: float = 40.0
@export var base_damage: float = 15.0
@export var enemy_type: EnemyType = EnemyType.PATROL
@export var patrol_speed: float = 2.2
@export var chase_speed: float = 4.2
@export var patrol_radius: float = 5.0
@export var view_angle: float = 60.0
@export var view_range: float = 8.0
@export var vision_obstacle_mask: int = 4

@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.0

var _current_alert: float = 0.0
var _is_awake: bool = false
var _erosion_tier: int = 0
var _current_hp: float = 0.0
var _state: State = State.SLEEP
var _attack_timer: float = 0.0
var _home_position: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _player_cache: Node3D = null
var _game_manager_cache: Node = null
var _has_signal_focus: bool = false
var _signal_focus_position: Vector3 = Vector3.ZERO

var _nav_agent: NavigationAgent3D = null
var _nav_update_timer: float = 0.0
var _cached_nav_direction: Vector3 = Vector3.ZERO
var _vision_check_timer: float = 0.0
var _cached_can_see_player: bool = false
var _vision_ever_checked: bool = false
var _vision_cone: MeshInstance3D = null

# 受击闪白
var _body_mesh: MeshInstance3D = null
var _original_material: Material = null
var _hit_flash_timer: float = 0.0
var _sprite: Sprite3D = null
const HIT_FLASH_DURATION := 0.1


func _ready() -> void:
	add_to_group("enemies")

	_body_mesh = get_node_or_null("BodyVisual") as MeshInstance3D
	if _body_mesh != null:
		_original_material = _body_mesh.material_override
		_body_mesh.visible = false
	_init_sprite()
	if enemy_type == EnemyType.PATROL:
		_create_vision_cone()
	_nav_agent = get_node_or_null("NavAgent") as NavigationAgent3D
	_home_position = global_position
	_state = State.PATROL if enemy_type == EnemyType.PATROL else State.SLEEP
	_is_awake = false
	_erosion_tier = _get_erosion_tier()
	_current_hp = get_scaled_hp()
	_pick_patrol_target()
	# 错开各敌人的定时器，分散同帧计算压力
	_nav_update_timer = randf() * NAV_UPDATE_INTERVAL
	_vision_check_timer = randf() * VISION_CHECK_INTERVAL


func _init_sprite() -> void:
	_sprite = get_node_or_null("Sprite") as Sprite3D
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite"
		# 巡逻 ≈ 1292×1551, 休眠 ≈ 1756×1286
		# pixel_size 0.0013 → 巡逻 1.68×2.02m / 休眠 2.28×1.67m，匹配 1.8-2.2m 敌人身高
		_sprite.position = Vector3(0, 1.0, 0)
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.pixel_size = 0.0013
		_sprite.shaded = false
		_sprite.transparent = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		add_child(_sprite)
	var path: String = ENEMY_TEXTURES.get(enemy_type, "")
	if path != "" and ResourceLoader.exists(path):
		_sprite.texture = load(path)


func _process(delta: float) -> void:
	if not _is_awake and _current_alert > 0.0:
		_current_alert = maxf(0.0, _current_alert - decay_rate * delta)
	# 受击闪白计时
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0 and _sprite != null:
			_sprite.modulate = Color.WHITE


func _physics_process(delta: float) -> void:
	if not _is_gameplay_active():
		velocity = Vector3.ZERO
		return
	var player := _get_player()
	if player == null:
		if _has_signal_focus:
			_update_signal_focus(delta)
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		global_position.y = 0.0
		return

	match _state:
		State.PATROL:
			_update_patrol(player, delta)
		State.SLEEP:
			velocity = Vector3.ZERO
		State.CHASE:
			_update_chase(player, delta)
		State.ATTACK:
			_update_attack(delta, player)
	move_and_slide()
	global_position.y = 0.0


func get_enemy_kind() -> String:
	return "patrol" if enemy_type == EnemyType.PATROL else "dormant"


func is_awake() -> bool:
	return _is_awake


func get_alert_ratio() -> float:
	if alert_threshold <= 0.0:
		return 1.0 if _current_alert > 0.0 else 0.0
	return clampf(_current_alert / alert_threshold, 0.0, 1.0)


func get_hp_ratio() -> float:
	var max_hp := get_scaled_hp()
	if max_hp <= 0.0:
		return 0.0
	return clampf(_current_hp / max_hp, 0.0, 1.0)


func get_signal_focus_position() -> Vector3:
	return _signal_focus_position


func get_ai_state_name() -> String:
	match _state:
		State.PATROL:
			return "PATROL"
		State.SLEEP:
			return "SLEEP"
		State.CHASE:
			return "CHASE"
		State.ATTACK:
			return "ATTACK"
	return "UNKNOWN"


func get_scaled_hp() -> float:
	return base_hp * FALLBACK_EROSION_STAT_MULTIPLIER[_erosion_tier]


func get_scaled_damage() -> float:
	return base_damage * FALLBACK_EROSION_STAT_MULTIPLIER[_erosion_tier]


func set_erosion_tier(tier: int) -> void:
	_erosion_tier = clampi(tier, 0, FALLBACK_EROSION_STAT_MULTIPLIER.size() - 1)
	_current_hp = get_scaled_hp()


func receive_noise(value: float) -> void:
	if _is_awake:
		return
	_current_alert = maxf(0.0, _current_alert + value)
	if _current_alert >= alert_threshold:
		force_awaken()


func force_awaken() -> void:
	_is_awake = true
	_current_alert = alert_threshold
	_state = State.CHASE


func take_damage(amount: float, from_player: bool = true) -> void:
	_current_hp -= amount
	# 受击闪白
	if _sprite != null:
		_sprite.modulate = Color(2.4, 2.4, 2.4, 1.0)
		_hit_flash_timer = HIT_FLASH_DURATION
	if from_player:
		force_awaken()
	if _current_hp <= 0.0:
		_die()


func react_to_signal_flare(origin: Vector3, extraction_position: Vector3 = Vector3.ZERO) -> void:
	# 信号弹位置由 extraction 广播，敌人记录此位置用于向信号弹移动
	var base := extraction_position if extraction_position != Vector3.ZERO else origin
	# 每个敌人在信号弹周围随机散布，避免扎堆
	var angle := randf() * TAU
	var spread := randf_range(3.0, 8.0)
	_signal_focus_position = base + Vector3(cos(angle) * spread, 0.0, sin(angle) * spread)
	_signal_focus_position.y = global_position.y
	_has_signal_focus = true
	# 唤醒由 player_3d.gd 中 NoiseManager.emit_noise(GLOBAL) 通过 receive_noise() 完成
	# 已觉醒的敌人也更新信号弹目标，使其向信号弹位置移动
	if _is_awake and _state != State.ATTACK:
		_state = State.CHASE


func _update_patrol(player: Node3D, _delta: float) -> void:
	if can_see_player(player):
		force_awaken()
		return

	# 用 NavigationAgent3D 判断是否到达当前巡逻点
	if _nav_agent != null and _nav_agent.is_navigation_finished():
		_pick_patrol_target()
	var to_target: Vector3 = _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.5:
		_pick_patrol_target()

	_nav_move_toward(_patrol_target, patrol_speed)


func _update_chase(player: Node3D, delta: float) -> void:
	if _has_signal_focus:
		# 信号弹阶段：优先追踪玩家，但定期更新信号弹位置
		# 如果能看到玩家则追玩家，否则向信号弹位置移动
		if can_see_player(player):
			_has_signal_focus = false
		else:
			_update_signal_focus(delta)
			return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist <= attack_range:
		_state = State.ATTACK
		velocity = Vector3.ZERO
		return

	_nav_move_toward(player.global_position, chase_speed)


func _update_signal_focus(_delta: float) -> void:
	var to_focus: Vector3 = _signal_focus_position - global_position
	to_focus.y = 0.0
	var dist_to_signal: float = to_focus.length()
	if dist_to_signal <= 1.5:
		# 到达信号弹附近后：驻守此区域，靠视觉发现玩家后才转入追击
		_has_signal_focus = false
		_state = State.PATROL
		_home_position = _signal_focus_position
		# 休眠型天生盲视（view_range=0），驻守时赋予临时警戒视野
		if enemy_type == EnemyType.DORMANT and view_range <= 0.0:
			view_range = 4.0
		_pick_patrol_target()
		velocity = Vector3.ZERO
		return

	var move_speed := maxf(chase_speed, patrol_speed)
	_nav_move_toward(_signal_focus_position, move_speed)


## 用 NavigationAgent3D 向目标移动。设置 target_position 让 nav server 算路径，
## 沿 get_next_path_position() 走 waypoint。NavMesh 几何精确，
## 不需要手写避障——障碍物（高/矮/箱子）在 navmesh bake 时已被排除。
## 节流：每 NAV_UPDATE_INTERVAL 秒更新一次路径查询，中间帧沿缓存方向移动。
func _nav_move_toward(target_pos: Vector3, speed: float) -> void:
	if _nav_agent == null:
		velocity = Vector3.ZERO
		return
	_nav_update_timer -= get_physics_process_delta_time()
	if _nav_update_timer <= 0.0:
		_nav_update_timer = NAV_UPDATE_INTERVAL
		_nav_agent.target_position = target_pos
		if not _nav_agent.is_navigation_finished():
			var next_pos: Vector3 = _nav_agent.get_next_path_position()
			var dir: Vector3 = next_pos - global_position
			dir.y = 0.0
			if dir.length_squared() > 0.01:
				_cached_nav_direction = dir.normalized()
			else:
				_cached_nav_direction = Vector3.ZERO
		else:
			_cached_nav_direction = Vector3.ZERO
	if _cached_nav_direction == Vector3.ZERO:
		velocity = Vector3.ZERO
		return
	velocity = _cached_nav_direction * speed
	_face_direction(_cached_nav_direction)


func _update_attack(delta: float, player: Node3D) -> void:
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > attack_range * 1.4:
		_state = State.CHASE
		return
	velocity = Vector3.ZERO
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_deal_damage(player)
		_attack_timer = attack_cooldown
	_face_direction(to_player)


func _move_flat(direction: Vector3, speed: float) -> void:
	if direction.length_squared() <= 0.01:
		velocity = Vector3.ZERO
	else:
		var dir := direction.normalized()
		velocity = dir * speed
		_face_direction(dir)


func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		look_at(global_position + direction.normalized(), Vector3.UP)


func _pick_patrol_target() -> void:
	var offset := Vector3(
		randf_range(-patrol_radius, patrol_radius),
		0.0,
		randf_range(-patrol_radius, patrol_radius)
	)
	var candidate := _home_position + offset
	# 将候选点吸附到 NavMesh 上，避免落在墙内
	# headless 模式下 NavigationServer 可能尚未同步，跳过吸附降级为原始坐标
	if _nav_agent != null:
		var map_rid := _nav_agent.get_navigation_map()
		if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0:
			candidate = NavigationServer3D.map_get_closest_point(map_rid, candidate)
	_patrol_target = candidate
	_patrol_target.y = 0.0


func _deal_damage(player: Node3D) -> void:
	var ph: Node = player.get_node_or_null("PlayerHealth")
	if ph and ph.has_method("take_damage"):
		ph.take_damage(get_scaled_damage())



func can_see_player(player: Node3D) -> bool:
	if player == null or view_range <= 0.0:
		return false
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > view_range:
		_cached_can_see_player = false
		return false
	if distance <= 0.01:
		return true

	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() <= 0.01:
		facing = Vector3.FORWARD
	var angle := rad_to_deg(facing.normalized().angle_to(to_player.normalized()))
	if angle > view_angle * 0.5:
		_cached_can_see_player = false
		return false
	# 射线检测部分节流；首次调用强制检测，不做节流
	_vision_check_timer -= get_physics_process_delta_time()
	if _vision_check_timer <= 0.0 or not _vision_ever_checked:
		_vision_check_timer = VISION_CHECK_INTERVAL
		_cached_can_see_player = _has_clear_line_to_player(player)
		_vision_ever_checked = true
	return _cached_can_see_player


## 强制下次 can_see_player 调用做完整射线检测（绕过节流）。
func reset_vision_cache() -> void:
	_vision_check_timer = 0.0


func _has_clear_line_to_player(player: Node3D) -> bool:
	if vision_obstacle_mask == 0:
		return true
	var world := get_world_3d()
	if world == null:
		return true
	var space_state := world.direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.7,
		player.global_position + Vector3.UP * 0.7,
		vision_obstacle_mask
	)
	query.exclude = [get_rid()]
	if player is CollisionObject3D:
		query.exclude.append((player as CollisionObject3D).get_rid())
	return space_state.intersect_ray(query).is_empty()


## 检测到某个世界坐标点是否有清晰的直线视野（无障碍物遮挡）
func _has_clear_line_to_point(target_pos: Vector3) -> bool:
	if vision_obstacle_mask == 0:
		return true
	var world := get_world_3d()
	if world == null:
		return true
	var space_state := world.direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.7,
		target_pos + Vector3.UP * 0.7,
		vision_obstacle_mask
	)
	query.exclude = [get_rid()]
	return space_state.intersect_ray(query).is_empty()


func _get_player() -> Node3D:
	if _player_cache == null or not is_instance_valid(_player_cache):
		_player_cache = get_tree().get_first_node_in_group("player") as Node3D
	return _player_cache


func _get_game_manager() -> Node:
	if _game_manager_cache == null or not is_instance_valid(_game_manager_cache):
		var tree := get_tree()
		if tree != null:
			_game_manager_cache = tree.root.get_node_or_null("GameManager")
	return _game_manager_cache


func _get_erosion_tier() -> int:
	var manager := _get_game_manager()
	if manager != null and manager.has_method("get_erosion_tier"):
		return manager.get_erosion_tier()
	return 0


func _is_gameplay_active() -> bool:
	var manager := _get_game_manager()
	if manager == null:
		return true
	var state: int = manager.get("current_state")
	return state == GAME_STATE_RUNNING or state == GAME_STATE_EXTRACTING





## 让血条和警戒条始终面向摄像机（billboard 效果）
## 使用 top_level 让 bar 脱离敌人旋转，直接设置全局位置跟随敌人 +
## 全局朝向对齐摄像机 basis，保证在斜俯视正交摄像机下始终正面可见。
func _create_vision_cone() -> void:
	if view_range <= 0.0:
		return
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Center vertex (apex of the fan), slightly opaque
	st.set_color(Color(1.0, 0.35, 0.12, 0.25))
	st.set_uv(Vector2(0.5, 0.0))
	st.add_vertex(Vector3.ZERO)

	var half_angle := deg_to_rad(view_angle * 0.5)
	var segments := 20
	for i in range(segments + 1):
		var a := lerpf(-half_angle, half_angle, float(i) / float(segments))
		var x := sin(a) * view_range
		var z := -cos(a) * view_range
		# Edge vertices fade to fully transparent
		st.set_color(Color(1.0, 0.35, 0.12, 0.0))
		st.set_uv(Vector2(float(i) / float(segments), 1.0))
		st.add_vertex(Vector3(x, 0.0, z))

	# Fan triangles: center (0) + edge_i + edge_{i+1}
	for i in range(segments):
		st.add_index(0)
		st.add_index(i + 1)
		st.add_index(i + 2)

	st.generate_normals()
	st.commit(mesh)

	_vision_cone = MeshInstance3D.new()
	_vision_cone.name = "VisionCone"
	_vision_cone.mesh = mesh
	_vision_cone.position = Vector3(0.0, 0.05, 0.0)  # Slightly above ground to avoid z-fighting

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.12, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.08, 1.0)
	mat.emission_energy_multiplier = 0.3
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	_vision_cone.material_override = mat
	_vision_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_vision_cone)





func _die() -> void:
	died.emit(self)
	_spawn_death_vfx()
	var manager := _get_game_manager()
	if manager != null and manager.has_method("register_kill"):
		manager.register_kill()
	queue_free()


func _spawn_death_vfx() -> void:
	const DEATH_TEXTURE := preload("res://assets/sprites/effects/effect_enemy_destroyed.png")
	const DEATH_VFX_DURATION := 0.45
	var parent := get_tree().current_scene
	if parent == null:
		return
	var sprite := Sprite3D.new()
	sprite.texture = DEATH_TEXTURE
	sprite.position = global_position + Vector3(0, 1.0, 0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# PNG ≈ 1325×1232；pixel_size 0.0015 → ≈ 1.99×1.85m
	sprite.pixel_size = 0.0015
	sprite.shaded = false
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	parent.add_child(sprite)
	parent.get_tree().create_timer(DEATH_VFX_DURATION).timeout.connect(Callable(sprite, "queue_free"))
