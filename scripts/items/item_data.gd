# item_data.gd
# Item resource data used by containers, pickups, inventory, and scoring.
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
