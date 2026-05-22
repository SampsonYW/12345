# item_data.gd
# 物品数据定义 (Resource)：存储物品重量、分值、图标颜色及消耗品效果等基础属性。
# Item resource data used by containers, pickups, inventory, and scoring.
# [AI-ASSISTED] 2026-05-22 — 按照 docs/rules.md 进行代码标准化
extends Resource
class_name ItemData

enum Type { COLLECTIBLE, AMMO, BATTERY, PURIFIER }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC }

@export var item_name: String = ""
@export var icon: Texture2D
@export var type: Type = Type.COLLECTIBLE
@export var rarity: Rarity = Rarity.COMMON
@export var weight: float = 1.0
@export var score_value: int = 0
@export var ammo_amount: int = 0
@export var heal_amount: float = 0.0
@export var purify_amount: float = 0.0
