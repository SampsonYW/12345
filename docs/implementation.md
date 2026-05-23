# 《余晖号》实现细节文档 (Godot 4.6 / GDScript)

> 本文档为 `design.md` 的技术实现补充。**完全脱离代码会很快过时，所以每次代码变更后必须按 `docs/rules.md §6.5` 同步更新本文档。**
>
> **最后更新**: 2026-05-23
>
> **当前口径**: 主玩法已完全切换到 3D 正交斜俯视。已落地：3D 玩家 / 射击 / HP / 背包 / 容器搜索（带条目模型 + 双向转移）/ 敌人 AI（巡逻 + 休眠合并一个脚本）/ 噪音 / 信号弹与撤离 / 时间-侵蚀刷怪 / 可视视野（视野锥 + 近距圆）/ 母车甲板与探索场景双地图切换 / POI 驱动的远征地图（8 个 POI 模块自包含构建）/ HUD 三态弹层（背包 / 仓库 / 容器搜索）+ 拖拽与右键菜单。本文档按模块自顶向下描述实现思路与**模块间耦合关系**。

---

## 0. 阅读指南

本文档不放具体代码，只描述：

1. 每个模块**做什么** —— 边界、状态、生命周期
2. 它**和谁耦合** —— 谁调它、它调谁、共享哪些信号/Group/Autoload
3. **耦合方向是否符合 rules.md §1.5 的依赖图** —— 不符合的地方会显式标注 ⚠️

实际签名、参数名以代码为准。本文档过期时，先改代码再回来同步本文档。

### 0.1 两类耦合的区分

本文档使用"耦合"一词时区分两类，因为它们的修复策略完全不同：

- **依赖耦合（call coupling）** —— 模块 A 直接调模块 B 的函数 / 读它的字段 / 监听它的信号。`§17 模块耦合总览` 是这类耦合的关系图。修复方式：抽接口、引入信号、改注入。
- **语义耦合（semantic coupling）** —— 模块 A 复用旧代码或旧常量，但**旧实现的隐含假设（"容器只读"、"槽位 8 个"、"id 从 0 开始连续"）在新场景下不再成立**，复用后产生行为 bug。这类耦合在调用图上**看不出来**，必须靠看具体场景的行为推断。修复方式：拆 API、移除假设、显式参数化。

⚠️ 在 §19 已知技术债里两类问题都列出，但分开标注。新功能"看着能跑就行"地复用旧 API 时，最容易引入语义耦合——AI 助手尤其要警惕。

---

## 1. 项目骨架

### 1.1 当前目录结构

```
project/
├── scenes/
│   ├── game_3d.tscn               # 主入口（project.godot 指向）
│   ├── afterglow_map.tscn         # 母车甲板地图（仓库 + 出发点）
│   ├── expedition_map.tscn        # 远征地图（POI 驱动）
│   ├── player_3d.tscn
│   ├── bullet_3d.tscn
│   ├── container_3d.tscn
│   ├── item_pickup_3d.tscn
│   ├── enemy_3d.tscn              # 巡逻型敌人外观
│   ├── patrol_enemy_3d.tscn       # 巡逻型实例化
│   ├── dormant_enemy_3d.tscn      # 休眠型实例化
│   ├── hud.tscn
│   ├── fog_of_war.tscn
│   ├── mothership_extraction_marker.tscn
│   ├── extraction_signal_beacon.tscn
│   ├── signal_flare_marker.tscn
│   └── explored_marker.tscn
├── scripts/
│   ├── game_3d.gd                 # 场景根（约 300 行）
│   ├── managers/                  # Autoload + 全场景管理器
│   │   ├── game_manager.gd        # Autoload
│   │   ├── noise_manager.gd       # Autoload
│   │   └── spawn_manager.gd       # 普通节点（挂在 Game3D 下）
│   ├── player/
│   │   ├── player_3d.gd
│   │   ├── player_shooting_3d.gd
│   │   ├── player_health.gd
│   │   ├── inventory.gd
│   │   └── bullet_3d.gd
│   ├── enemies/
│   │   └── enemy_3d.gd            # 巡逻 + 休眠两种类型合并到这个脚本
│   ├── items/
│   │   ├── container_3d.gd        # 含搜索条目模型 + 双向转移
│   │   ├── item_data.gd
│   │   └── item_pickup_3d.gd
│   ├── systems/
│   │   ├── fog_of_war.gd          # 实际是"可视视野"，文件名沿用
│   │   └── extraction.gd          # 信号弹后的等待 → 母车 → 登船流程
│   ├── maps/
│   │   ├── afterglow_map.gd       # 母车甲板交互（仓库、出发点）
│   │   ├── expedition_map.gd      # 远征地图：调度 POI 注册表
│   │   ├── poi_dump_utility.gd    # 编辑器把节点位置写回 POI .gd 文件
│   │   ├── core_wreck_poi.gd
│   │   ├── ash_outskirts_poi.gd
│   │   ├── black_yard_poi.gd
│   │   ├── broken_rail_poi.gd
│   │   ├── frozen_depot_poi.gd
│   │   ├── silent_array_poi.gd
│   │   ├── south_approach_poi.gd
│   │   └── wasteland_decoration_poi.gd
│   └── ui/
│       ├── hud.gd                 # ⚠️ 巨型脚本 1800 行，见 §10
│       ├── minimap.gd
│       └── storage_drag_slot.gd   # 给 HUD 容器 / 仓库 / 背包当 drag-drop 包装
├── resources/items/               # ItemData .tres
├── tests/                         # SceneTree 子类做的 headless runtime checks
└── project.godot
```

历史遗留：旧 2D 原型脚本（`player.gd` / `enemy_base.gd` / `container.gd` 等）已删除。`fog_of_war.gd` 名字保留是为了不破坏 `fog_of_war.tscn` 的 script path 引用。

### 1.2 Autoload

只有两个：

| 名称 | 脚本 | 职责 |
|------|------|------|
| `GameManager` | `scripts/managers/game_manager.gd` | Run 状态机、侵蚀、计时、信号弹冷却、UI 阻塞开关、当前地图位置 |
| `NoiseManager` | `scripts/managers/noise_manager.gd` | 噪音广播（按 group "enemies" 遍历 + 距离衰减） |

⚠️ `SpawnManager` **不是 Autoload**——它是 `Game3D` 节点下的普通节点，意味着其他模块拿它只能 `get_tree().current_scene.get_node_or_null("SpawnManager")`，或者由 `Game3D` 在初始化时显式注入。

### 1.3 Game3D 节点树

```
Game3D (Node3D)                       — scripts/game_3d.gd
├── WorldEnvironment
├── Sun (DirectionalLight3D)
├── World (Node3D)
│   ├── AfterglowMap (Node3D)         — scripts/maps/afterglow_map.gd
│   ├── ExpeditionMap (Node3D)        — scripts/maps/expedition_map.gd
│   │   ├── Ground
│   │   ├── Obstacles                 — 由 POI build_obstacles 填充
│   │   ├── Containers                — 由 POI build_containers 填充
│   │   ├── InitialSpawns             — 由 POI build_spawns 填充
│   │   └── RiskZones                 — 由 POI build_zone_marker 填充
│   └── WorldPrompt (Label3D)         — 世界空间提示文字
├── CameraRig
│   └── Camera3D                      — 正交斜俯视，跟随玩家
├── Entities
│   ├── Enemies
│   ├── Containers                    — 注意：当前为空，容器全在 ExpeditionMap/Containers
│   ├── Pickups
│   ├── Projectiles
│   └── Player3D                      — 含子节点 Inventory / PlayerHealth / PlayerShooting / FirePoint
├── SpawnManager                      — scripts/managers/spawn_manager.gd
├── Extraction                        — scripts/systems/extraction.gd
├── FogOfWar                          — 实例化自 fog_of_war.tscn
└── UI (CanvasLayer)
    └── HUD                           — scripts/ui/hud.gd
```

GameManager / NoiseManager 不在树里，挂在 `/root` 下。

---

## 2. GameManager —— Run 状态与全局数值

### 2.1 它持有什么

- **状态机**：`State { PREPARING, RUNNING, EXTRACTING, SUCCESS, DEAD }` + `Location { TITLE, AFTERGLOW, EXPEDITION }`
- **数值**：`elapsed_time`、`player_erosion`、`max_weight`、`max_erosion`、`kill_count`
- **信号弹槽位**：`signal_flare_used / position / time`（一局只能放一次）
- **UI 阻塞标志**：`ui_blocking_input`（HUD 打开弹层时为 true，玩家/容器/敌人都不该响应输入）
- **player_position 缓存**：`Vector3`，玩家每帧自己写入；其他模块只读

### 2.2 信号

`state_changed`、`erosion_changed`、`erosion_tier_changed`、`signal_flare_fired(origin)`、`run_finished`、`location_changed`、`ui_blocking_changed`。

### 2.3 它依赖谁

**几乎不依赖任何人**——它是单向广播源。它**只读自身状态**驱动 `elapsed_time` 累加和侵蚀自然增长（`_process`）。

### 2.4 谁依赖它（耦合最重的 Autoload）

| 调用者 | 用法 | 频次 |
|------|------|------|
| `Player3D` | `start_run / fire_signal_flare / set_state / player_position / current_state / current_location / ui_blocking_input` | 每帧+输入 |
| `PlayerShooting3D` | `current_state / ui_blocking_input` | 每帧 |
| `PlayerHealth` | `add_erosion(HIT_EROSION_AMOUNT) / set_state(DEAD)` | 受击/死亡 |
| `Inventory` | `max_weight / player_erosion / max_erosion / reduce_erosion` | 拾取/使用净化剂 |
| `Container3D` | `player_erosion / ui_blocking_input` | 每帧（破解时） |
| `Enemy3D` | `get_erosion_tier / register_kill / current_state` | 受击/死亡/AI |
| `SpawnManager` | `current_state / elapsed_time / get_erosion_tier / player_position` | 每帧 |
| `Extraction` | `signal_flare_fired / state_changed / current_state / ui_blocking_input / player_position` | 每帧 |
| `FogOfWar` | `player_erosion / max_erosion` | 每帧 |
| `HUD` | 几乎所有信号 + `set_ui_blocking_input` | 每帧 |
| `AfterglowMap / ExpeditionMap` | `current_state / ui_blocking_input / begin_expedition` | 每帧 |
| `Game3D` | `state_changed / location_changed` | 状态切换 |

**耦合判断**：符合 rules.md §1.5 的依赖方向（GameManager 是所有人的下游 read-only 数据源 + 状态广播）。

---

## 3. NoiseManager —— 噪音广播

### 3.1 实现

只有一个公有方法 `emit_noise(origin, level)`。`Level` 枚举 = `{NONE 0, LOW 20, MEDIUM 50, HIGH 80, GLOBAL 999}`，`RANGE_MAP` 给每个 level 一个距离半径（LOW 8m、MEDIUM 18m、HIGH 36m、GLOBAL 99999m）。

调用时遍历 `group "enemies"`，对每个敌人按距离做线性衰减（`1 - dist/range`），调它的 `receive_noise(value)`。`origin` 接受 `Vector3` 或 `Node3D`。

### 3.2 耦合

| 调用者 | 时机 |
|------|------|
| `Player3D` | 冲刺（MEDIUM）、信号弹（GLOBAL） |
| `PlayerShooting3D` | 每次开火（HIGH） |
| `Container3D` | 破解完成（LOW） |

读侧只有一处：`Enemy3D.receive_noise(value)`。结构很干净——所有人调一个公有 API，敌人侧只暴露一个接收函数。

⚠️ 隐含约束：所有敌人必须 `add_to_group("enemies")`，否则收不到噪音。当前由 `Enemy3D._ready` 保证。

---

## 4. Player3D —— 玩家控制

### 4.1 节点结构

`Player3D` 是 `CharacterBody3D`，挂在 `Game3D/Entities`。子节点：

- `Inventory`（Node）— 背包数据 + 信号
- `PlayerHealth`（Node）— HP/无敌帧
- `PlayerShooting`（Node）— 弹药 + 子弹池
- `FirePoint`（Marker3D）— 子弹发射原点
- `Camera3D` 由 `Game3D` 持有，不挂在玩家下

### 4.2 实现

- **移动**：`_physics_process` 读 `Input.get_vector` 在 XZ 平面上构造方向，叠 sprint 倍率，`move_and_slide`。
- **瞄准**：每帧把鼠标位置反投射到 `Y=player.y` 平面，得到瞄准方向；如果鼠标读不到（headless 测试）退化为最后一次移动方向。`look_at` 让模型朝向瞄准方向。`get_aim_direction()` 供 PlayerShooting 和 FogOfWar 查询。
- **冲刺**：单次 1 秒、CD 3 秒，触发时调 `NoiseManager.emit_noise(MEDIUM)`。
- **信号弹**：`signal_flare` 按键 → 调 `GameManager.fire_signal_flare(pos)`，成功后再调 `NoiseManager.emit_noise(GLOBAL)` 并生成 4 秒视觉标记。
- **快捷键 1–8**：按下后调 `$Inventory.use_slot(i)`。
- **边界 clamp**：根据 `GameManager.current_location` 在母车甲板用固定矩形 clamp，远征用 `Game3D.get_expedition_bounds()` 反查 ExpeditionMap 边界。
- **输入锁**：`is_input_locked` 反映 `GameManager.ui_blocking_input`；锁住时移动/射击/信号弹都不响应。

### 4.3 耦合

- **下游**（玩家被调用）：HUD 通过 `_bind_player_refs()` 拿到 Player 下的 `Inventory / PlayerHealth / PlayerShooting` 三个子节点直接连信号。Enemy 通过 `get_tree().get_first_node_in_group("player")` 拿玩家算视野/追击/攻击。Bullet 不直接引用 Player，但起点由 PlayerShooting 取自 `FirePoint`。
- **上游**：调 GameManager / NoiseManager / Inventory.use_slot。
- ⚠️ Player 直接 `get_tree().current_scene.has_method("get_expedition_bounds")` 反查地图边界——这是 Player → Game3D 的反向耦合，让 Player 知道 Game3D 暴露这个方法。改 Player 边界 clamp 时要同步 `Game3D.get_expedition_bounds`。

---

## 5. PlayerHealth / PlayerShooting / Inventory —— 玩家三大子组件

### 5.1 PlayerHealth

- 最简单：`max_hp / current_hp / iframe_timer`，`take_damage` 检查无敌帧后扣血、调 `GameManager.add_erosion(HIT_EROSION_AMOUNT)`、广播 `damaged` 信号、`current_hp ≤ 0` 时 `_die()` 调 `GameManager.set_state(DEAD)`。
- 信号：`damaged` / `died` / `health_changed(current, max)`。
- 调用者：Enemy3D 攻击时取 `player.get_node_or_null("PlayerHealth").take_damage`；Container3D 破解被打断时连 `damaged` 信号（看 §7）；Inventory 用电池时调 `heal`。
- **特殊**：Game3D 在切换 location 时主动调 `reset_health()`（修复 HP 跨 Run 残留 bug）。

### 5.2 PlayerShooting3D

- 持子弹池（默认 18 颗，按需扩容），从 `Entities/Projectiles` 里捞实例。开火扣弹药、调 `bullet.activate(origin, dir, speed)`、调 `NoiseManager.emit_noise(HIGH)`。
- 信号：`ammo_changed(current, max)`。
- 依赖 Player3D 的 `get_aim_direction()`；间接依赖 Bullet 实例的 `activate / deactivate` 公有 API。

### 5.3 Inventory

- 8 槽（`SLOT_COUNT = 8`），`Array[ItemData]`。
- 信号：`inventory_changed(slots, weight, max_weight)` / `pickup_blocked(reason)` / `collectible_changed(count, score)` / `use_blocked(reason)`。
- 公有 API：`add_item / use_slot / get_slot_item / remove_slot_item / get_current_weight / get_collectible_count / calculate_score / clear_on_death / transfer_revealed_item_from_container(container, index)`。
- `add_item` 检查侵蚀上限 / 空槽 / 负重三项，任一失败发 `pickup_blocked`。
- `use_slot` 按物品 type 分发：AMMO → PlayerShooting.add_ammo；BATTERY → PlayerHealth.heal；PURIFIER → GameManager.reduce_erosion；COLLECTIBLE → 拒绝并广播 `use_blocked`。
- **耦合**：`use_slot` 直接 `get_parent().get_node_or_null("PlayerShooting" / "PlayerHealth")` —— 隐含 Inventory 必须挂在 Player 下。⚠️ 这是 Inventory → 玩家结构耦合，不能把 Inventory 移到别处。
- `transfer_revealed_item_from_container` 委托给 `container.transfer_revealed_item_to_inventory(index, self)`，反向调用 Container 的公有 API。

### 5.4 Bullet3D

- `Area3D`，`activate(origin, dir, speed)` 启动飞行，`deactivate` 回池。命中 group `"enemies"` 时调 `body.take_damage(damage)` 再 `call_deferred("deactivate")`。
- 完全不直接知道 Player；纯输入驱动。

---

## 6. Enemy3D —— 巡逻 + 休眠合并

### 6.1 实现

文件 `scripts/enemies/enemy_3d.gd`（约 485 行）。一个脚本覆盖两种敌人：通过 `enemy_type: EnemyType { PATROL, DORMANT }` 区分初始状态：

- PATROL 起始 `State = PATROL`，`is_awake = true`，在 home 附近随机巡逻；看到玩家直接 `force_awaken → CHASE`。
- DORMANT 起始 `State = SLEEP`，`is_awake = false`，靠 `receive_noise` 累积警戒值；达到 `alert_threshold` 唤醒进 CHASE。

状态机：`SLEEP / PATROL / CHASE / ATTACK`。每帧 `_physics_process` 按状态推进 + `move_and_slide()` + `global_position.y = 0.0`（防止爬障碍）。

视觉：自建 `AlertBar`（橙色警戒条）+ `HpBar`（红色血条）两个跟随节点。

### 6.2 关键耦合

- **依赖 GameManager**：取 `current_state` 决定是否冻结、取 `get_erosion_tier` 缩放 HP/伤害、`register_kill` 上报死亡。
- **依赖 Player**：`get_tree().get_first_node_in_group("player")` 拿玩家；攻击调 `player.get_node_or_null("PlayerHealth").take_damage(...)`（⚠️ 直接依赖 Player 节点结构）。
- **被 NoiseManager 调用**：`receive_noise(value)`。
- **被 Extraction 调用**：`react_to_signal_flare(origin, extraction_position)`，让所有巡逻型奔向母车降落点。
- **被 Bullet3D 调用**：`take_damage(amount, from_player)`；`from_player=true` 时会顺便 `force_awaken`（被打就觉醒）。
- 死亡时 `_die()` 广播 `died(self)` 信号、调 `GameManager.register_kill`、`queue_free`。

⚠️ 这个脚本同时承担"巡逻型"和"休眠型"两种行为是当前的简化。如果后续两种类型差异变大（如休眠型加觉醒动画、巡逻型加路径点），需要按 rules.md §3.1 的"不超过 2 层继承"原则拆 base + 两个子类。

---

## 7. Container3D —— 容器搜索

### 7.1 数据模型

容器有两个阶段：

1. **未破解**：玩家长按 E 进入 `_is_cracking`，`_crack_progress` 按 `get_crack_duration()` 推进（侵蚀越高越慢），完成后 `_complete_crack()` 调 `NoiseManager.emit_noise(LOW)` + `open_container()` + 广播 `cracked(self)`。
2. **已破解**：内部 `_search_entries: Array[Dictionary]`，每条 `{item, revealed, transferred, search_progress}`。`MAX_ENTRIES = 12` 上限（对齐 HUD 的 ContainerGrid 格数）。

### 7.2 搜索条目 API（HUD 调用）

- `open_container()` —— 把 `loot_table` 初始化为 entries（已破解后第二次进入 overlay 直接复用）
- `get_search_entry_count() / get_capacity()` —— 槽数信息
- `is_entry_revealed / is_entry_transferred / get_search_duration_for_entry / get_search_progress_ratio / get_revealed_item_name`
- `search_entry(index, duration)` —— 累积搜索进度，到时间翻 revealed=true
- `transfer_revealed_item_to_inventory(index, inventory)` —— 把条目交给 inventory（成功后标记 transferred）
- `add_item_to_container(item)` —— 反向：把背包物品放回容器，优先复用 transferred 槽（保持 UI 槽位索引稳定），全满时 append 直到 MAX_ENTRIES
- `reset()` —— 切换 location 时由 ExpeditionMap.reset 调用

### 7.3 耦合

- **被 ExpeditionMap 调用**：地图 `_wire_containers()` 监听 `cracked` 信号，玩家靠近时 ExpeditionMap 检查 `is_opened()` 决定显示"长按 E 开启"还是"E 搜索"。
- **被 HUD 调用**：所有 7.2 列的 API；HUD `_process_container_search` 每帧调 `search_entry(active_index, delta)` 推进搜索。
- **依赖 GameManager**：`player_erosion`（影响破解时间）、`ui_blocking_input`（弹层打开时不响应破解输入）。
- **依赖 Inventory**：通过 `inventory.add_item(item)` 完成转移（在 `transfer_revealed_item_to_inventory` 里）；不直接依赖 Player，签名上要求外部传入 inventory 节点。
- **依赖 NoiseManager**：破解完成发 LOW 噪音。

⚠️ 容器和 HUD 是这套系统耦合最重的部分——HUD 每帧轮询容器状态、容器把搜索条目的 UI 标签格式（"搜索中... %d%%"）的格式权交给 HUD 处理是正确的。但 HUD 在 `_populate_container_list` 直接知道 entries 的结构（revealed / transferred 含义），如果以后容器内部改成别的模型，HUD 必须同步改。

---

## 8. NoiseManager / 噪音传播

见 §3。无新增内容。

---

## 9. SpawnManager —— 时间-侵蚀刷怪

### 9.1 实现

- **不是 Autoload**，是 `Game3D` 下的普通节点。
- `_ready` 监听 `GameManager.state_changed`，状态进入 PREPARING 时 reset 压力。
- `configure(enemy_parent, patrol_scene, dormant_scene)` 由 `Game3D._add_spawn_manager` 注入需要的场景引用——避免硬编码节点路径。
- **刷怪曲线**：`spawn_curve: Array<[time_threshold, spawns_per_minute]>`，默认 0→30→60→120→180→240→300 秒，对应 0→2→4→8→15→25→40 spm。`sample_curve(t)` 做线性插值。
- 每帧累积 `_spawn_budget += spm * delta / 60.0`；超过 1.0 就 `spawn_enemy()` 一次，单帧上限 3 个避免暴刷。
- `spawn_enemy` 选场景：超过 60 秒且 `randf() < EROSION_DORMANT_RATIO[tier]` 时刷休眠型，否则巡逻型。位置由 `get_farthest_spawn_point` 选——离玩家最远且 ≥ `minimum_spawn_distance`、不在视野避让圆内的点。
- `_find_clear_spawn_position` 从候选点向下射 raycast 检查是否站在障碍上，否则按 8+4 偏移螺旋找空位。

### 9.2 信号 / 公有 API

- 信号：`spawn_occurred(position, kind)`（HUD 用来画 spawn pulse）
- API：`seed_initial_enemies()`、`spawn_enemy(elapsed, tier)`、`on_signal_flare()`、`set_visible_spawn_avoidance(center, radius)`、`get_spawn_direction`、`get_pressure_status`、`get_current_spawns_per_minute`、`get_spawn_points`、`reset_pressure`、`is_signal_active`

### 9.3 耦合

- **依赖 GameManager**：`current_state / elapsed_time / get_erosion_tier / player_position`。
- **依赖 Extraction**：被 Extraction 在信号弹时调 `on_signal_flare()`（注入压力放大）。
- **被 HUD 调用**：`get_pressure_status` 给指示，`spawn_occurred` 信号给屏幕脉冲。
- **被 Minimap 调用**：`get_spawn_points`。
- ⚠️ `seed_initial_enemies` 直接 `get_node_or_null("../World/ExpeditionMap")` 找 `InitialSpawns` 子节点遍历——这是 SpawnManager → ExpeditionMap 的硬编码路径耦合。如果 Game3D 节点树重排会断。

---

## 10. HUD（hud.gd）⚠️ —— 耦合最重的脚本

### 10.1 它做什么

约 1800 行的 Control 脚本。在主玩法过程中承担：

1. **状态条** — HP / 侵蚀 / 弹药 / 负重 / 分数 / 残响碎片数 / 当前 zone 信息 / 风险标签 / 计时
2. **背包格 + 三种弹层**：
   - **背包弹层**（按 B 打开）— 8 格只显示
   - **仓库弹层**（甲板靠近仓库按 E 打开）— 背包 8 格 + 仓库列表，双向拖拽 / 右键转移
   - **容器搜索弹层**（容器破解后按 E 打开）— 背包 8 格 + 容器 12 格网格，双向拖拽 + 实时搜索进度
3. **拖拽路由** — 通过 `storage_drag_slot.gd` 包装，统一在 `can_accept_storage_drop / accept_storage_drop` 路由不同 source/target 组合（backpack ↔ warehouse，backpack ↔ container）
4. **右键菜单** — 上下文菜单 ID 1..6 分别覆盖：使用 / 丢弃 / 背包→仓库 / 仓库→背包 / 容器→背包 / 背包→容器
5. **结果弹层** — Run 结束（SUCCESS/DEAD）的成绩屏 + 重启
6. **主菜单 overlay** — PREPARING 状态的"开始游戏"提示
7. **保持进度条** — afterglow 出发点长按 E 进度
8. **屏幕边缘警戒指示** — `_alert_indicators` 把 ALERT_DETECTION_RANGE 内觉醒的敌人画成屏幕边缘红点
9. **刷怪脉冲** — 监听 `SpawnManager.spawn_occurred`，在敌人方向上画一次性脉冲
10. **小地图** — `_minimap = Minimap.new()`，绘制由 Minimap 类自己处理
11. **键盘输入劫持** — `_unhandled_input` 响应：B（开/关背包 overlay）、ESC（关闭任意 overlay）、Enter/Space（在主菜单/结果弹层时确认）。**注意**：`use_slot_1..8` 数字键由 Player3D 处理直接对应背包槽位，HUD 不再劫持（2026-05-23 之前曾用 `SHORTCUT_KEYS` 在 overlay 打开时把 1-8 劫持成"快速转移容器/仓库第 N 项"，已删除——参见 §19.4 已修复案例）。
12. **结算屏接管** — `_update_end_flow` 在 SUCCESS/DEAD 进入时**强制关闭任意激活的 blocking overlay**（背包/仓库/容器搜索）+ 隐藏 main_overlay + 隐藏运行时 HUD + 显示 result_overlay。强制关闭这一步是必须的——否则玩家在 loot 界面里被打死时 overlay 会挡住 result_overlay，UI 卡住。

### 10.2 内部状态字段（直接节点引用 + 数据缓存共 70+ 变量）

主要类别：
- 玩家三大组件的弱引用：`_inventory / _player_health / _player_shooting`
- 外部系统引用：`_extraction / _spawn_manager / _search_container`
- 弹层根节点：`_backpack_overlay / _storage_overlay / _search_overlay / _active_blocking_overlay / _main_overlay / _result_overlay`
- 状态标签：`_state_label / _time_label / _signal_label / _prompt_label / _risk_label / _zone_name_label / _zone_risk_label / _zone_container`
- 上下文菜单临时状态：`_context_menu / _context_slot_index / _context_warehouse_name / _context_container_index`
- 仓库 stock 字典（hardcoded 4 种物品名 → 数量）：`_warehouse_stock / _warehouse_order / _warehouse_items`
- 容器搜索内部：`_search_active_index / _search_feedback_label / _search_entry_snapshot`
- 视觉效果：`_alert_indicators / _spawn_pulses / _blocked_hide_timer`

### 10.3 耦合

| 方向 | 谁 | 怎么耦 |
|------|----|--------|
| ← | GameManager | 监听所有信号 + 读全局状态 |
| ← | Inventory（Player 子节点）| 监听 4 个信号 + 读 slots / get_current_weight / calculate_score |
| ← | PlayerHealth、PlayerShooting | 监听信号，初始化时读当前值 |
| ← | Extraction | 每帧读 `get_status_text / get_pressure_status` |
| ← | SpawnManager | 监听 `spawn_occurred` + 读 `get_pressure_status` |
| ← | Container3D（_search_container）| 每帧读 entry 数 / 各 entry revealed/transferred/progress + 调 `search_entry / transfer_revealed_item_to_inventory / add_item_to_container` |
| → | Inventory | 调 `add_item / remove_slot_item / get_slot_item / transfer_revealed_item_from_container / use_slot` |
| → | Container3D | 调上面的搜索/转移 API |
| → | GameManager | 写 `set_ui_blocking_input` |
| → | AfterglowMap / ExpeditionMap | 被它们调 `open_storage / open_container_search / set_prompt_text / set_zone_info / set_risk_label_text / show_hold_progress / hide_hold_progress` |

⚠️ **HUD 是当前最严重的耦合枢纽**：

1. **HUD 知道 Player 节点结构**：`_bind_player_refs` 直接 `player.get_node_or_null("PlayerHealth" / "PlayerShooting" / "Inventory")`，写死了 Player 子节点名。
2. **HUD 知道 Container 内部数据**：`_get_container_entry_label` 把 revealed/transferred/search_progress 三个内部字段的语义都搬到 UI 里。
3. **HUD 持有仓库库存**：`_warehouse_stock` 字典写死在 HUD 里，是真正的仓库数据源——这违反了 rules.md §1.4 "HUD 不承担玩法逻辑"。建议把 warehouse 单独抽成一个数据节点。
4. **HUD 直接 hardcode 物品资源路径**：`ITEM_RELIC / ITEM_AMMO / ITEM_BATTERY / ITEM_PURIFIER` 四个常量 preload `.tres`——其他模块改 `.tres` 路径 / 增加物品种类时必须同步 HUD。
5. **HUD 路由所有拖拽**：`storage_drag_slot.gd` 是薄包装；所有 source/target 配对的合法性判断和实际转移都在 HUD 的 `can_accept_storage_drop / accept_storage_drop`，未来新增第 4 种 drop 上下文（如 "丢弃到地面"）都要改 HUD。
6. **HUD 同时是 Render 也是 Controller**：右键菜单弹出、ID 分发、上下文 slot/container index 记忆全在 HUD，这部分逻辑可以抽出成单独的 ContextMenuController。

短期不动，但下次重构 UI 时应优先解决 #3 仓库逻辑、#5 拖拽路由这两点。

### 10.4 storage_drag_slot.gd —— 拖拽包装

30 行的薄 wrapper：把任意 Control 挂上这个脚本 + 设 `owner_hud / accept_target / drag_payload` 三个变量，就能参与 HUD 的拖拽体系。Godot `_get_drag_data / _can_drop_data / _drop_data` 三个回调都委托给 `owner_hud.can_accept_storage_drop / accept_storage_drop`。

它**唯一耦合 HUD**——只能给 HUD 用，不能脱离 HUD 单独工作。

### 10.5 minimap.gd

`Class Minimap extends Control`，约 100 行。每帧根据玩家朝向画三角箭头 + 障碍方块 + 刷怪点红点。

耦合：通过 `get_tree().current_scene.get_node_or_null("World/ExpeditionMap" / "SpawnManager")` 反查外部数据；调 `ExpeditionMap.get_bounds / collect_obstacle_positions` 和 `SpawnManager.get_spawn_points`。

---

## 11. 地图系统：双地图切换 + POI 驱动

### 11.1 Game3D 的地图编排

Game3D 的 `_apply_location(location)` 是地图切换核心：

1. 调对应地图的 `deactivate()` 隐藏旧地图、清碰撞
2. 调 `_reset_player_health()`（修 HP 残留 bug）
3. 切到目标地图，调它的 `activate(player, hud, world_prompt)`
4. 远征模式才显示 `Entities/Enemies` / `Pickups` / `Projectiles` 三个父节点，否则 `visible=false + process_mode=DISABLED`，并清空它们的子节点（防止 loot/敌人/子弹跨 Run 泄漏）
5. FogOfWar 跟着远征模式开关
6. 远征模式还会调 `_reset_expedition_map() → ExpeditionMap.reset()` 把容器都恢复未破解

切换由 `GameManager.location_changed` 信号驱动。

### 11.2 AfterglowMap（母车甲板）

`scripts/maps/afterglow_map.gd`，约 180 行。

- **节点结构**：`afterglow_map.tscn` 里手摆地板、墙、家具 + 两个 `Marker3D`：`WarehousePoint` 和 `DeparturePoint`。
- **交互**：每帧 `_update_interactions` 查玩家离哪个 marker ≤ 3.25m 算"靠近"：
  - WarehousePoint：显示"E 打开仓库"，按 E 调 `_hud.open_storage()`。
  - DeparturePoint：显示"长按 E 出发"，按住 1.4 秒后调 `GameManager.begin_expedition()` 进远征。
- **耦合**：依赖 HUD 的 `open_storage / set_prompt_text / show_hold_progress / hide_hold_progress` 公有 API；依赖 GameManager 状态。
- **测试 hook**：`set_player_near_point(name)` 和 `complete_departure_for_test()` 给 headless 测试用。

### 11.3 ExpeditionMap（远征地图）

`scripts/maps/expedition_map.gd`，约 400 行，关键字段：

- `POI_REGISTRY: Array<Script>` —— 列出当前所有 POI 脚本
- `_risk_zones: Array<Dictionary>` —— 运行时唯一的 zone 数据来源，由 POI 在 `build_all` 时填充
- `@tool` 模式：场景在编辑器里打开就重建 POI，3D 视图直接预览整张地图

**生命周期**：

1. `_ready` 调 `_clear_authored_content`（清掉 `.tscn` 里手摆的 Obstacles/Containers/InitialSpawns/RiskZones 残留），然后 `_build_pois` 遍历 `POI_REGISTRY` 调每个 POI 的 `build_all(parents)`。
2. `activate(player, hud, world_prompt)` 由 Game3D 注入引用、`_wire_containers()` 给每个容器接 `cracked` 信号。
3. `update(delta)` 每帧由 Game3D 调用，做两件事：`_update_risk_label`（把当前 zone 名/风险传给 HUD）和 `_update_container_interactions`（找玩家附近 ≤ 3.2m 的容器，显示"长按 E 开启"或"E 搜索"）。

**对外查询**：`get_bounds / get_risk_zones / get_zone_density_summary / get_player_zone_info / get_player_risk_label / get_containers_node / collect_obstacle_positions`。

**编辑器工具按钮**：`@export_tool_button("Dump POI positions to .gd files")` 调 `poi_dump_utility.gd` 把当前编辑器里 POI 节点的位置反写回各 `*_poi.gd` 源文件（原文件备份为 `.bak`），是用户偏好"手工 + 数据驱动"的关键设施。

### 11.4 POI 模块（8 个）

每个 POI（`core_wreck_poi.gd / south_approach_poi.gd / ...`）是一个 `RefCounted` 子类，通过 `class_name` 注册。约束：

- **常量数据**：
  - `OBSTACLES: Array<[Kind, x, z, sx, sy, sz, rot_deg]>` —— 障碍
  - `CONTAINERS: Array<[x, z, risk, loot_table]>` —— 容器位置 + 风险等级 + loot
  - `SPAWNS: Array<[kind_str, x, z]>` —— 初始 spawn marker
  - `POI_CENTER / POI_SIZE / COMPACT_OFFSET` —— 区域几何
- **静态方法**：
  - `get_zone_def() -> Dictionary` 返回 `{name, center, size, risk, enemy_density, container_density, high_value_weight}`
  - `build_all(parents) -> Dictionary` 调度下面 4 个 build；返回 zone_def
  - `build_obstacles / build_containers / build_spawns / build_zone_marker` 在传入的 4 个父 Node3D 下生成节点
  - `dump_current_state(parents) -> Dictionary` 通过 `poi_dump_utility` 把节点位置写回源文件
  - `_make_static_body / _make_mesh / _make_shape / _make_material` 私有工具

每个 POI 给生成的节点写 `meta["poi_class"] = POI_CLASS_NAME / meta["poi_data_index"] = i`，让 dump 能精确回写到 `OBSTACLES`/`CONTAINERS`/`SPAWNS` 对应数组的对应索引。

**耦合**：POI 之间**互相不知道彼此存在**——`POI_REGISTRY` 是平铺数组，没有依赖关系。POI 只看 `parents` 字典（4 个 Node3D），不知道地图坐标系以外的世界。

⚠️ **共享约束**：POI 现在分布在 EXPEDITION_BOUNDS 内（`Rect2(-300, -175, 600, 350)`），POI 之间几何不重叠是手工保证的。新增 POI 时要肉眼对 zone 矩形（`get_zone_def().center + size`）。

---

## 12. 撤离系统（Extraction）

### 12.1 流程

1. 玩家按 Q：`Player3D._fire_signal_flare` → `GameManager.fire_signal_flare(global_position)` 状态机切到 EXTRACTING + 广播 `signal_flare_fired(origin)` + 玩家额外 `NoiseManager.emit_noise(GLOBAL)`。
2. `Extraction._on_signal_flare_fired`（在 `_ready` 连的信号回调）记录降落位置（`origin + arrival_offset`）、开 75 秒倒计时、调 `SpawnManager.on_signal_flare()` 注入压力、调所有敌人的 `react_to_signal_flare(origin, _landing_position)`（巡逻型奔向母车降落位形成压力波）、生成 `extraction_signal_beacon.tscn`（等待标记）。
3. `_process` 每帧倒计时；到 0 时切场景到 `mothership_extraction_marker.tscn`。
4. 玩家进 `boarding_range = 3.75m` 后按 E → `try_board() → GameManager.set_state(SUCCESS)`。

### 12.2 耦合

- 依赖 GameManager 信号 / 状态。
- 调 SpawnManager.on_signal_flare（通过 `get_parent().get_node_or_null("SpawnManager")` —— 又一处节点路径耦合）。
- 调所有 group "enemies" 的 `react_to_signal_flare`。
- 被 HUD 通过 `_extraction = scene.get_node_or_null("Extraction")` 反查 + 调 `get_status_text / get_pressure_status / get_remaining_time / has_arrived`。

---

## 13. 可视视野（FogOfWar）

实现风格 Project Zomboid：视野锥（鼠标瞄向方向 ±60°，14m）+ 近距 360° 感知圆（3.5m）+ obstacle layer 射线遮挡。

侵蚀拉满时 `cone_range × 0.5`、`close_radius × 0.85`。

实体可见性按 20Hz 刷新（`update_interval = 0.05s`），对 group `["enemies", "pickups"]` 里的 Node3D 设 `visible = true/false`。容器和障碍物不参与判定，始终可见——玩家需要记地图。

公有 API：
- `get_current_cone_range / get_current_close_radius` —— 当前侵蚀下的几何尺寸
- `is_position_visible(world_pos)` —— 单点可见性查询
- `reset_visibility / clear_trail` —— 离开 EXPEDITION 时让所有被隐藏实体复位

耦合：依赖 GameManager.player_erosion / max_erosion；依赖 group "player" 拿玩家；调 Player3D 的 `get_aim_direction()`。被 Game3D 在 location 切换时显式 `process_mode = DISABLED`。

---

## 14. 输入映射

由 `project.godot [input]` 段定义。

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
| `backpack` | B |
| `use_slot_1` ~ `use_slot_8` | 1 ~ 8 |

⚠️ `pause` 按键被定义但**当前没有任何脚本响应**——后续要加暂停菜单时记得检查。

---

## 15. 物理 / 碰撞配置

- 物理引擎：Jolt（`project.godot [physics] 3d/physics_engine="Jolt Physics"`）
- 渲染：D3D12 driver

### 15.1 碰撞层（rules.md §3.2 同步）

| Layer | 名称 | 谁用 |
|-------|------|------|
| 1 | Player | Player3D |
| 2 | Enemy | Enemy3D |
| 3 | Obstacles | POI 障碍 StaticBody3D，layer = 4（位 3 = bit 2 = value 4） |
| 4 | Projectiles | Bullet3D Area3D |
| 5 | Containers | Container3D 的 InteractArea |
| 6 | Boundary | 地图边界 wall |

视野系统的 obstacle 射线掩码 = `1 << 2 = 4`，刷怪点的地面检测 mask = `4`，都对齐"obstacles 在 layer 3"。

### 15.2 Groups

| Group | 谁加入 | 谁查 |
|-------|--------|------|
| `player` | Player3D `_ready` 主动加入 | Enemy3D / Bullet3D / FogOfWar / HUD / Minimap |
| `enemies` | Enemy3D `_ready` 主动加入 | NoiseManager / Bullet3D / Extraction |
| `pickups` | ItemPickup3D | FogOfWar |

---

## 16. 关键数值（rules.md §4.2 的数据"来源真相"对应）

| 参数 | 当前值 | 定义位置 |
|------|--------|----------|
| `GameManager.EROSION_RATE` | 0.0167/s（≈ 1%/60s） | `game_manager.gd` const |
| `GameManager.HIT_EROSION_AMOUNT` | 2.5 | `game_manager.gd` const |
| `GameManager.PURIFIER_REDUCTION` | 17.5 | `game_manager.gd` const |
| `GameManager.max_weight` | 50 | `game_manager.gd` var |
| `GameManager.max_erosion` | 100 | `game_manager.gd` var |
| `EROSION_STAT_MULTIPLIER` | [1.0, 1.0, 1.1, 1.2, 1.35] | `game_manager.gd` const |
| `EROSION_SPAWN_INTERVAL_MULTIPLIER` | [1.0, 1.0, 0.85, 0.7, 0.5] | `game_manager.gd` const |
| `EROSION_DORMANT_RATIO` | [0.0, 0.0, 0.15, 0.3, 0.5] | `game_manager.gd` const |
| Player base_speed | 7.0 | `player_3d.gd` @export |
| Player sprint_multiplier | 1.55 | `player_3d.gd` @export |
| Player sprint duration / cooldown | 1.0s / 3.0s | `player_3d.gd` @export |
| PlayerHealth max_hp | 100 | `player_health.gd` @export |
| PlayerHealth iframe | 0.5s | `player_health.gd` @export |
| PlayerShooting fire_rate | 0.15s | `player_shooting_3d.gd` @export |
| PlayerShooting max_ammo | 60 | `player_shooting_3d.gd` @export |
| Bullet speed | 18.0 | `bullet_3d.gd` @export（PlayerShooting 也用 18.0 默认） |
| Bullet damage | 20.0 | `bullet_3d.gd` @export |
| Bullet lifetime | 1.5s | `bullet_3d.gd` @export |
| Enemy alert_threshold | 100 | `enemy_3d.gd` @export |
| Enemy decay_rate | 5.0/s | `enemy_3d.gd` @export |
| Enemy base_hp / damage | 40 / 15 | `enemy_3d.gd` @export |
| Enemy patrol_speed / chase_speed | 2.2 / 4.2 | `enemy_3d.gd` @export |
| Enemy view_angle / range | 60° / 8m | `enemy_3d.gd` @export |
| Container MAX_ENTRIES | 12 | `container_3d.gd` const |
| Container base_crack_time | 2.0s | `container_3d.gd` @export |
| Container base_search_time | 1.0s | `container_3d.gd` @export |
| NoiseManager Level ranges | LOW 8m / MEDIUM 18m / HIGH 36m | `noise_manager.gd` RANGE_MAP |
| FogOfWar cone_range | 14m | `fog_of_war.gd` @export |
| FogOfWar cone_half_angle | 60° (总 120°) | `fog_of_war.gd` @export |
| FogOfWar close_radius | 3.5m | `fog_of_war.gd` @export |
| FogOfWar erosion_cone_shrink | ×0.5 | `fog_of_war.gd` @export |
| Extraction wait_time | 75s | `extraction.gd` @export |
| Extraction boarding_range | 3.75m | `extraction.gd` @export |
| SpawnManager max_alive_enemies | 32 | `spawn_manager.gd` @export |
| SpawnManager signal_flare_multiplier | 3.0 | `spawn_manager.gd` @export |
| EXPEDITION_BOUNDS | Rect2(-300, -175, 600, 350) | `expedition_map.gd` const |

修改任一数值前先看一眼上述表格找到准确位置；改完后回来更新本表。

---

## 17. 模块耦合总览

将本文档中各模块的耦合方向汇总成下表（→ 表示调用 / 读取）：

```
Player3D ─→ GameManager / NoiseManager / Inventory.use_slot
        ─→ Game3D.get_expedition_bounds  ⚠️ 反向（玩家知道场景根的方法）

PlayerShooting ─→ NoiseManager / Player.get_aim_direction / Bullet.activate

PlayerHealth ─→ GameManager.add_erosion + set_state(DEAD)

Inventory ─→ GameManager / PlayerShooting.add_ammo / PlayerHealth.heal / Container.transfer_revealed_item_to_inventory  ⚠️ 通过 get_parent() 拿 Player 子节点

Container3D ─→ GameManager / NoiseManager / Inventory.add_item
            ←─ HUD（每帧轮询 + 调搜索/转移 API）
            ←─ ExpeditionMap（监听 cracked，靠近时提示）

Enemy3D ─→ GameManager / PlayerHealth.take_damage  ⚠️ 直接 get_node_or_null("PlayerHealth")
        ←─ NoiseManager.receive_noise
        ←─ Bullet.take_damage
        ←─ Extraction.react_to_signal_flare

Bullet3D ─→ Enemy.take_damage  ⚠️ 通过 group "enemies"

SpawnManager ─→ GameManager / Enemy 场景实例化
            ←─ Extraction.on_signal_flare
            ←─ HUD.spawn_occurred
           ⚠️ 直接 get_node_or_null("../World/ExpeditionMap") 找 InitialSpawns

Extraction ─→ GameManager / SpawnManager / Enemy.react_to_signal_flare
           ⚠️ get_parent().get_node_or_null("SpawnManager")

FogOfWar ─→ GameManager / Player.get_aim_direction
         ─→ enemies/pickups group 遍历

AfterglowMap ─→ GameManager / HUD.open_storage / HUD.set_prompt_text

ExpeditionMap ─→ GameManager / HUD（多个 setter）/ Container 信号 + 状态
              ─→ POI_REGISTRY 里的 8 个 POI（数据来源）

POI (× 8) ─→ 只看自己的 OBSTACLES/CONTAINERS/SPAWNS + 传入的 4 个父节点
          ⚠️ POI 之间互不知晓

Game3D ─→ GameManager 信号 + 所有子系统的 activate/deactivate

HUD ─→ Inventory / PlayerHealth / PlayerShooting（Player 子节点）⚠️
     ─→ Container（_search_container, 知道 entry 内部结构）⚠️
     ─→ Extraction / SpawnManager（场景节点反查）⚠️
     ─→ ExpeditionMap（被它调 setter）
     ─→ GameManager.set_ui_blocking_input
     ─→ 仓库库存逻辑 ⚠️（应抽出去）
     ←─ storage_drag_slot.gd（drag-drop 入口）

Minimap ─→ ExpeditionMap.get_bounds / collect_obstacle_positions
        ─→ SpawnManager.get_spawn_points
        ─→ group "player" 拿玩家
```

⚠️ 标记是当前**已知**且**预期会引起未来重构成本**的耦合。整改优先级（高→低）：

1. **HUD 仓库逻辑外放** —— `_warehouse_stock` 应该是独立数据节点（如 `WarehouseInventory`），HUD 只显示
2. **HUD 不再直接持 Container 内部状态语义** —— 容器自己提供 `get_slot_display_text(index)` 让 HUD 当字符串显示
3. **节点路径反查** —— SpawnManager、Extraction、HUD、Minimap 都靠 `get_tree().current_scene.get_node_or_null("...")` 找其他节点；如果 Game3D 节点树重排会同时断掉多处。考虑引入一个 ServiceLocator autoload 或者由 Game3D 统一注入
4. **Player.get_node("PlayerHealth")** —— Enemy / Inventory / HUD 都依赖 PlayerHealth 是 Player 子节点；如果 PlayerHealth 改成单独的 Autoload 或 Component，需要同时改三处

---

## 18. 测试入口

`tests/` 下的 `*_runtime_checks.gd` 都是 `SceneTree` 子类，可在 headless 模式运行。约定：

- 文件命名 `<module>_runtime_checks.gd` + `.uid`
- 通过 `tests/run_godot_runtime_checks.ps1` 跑全部
- `tests/dev_a_static_checks.ps1 / game_3d_static_checks.ps1` 跑静态语法 / 节点路径检查
- 每个测试用 `_expect(condition, message)` 收集失败，结尾 `quit(0/1)`

当前共 11 个 runtime 套件 + 2 个 static 套件，新加功能需要按相同模式新增对应套件并在 `run_godot_runtime_checks.ps1` 里登记。

---

## 19. 已知技术债（截至 2026-05-23）

按 §0.1 的两类耦合分开列。同一条问题可能同时属于两类，按主要矛盾归类。

### 19.1 依赖耦合（call graph 反向 / 紧耦合）

1. **HUD 1800 行** —— 见 §10.3。整个 UI 层既是 View 又是 Controller，仓库库存 / 拖拽路由 / 上下文菜单 / 警戒指示全在一个脚本里。
2. **Inventory.use_slot 直接 `get_parent()` 拿 Player 子节点** —— §5.3。Inventory 必须挂在 Player 下，不能脱离 Player 单独工作。
3. **SpawnManager / Extraction / HUD / Minimap 反查节点路径** —— §17 ⚠️。这四处都靠 `get_tree().current_scene.get_node_or_null("...")` 找其他节点，Game3D 节点树一重排就同时断。考虑引入 ServiceLocator autoload，或由 Game3D 统一注入。
4. **历史脚本 `fog_of_war.gd` 名字与实际职责（可视视野）不一致** —— 改名要同步 fog_of_war.tscn 的 script path 引用 + `.uid`。
5. **`Entities/Containers` 节点空着** —— 容器全在 `ExpeditionMap/Containers`，Game3D 树里的预留父节点没用，建议删。

### 19.2 语义耦合（旧实现的隐含假设泄漏到新场景）

这一类在调用图上看不出来，必须靠看具体场景行为推断。AI 助手"复用现有 API 就完事"时最容易引入。

1. **Container `add_item_to_container` 用"第一个 transferred 槽"复用** —— §7.2。`_search_entries` 的索引语义原本为"按顺序揭示 / 单向转移走"设计，反向写入硬塞了 hack："找到第一个 transferred=true 的槽位填进去"。后果：用户拖到具体某格时，物品落在别处。修复方向：`add_item_to_container(item, target_index)` 接受目标位置参数，让 HUD 拖放路由把具体格子传进来。
2. **HUD `accept_storage_drop(data, target)` 的 target 只到 list 级别** —— §10.3 #5。`target = "container_list"` 是整片 GridContainer，drop 协议**丢了具体哪个格子的空间信息**。修复方向同 #1：把目标 entry_index 也写进 payload。
3. **Container 与 HUD 协议未抽象** —— §10.3 #2 / §7.3。HUD 知道 entries 的 revealed / transferred / search_progress 三个内部字段的语义，并自己拼出"搜索中... %d%%"文案。Container 内部模型一动，HUD 必须同步。修复方向：Container 提供 `get_slot_display_text(index)` 等只读 façade，HUD 当字符串显示。
4. **POI 几何不重叠靠人肉保证** —— §11.4。POI 之间互相不知道彼此存在，但实际在同一坐标系下分布。新增 POI 时需要肉眼对各自的 `get_zone_def().center + size` 矩形。修复方向：在 expedition_map `_build_pois` 后加一个 zone 矩形重叠校验，发现重叠 push_warning。

### 19.3 其他（杂项 / 未实现功能）

1. **`pause` 按键定义但未实现** —— §14。`project.godot` 里有 pause action 但**没有任何脚本响应**，按 ESC 关弹层是 HUD 自己监听 `KEY_ESCAPE` 实现的。后续要加暂停菜单时记得检查。

### 19.4 已修复的案例（教育性记录）

为了让以后接手的 AI 和开发者识别**怎样算"语义耦合"**，这里记录一些已修复案例，**不是 changelog**：

- **HUD overlay 数字键劫持（SHORTCUT_KEYS）** —— 2026-05-23 删除。`hud.gd` 曾有 `SHORTCUT_KEYS = [KEY_1..KEY_8]` 常量 + `_handle_overlay_shortcut`：在 search overlay 打开时把 1-8 键映射到 `_transfer_container_entry(index)`，在 storage overlay 打开时映射到仓库列表。这个机制最初是从背包 8 槽设计的（背包就是 8 个），后来容器扩到 12 格，但常量没人改——结果**容器第 9-12 格的物品没办法用数字键快取**。这是经典语义耦合：旧场景的隐含假设（"槽数 ≤ 8"）跟着代码复用渗透到了新场景，但行为不对。修复方式不是"扩 SHORTCUT_KEYS 到 12"——那样仓库又得对齐——而是直接砍掉劫持，鼠标点击 / 拖拽 / 右键菜单已经能完成转移。
- **容器搜索 overlay 取出后槽位仍显示"已转移"** —— 已修复。`_populate_container_list` 把 transferred 槽设成空字符串，但 `_update_container_search_labels` 每帧又把它覆盖回"已转移"。两个函数有各自的"该显示什么"判断，不一致 → 视觉残留 → 用户以为槽位不可重用。修复方式：抽 `_container_slot_text(index)` 共享 helper，单一真相源。
- **loot/背包 overlay 打开时被怪打死卡 UI** —— 2026-05-23 修复。HUD `_update_end_flow` 进入 SUCCESS/DEAD 状态时显示 result_overlay 并把 ui_blocking 设回 true，但**忘了关已激活的 blocking overlay**。结果两层 UI 互相挡，玩家看不到结算屏。是典型的"两个独立功能（弹层管理 vs 结算流程）共享同一个 ui_blocking 开关但不互相通知"造成的状态不一致。修复方式：`_update_end_flow` 在 SUCCESS/DEAD 分支开头先 `close_blocking_overlay()` 再走结算流程。

---

*文档结束。修改任何代码后，请按 rules.md §6.5 同步更新对应章节。*
