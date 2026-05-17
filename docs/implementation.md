# 《余晖号》实现细节文档 (Godot 4.x / GDScript)

> 本文档为 `design.md` 的技术实现补充，面向开发团队。

---

## 1. 项目架构

### 1.1 目录结构

```
project/
├── scenes/
│   ├── main_menu.tscn
│   ├── game.tscn              # 核心游戏场景
│   └── result_screen.tscn
├── scripts/
│   ├── managers/
│   │   ├── game_manager.gd
│   │   ├── spawn_manager.gd
│   │   ├── event_manager.gd
│   │   └── noise_manager.gd
│   ├── player/
│   │   ├── player.gd
│   │   ├── player_shooting.gd
│   │   ├── player_health.gd
│   │   └── inventory.gd
│   ├── enemies/
│   │   ├── enemy_base.gd
│   │   ├── patrol_enemy.gd
│   │   └── dormant_enemy.gd
│   ├── items/
│   │   ├── container.gd
│   │   └── item_data.gd
│   ├── systems/
│   │   ├── fog_of_war.gd
│   │   └── extraction.gd
│   └── ui/
│       └── hud.gd
├── resources/
│   ├── items/                 # ItemData .tres 资源
│   └── events/                # GameEvent .tres 资源
├── assets/
│   ├── sprites/
│   ├── tiles/
│   ├── audio/
│   └── fonts/
└── project.godot
```

### 1.2 GameScene 节点树

```
Game (Node2D)
├── GameManager (Node)
├── NoiseManager (Node)
├── SpawnManager (Node)
├── EventManager (Node)
├── Map (Node2D)
│   ├── Ground (TileMapLayer)
│   ├── Obstacles (TileMapLayer)     # 碰撞层
│   ├── Decoration (TileMapLayer)
│   ├── Boundaries (StaticBody2D)
│   └── SpawnPoints (Node2D)
│       ├── SpawnPoint1 (Marker2D)
│       └── SpawnPoint2 (Marker2D) ...
├── Entities (Node2D)
│   ├── Player (CharacterBody2D)
│   ├── Enemies (Node2D)
│   └── Containers (Node2D)
├── FogOfWar (CanvasLayer)
├── UI (CanvasLayer)
│   ├── HUD
│   └── EventNotification
└── Extraction (Node2D)
```

---

## 2. 玩家系统

### 2.1 Player 节点结构

```
Player (CharacterBody2D)
├── Sprite2D                  # 角色动画
├── CollisionShape2D          # 碰撞体
├── InteractionArea (Area2D)  # 交互检测（容器）
│   └── CollisionShape2D
├── Camera2D                  # 跟随摄像机
├── GunPivot (Node2D)         # 瞄准旋转轴
│   └── FirePoint (Marker2D)
└── HurtBox (Area2D)          # 受伤检测
```

### 2.2 移动 + 射击

```gdscript
# player.gd
extends CharacterBody2D

@export var base_speed := 300.0
@export var sprint_multiplier := 1.6
@export var sprint_duration := 1.0
@export var sprint_cooldown := 3.0

var sprint_timer := 0.0
var cooldown_timer := 0.0
var is_sprinting := false

@onready var gun_pivot := $GunPivot

func _physics_process(delta: float) -> void:
    # 移动输入
    var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var speed := base_speed * (sprint_multiplier if is_sprinting else 1.0)
    velocity = input * speed
    move_and_slide()

    # 鼠标瞄准
    gun_pivot.look_at(get_global_mouse_position())

    # 冲刺计时
    if is_sprinting:
        sprint_timer -= delta
        if sprint_timer <= 0:
            is_sprinting = false
    cooldown_timer -= delta

func _unput(event: InputEvent) -> void:
    if event.is_action_pressed("sprint") and cooldown_timer <= 0:
        is_sprinting = true
        sprint_timer = sprint_duration
        cooldown_timer = sprint_cooldown
        NoiseManager.emit_noise(global_position, NoiseManager.Level.MEDIUM)
```

### 2.3 射击

```gdscript
# player_shooting.gd
extends Node

@export var bullet_scene: PackedScene
@export var fire_rate := 0.15
@export var bullet_speed := 800.0
@export var max_ammo := 60

var current_ammo: int
var fire_cooldown := 0.0

@onready var fire_point: Marker2D = %FirePoint

func _ready() -> void:
    current_ammo = max_ammo

func _process(delta: float) -> void:
    fire_cooldown -= delta
    if Input.is_action_pressed("shoot") and fire_cooldown <= 0 and current_ammo > 0:
        fire()

func fire() -> void:
    var bullet = bullet_scene.instantiate()
    bullet.global_position = fire_point.global_position
    var dir = (get_viewport().get_mouse_position() - fire_point.get_viewport_rect().size / 2).normalized()
    bullet.direction = fire_point.global_transform.x
    bullet.speed = bullet_speed
    get_tree().root.add_child(bullet)
    current_ammo -= 1
    fire_cooldown = fire_rate
    NoiseManager.emit_noise(global_position, NoiseManager.Level.HIGH)

func add_ammo(amount: int) -> void:
    current_ammo = mini(current_ammo + amount, max_ammo)
```

### 2.4 生命系统

```gdscript
# player_health.gd
extends Node

signal died
signal health_changed(current, maximum)

@export var max_hp := 100.0
@export var iframe_duration := 0.5

var current_hp: float
var iframe_timer := 0.0

func _ready() -> void:
    current_hp = max_hp

func _process(delta: float) -> void:
    iframe_timer -= delta

func take_damage(amount: float) -> void:
    if iframe_timer > 0:
        return
    current_hp -= amount
    iframe_timer = iframe_duration
    GameManager.add_erosion(GameManager.HIT_EROSION_AMOUNT)
    health_changed.emit(current_hp, max_hp)
    if current_hp <= 0:
        died.emit()

func heal(amount: float) -> void:
    current_hp = minf(current_hp + amount, max_hp)
    health_changed.emit(current_hp, max_hp)
```

---

## 3. 物品与容器系统

### 3.1 ItemData (Resource)

```gdscript
# item_data.gd
class_name ItemData
extends Resource

enum Type { COLLECTIBLE, AMMO, BATTERY, PURIFIER }

@export var item_name: String
@export var icon: Texture2D
@export var type: Type
@export var weight: float         # 负重 Tag
@export var erosion: float        # 侵蚀 Tag（仅拾取时判断是否超限，不增加侵蚀值）
@export var score_value: int      # 撤出分数（COLLECTIBLE）
@export var ammo_amount: int      # 弹药补给量（AMMO）
@export var heal_amount: float    # 回复量（BATTERY）
@export var purify_amount: float  # 净化量（PURIFIER）
```

### 3.2 容器

```
Container (StaticBody2D)
├── Sprite2D
├── CollisionShape2D
├── InteractArea (Area2D)     # 玩家交互检测
│   └── CollisionShape2D
└── CrackProgressBar (TextureProgressBar)  # 读条 UI
```

```gdscript
# container.gd
extends StaticBody2D

signal cracked(container)

@export var loot_table: Array[ItemData]
@export var base_crack_time := 2.0

var is_cracked := false
var current_loot: ItemData
var crack_progress := 0.0
var is_cracking := false

func _ready() -> void:
    current_loot = loot_table.pick_random()

func get_crack_duration() -> float:
    var erosion := GameManager.player_erosion / 100.0
    return base_crack_time * (1.0 + erosion * 1.5)

func start_crack() -> void:
    if is_cracked:
        return
    is_cracking = true
    crack_progress = 0.0

func _process(delta: float) -> void:
    if not is_cracking:
        return
    crack_progress += delta / get_crack_duration()
    $CrackProgressBar.value = crack_progress
    if crack_progress >= 1.0:
        complete_crack()

func complete_crack() -> void:
    is_cracking = false
    is_cracked = true
    NoiseManager.emit_noise(global_position, NoiseManager.Level.LOW)
    cracked.emit(self)

func interrupt() -> void:
    is_cracking = false
    crack_progress = 0.0
```

### 3.3 背包

```gdscript
# inventory.gd
extends Node

var carried_items: Array[ItemData] = []
var current_weight := 0.0

func can_pickup(item: ItemData) -> bool:
    if current_weight + item.weight > GameManager.max_weight:
        return false
    if GameManager.player_erosion + item.erosion > GameManager.max_erosion:
        return false
    return true

func pickup(item: ItemData) -> void:
    if not can_pickup(item):
        return
    current_weight += item.weight
    carried_items.append(item)
    match item.type:
        ItemData.Type.AMMO:
            %PlayerShooting.add_ammo(item.ammo_amount)
        ItemData.Type.BATTERY:
            %PlayerHealth.heal(item.heal_amount)
        ItemData.Type.PURIFIER:
            GameManager.reduce_erosion(item.purify_amount)

func calculate_score() -> int:
    var score := 0
    for item in carried_items:
        if item.type == ItemData.Type.COLLECTIBLE:
            score += item.score_value
    return score
```

---

## 4. 噪音与警戒值系统

### 4.1 NoiseManager (Autoload 单例)

```gdscript
# noise_manager.gd — 注册为 Autoload
extends Node

enum Level { NONE = 0, LOW = 20, MEDIUM = 50, HIGH = 80, GLOBAL = 999 }

const RANGE_MAP := {
    Level.LOW: 150.0,
    Level.MEDIUM: 400.0,
    Level.HIGH: 750.0,
    Level.GLOBAL: 99999.0
}

func emit_noise(origin: Vector2, level: Level) -> void:
    var range_val: float = RANGE_MAP.get(level, 0.0)
    var noise_value := float(level)

    for enemy in get_tree().get_nodes_in_group("enemies"):
        var dist := origin.distance_to(enemy.global_position)
        if dist > range_val:
            continue
        var attenuation := 1.0 - (dist / range_val)
        enemy.receive_noise(noise_value * attenuation)
```

### 4.2 敌人警戒值

```gdscript
# enemy_base.gd
extends CharacterBody2D

signal awakened

@export var alert_threshold := 100.0
@export var decay_rate := 5.0
@export var base_hp := 40.0
@export var base_damage := 15.0

var current_alert := 0.0
var is_awake := false
var erosion_tier := 0

# 侵蚀属性倍率表（由 SpawnManager 定义，这里引用）
const EROSION_STAT_MULTIPLIER := [1.0, 1.0, 1.1, 1.2, 1.35]

func _ready() -> void:
    add_to_group("enemies")

func get_scaled_hp() -> float:
    return base_hp * EROSION_STAT_MULTIPLIER[erosion_tier]

func get_scaled_damage() -> float:
    return base_damage * EROSION_STAT_MULTIPLIER[erosion_tier]

func receive_noise(value: float) -> void:
    if is_awake:
        return
    current_alert += value
    if current_alert >= alert_threshold:
        awaken()

func force_awaken() -> void:
    awaken()

func awaken() -> void:
    is_awake = true
    current_alert = alert_threshold
    awakened.emit()

func _process(delta: float) -> void:
    if not is_awake and current_alert > 0:
        current_alert = maxf(0.0, current_alert - decay_rate * delta)
```

---

## 5. 敌人 AI

### 5.1 巡逻型

```gdscript
# patrol_enemy.gd
extends "res://scripts/enemies/enemy_base.gd"

enum State { PATROL, CHASE, ATTACK }

@export var patrol_speed := 100.0
@export var chase_speed := 200.0
@export var view_angle := 60.0
@export var view_range := 300.0
@export var attack_range := 60.0
@export var attack_cooldown := 1.0

var state := State.PATROL
var patrol_target: Vector2
var attack_timer := 0.0
var player: CharacterBody2D

func _ready() -> void:
    super._ready()
    player = get_tree().get_first_node_in_group("player")
    pick_patrol_target()
    awakened.connect(func(): state = State.CHASE)

func _physics_process(delta: float) -> void:
    match state:
        State.PATROL:
            update_patrol(delta)
        State.CHASE:
            update_chase(delta)
        State.ATTACK:
            update_attack(delta)

func update_patrol(delta: float) -> void:
    # 向巡逻点移动
    var dir := global_position.direction_to(patrol_target)
    velocity = dir * patrol_speed
    move_and_slide()
    if global_position.distance_to(patrol_target) < 10:
        pick_patrol_target()

    # 视觉锥检测
    if can_see_player():
        force_awaken()
        state = State.CHASE

func update_chase(_delta: float) -> void:
    var dist := global_position.distance_to(player.global_position)
    if dist <= attack_range:
        state = State.ATTACK
        return
    velocity = global_position.direction_to(player.global_position) * chase_speed
    move_and_slide()

func update_attack(delta: float) -> void:
    attack_timer -= delta
    if attack_timer <= 0:
        player.get_node("PlayerHealth").take_damage(get_scaled_damage())
        attack_timer = attack_cooldown
    if global_position.distance_to(player.global_position) > attack_range * 1.5:
        state = State.CHASE

func can_see_player() -> bool:
    var to_player := player.global_position - global_position
    if to_player.length() > view_range:
        return false
    var facing := Vector2.from_angle(rotation)
    if rad_to_deg(facing.angle_to(to_player)) > view_angle / 2.0:
        return false
    # Raycast 检查遮挡
    var space := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(
        global_position, player.global_position, 0b0100)  # Obstacles layer
    var result := space.intersect_ray(query)
    return result.is_empty()

func pick_patrol_target() -> void:
    patrol_target = global_position + Vector2(
        randf_range(-200, 200), randf_range(-200, 200))
```

### 5.2 休眠型

```gdscript
# dormant_enemy.gd
extends "res://scripts/enemies/enemy_base.gd"

enum State { SLEEP, CHASE, ATTACK }

@export var chase_speed := 150.0
@export var base_attack_range := 80.0
@export var attack_cooldown := 1.5

var state := State.SLEEP
var attack_timer := 0.0
var player: CharacterBody2D

func _ready() -> void:
    super._ready()
    player = get_tree().get_first_node_in_group("player")
    awakened.connect(func(): state = State.CHASE)

func _physics_process(_delta: float) -> void:
    match state:
        State.SLEEP:
            pass  # 不动
        State.CHASE:
            var dist := global_position.distance_to(player.global_position)
            if dist <= base_attack_range:
                state = State.ATTACK
            else:
                velocity = global_position.direction_to(player.global_position) * chase_speed
                move_and_slide()
        State.ATTACK:
            attack_timer -= _delta
            if attack_timer <= 0:
                player.get_node("PlayerHealth").take_damage(get_scaled_damage())
                attack_timer = attack_cooldown
            if global_position.distance_to(player.global_position) > base_attack_range * 1.5:
                state = State.CHASE
```

---

## 6. 时间刷怪系统

### 6.1 侵蚀→敌人倍率映射

```gdscript
# 侵蚀阶梯影响——由 GameManager.get_erosion_tier() 驱动

# 敌人属性倍率 (HP / 伤害)
const EROSION_STAT_MULTIPLIER := [1.0, 1.0, 1.1, 1.2, 1.35]

# 刷怪间隔乘数
const EROSION_SPAWN_INTERVAL_MULTIPLIER := [1.0, 1.0, 0.85, 0.7, 0.5]

# 休眠型出现概率
const EROSION_DORMANT_RATIO := [0.0, 0.0, 0.15, 0.3, 0.5]
```

### 6.2 SpawnManager

```gdscript
# spawn_manager.gd
extends Node

@export var spawn_points: Array[Marker2D]
@export var patrol_scene: PackedScene
@export var dormant_scene: PackedScene
@export var signal_flare_multiplier := 3.0

# 刷怪曲线: [时间阈值, 每分钟刷怪数]
var spawn_curve := [
    [0,   0],
    [30,  2],
    [60,  4],
    [120, 8],
    [180, 15],
    [240, 25],
    [300, 40],
]

var spawn_timer := 0.0
var signal_active := false

func _process(delta: float) -> void:
    var elapsed := GameManager.elapsed_time
    var tier := GameManager.get_erosion_tier()
    var spm := sample_curve(elapsed)
    if signal_active:
        spm *= signal_flare_multiplier
    spm /= EROSION_SPAWN_INTERVAL_MULTIPLIER[tier]
    var interval := 60.0 / maxf(spm, 0.1)
    spawn_timer -= delta
    if spawn_timer <= 0:
        spawn_enemy(elapsed, tier)
        spawn_timer = interval

func spawn_enemy(elapsed: float, tier: int) -> void:
    var point := get_farthest_spawn_point()
    var spawn_dormant := elapsed > 60 and randf() < EROSION_DORMANT_RATIO[tier]
    var scene := dormant_scene if spawn_dormant else patrol_scene
    var enemy := scene.instantiate()
    enemy.global_position = point.global_position
    enemy.erosion_tier = tier
    get_node("/root/Game/Entities/Enemies").add_child(enemy)

func get_farthest_spawn_point() -> Marker2D:
    var player_pos := GameManager.player_position
    var valid := spawn_points.filter(
        func(p): return p.global_position.distance_to(player_pos) > 600)
    if valid.is_empty():
        return spawn_points.pick_random()
    valid.sort_custom(func(a, b):
        return a.global_position.distance_to(player_pos) > b.global_position.distance_to(player_pos))
    return valid[0]

func on_signal_flare() -> void:
    signal_active = true

func sample_curve(t: float) -> float:
    for i in range(spawn_curve.size() - 1):
        if t >= spawn_curve[i][0] and t < spawn_curve[i + 1][0]:
            var ratio := (t - spawn_curve[i][0]) / (spawn_curve[i + 1][0] - spawn_curve[i][0])
            return lerpf(spawn_curve[i][1], spawn_curve[i + 1][1], ratio)
    return spawn_curve[-1][1]
```

---

## 7. 事件系统

```gdscript
# event_manager.gd
extends Node

@export var check_interval := 30.0
@export var base_chance := 0.3

var check_timer: float

enum EventType { CONTAINER_ALARM, EMERGENCY_SUPPLY, EM_PULSE, AREA_UNLOCK, ENEMY_TIDE }

func _process(delta: float) -> void:
    check_timer -= delta
    if check_timer <= 0:
        check_timer = check_interval
        try_trigger()

func try_trigger() -> void:
    var chance := base_chance + (GameManager.elapsed_time / 300.0) * 0.3
    if randf() < chance:
        var event_type: EventType = EventType.values().pick_random()
        execute_event(event_type)

func execute_event(type: EventType) -> void:
    match type:
        EventType.CONTAINER_ALARM:
            # 范围内敌人警戒值暴涨
            for enemy in get_tree().get_nodes_in_group("enemies"):
                enemy.receive_noise(80.0)
        EventType.EMERGENCY_SUPPLY:
            # 在随机位置生成补给容器
            pass
        EventType.EM_PULSE:
            # 某区域敌人强制觉醒
            for enemy in get_tree().get_nodes_in_group("enemies"):
                if randf() < 0.5:
                    enemy.force_awaken()
        EventType.AREA_UNLOCK:
            # 开启封锁门 (AnimatableBody2D 移除)
            pass
        EventType.ENEMY_TIDE:
            # 连续快速刷怪
            for i in range(5):
                $"../SpawnManager".spawn_enemy(GameManager.elapsed_time)
```

---

## 8. 战争迷雾

使用 **Light2D + CanvasModulate** 方案（Godot 原生支持）：

```
FogOfWar (CanvasLayer)
├── CanvasModulate             # 全局变暗（未探索区域）
└── (玩家身上)
    └── PointLight2D           # 照亮玩家视野
```

```gdscript
# fog_of_war.gd — 挂在 Player 的 PointLight2D 上
extends PointLight2D

@export var base_radius := 400.0
@export var min_radius := 150.0

func _process(_delta: float) -> void:
    var erosion := GameManager.player_erosion / 100.0
    texture_scale = lerpf(base_radius, min_radius, erosion) / 512.0
    # 512 = light 纹理基准大小
```

已探索区域留痕可通过 **SubViewport + 白色圆绘制到 RenderTexture** 实现，或使用 `Line2D` 轨迹简化。

---

## 9. 撤离系统

```gdscript
# extraction.gd
extends Node2D

@export var wait_time := 75.0
@export var mothership_scene: PackedScene
@export var boarding_range := 100.0

var signal_fired := false
var wait_timer := 0.0
var signal_position: Vector2
var mothership: Node2D

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("signal_flare") and not signal_fired:
        fire_signal()

func fire_signal() -> void:
    signal_fired = true
    signal_position = GameManager.player_position
    wait_timer = wait_time
    NoiseManager.emit_noise(signal_position, NoiseManager.Level.GLOBAL)
    $"../SpawnManager".on_signal_flare()
    GameManager.set_state(GameManager.State.EXTRACTING)

func _process(delta: float) -> void:
    if not signal_fired:
        return
    wait_timer -= delta
    if wait_timer <= 0 and mothership == null:
        mothership = mothership_scene.instantiate()
        mothership.global_position = signal_position
        add_child(mothership)
    if mothership and Input.is_action_just_pressed("interact"):
        var dist := GameManager.player_position.distance_to(mothership.global_position)
        if dist < boarding_range:
            GameManager.set_state(GameManager.State.SUCCESS)
```

---

## 10. GameManager (Autoload)

```gdscript
# game_manager.gd — 注册为 Autoload
extends Node

enum State { PREPARING, RUNNING, EXTRACTING, SUCCESS, DEAD }

var current_state := State.PREPARING
var elapsed_time := 0.0
var player_erosion := 0.0
var max_weight := 50.0
var max_erosion := 100.0
var player_position: Vector2
var kill_count := 0

# 侵蚀增长速率（每秒百分比）
const EROSION_RATE := 0.0167  # 约每 60 秒 +1%
const HIT_EROSION_AMOUNT := 2.5  # 受击跳升 %
const PURIFIER_REDUCTION := 17.5  # 净化剂降低 %

func _process(delta: float) -> void:
    if current_state == State.RUNNING or current_state == State.EXTRACTING:
        elapsed_time += delta
        add_erosion(EROSION_RATE * delta)

func set_state(new_state: State) -> void:
    current_state = new_state
    match new_state:
        State.SUCCESS:
            get_tree().change_scene_to_file("res://scenes/result_screen.tscn")
        State.DEAD:
            get_tree().change_scene_to_file("res://scenes/result_screen.tscn")

func add_erosion(amount: float) -> void:
    player_erosion = minf(player_erosion + amount, max_erosion)

func reduce_erosion(amount: float) -> void:
    player_erosion = maxf(player_erosion - amount, 0.0)

func get_erosion_tier() -> int:
    ## 返回侵蚀阶梯 0-4
    if player_erosion < 25: return 0
    if player_erosion < 50: return 1
    if player_erosion < 75: return 2
    return 3 if player_erosion < 100 else 4
```

---

## 11. 输入映射 (Project Settings > Input Map)

| Action | 按键 |
|--------|------|
| `move_left` | A |
| `move_right` | D |
| `move_up` | W |
| `move_down` | S |
| `shoot` | 鼠标左键 |
| `interact` | E |
| `sprint` | Left Shift |
| `signal_flare` | Q |
| `pause` | Escape |

---

## 12. 碰撞层规划

| Layer | 名称 | 用途 |
|-------|------|------|
| 1 | Player | 玩家碰撞 |
| 2 | Enemy | 敌人碰撞 |
| 3 | Obstacles | 障碍物（阻挡移动+子弹+视线） |
| 4 | Projectiles | 子弹 |
| 5 | Containers | 容器交互触发器 |
| 6 | Boundary | 地图边界 |

碰撞关系：
- 玩家：碰撞 Enemy, Obstacles, Containers
- 敌人：碰撞 Player, Obstacles, Projectiles
- 子弹：碰撞 Enemy, Obstacles
- 容器：仅被 Player Area2D 检测

---

## 13. 关键数值参考（初始值，待 Balance）

| 参数 | 初始值 | 备注 |
|------|--------|------|
| 玩家 HP | 100 | |
| 移动速度 | 300 px/s | |
| 冲刺倍率 | 1.6x | |
| 冲刺持续 | 1 秒 | |
| 冲刺 CD | 3 秒 | |
| maxWeight | 50 | |
| maxErosion | 100% | |
| 侵蚀时间增长 | ~1%/60s | EROSION_RATE = 0.0167/s |
| 受击侵蚀跳升 | 2.5% | |
| 净化剂降侵蚀 | 17.5% | |
| 初始弹药 | 60 发 | |
| 射击间隔 | 0.15 秒 | |
| 子弹伤害 | 20 | |
| 弹药箱补给 | 25 发 | |
| 基础破解时间 | 2 秒 | |
| 视野基础半径 | 400 px | |
| 视野最小半径 | 150 px | 侵蚀 100% 时 |
| 无敌帧 | 0.5 秒 | |
| 巡逻型 HP | 40 | 基础值，侵蚀倍率加成 |
| 休眠型 HP | 80 | 基础值，侵蚀倍率加成 |
| 巡逻型伤害 | 15/次 | 基础值，侵蚀倍率加成 |
| 休眠型伤害 | 25/次 | 基础值，侵蚀倍率加成 |
| 巡逻型视觉锥 | 60° / 300 px | |
| 警戒阈值 | 100 | |
| 警戒消退 | 5/秒 | |
| 信号弹等待 | 75 秒 | |

---

*文档结束*
