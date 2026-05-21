# 打磨阶段实现计划

> 日期: 2026-05-21
> 阶段: 新内容 + 打磨（MVP 核心闭环已完成）

---

## Plan 1: 事件系统

**目标**: 实现 §9.3 全部 5 种事件，为固定地图提供重玩随机性。

### 1.1 新建 `EventManager`

- 路径: `scripts/managers/event_manager.gd`
- 挂载: 作为 `game_3d.tscn` 的 `EventManager` 子节点（非 Autoload，仅在 Expedition 期间活跃）
- 生命周期: 随 GameManager.state 变化启动/停止

### 1.2 事件定义

| 事件 | 触发条件 | 效果 | 冷却 (s) |
|------|---------|------|----------|
| **容器警报** | 破解完成时 15% 概率 | 以容器为圆心 40 单位内敌人警戒值 +70（不直接觉醒） | 45 |
| **紧急补给** | 每 60-120s 随机抽检 | 在随机低风险区生成 1 个临时补给品（弹药/电池），60s 后消失 | 90 |
| **电磁脉冲** | 每 90-180s 随机抽检 | 随机选择一个风险区，区域内休眠型敌人全部觉醒；屏幕闪白 + HUD 警告 3s | 120 |
| **封锁区域开启** | 90s 和 180s 各触发一次 | 地图角落打开一个新区域，内含 2-3 个高价值容器 | —（单次） |
| **敌人潮汐** | 120s+ 后每 60-120s 随机抽检 | 从某一地图边缘方向连刷 5-8 个巡逻型敌人（3s 内刷完） | 90 |

### 1.3 实现细节

**event_manager.gd 结构**:
```
Node
├── _event_timers: Dictionary[String, float]   # 冷却计时
├── _triggered_events: Array[String]            # 已触发的一次性事件名
├── _process(delta)                              # 定时抽检
├── trigger_container_alarm(container_pos)
├── spawn_emergency_supply()
├── trigger_emp_pulse()
├── trigger_blocked_area()
├── trigger_enemy_tide()
└── _show_hud_notification(text, duration)
```

**与现有系统交互**:
- 容器警报: 连接 `container_3d.cracked` 信号（在 expedition_map._wire_containers 中）
- 紧急补给: 通过 SpawnManager 或在 Map/Entities/Pickups 下生成 ItemPickup3D
- 电磁脉冲: 遍历 enemies group，对休眠型调用 force_awaken()
- 封锁区域: 需要在地图 .tscn 中预留 "BlockedArea" 节点，事件触发时 visible=true
- 敌人潮汐: 调用 SpawnManager 的批量生成接口

**HUD 通知**: 在 HUD 顶部居中显示事件文本（如 "⚠ CONTAINER ALARM"），3s 淡出。颜色按事件类型区分。

### 1.4 工时估算

| 任务 | 工时 |
|------|------|
| event_manager.gd 核心逻辑 | 1.5h |
| 5 种事件各自实现 | 2h |
| HUD 事件通知 UI | 0.5h |
| 地图预留 BlockedArea 节点 | 0.5h |
| 测试 + 调参 | 1h |
| **合计** | **~5.5h** |

---

## Plan 2: 小地图

**目标**: 在 HUD 左下角显示完整地图（障碍物 + 刷怪点 + 玩家位置），不显示 Loot。

### 2.1 方案选择

采用 **2D 绘制方案**（而非 SubViewport），理由:
- 地图为固定布局，障碍物位置已知
- 无须额外渲染管线
- 性能开销为零
- 更易添加动态标记（玩家位置、刷怪脉冲）

### 2.2 实现

**新建文件**: `scripts/ui/minimap.gd`

```
class_name Minimap
extends Control

const MAP_SIZE := Vector2(240, 120)           # 小地图像素尺寸
const WORLD_BOUNDS := Rect2(-240, -120, 480, 240)  # 世界坐标范围
const PLAYER_DOT_RADIUS := 3.0
const SPAWN_DOT_RADIUS := 2.5

var _player_dot_color := Color(0.3, 0.9, 0.5, 1.0)
var _spawn_dot_color := Color(1.0, 0.3, 0.2, 1.0)
var _obstacle_color := Color(0.25, 0.25, 0.25, 0.8)
```

**数据来源**:
- 障碍物: 从 `expedition_map` 获取障碍物世界坐标列表（新增 export Array[Vector2]）
- 刷怪点: 从 `SpawnManager.DEFAULT_SPAWN_POINTS` 读取
- 玩家位置: `GameManager.player_position`

**绘制**:
- `_ready()`: 初始化 Control 尺寸、位置（HUD 左下角 anchored）
- `_draw()`: 
  1. 绘制背景（半透明深色矩形）
  2. 遍历障碍物坐标，按比例映射绘制小方块
  3. 绘制刷怪点（红色小圆）
  4. 绘制玩家位置（绿色小三角，带方向指示）
  5. 如果有信号弹激活，绘制信号弹位置（橙色闪烁）

**坐标映射**:
```gdscript
func world_to_minimap(world_pos: Vector3) -> Vector2:
    var ratio := (Vector2(world_pos.x, world_pos.z) - WORLD_BOUNDS.position) / WORLD_BOUNDS.size
    return ratio * MAP_SIZE
```

### 2.3 数据准备

**expedition_map.tscn 障碍物数据导出**:
- 在 `expedition_map.gd` 新增 `@export var obstacle_positions: Array[Vector2] = []`
- 遍历 World/Obstacles 子节点收集每个 StaticBody3D 的 `global_position.xz`
- 或在 `_ready()` 中自动收集 CollisionShape3D 的 global_position

**expedition_map.gd 追加**:
```gdscript
func collect_obstacle_positions() -> Array[Vector2]:
    var positions: Array[Vector2] = []
    var obstacles := get_node_or_null("Obstacles")
    if obstacles == null:
        return positions
    for child in obstacles.get_children():
        if child is Node3D:
            positions.append(Vector2(child.global_position.x, child.global_position.z))
    return positions
```

### 2.4 工时估算

| 任务 | 工时 |
|------|------|
| minimap.gd 绘制逻辑 | 1h |
| 障碍物数据收集 | 0.5h |
| HUD 集成（位置、锚点） | 0.5h |
| 测试 | 0.5h |
| **合计** | **~2.5h** |

---

## Plan 3: 敌人警觉 UI

**目标**: 屏幕边缘脉冲方向指示，提醒玩家觉醒敌人来自哪个方向。

### 3.1 实现

**在 `hud.gd` 中追加**（不新建文件，逻辑较轻）:

```gdscript
const ALERT_INDICATOR_SIZE := 32.0
const ALERT_PULSE_SPEED := 4.0
const ALERT_MAX_OPACITY := 0.9
const ALERT_DETECTION_RANGE := 25.0

var _alert_indicators: Array[Dictionary] = []  # [{enemy, screen_pos, opacity}]
```

**_process 中追加 `_update_alert_indicators(delta)`**:
1. 遍历 `enemies` group
2. 筛选 `is_awake() and get_ai_state_name() in ["CHASE", "ATTACK"]`
3. 计算敌人世界坐标 → 屏幕坐标（Camera3D.unproject_position）
4. 如果屏幕坐标在视口外 → 计算最近的屏幕边缘点
5. 应用脉冲效果: `opacity = sin(Time * pulse_speed) * range_factor`
6. 将（位置, 颜色, 透明度）存入 `_alert_indicators`

**_draw 中追加 `_draw_alert_indicators()`**:
- 在屏幕边缘绘制红色楔形三角指向敌人方向
- 多种敌人同方向 → 合并为一个更亮的指示器

**指示器设计**:
- 形状: 指向内侧的三角形（▶ 朝向屏幕中心）
- 颜色: 红色 `Color(1.0, 0.25, 0.15, alpha)`
- 尺寸: 32-40px
- 位置: 从屏幕边缘向内偏移 8px
- 动画: alpha 按 sin 脉冲（周期 ~0.5s）

### 3.2 工时估算

| 任务 | 工时 |
|------|------|
| 屏幕坐标映射逻辑 | 0.5h |
| 脉冲动画 + 绘制 | 1h |
| 同方向合并逻辑 | 0.5h |
| 测试 | 0.5h |
| **合计** | **~2.5h** |

---

## Plan 4: 刷怪脉冲提示

**目标**: 当敌人从地图边缘刷出时，屏幕边缘出现方向脉冲 + 方向音效。

### 4.1 信号链路

```
SpawnManager.spawn_enemy() → 发射 spawn_occurred(spawn_position: Vector3)
    → HUD._on_spawn_occurred(pos) → 创建 SpawnPulse 指示器
    → NoiseManager/AudioManager 播放方向音效
```

### 4.2 实现

**SpawnManager 追加**:
```gdscript
signal spawn_occurred(position: Vector3, kind: String)

# 在 spawn_enemy() 成功创建敌人后:
spawn_occurred.emit(point, "enemy")
```

**HUD 追加**:
```gdscript
var _spawn_pulses: Array[Dictionary] = []  # [{direction, timer, opacity}]

func _on_spawn_occurred(pos: Vector3, _kind: String) -> void:
    # 计算从玩家到刷怪点的方向
    var to_spawn := pos - GameManager.player_position
    to_spawn.y = 0.0
    var dir := to_spawn.normalized()
    # 计算屏幕边缘位置
    var edge_pos := _direction_to_screen_edge(dir)
    # 添加脉冲记录
    _spawn_pulses.append({
        "screen_pos": edge_pos,
        "remaining": 2.0,        # 显示 2s
        "max_time": 2.0,
        "direction": dir,
    })
    # 播放音效（带 panning）
    _play_directional_audio("spawn_pulse", dir)
```

**脉冲绘制** (`_draw`):
- 橙色/黄色三角 `Color(1.0, 0.7, 0.15, alpha)`
- 从屏幕边缘向内动画（0.2s 进入 → 1.5s 保持 → 0.3s 淡出）
- 比警觉 UI 更大（~48px）

### 4.3 音效（方向）

**最小化音效方案**（无需完整音频系统）:
- 在 `game_3d.tscn` 根节点放一个 `AudioStreamPlayer`
- 使用 `AudioServer.get_bus_index("Master")` 设置 panning
- 或更简单: 播放时根据方向设置 `volume_db` 偏移（后续可完善）
- 现阶段: 先实现视觉脉冲，音效接口预留

### 4.4 工时估算

| 任务 | 工时 |
|------|------|
| SpawnManager signal 追加 | 0.3h |
| HUD 脉冲绘制 + 动画 | 1h |
| 方向音效接口 | 0.5h |
| 测试 | 0.5h |
| **合计** | **~2.3h** |

---

## Plan 5: 地图规模扩展

**目标**: 从当前 480×240 (16×14屏) 扩展至 600×350 (20×23屏)，达到设计文档 20-30 屏要求。

### 5.1 修改清单

**`expedition_map.gd`**:
```gdscript
# 当前
const EXPEDITION_BOUNDS := Rect2(Vector2(-240.0, -120.0), Vector2(480.0, 240.0))

# 目标
const EXPEDITION_BOUNDS := Rect2(Vector2(-300.0, -175.0), Vector2(600.0, 350.0))
```

**`spawn_manager.gd`**:
```gdscript
# 扩展刷怪点覆盖新范围
const DEFAULT_SPAWN_POINTS := [
    Vector3(-270.0, 0.0, -140.0),
    Vector3(-200.0, 0.0, 140.0),
    Vector3(-100.0, 0.0, -155.0),
    Vector3(0.0, 0.0, 145.0),
    Vector3(80.0, 0.0, -158.0),
    Vector3(160.0, 0.0, 130.0),
    Vector3(240.0, 0.0, -145.0),
    Vector3(280.0, 0.0, 80.0),
    Vector3(-280.0, 0.0, -50.0),
    Vector3(-260.0, 0.0, 80.0),
    Vector3(150.0, 0.0, 150.0),
    Vector3(-150.0, 0.0, -140.0),
]
```

**`expedition_map.tscn`** (Godot 编辑器操作):
- 扩展地形 Tile/地面覆盖至新边界
- 新增障碍物区域（废墟、残骸、管道）
- 新增容器分布（按高低风险区密度放置）
- 新增风险区或扩展已有风险区

### 5.2 新风险区规划

| 区域 | 中心 | 尺寸 | 风险 | 描述 |
|------|------|------|------|------|
| Ash Outskirts | (-132, 0) | 192×210 | 低 | 保持 |
| Broken Rail | (8, -22) | 176×182 | 低 | 保持 |
| Black Yard | (132, 8) | 184×214 | 高 | 保持 |
| Core Wreck | (32, 66) | 120×92 | 高 | 保持 |
| **Frozen Depot** | (-200, 100) | 140×100 | 低 | **新增**: 废弃物流仓库，稀疏敌人，低价值容器 |
| **Silent Array** | (220, -80) | 130×120 | 高 | **新增**: 旧天线阵列，密集休眠型守卫，高价值容器 |

### 5.3 工时估算

| 任务 | 工时 |
|------|------|
| expedition_map.gd bounds 更新 | 0.1h |
| spawn_manager 刷怪点扩展 | 0.2h |
| 地图 .tscn 地形扩展 | 1.5h |
| 障碍物 + 容器放置 | 1.5h |
| 新风险区定义 | 0.3h |
| 初始敌人放置 | 0.5h |
| 测试 | 0.5h |
| **合计** | **~4.6h** |

---

## 总工时汇总

| Plan | 内容 | 工时 |
|------|------|------|
| 1 | 事件系统 | 5.5h |
| 2 | 小地图 | 2.5h |
| 3 | 敌人警觉 UI | 2.5h |
| 4 | 刷怪脉冲提示 | 2.3h |
| 5 | 地图规模扩展 | 4.6h |
| **合计** | | **~17.4h** |

---

## 开发顺序建议

```
Phase 1 (先跑通基础设施):
  Plan 2 小地图      (独立系统，不依赖其他)
  Plan 5 地图扩展     (内容工作，阻塞 Plan 1 封锁区域)

Phase 2 (体验增强):
  Plan 1 事件系统    (依赖 Plan 5 的新区域节点)
  Plan 3 敌人警觉 UI  (独立系统)

Phase 3 (收尾):
  Plan 4 刷怪脉冲     (依赖 SpawnManager signal)
```

---

## 风险点

1. **Plan 1 封锁区域**: 需要在地图 .tscn 中预埋 BlockedArea 节点，与 Plan 5 地图扩展有耦合
2. **Plan 2 障碍物数据**: 如果 .tscn 中障碍物不在统一的 "Obstacles" 节点下，需要手动收集坐标
3. **Plan 3+4 UI 叠加**: 警觉 UI 和刷怪脉冲都在屏幕边缘绘制，需要避免视觉冲突（建议警觉 UI 用红色三角、刷怪用橙色三角，位置错开）
