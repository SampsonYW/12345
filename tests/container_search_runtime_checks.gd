# container_search_runtime_checks.gd
# Verifies container search entries, rarity timing, and explicit inventory transfer.
extends SceneTree

const ItemDataResource := preload("res://scripts/items/item_data.gd")
const INVENTORY_SLOT_COUNT: int = 8
const RARITY_COMMON: int = 0
const RARITY_RARE: int = 2

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager: Node = root.get_node_or_null("GameManager")
	_expect(game_manager != null, "GameManager autoload should exist")
	if game_manager == null:
		await _finish(null, null, 0.0, 0.0, null)
		return
	var previous_max_weight: float = game_manager.max_weight
	var previous_erosion: float = game_manager.player_erosion
	game_manager.max_weight = 10.0
	game_manager.player_erosion = 0.0

	var container_script: Script = load("res://scripts/items/container_3d.gd")
	var inventory_script: Script = load("res://scripts/player/inventory.gd")
	_expect(container_script != null, "Container script should load")
	_expect(inventory_script != null, "Inventory script should load")
	if container_script == null or inventory_script == null:
		await _finish(null, null, previous_max_weight, previous_erosion, game_manager)
		return

	var common_relic := _make_item("Common Relic", RARITY_COMMON, 2.0, 10)
	var rare_relic := _make_item("Rare Relic", RARITY_RARE, 3.0, 25)
	var heavy_relic := _make_item("Heavy Relic", RARITY_COMMON, 9.0, 100)

	var container: Node = container_script.new()
	var loot: Array[ItemDataResource] = [common_relic, rare_relic, heavy_relic]
	container.loot_table = loot
	if _has_property(container, "base_search_time"):
		container.base_search_time = 1.0
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	container.add_child(visual)
	var interact_area := Area3D.new()
	interact_area.name = "InteractArea"
	container.add_child(interact_area)
	root.add_child(container)

	var inventory: Node = inventory_script.new()
	root.add_child(inventory)
	await process_frame

	_expect(_has_property(common_relic, "rarity"), "ItemData should expose rarity")
	_expect(_has_property(container, "base_search_time"), "Container should expose base_search_time")
	_expect(container.has_method("open_container"), "Container should expose open_container()")
	_expect(container.has_method("get_search_entry_count"), "Container should expose get_search_entry_count()")
	_expect(container.has_method("is_entry_revealed"), "Container should expose is_entry_revealed(index)")
	_expect(container.has_method("get_search_duration_for_entry"), "Container should expose get_search_duration_for_entry(index)")
	_expect(container.has_method("search_entry"), "Container should expose search_entry(index, duration)")
	_expect(container.has_method("transfer_revealed_item_to_inventory"), "Container should expose transfer_revealed_item_to_inventory(index, inventory)")
	_expect(container.has_method("is_entry_transferred"), "Container should expose is_entry_transferred(index)")
	_expect(inventory.has_method("transfer_revealed_item_from_container"), "Inventory should expose transfer_revealed_item_from_container(container, index)")
	if not _failures.is_empty():
		await _finish(container, inventory, previous_max_weight, previous_erosion, game_manager)
		return

	_expect(container.open_container(), "Opening should create searchable entries")
	_expect(container.get_search_entry_count() == 3, "Open container should create one entry per loot item")
	_expect(not container.is_entry_revealed(0), "Opened entries should start unknown")
	_expect(not container.is_entry_revealed(1), "Opened entries should keep each item hidden until searched")
	_expect(container.get_search_duration_for_entry(1) > container.get_search_duration_for_entry(0), "Rare items should take longer to search than common items")

	_expect(not container.transfer_revealed_item_to_inventory(0, inventory), "Unknown entries should not transfer")
	_expect(container.search_entry(0, container.get_search_duration_for_entry(0)), "Searching for the required duration should reveal an entry")
	_expect(container.is_entry_revealed(0), "Searched entry should be revealed")
	_expect(inventory.get_collectible_count() == 0, "Revealed items should not be auto-picked-up")

	_expect(inventory.transfer_revealed_item_from_container(container, 0), "Inventory transfer API should move a revealed entry")
	_expect(inventory.get_collectible_count() == 1, "Transferred relic should appear in inventory")
	_expect(container.is_entry_transferred(0), "Transferred entry should be marked unavailable")
	_expect(not container.transfer_revealed_item_to_inventory(0, inventory), "Transferred entries should not transfer twice")

	_expect(container.search_entry(2, container.get_search_duration_for_entry(2)), "Heavy entry should reveal before transfer")
	_expect(not container.transfer_revealed_item_to_inventory(2, inventory), "Transfer should block when inventory would exceed max weight")
	_expect(not container.is_entry_transferred(2), "Blocked transfer should leave the entry in the container")

	for i in INVENTORY_SLOT_COUNT - 1:
		_expect(inventory.add_item(_make_item("Filler %d" % i, RARITY_COMMON, 0.1, 1)), "Filler item should fit")
	_expect(container.search_entry(1, container.get_search_duration_for_entry(1)), "Rare entry should reveal before full-inventory transfer")
	_expect(not container.transfer_revealed_item_to_inventory(1, inventory), "Transfer should block when inventory has no empty slots")
	_expect(not container.is_entry_transferred(1), "Full-inventory block should leave item in the container")

	# ----- 双向 round-trip: 背包→容器（add_item_to_container）-----
	_expect(container.has_method("add_item_to_container"), "Container should expose add_item_to_container(item)")
	_expect(not container.add_item_to_container(null), "add_item_to_container(null) should fail")

	# 此时 entry 0 已 transferred、entry 1/2 占用未 transferred；新 item 应复用 entry 0
	var entry_count_before: int = container.get_search_entry_count()
	_expect(container.is_entry_transferred(0), "Precondition: entry 0 should be transferred")
	var new_item := _make_item("Stowed Battery", RARITY_COMMON, 0.5, 5)
	_expect(container.add_item_to_container(new_item), "add_item_to_container should accept valid items")
	_expect(container.get_search_entry_count() == entry_count_before, "Stowed item should reuse the transferred slot, not append")
	_expect(not container.is_entry_transferred(0), "Reused slot should clear transferred flag")
	_expect(container.is_entry_revealed(0), "Reused slot should be immediately revealed")
	_expect(container.get_revealed_item_name(0) == "Stowed Battery", "Reused slot should hold the new item")

	# 没有 transferred 槽时应 append（再 transfer 一次然后看新 append 还是复用）
	var inv2: Node = inventory_script.new()
	root.add_child(inv2)
	await process_frame
	# 让所有 entries 都非 transferred，且容量未满 → append
	var count_after_reuse: int = container.get_search_entry_count()
	var append_item := _make_item("Appended Tag", RARITY_COMMON, 0.1, 1)
	_expect(container.add_item_to_container(append_item), "When no transferred slot exists, add should append")
	_expect(container.get_search_entry_count() == count_after_reuse + 1, "Append should increase entry count by 1")
	inv2.queue_free()

	await _finish(container, inventory, previous_max_weight, previous_erosion, game_manager)


func _make_item(item_name: String, rarity: int, weight: float, score_value: int) -> ItemDataResource:
	var item := ItemDataResource.new()
	item.item_name = item_name
	item.type = ItemDataResource.Type.COLLECTIBLE
	if _has_property(item, "rarity"):
		item.rarity = rarity
	item.weight = weight
	item.score_value = score_value
	return item


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.get("name", "") == property_name:
			return true
	return false


func _finish(container: Node, inventory: Node, previous_max_weight: float, previous_erosion: float, game_manager: Node) -> void:
	if container != null:
		container.queue_free()
	if inventory != null:
		inventory.queue_free()
	await process_frame
	if game_manager != null:
		game_manager.max_weight = previous_max_weight
		game_manager.player_erosion = previous_erosion

	if _failures.is_empty():
		print("Container search runtime checks passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
