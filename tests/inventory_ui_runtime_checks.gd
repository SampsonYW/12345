# inventory_ui_runtime_checks.gd
# Runtime checks for blocking backpack/storage overlays and Afterglow prompts.
extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame

	var manager: Node = root.get_node_or_null("GameManager")
	var hud := scene.get_node_or_null("UI/HUD")
	var player := scene.get_node_or_null("Entities/Player3D")
	_expect(manager != null, "GameManager exists")
	_expect(hud != null, "HUD exists")
	_expect(player != null, "Player exists")
	if manager == null or hud == null or player == null:
		_finish(scene)
		return

	if manager.has_method("enter_afterglow"):
		manager.enter_afterglow()
	await process_frame

	var fog := scene.get_node_or_null("FogOfWar")
	_expect(fog == null or not fog.visible, "Fog/vision discs are hidden on Afterglow map")
	var bottom_bar := hud.get_node_or_null("BottomBar") as Control
	_expect(bottom_bar != null and not bottom_bar.visible, "Backpack quick slots are hidden during live gameplay")
	var prompt_label := hud.get_node_or_null("PromptLabel") as Control
	_expect(prompt_label == null or not prompt_label.visible, "Operation prompt is not drawn in HUD")

	_expect(player.has_method("is_input_locked"), "Player exposes input lock state")
	if player.has_method("is_input_locked"):
		_expect(not player.is_input_locked(), "Player is unlocked on Afterglow map")

	_expect(hud.has_method("open_backpack"), "HUD can open backpack overlay")
	if hud.has_method("open_backpack"):
		hud.open_backpack()
	await process_frame
	_expect(manager.get("ui_blocking_input") != null, "GameManager tracks UI blocking input")
	if manager.get("ui_blocking_input") != null:
		_expect(bool(manager.get("ui_blocking_input")), "Opening backpack blocks input")
	if player.has_method("is_input_locked"):
		_expect(player.is_input_locked(), "Opening backpack locks player movement")
	_expect(hud.get_node_or_null("BackpackOverlay") != null, "Backpack overlay exists")
	var container_parent := scene.get_node_or_null("World/ExpeditionMap/Containers")
	var container := container_parent.get_child(0) if container_parent != null and container_parent.get_child_count() > 0 else null
	if container != null:
		var cracked_before: bool = container.is_opened() if container.has_method("is_opened") else false
		if container.has_method("_complete_crack"):
			container._complete_crack()
		await process_frame
		var cracked_after: bool = container.is_opened() if container.has_method("is_opened") else false
		_expect(cracked_after == cracked_before, "Blocking UI prevents container cracking behind overlay")

	_expect(hud.has_method("close_blocking_overlay"), "HUD can close blocking overlays")
	if hud.has_method("close_blocking_overlay"):
		hud.close_blocking_overlay()
	await process_frame
	if manager.get("ui_blocking_input") != null:
		_expect(not bool(manager.get("ui_blocking_input")), "Closing backpack clears input block")
	if player.has_method("is_input_locked"):
		_expect(not player.is_input_locked(), "Closing backpack unlocks player")

	if hud.has_method("_on_title_clicked"):
		hud._on_title_clicked()
	await process_frame
	manager.set_location(manager.Location.TITLE)
	await process_frame
	_press_key(hud, KEY_B)
	await process_frame
	_expect(not bool(manager.get("ui_blocking_input")), "Backpack shortcut is ignored on title overlay")

	_expect(hud.has_method("get_prompt_text"), "HUD exposes current prompt")
	if scene.has_method("set_player_near_afterglow_point"):
		scene.set_player_near_afterglow_point("warehouse")
	await process_frame
	if hud.has_method("get_prompt_text"):
		_expect(hud.get_prompt_text().find("仓库") >= 0, "Warehouse prompt appears in range")
	var world_prompt := scene.get_node_or_null("World/WorldPrompt") as Label3D
	_expect(
		world_prompt != null and world_prompt.visible and world_prompt.text.find("仓库") >= 0,
		"Warehouse prompt renders as world-space ground text"
	)
	_expect(scene.get_node_or_null("World/AfterglowMap/WarehouseCollision") != null, "Warehouse has physical collision")
	_expect(hud.has_method("transfer_storage_item_to_backpack"), "Storage UI exposes warehouse-to-backpack transfer")
	_expect(hud.has_method("transfer_backpack_slot_to_storage"), "Storage UI exposes backpack-to-warehouse transfer")

	_expect(hud.has_method("open_storage"), "HUD can open storage overlay")
	if hud.has_method("open_storage"):
		hud.open_storage()
	await process_frame
	var storage_overlay := hud.get_node_or_null("StorageOverlay")
	_expect(storage_overlay != null, "Storage overlay exists")
	_expect(
		storage_overlay != null and storage_overlay.find_child("BackpackGrid", true, false) != null,
		"Storage UI has backpack grid"
	)
	_expect(
		storage_overlay != null and storage_overlay.find_child("WarehouseList", true, false) != null,
		"Storage UI has warehouse list"
	)
	_expect(hud.has_method("get_visible_backpack_item_names"), "HUD exposes visible backpack names for tests")
	if hud.has_method("get_visible_backpack_item_names"):
		_expect(hud.get_visible_backpack_item_names().is_empty(), "Empty backpack shows no item names inside overlay")
	if hud.has_method("transfer_storage_item_to_backpack") and hud.has_method("transfer_backpack_slot_to_storage"):
		var moved_to_backpack: bool = hud.transfer_storage_item_to_backpack("能量电池")
		_expect(moved_to_backpack, "Warehouse item can move into backpack through shared transfer API")
		var moved_back: bool = hud.transfer_backpack_slot_to_storage(0)
		_expect(moved_back, "Backpack item can move back into warehouse")
		_expect(hud.has_method("can_accept_storage_drop"), "Storage UI exposes drag-drop validation")
		_expect(hud.has_method("accept_storage_drop"), "Storage UI exposes drag-drop transfer")
	if hud.has_method("close_blocking_overlay"):
		hud.close_blocking_overlay()
	await process_frame
	if hud.has_method("get_visible_backpack_item_names"):
		_expect(hud.get_visible_backpack_item_names().is_empty(), "HUD hides backpack item names outside overlay")

	_finish(scene)


func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if _failures.is_empty():
		print("Inventory UI runtime checks passed.")
		quit(0)
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _press_key(hud: Node, keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	hud._unhandled_input(event)
