# poi_dump_utility.gd
# 把编辑器场景中 POI 节点的当前位置/旋转写回对应的 *_poi.gd 数据数组。
# 保留所有注释和格式，只更新数字字段（X / Z / 旋转 Y / X / Z / X / Z）。
# 写入前备份原文件为 *.gd.bak。
# [AI-ASSISTED] 2026-05-23 - 编辑器拖动 → 自动改代码工作流
class_name POIDumpUtility
extends RefCounted

# Obstacle 行：\t[Kind.XXX, X, Z, SX, SY, SZ, ROT_Y_DEG],
# 捕获组：1=前缀  2=X  3=,空格  4=Z  5=,SX,SY,SZ,  6=ROT  7=后缀
const OBSTACLE_PATTERN := "^(\\s*\\[Kind\\.\\w+,\\s*)([-+]?\\d+\\.?\\d*)(,\\s*)([-+]?\\d+\\.?\\d*)(,\\s*\\d+\\.?\\d*,\\s*\\d+\\.?\\d*,\\s*\\d+\\.?\\d*,\\s*)([-+]?\\d+\\.?\\d*)(\\s*\\],?.*)$"

# Container 行：\t[X, Z, "risk", [ITEM_X, ITEM_Y]],
# 捕获组：1=前缀  2=X  3=,空格  4=Z  5=后续（含 risk + loot 数组）
const CONTAINER_PATTERN := "^(\\s*\\[)([-+]?\\d+\\.?\\d*)(,\\s*)([-+]?\\d+\\.?\\d*)(\\s*,.+)$"

# Spawn 行：\t["patrol"/"dormant", X, Z],
# 捕获组：1=前缀  2=X  3=,空格  4=Z  5=后缀
const SPAWN_PATTERN := "^(\\s*\\[\"[a-z_]+\",\\s*)([-+]?\\d+\\.?\\d*)(,\\s*)([-+]?\\d+\\.?\\d*)(\\s*\\],?.*)$"


## 把编辑器场景里属于 poi_class 的节点位置写回 source_path 文件。
## 返回 {ok: bool, obstacles: int, containers: int, spawns: int, error: String}
static func dump(source_path: String, poi_class: String, parents: Dictionary) -> Dictionary:
	var states := _collect_states(poi_class, parents)
	return _rewrite_file(source_path, states)


static func _collect_states(poi_class: String, parents: Dictionary) -> Dictionary:
	var states := {"obstacles": {}, "containers": {}, "spawns": {}}
	for key in ["obstacles", "containers", "spawns"]:
		var parent_node: Node = parents.get(key)
		if parent_node == null:
			continue
		for child in parent_node.get_children():
			if not child.has_meta("poi_class"):
				continue
			if child.get_meta("poi_class") != poi_class:
				continue
			var idx: int = child.get_meta("poi_data_index")
			var node := child as Node3D
			states[key][idx] = {
				"x": node.global_position.x,
				"z": node.global_position.z,
				"rot_y_deg": rad_to_deg(node.rotation.y),
			}
	return states


static func _rewrite_file(source_path: String, states: Dictionary) -> Dictionary:
	var f := FileAccess.open(source_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot read %s" % source_path}
	var content := f.get_as_text()
	f.close()

	var obstacle_re := RegEx.new()
	obstacle_re.compile(OBSTACLE_PATTERN)
	var container_re := RegEx.new()
	container_re.compile(CONTAINER_PATTERN)
	var spawn_re := RegEx.new()
	spawn_re.compile(SPAWN_PATTERN)

	var lines := content.split("\n")
	var new_lines: PackedStringArray = PackedStringArray()
	var section := ""
	var section_index := 0
	var counts := {"obstacles": 0, "containers": 0, "spawns": 0}

	for line in lines:
		var trimmed := line.strip_edges()
		# Section boundary detection
		if section == "":
			if trimmed.begins_with("const OBSTACLES"):
				section = "obstacles"
				section_index = 0
				new_lines.append(line)
				continue
			elif trimmed.begins_with("const CONTAINERS"):
				section = "containers"
				section_index = 0
				new_lines.append(line)
				continue
			elif trimmed.begins_with("const SPAWNS"):
				section = "spawns"
				section_index = 0
				new_lines.append(line)
				continue
			new_lines.append(line)
			continue

		if trimmed == "]":
			section = ""
			new_lines.append(line)
			continue

		# Within a section: try to update if this is a data line
		var re: RegEx = null
		match section:
			"obstacles":
				re = obstacle_re
			"containers":
				re = container_re
			"spawns":
				re = spawn_re

		var m := re.search(line) if re != null else null
		if m == null:
			# Comment or blank line within section — keep as-is, don't advance index
			new_lines.append(line)
			continue

		var st_dict: Dictionary = states.get(section, {})
		if st_dict.has(section_index):
			var st: Dictionary = st_dict[section_index]
			var updated := _format_updated_line(section, m, st)
			if updated != line:
				counts[section] += 1
			new_lines.append(updated)
		else:
			new_lines.append(line)
		section_index += 1

	var new_content := "\n".join(new_lines)
	if new_content == content:
		return {"ok": true, "obstacles": 0, "containers": 0, "spawns": 0, "note": "no changes"}

	# Backup
	var bak := FileAccess.open(source_path + ".bak", FileAccess.WRITE)
	if bak != null:
		bak.store_string(content)
		bak.close()

	var out := FileAccess.open(source_path, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "cannot write %s" % source_path}
	out.store_string(new_content)
	out.close()

	return {
		"ok": true,
		"obstacles": counts["obstacles"],
		"containers": counts["containers"],
		"spawns": counts["spawns"],
	}


static func _format_updated_line(section: String, m: RegExMatch, st: Dictionary) -> String:
	match section:
		"obstacles":
			return "%s%s%s%s%s%s%s" % [
				m.get_string(1),
				_fmt(st["x"]),
				m.get_string(3),
				_fmt(st["z"]),
				m.get_string(5),
				_fmt(st["rot_y_deg"]),
				m.get_string(7),
			]
		"containers", "spawns":
			return "%s%s%s%s%s" % [
				m.get_string(1),
				_fmt(st["x"]),
				m.get_string(3),
				_fmt(st["z"]),
				m.get_string(5),
			]
	return m.get_string(0)


static func _fmt(value: float) -> String:
	# 与原代码风格保持一致：保留 1 位小数（除非更精细的尾数）
	if absf(value - roundf(value)) < 0.05:
		return "%.1f" % value
	return "%.2f" % value
