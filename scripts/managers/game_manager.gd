# game_manager.gd
# Autoload singleton: 全局游戏状态、侵蚀、计时器
# 在 project.godot 中注册为 Autoload (GameManager)
extends Node

# ----- 信号 -----
signal state_changed(new_state: State)
signal erosion_changed(value: float)
signal erosion_tier_changed(tier: int)

# ----- 枚举 -----
enum State { PREPARING, RUNNING, EXTRACTING, SUCCESS, DEAD }

# ----- 常量（design.md §15 / implementation.md §13）-----
const EROSION_RATE := 0.0167       # 约每 60 秒 +1%
const HIT_EROSION_AMOUNT := 2.5     # 受击跳升 %
const PURIFIER_REDUCTION := 17.5    # 净化剂降低 %

# 侵蚀阶梯影响表（implementation.md §6.1）
const EROSION_STAT_MULTIPLIER := [1.0, 1.0, 1.1, 1.2, 1.35]       # 敌人 HP/伤害倍率
const EROSION_SPAWN_INTERVAL_MULTIPLIER := [1.0, 1.0, 0.85, 0.7, 0.5]  # 刷怪间隔乘数
const EROSION_DORMANT_RATIO := [0.0, 0.0, 0.15, 0.3, 0.5]          # 休眠型出现概率

# ----- 局内状态 -----
var current_state: State = State.PREPARING
var elapsed_time: float = 0.0
var player_erosion: float = 0.0
var max_weight: float = 50.0
var max_erosion: float = 100.0
var player_position: Vector2 = Vector2.ZERO
var kill_count: int = 0

var _last_tier: int = 0


func _process(delta: float) -> void:
	if current_state == State.RUNNING or current_state == State.EXTRACTING:
		elapsed_time += delta
		add_erosion(EROSION_RATE * delta * 100.0)
		# 注：EROSION_RATE 单位是「每秒百分点」(0.0167 ≈ 1%/60s)，×100 换算成 0-100 区间


func start_run() -> void:
	# 由 Game 场景在 _ready() 中调用，开始一局
	reset_run()
	set_state(State.RUNNING)


func reset_run() -> void:
	elapsed_time = 0.0
	player_erosion = 0.0
	kill_count = 0
	_last_tier = 0
	erosion_changed.emit(player_erosion)


func set_state(new_state: State) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state)
	match new_state:
		State.SUCCESS, State.DEAD:
			# TODO Day 5：跳转结算场景
			# get_tree().change_scene_to_file("res://scenes/result_screen.tscn")
			pass


func add_erosion(amount: float) -> void:
	var prev := player_erosion
	player_erosion = clampf(player_erosion + amount, 0.0, max_erosion)
	if player_erosion != prev:
		erosion_changed.emit(player_erosion)
		_check_tier_change()


func reduce_erosion(amount: float) -> void:
	add_erosion(-amount)


func get_erosion_tier() -> int:
	# 返回侵蚀阶梯 0-4（参考 design.md §5.4）
	# 0: 0-25%, 1: 25-50%, 2: 50-75%, 3: 75-99%, 4: 100%
	if player_erosion < 25.0: return 0
	if player_erosion < 50.0: return 1
	if player_erosion < 75.0: return 2
	if player_erosion < 100.0: return 3
	return 4


func _check_tier_change() -> void:
	var tier := get_erosion_tier()
	if tier != _last_tier:
		_last_tier = tier
		erosion_tier_changed.emit(tier)


func register_kill() -> void:
	kill_count += 1
