# noise_manager.gd
# Autoload singleton for sound level broadcasting and alert updates.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Node

enum Level {
	NONE = 0,
	LOW = 20,
	MEDIUM = 50,
	HIGH = 80,
	GLOBAL = 999,
}

const RANGE_MAP := {
	Level.LOW: 8.0,
	Level.MEDIUM: 18.0,
	Level.HIGH: 36.0,
	Level.GLOBAL: 99999.0,
}


func emit_noise(origin: Variant, level: Level) -> void:
	var range_val: float = RANGE_MAP.get(level, 0.0)
	if range_val <= 0.0:
		return
	var noise_value := float(level)
	var origin_pos: Vector3 = _to_noise_position(origin)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		var enemy_pos: Vector3 = _to_noise_position(enemy)
		var dist: float = origin_pos.distance_to(enemy_pos)
		if dist > range_val:
			continue
		var attenuation: float = 1.0 - (dist / range_val)
		if enemy.has_method("receive_noise"):
			enemy.receive_noise(noise_value * attenuation)


func _to_noise_position(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Node3D:
		return value.global_position
	return Vector3.ZERO
