# player_health.gd
# 生命系统：管理玩家 HP、受击侵蚀增加、血量耗尽触发 DEAD 局状态。
# Player HP, invulnerability frames, damage erosion, healing, and death state.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node

signal damaged
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
	GameManager.add_erosion(GameManager.HIT_EROSION_AMOUNT)
	health_changed.emit(current_hp, max_hp)
	damaged.emit()
	if current_hp <= 0.0:
		_die()


func reset_health() -> void:
	current_hp = max_hp
	iframe_timer = 0.0
	health_changed.emit(current_hp, max_hp)


func heal(amount: float) -> void:
	if current_hp <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	health_changed.emit(current_hp, max_hp)


func _die() -> void:
	died.emit()
	GameManager.set_state(GameManager.State.DEAD)
