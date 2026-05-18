# player.gd
# 主角控制脚本：360° 移动 + 冲刺 + 鼠标瞄准
# 挂载在 Player (CharacterBody2D) 上
# [AI-ASSISTED] 2026-05-19 - 按 docs/rules.md 规范化内部状态命名
extends CharacterBody2D

# ----- 移动参数（implementation.md §13）-----
@export var base_speed: float = 300.0
@export var sprint_multiplier: float = 1.6
@export var sprint_duration: float = 1.0
@export var sprint_cooldown: float = 3.0

# ----- 内部状态 -----
var _sprint_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _is_sprinting: bool = false

@onready var gun_pivot: Node2D = $GunPivot


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	# 移动输入（自动归一化对角线）
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed: float = base_speed * (sprint_multiplier if _is_sprinting else 1.0)
	velocity = input * speed
	move_and_slide()

	# 鼠标瞄准：GunPivot 旋转指向鼠标
	gun_pivot.look_at(get_global_mouse_position())

	# 同步到 GameManager
	GameManager.player_position = global_position

	# 冲刺计时
	if _is_sprinting:
		_sprint_timer -= delta
		if _sprint_timer <= 0.0:
			_is_sprinting = false
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sprint") and _cooldown_timer <= 0.0 and not _is_sprinting:
		_is_sprinting = true
		_sprint_timer = sprint_duration
		_cooldown_timer = sprint_cooldown
		NoiseManager.emit_noise(global_position, NoiseManager.Level.MEDIUM)
		return

	# 数字键 1-8 主动使用对应槽位的物品
	for i in 8:
		if event.is_action_pressed("use_slot_%d" % (i + 1)):
			_use_inventory_slot(i)
			return


# 提供给冲刺 UI 查询冷却进度（0.0 = 可用，1.0 = 刚触发）
func get_sprint_cooldown_ratio() -> float:
	if sprint_cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_timer / sprint_cooldown, 0.0, 1.0)


func _use_inventory_slot(idx: int) -> void:
	var inv: Node = get_node_or_null("Inventory")
	if inv != null and inv.has_method("use_slot"):
		inv.use_slot(idx)
