# drag_drop_controller.gd
# HUD 的拖拽交互控制器，集中处理源与目标的拖拽校验与转移逻辑
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd 以实现 MVC 架构解耦
extends Node

signal transfer_warehouse_to_backpack_requested(item_name: String)
signal transfer_container_to_backpack_requested(entry_index: int)
signal transfer_backpack_to_warehouse_requested(slot_index: int)
signal transfer_backpack_to_container_requested(slot_index: int)

func can_accept_drop(data: Variant, target: String) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	var source := String(payload.get("source", ""))
	if target == "backpack_slot":
		return source == "warehouse" or source == "container"
	if target == "warehouse_list":
		return source == "backpack"
	if target == "container_list":
		return source == "backpack"
	return false

func accept_drop(data: Variant, target: String) -> bool:
	if not can_accept_drop(data, target):
		return false
	var payload: Dictionary = data
	var source := String(payload.get("source", ""))
	if target == "backpack_slot" and source == "warehouse":
		transfer_warehouse_to_backpack_requested.emit(String(payload.get("item_name", "")))
		return true
	if target == "backpack_slot" and source == "container":
		transfer_container_to_backpack_requested.emit(int(payload.get("entry_index", -1)))
		return true
	if target == "warehouse_list" and source == "backpack":
		transfer_backpack_to_warehouse_requested.emit(int(payload.get("slot_index", -1)))
		return true
	if target == "container_list" and source == "backpack":
		transfer_backpack_to_container_requested.emit(int(payload.get("slot_index", -1)))
		return true
	return false
