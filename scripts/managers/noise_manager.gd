# noise_manager.gd
# Autoload singleton for sound level broadcasting and alert updates.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node

enum Level {
	NONE = 0,
	VERY_LOW = 10,
	LOW = 20,
	MEDIUM = 50,
	HIGH = 70,
	GLOBAL = 120,
}

## 半衰距离（衰减至 0.5 的距离），用平方反比公式：atten = 1/(1+(d/half)²)，无硬截断
const HALF_DISTANCE := {
	Level.VERY_LOW: 3.0,
	Level.LOW: 5.0,
	Level.MEDIUM: 12.0,
	Level.HIGH: 24.0,
	Level.GLOBAL: 150.0,
}

## GLOBAL 级别信号弹：多脉冲冲击波，让远处敌人延迟几秒才醒
const GLOBAL_PULSE_COUNT := 5
const GLOBAL_PULSE_INTERVAL := 0.5


func emit_noise(origin: Variant, level: Level) -> void:
	var half_dist: float = HALF_DISTANCE.get(level, 0.0)
	if half_dist <= 0.0:
		return
	var noise_value := float(level)
	var origin_pos: Vector3 = _to_noise_position(origin)

	if level == Level.GLOBAL:
		_emit_global_pulses(origin_pos, noise_value, half_dist)
	else:
		_emit_single(origin_pos, noise_value, half_dist)


func _emit_single(origin_pos: Vector3, noise_value: float, half_dist: float) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var enemy_pos: Vector3 = _to_noise_position(enemy)
		var dist: float = origin_pos.distance_to(enemy_pos)
		var ratio := dist / half_dist
		var attenuation: float = 1.0 / (1.0 + ratio * ratio)
		if enemy.has_method("receive_noise"):
			enemy.receive_noise(noise_value * attenuation)


func _emit_global_pulses(origin_pos: Vector3, noise_value: float, half_dist: float) -> void:
	for i in GLOBAL_PULSE_COUNT:
		_emit_single(origin_pos, noise_value, half_dist)
		if i < GLOBAL_PULSE_COUNT - 1:
			await get_tree().create_timer(GLOBAL_PULSE_INTERVAL).timeout


func _to_noise_position(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Node3D:
		return value.global_position
	return Vector3.ZERO
