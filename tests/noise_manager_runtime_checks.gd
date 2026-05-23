# noise_manager_runtime_checks.gd
# Runtime checks for 3D-scale noise ranges and distance attenuation.
extends SceneTree

class ProbeEnemy:
	extends Node3D

	var received_noise: float = 0.0

	func _ready() -> void:
		add_to_group("enemies")

	func receive_noise(value: float) -> void:
		received_noise += value


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = root.get_node_or_null("NoiseManager")
	_expect(manager != null, "NoiseManager autoload should exist")
	if manager == null:
		_finish([])
		return

	var near_enemy := _make_probe(Vector3(4.0, 0.0, 0.0))
	var mid_enemy := _make_probe(Vector3(14.0, 0.0, 0.0))
	var far_enemy := _make_probe(Vector3(34.0, 0.0, 0.0))
	var enemies := [near_enemy, mid_enemy, far_enemy]

	manager.emit_noise(Vector3.ZERO, manager.Level.LOW)
	_expect(near_enemy.received_noise > 0.0, "LOW noise should reach nearby enemies")
	_expect(mid_enemy.received_noise <= 0.0, "LOW noise should not cover most of the 3D map")
	_expect(far_enemy.received_noise <= 0.0, "LOW noise should not reach far enemies")

	_reset_probes(enemies)
	manager.emit_noise(Vector3.ZERO, manager.Level.MEDIUM)
	_expect(near_enemy.received_noise > mid_enemy.received_noise, "MEDIUM noise should attenuate with distance")
	_expect(mid_enemy.received_noise > 0.0, "MEDIUM noise should reach mid-range enemies")
	_expect(far_enemy.received_noise <= 0.0, "MEDIUM noise should not be effectively global")

	_reset_probes(enemies)
	manager.emit_noise(Vector3.ZERO, manager.Level.HIGH)
	_expect(far_enemy.received_noise > 0.0, "HIGH noise should reach distant enemies within combat range")
	_expect(near_enemy.received_noise > far_enemy.received_noise, "HIGH noise should still attenuate by distance")

	_finish(enemies)


func _make_probe(position: Vector3) -> ProbeEnemy:
	var enemy := ProbeEnemy.new()
	root.add_child(enemy)
	enemy.global_position = position
	return enemy


func _reset_probes(enemies: Array) -> void:
	for enemy in enemies:
		enemy.received_noise = 0.0


func _finish(enemies: Array) -> void:
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	if _failures.is_empty():
		print("NoiseManager runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
