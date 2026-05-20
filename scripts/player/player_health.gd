# player_health.gd
# Player HP, invulnerability frames, damage erosion, healing, and death state.
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


func heal(amount: float) -> void:
	if current_hp <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	health_changed.emit(current_hp, max_hp)


func _die() -> void:
	died.emit()
	GameManager.set_state(GameManager.State.DEAD)
