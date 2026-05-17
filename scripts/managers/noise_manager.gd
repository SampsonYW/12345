# noise_manager.gd
# Autoload singleton: 噪音传播系统
# 在 project.godot 中注册为 Autoload (NoiseManager)
extends Node

# 噪音等级 (design.md §7.1)
enum Level {
	NONE = 0,
	LOW = 20,     # 破解容器
	MEDIUM = 50,  # 冲刺
	HIGH = 80,    # 开枪
	GLOBAL = 999  # 信号弹（全图）
}

# 各等级噪音传播范围（像素）
const RANGE_MAP := {
	Level.LOW: 150.0,
	Level.MEDIUM: 400.0,
	Level.HIGH: 750.0,
	Level.GLOBAL: 99999.0,
}


# 发出一次噪音事件：origin 是噪音源世界坐标，level 决定噪音值与传播范围
# 按距离线性衰减后，累加到范围内每个敌人的警戒值
func emit_noise(origin: Vector2, level: Level) -> void:
	var range_val: float = RANGE_MAP.get(level, 0.0)
	if range_val <= 0.0:
		return
	var noise_value := float(level)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D:
			continue
		var dist: float = origin.distance_to(enemy.global_position)
		if dist > range_val:
			continue
		var attenuation: float = 1.0 - (dist / range_val)
		enemy.receive_noise(noise_value * attenuation)
