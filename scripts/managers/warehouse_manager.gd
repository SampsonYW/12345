# warehouse_manager.gd
# Autoload 单例：母船仓库库存。从 HUD 剥离以消除 UI 持有玩法数据
# 的耦合（rules.md §1.4），使仓库成为独立数据源而非 UI 附属。
# [AI-ASSISTED] 2026-05-25 — 抽取自 hud.gd 的 _warehouse_stock / _warehouse_items
#   字典，注册为 Autoload 实现数据与视图解耦。
extends Node

signal stock_changed(item_name: String, new_amount: int)

# The four standard items in the game.
const ITEM_RELIC = preload("res://resources/items/relic_small.tres")
const ITEM_AMMO = preload("res://resources/items/standard_ammo.tres")
const ITEM_BATTERY = preload("res://resources/items/battery_small.tres")
const ITEM_PURIFIER = preload("res://resources/items/purifier.tres")

const ITEM_CATALOG = {
	"标准弹药": ITEM_AMMO,
	"能量电池": ITEM_BATTERY,
	"净化剂": ITEM_PURIFIER,
	"残响碎片": ITEM_RELIC,
}

var order: Array[String] = ["标准弹药", "能量电池", "净化剂", "残响碎片"]

var _stock := {
	"标准弹药": 12,
	"能量电池": 6,
	"净化剂": 2,
	"残响碎片": 1,
}

func get_item_resource(item_name: String) -> ItemData:
	return ITEM_CATALOG.get(item_name)

func get_stock(item_name: String) -> int:
	return _stock.get(item_name, 0)

func add_item(item: ItemData) -> bool:
	if not ITEM_CATALOG.has(item.item_name):
		return false
	_stock[item.item_name] = _stock.get(item.item_name, 0) + 1
	stock_changed.emit(item.item_name, _stock[item.item_name])
	return true

func remove_item(item_name: String) -> ItemData:
	if not ITEM_CATALOG.has(item_name):
		return null
	if _stock.get(item_name, 0) <= 0:
		return null
	
	_stock[item_name] -= 1
	stock_changed.emit(item_name, _stock[item_name])
	return ITEM_CATALOG[item_name].duplicate()
