# context_menu_controller.gd
# HUD 的右键菜单控制器，负责生成弹窗并分发点击事件
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd 以实现 MVC 架构解耦
extends Node

const ItemDataResource := preload("res://scripts/items/item_data.gd")

signal item_use_requested(slot_index: int)
signal item_discard_requested(slot_index: int)
signal transfer_to_warehouse_requested(slot_index: int)
signal transfer_to_backpack_from_warehouse_requested(item_name: String)
signal transfer_to_backpack_from_container_requested(entry_index: int)
signal transfer_to_container_requested(slot_index: int)

var _context_menu: PopupMenu = null
var _hud: Control = null

var _context_slot_index: int = -1
var _context_warehouse_name: String = ""
var _context_container_index: int = -1

func setup(hud: Control) -> void:
	_hud = hud

func show_for_backpack(at_position: Vector2, item: ItemDataResource, slot_index: int, loc: int, is_search_active: bool) -> void:
	_context_slot_index = slot_index
	var menu := _prepare_context_menu()
	var type_name := _get_item_type_name(item.type)
	menu.add_item("%s  [%s]" % [item.item_name, type_name], 0)
	menu.set_item_disabled(0, true)
	menu.add_separator()

	if loc == GameManager.Location.EXPEDITION:
		var can_use := item.type != ItemDataResource.Type.COLLECTIBLE
		menu.add_item("使用", 1)
		if not can_use:
			var use_idx := menu.get_item_index(1)
			menu.set_item_disabled(use_idx, true)
			menu.set_item_tooltip(use_idx, "残响碎片仅在撤离后结算分数")
		menu.add_item("丢弃", 2)
		if is_search_active:
			menu.add_item("存入容器", 6)
	elif loc == GameManager.Location.AFTERGLOW:
		menu.add_item("转移到仓库", 3)
	
	_finalize_context_menu(at_position)

func show_for_warehouse(at_position: Vector2, item_name: String, stock: int) -> void:
	_context_warehouse_name = item_name
	var menu := _prepare_context_menu()
	menu.add_item("%s  x%d" % [item_name, stock], 0)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	menu.add_item("转移到背包", 4)
	_finalize_context_menu(at_position)

func show_for_container(at_position: Vector2, entry_index: int, label_text: String) -> void:
	_context_container_index = entry_index
	var menu := _prepare_context_menu()
	menu.add_item(label_text, 0)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	menu.add_item("转移到背包", 5)
	_finalize_context_menu(at_position)

func _prepare_context_menu() -> PopupMenu:
	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
	_context_menu = PopupMenu.new()
	_context_menu.name = "SlotContextMenu"
	return _context_menu

func _finalize_context_menu(at_position: Vector2) -> void:
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	if _hud != null:
		_hud.add_child(_context_menu)
	_context_menu.position = Vector2i(int(at_position.x), int(at_position.y))
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		1:
			if _context_slot_index >= 0:
				item_use_requested.emit(_context_slot_index)
		2:
			if _context_slot_index >= 0:
				item_discard_requested.emit(_context_slot_index)
		3:
			if _context_slot_index >= 0:
				transfer_to_warehouse_requested.emit(_context_slot_index)
		4:
			if _context_warehouse_name != "":
				transfer_to_backpack_from_warehouse_requested.emit(_context_warehouse_name)
		5:
			if _context_container_index >= 0:
				transfer_to_backpack_from_container_requested.emit(_context_container_index)
		6:
			if _context_slot_index >= 0:
				transfer_to_container_requested.emit(_context_slot_index)
	
	_context_slot_index = -1
	_context_warehouse_name = ""
	_context_container_index = -1

func _get_item_type_name(type: int) -> String:
	match type:
		ItemDataResource.Type.COLLECTIBLE: return "收藏品"
		ItemDataResource.Type.AMMO: return "弹药"
		ItemDataResource.Type.BATTERY: return "电池"
		ItemDataResource.Type.PURIFIER: return "净化剂"
	return "未知"
