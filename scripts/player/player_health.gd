# player_health.gd
# 玩家生命系统：HP 条、受伤 (含无敌帧 0.5s + 触发侵蚀跳升)、能量电池回复
# 死亡 → GameManager.set_state(DEAD)
# 挂在 Player 下的 PlayerHealth Node 上
extends Node

signal damaged                              # 实际受伤（非 iframe 阻挡）后触发
signal died
signal health_changed(current: float, maximum: float)

@export var max_hp: float = 100.0
@export var iframe_duration: float = 0.5

var current_hp: float = 0.0
var iframe_timer: float = 0.0


func _ready() -> void:
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)


func _process(delta: float) -> void:
	if iframe_timer > 0.0:
		iframe_timer -= delta


func take_damage(amount: float) -> void:
	if iframe_timer > 0.0:
		return
	if current_hp <= 0.0:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	iframe_timer = iframe_duration
	# 受击侵蚀跳升（design.md §5.4 / §11.1）
	GameManager.add_erosion(GameManager.HIT_EROSION_AMOUNT)
	health_changed.emit(current_hp, max_hp)
	damaged.emit()
	if current_hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	if current_hp <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	health_changed.emit(current_hp, max_hp)


func _die() -> void:
	died.emit()
	GameManager.set_state(GameManager.State.DEAD)
