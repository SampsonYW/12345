# item_data.gd
# 物品数据资源类。每个具体物品（标准弹药、净化剂、收集品等）保存为 .tres 文件
# 使用方式：在 Container.loot_table 中引用，破解后生成对应实例
class_name ItemData
extends Resource

enum Type { COLLECTIBLE, AMMO, BATTERY, PURIFIER }

@export var item_name: String = ""
@export var icon: Texture2D
@export var type: Type = Type.COLLECTIBLE

# 负重（design.md §5.1）。所有类型物品都有 weight
@export var weight: float = 1.0

# 类型特定值
@export var score_value: int = 0      # COLLECTIBLE：撤出后计入分数
@export var ammo_amount: int = 0      # AMMO：弹药补给量
@export var heal_amount: float = 0.0  # BATTERY：回复 HP 量
@export var purify_amount: float = 0.0  # PURIFIER：降低侵蚀百分比
