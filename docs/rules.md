# 《余晖号》开发规范 (Development Rules)

> **适用范围**: 本项目所有开发者（人类 & AI 助手）  
> **引擎**: Godot 4.x · GDScript  
> **最后更新**: 2026-05-24

---

## 1. 项目结构规范

### 1.1 目录布局

```
project/
├── scenes/          # .tscn 场景文件（按功能命名）
├── scripts/         # .gd 脚本（按模块分子目录）
│   ├── managers/    # Autoload 单例 & 全局管理器
│   ├── maps/        # 地图 POI 构建脚本（expedition_map, afterglow_map, POI 模块）
│   ├── player/      # 玩家相关脚本
│   ├── enemies/     # 敌人 AI 脚本
│   ├── items/       # 物品 & 容器脚本
│   ├── systems/     # 独立系统（可视视野、撤离等）
│   └── ui/          # UI 逻辑脚本
├── resources/       # .tres 资源文件（ItemData 等）
│   ├── items/       # 物品数据资源
│   └── events/      # 事件数据资源
├── assets/          # 美术 / 音频 / 字体素材
│   ├── sprites/
│   ├── tiles/
│   ├── audio/
│   └── fonts/
├── docs/            # 设计文档（design.md / implementation.md / sprint.md 等）
└── project.godot
```

### 1.2 文件放置规则

| 类型 | 位置 | 命名 |
|------|------|------|
| 场景 | `scenes/` | `snake_case.tscn` |
| 脚本 | `scripts/<module>/` | `snake_case.gd` |
| 资源 | `resources/<type>/` | `snake_case.tres` |
| 素材 | `assets/<type>/` | `snake_case.png/.wav/.ttf` |
| 文档 | `docs/` | `snake_case.md` |

> **禁止**：在项目根目录随意放置脚本或场景文件（`game.gd` 作为历史遗留暂时保留，后续应迁入 `scripts/`；`scripts/game_3d.gd` 作为历史遗留暂时保留，后续应迁入 `scripts/systems/` 或拆分到各模块）。

### 1.3 Autoload 管理

当前已注册的 Autoload（见 `project.godot`）：

| 名称 | 脚本路径 | 职责 |
|------|----------|------|
| `GameManager` | `scripts/managers/game_manager.gd` | 全局状态、侵蚀、计时、信号弹状态 |
| `NoiseManager` | `scripts/managers/noise_manager.gd` | 噪音传播 & 警戒值 |
| `WarehouseManager` | `scripts/managers/warehouse_manager.gd` | 仓库数据与物品存储中心 |

寻路用 Godot 内建 `NavigationServer3D` + `NavigationRegion3D`（在 expedition_map 场景内）+ `NavigationAgent3D`（在 enemy 场景内），不通过 autoload。

新增 Autoload 必须：
1. 放在 `scripts/managers/` 下
2. 在 `project.godot` 的 `[autoload]` 段注册
3. 在本文件的表格中同步更新

### 1.4 模块边界规则

跨模块协作优先通过 Autoload、信号、Group、Resource 和公有函数完成。

- HUD 只展示状态，不承担玩法逻辑。玩法逻辑放回 Player / Inventory / Enemy / Manager 模块。
- `GameManager` 只保存全局状态、侵蚀、计时、Run 状态，不直接生成物品、敌人或 UI。
- `NoiseManager` 是唯一噪音传播入口。开枪、冲刺、破解、信号弹都调用它，不在各自脚本里重复遍历敌人。
- `ItemData` 是物品数值唯一来源。分数、负重、补给量、回血、净化量不散落在容器、玩家或结算脚本中。
- `EnemyBase` 暴露 `take_damage()` 和 `receive_noise()`，子弹和噪音系统不关心敌人具体状态机。

### 1.5 模块依赖方向

允许的主依赖方向如下：

```text
Player/Input -> GameManager
PlayerShooting -> NoiseManager -> EnemyBase/Enemy AI
Bullet -> EnemyBase.take_damage()
Enemy AI -> PlayerHealth.take_damage() -> GameManager.add_erosion()
Container -> ItemPickup -> Inventory -> HUD
Inventory -> PlayerShooting / PlayerHealth / GameManager
SpawnManager -> Enemy scenes
Extraction -> NoiseManager + SpawnManager + GameManager
HUD -> 只监听信号，不反向控制玩法
```

**禁止反向耦合**：

- `scripts/items/*` 不直接控制敌人 AI。
- `scripts/enemies/*` 不生成 Loot，不计算背包分数。
- `scripts/ui/*` 不直接修改血量、背包、敌人状态或刷怪曲线。
- `scripts/player/*` 不遍历所有敌人做 AI 决策；需要影响敌人时通过子弹命中或 `NoiseManager`。
- `scripts/managers/game_manager.gd` 不承担具体系统实现，只提供状态和全局数值接口。

---

## 2. GDScript 编码规范

### 2.1 基础风格

遵循 [GDScript 官方风格指南](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)：

- **缩进**: Tab（Godot 默认），**不要用空格**
- **命名**:
  - 变量 / 函数: `snake_case`
  - 类名 / 枚举名: `PascalCase`
  - 常量: `UPPER_SNAKE_CASE`
  - 信号: `snake_case`（过去式动词，如 `died`, `health_changed`）
  - 私有成员: `_leading_underscore`
- **行宽**: 尽量 ≤ 100 字符
- **文件编码**: UTF-8（见 `.editorconfig`）

### 2.2 脚本结构顺序

每个 `.gd` 文件按以下顺序组织：

```gdscript
# 文件名.gd
# 一句话描述此脚本职责
# 额外说明（挂载节点类型等）
extends BaseClass

# 1. 信号
signal something_happened(param: Type)

# 2. 枚举
enum State { IDLE, RUNNING, DEAD }

# 3. 常量
const MAX_SPEED := 300.0

# 4. @export 变量（按逻辑分组，用注释分隔）
@export var speed: float = 200.0

# 5. 普通成员变量
var _internal_state: int = 0

# 6. @onready 变量
@onready var sprite: Sprite2D = $Sprite2D

# 7. 生命周期函数（_ready, _process, _physics_process, _unhandled_input）
func _ready() -> void:
    pass

# 8. 公有函数
func take_damage(amount: float) -> void:
    pass

# 9. 私有函数
func _update_internal() -> void:
    pass
```

### 2.3 类型标注

**强制要求**所有公有函数使用类型标注：

```gdscript
# ✅ 正确
func get_scaled_hp() -> float:
    return base_hp * multiplier

func take_damage(amount: float, from_player: bool = true) -> void:
    pass

# ❌ 错误
func get_scaled_hp():
    return base_hp * multiplier
```

变量声明推荐使用类型推断或显式标注：

```gdscript
var speed: float = 200.0        # 显式标注
var speed := 200.0              # 类型推断（均可）
const MAX_HP := 100.0           # 常量用 :=
```

### 2.4 注释规范

```gdscript
# ----- 区域分隔 -----            ← 用于脚本内逻辑分组

# 单行注释：解释 WHY，不解释 WHAT
var erosion_rate := 0.0167       # 约每 60 秒 +1%（design.md §15）

## 文档注释（Godot 会在编辑器中显示）
## 返回侵蚀阶梯 0-4（参考 design.md §5.4）
func get_erosion_tier() -> int:
```

**文档溯源**：涉及设计决策的常量/参数，在注释中标注出处（如 `design.md §5.4`、`implementation.md §13`）。

### 2.5 信号使用规范

```gdscript
# 定义信号时标注参数类型
signal health_changed(current: float, maximum: float)
signal died(enemy: CharacterBody2D)

# 连接信号：优先用编辑器连接，代码连接时用 Callable
awakened.connect(_on_awakened)

# 避免用匿名 lambda 连接复杂逻辑
# ✅ 简单单行可以用 lambda
awakened.connect(func(): state = State.CHASE)

# ❌ 复杂逻辑不要用 lambda
# awakened.connect(func():
#     state = State.CHASE
#     play_sound()
#     update_ui())
```

### 2.6 节点引用

```gdscript
# ✅ @onready 获取子节点
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# ✅ 安全获取（可能不存在时）
var node := get_node_or_null("OptionalChild")

# ✅ 通过 group 查找（跨场景）
var player := get_tree().get_first_node_in_group("player")

# ❌ 硬编码绝对路径
# var player = get_node("/root/Game/Entities/Player")
```

---

## 3. 场景 & 节点规范

### 3.1 场景设计原则

- **单一职责**: 每个场景代表一个独立实体（Player、PatrolEnemy、Container 等）
- **组合优于继承**: 优先使用子节点组合功能，而非深层继承链
- **当前继承结构**: `enemy_base.gd` ← `patrol_enemy.gd` / `dormant_enemy.gd`（保持不超过 2 层）

### 3.2 碰撞层定义

已在 `project.godot` 中定义（**不要随意修改**）：

| Layer | 名称 | 用途 |
|-------|------|------|
| 1 | Player | 玩家碰撞体 |
| 2 | Enemy | 敌人碰撞体 |
| 3 | Obstacles | 障碍物 / 墙壁（高，挡视线/子弹） |
| 4 | Projectiles | 子弹 |
| 5 | Containers | 容器交互 |
| 6 | Boundary | 地图边界 |
| 7 | LowObstacle | 矮障碍物（不挡视线/子弹，挡玩家/敌人移动，AI 寻路要绕） |

新增碰撞层需在此表格和 `project.godot` 中同步更新。

### 3.3 Group 使用

| Group 名 | 成员 | 用途 |
|-----------|------|------|
| `"player"` | Player 节点 | 全局查找玩家 |
| `"enemies"` | 所有敌人 | 噪音传播遍历 |

新增 Group 需在此处登记。

---

## 4. 资源 & 数据规范

### 4.1 ItemData 资源

所有物品数据使用 `ItemData` (Resource) 定义，保存为 `.tres` 文件到 `resources/items/`：

```
resources/items/
├── relic_small.tres
├── standard_ammo.tres
├── battery_small.tres
└── purifier.tres
```

字段说明见 `scripts/items/item_data.gd`。新增物品类型需先在 `ItemData.Type` 枚举中添加。

### 4.2 数值参数管理

游戏平衡参数集中在以下位置：

| 参数类 | 定义位置 | 示例 |
|--------|----------|------|
| 全局侵蚀参数 | `game_manager.gd` 常量 | `EROSION_RATE`, `HIT_EROSION_AMOUNT` |
| 噪音传播参数 | `noise_manager.gd` 常量 | `Level` 枚举, `RANGE_MAP` |
| 角色运动参数 | `player.gd` @export | `base_speed`, `sprint_multiplier` |
| 敌人属性 | `enemy_base.gd` @export | `alert_threshold`, `base_hp` |
| 物品数值 | `.tres` 资源文件 | `weight`, `score_value` |

> **原则**: 可调参数使用 `@export` 暴露到编辑器；固定设计常量使用 `const`。修改数值时记录在 commit message 中。

---

## 5. Git 工作流

### 5.1 分支策略

```
main              ← 稳定可运行版本，Day 4+ 后保持可跑通
├── dev           ← 日常开发主分支，每日合并
├── feat/xxx      ← 功能分支（如 feat/extraction-system）
└── fix/xxx       ← Bug 修复分支
```

Game Jam 期间简化流程：
- 小改动可直接推 `dev`
- 大功能（跨多文件）走 `feat/` 分支 + PR
- `main` 仅在里程碑验收通过后合并

### 5.1.1 模块化并行开发规则

- 功能分支按模块命名，推荐格式：`feat/player-shooting`、`feat/items-loot`、`feat/enemy-spawn`、`fix/hud-erosion-display`。
- 一个分支尽量只覆盖一个模块。确实需要跨模块时，在 PR 描述中列出涉及的模块和接口变化。
- 多人并行时，优先避免同时修改同一个 `.tscn`。需要改同一场景时，由一个人统一落地节点结构，其他人只改脚本或资源。
- 每天最后 30-45 分钟只做集成和冲突处理，不再启动新的大功能。
- Day 4 之后 `main` 必须保持可跑通完整 Run；未跑通的实验留在 `dev` 或功能分支。

### 5.2 Commit 规范

格式：`<type>(<scope>): <简要描述>`

```
feat(player): 添加冲刺噪音反馈
fix(enemy): 修复巡逻型视觉锥角度计算
balance(erosion): 调整受击侵蚀跳升 2.5% → 3%
docs(design): 更新侵蚀阶梯表
refactor(managers): 提取噪音衰减为独立函数
asset(sprites): 添加休眠型敌人觉醒动画帧
```

Type 列表：`feat` / `fix` / `balance` / `docs` / `refactor` / `asset` / `chore`

### 5.3 .gitignore

已配置忽略（见 `.gitignore`）：
- `.godot/` — 编辑器缓存
- `.claude/` — AI 助手本地状态
- `*.tex` / `*.pdf` — 展示用文档（不入版本控制）
- 临时文件（`*.tmp`, `*.bak`, `*.swp`）

**不要提交**：`.godot/` 目录、个人编辑器布局、AI 会话文件。

---

## 6. AI 辅助开发规范

### 6.1 AI 助手的角色定位

AI 是**结对编程伙伴**，不是自动驾驶。AI 应当：
- ✅ 理解并遵循本文件所有规范
- ✅ 修改前先阅读相关现有代码，保持风格一致
- ✅ 引用设计文档（`design.md`, `implementation.md`）作为决策依据
- ✅ 对不确定的设计决策主动询问，而非自行决定
- ❌ 不要在没有上下文的情况下大规模重构
- ❌ 不要引入项目未使用的第三方依赖或插件
- ❌ 不要修改 `project.godot` 的碰撞层 / 输入映射，除非被明确要求

### 6.2 AI 代码变更守则

#### 变更前

1. **阅读上下文**: 修改文件前，先读取该文件和相关文件的完整内容
2. **理解架构**: 了解 Autoload 单例模式（GameManager / NoiseManager）和信号驱动模式
3. **查阅文档**: 涉及游戏设计的变更，先查阅 `docs/design.md` 对应章节
4. **识别模块**: 根据 §1.4 确认目标模块边界和禁止改动区域
5. **确认范围**: 向人类确认变更范围，避免过度修改

#### 变更中

1. **最小改动**: 只修改必要的代码，不要"顺手"重构无关部分
2. **保留注释**: 不要删除现有的文档注释和设计溯源注释
3. **保持一致**: 使用与现有代码相同的模式（如 `@onready`, `signal`, `match` 语句风格）
4. **类型安全**: 所有新增公有函数必须有完整类型标注
5. **向后兼容**: 修改信号签名或公有函数签名前，检查所有调用点
6. **尊重边界**: 非本模块文件只改调用侧；需要改模块内部实现时，说明原因和影响面

#### 变更后

1. **说明变更**: 在回复中简要总结修改了什么、为什么这样改
2. **指出风险**: 如果改动可能影响其他系统，明确指出
3. **说明接口影响**: 公有函数、信号、Group、Resource 字段有变化时明确列出
4. **建议测试**: 提出验证方法（如 "在编辑器中运行 game.tscn，测试冲刺是否产生噪音"）

### 6.3 AI 禁止操作清单

| 禁止事项 | 原因 |
|----------|------|
| 删除 `.tres` 资源文件 | 可能破坏场景引用 |
| 修改碰撞层编号 / Input Map | 需全项目同步，编辑器操作更安全 |
| 引入 GDExtension / 插件 | 需团队讨论 |
| 修改 `.import` 文件 | 由 Godot 引擎自动生成 |
| 删除现有信号或改变信号参数 | 可能断开编辑器中的信号连接 |
| 绕过模块边界直接改其他模块核心逻辑 | 会破坏模块化和责任归属 |
| 在 HUD 中加入玩法逻辑 | UI 与玩法反向耦合，后续难维护 |
| 在敌人脚本中写背包或 Loot 规则 | 破坏物品系统边界 |
| 在容器脚本中直接控制敌人或刷怪 | 破坏压力系统边界 |

### 6.4 AI 生成代码标记

AI 生成或大幅修改的代码，在文件头部注释中标注：

```gdscript
# extraction.gd
# 撤离系统：信号弹发射 → 等待 → 母车到达 → 登车
# [AI-ASSISTED] 2026-05-18 — 基于 implementation.md §9 生成骨架
extends Node2D
```

这不是为了追责，而是帮助团队快速识别哪些代码需要额外 review。

### 6.5 AI 必须随代码同步更新 implementation.md（强制）

`docs/implementation.md` 是项目结构 + 每个模块的实现思路 + **模块间耦合关系**的权威清单。它会很快过时，**AI 是最容易"改完代码就提交，忘了同步文档"的角色**，所以这条单独列为 AI 规范的一部分。任何 AI 进行的代码变更必须**同步更新 implementation.md 对应章节**，否则视为变更未完成。

具体触发条件：

| 代码变更类型 | 必须同步的 implementation.md 章节 |
|------------|-------------------------------|
| 新增 / 删除 / 重命名 `.gd` 文件 | §1.1 目录结构 |
| 修改 Autoload 列表 | §1.2 Autoload + 本文件 §1.3 |
| 修改 `game_3d.tscn` 节点树 | §1.3 Game3D 节点树 |
| 修改 GameManager / NoiseManager 公有 API 或信号 | §2 / §3 |
| 修改 Player / Inventory / Container / Enemy 等模块的实现思路或耦合 | §4–§9 |
| 新增 / 删除 HUD 弹层、拖拽路由、上下文菜单 ID、overlay 快捷键 | §10 |
| 新增 POI 模块 / 修改 expedition_map 的 POI_REGISTRY | §11.3 / §11.4 |
| 修改撤离流程 | §12 |
| 修改可视视野系统 | §13 |
| 修改输入映射 / 碰撞层 / Group | §14 / §15 |
| 调整任意 §16 表格里列出的数值 | §16 关键数值表 |
| 引入新的反向耦合 / 修复已知耦合 / 发现新的语义耦合 | §17 总览图 + §19 技术债 |
| 新增 / 删除 headless test 套件 | §18 测试入口 |

**AI 同步流程**（强制）：

1. 完成代码改动后，**在同一回合内**立即更新 implementation.md 对应章节
2. 即使改动不影响耦合关系，**至少**更新顶部的"最后更新"日期
3. 在回复中显式列出"已同步 implementation.md 第 X 节"，没同步的章节也要说明（如"§17 总览图无变化"）
4. commit message 用 `docs(impl): ...` 标注文档同步

AI 不允许"先 commit 代码、回头再补文档"——这种延迟同步等同于不同步。

---

## 7. 人类开发者规范

### 7.1 日常工作流

```
1. 拉取最新代码 (git pull)
2. 确认今天负责的模块和接口依赖
3. 在 Godot 编辑器中打开项目
4. 编写/修改代码（遵循 §2 编码规范）
5. 在编辑器中运行测试
6. 提交（遵循 §5.2 commit 规范）
7. 推送 & 必要时发 PR
```

### 7.1.1 每日集成节奏

1. 每天前半段各自完成模块的小闭环。
2. 中途同步一次接口变化，尤其是公有函数、信号、Group、Resource 字段。
3. 当天最后 30-45 分钟只做联调。
4. 如果出现跨域 Bug，先判断是调用方错误还是模块内部错误；调用方错误由调用方修，内部逻辑由模块维护者修。
5. Day 4 是硬节点。如果完整 Run 还没跑通，Day 5-7 暂停新增 polish，全员优先修主流程。

### 7.2 与 AI 协作的最佳实践

- **给 AI 足够上下文**: 描述需求时引用具体文档章节（如 "参考 design.md §8.2 实现休眠型 AI"）
- **分步进行**: 大功能拆成小步骤，逐步让 AI 实现并验证
- **Review AI 输出**: AI 生成的代码必须人工 review 后再合并
- **反馈纠正**: AI 犯错时直接指出，帮助其在本次会话中学习
- **利用 AI 优势**: 模板代码、数据表填充、文档编写、Bug 分析

### 7.3 场景编辑注意事项

- 场景文件（`.tscn`）的结构修改可在 Godot 编辑器或 AI 辅助下进行
- AI 修改 `.tscn` 时需保持节点 `unique_name_in_owner` 标记和信号连接完整
- 多人同时修改同一 `.tscn` 容易冲突，通过分工避免
- 修改后应在编辑器中打开确认节点树、信号连接和布局正常

---

## 8. 文档维护规范

### 8.1 文档体系

| 文档 | 路径 | 用途 | 维护者 |
|------|------|------|--------|
| 游戏设计 | `docs/design.md` | 核心玩法设计（权威来源） | 全员 |
| 技术实现 | `docs/implementation.md` | 代码架构 & 伪代码 | 开发者 |
| 冲刺计划 | `docs/sprint.md` | 每日任务分配 | 全员 |
| 资源清单 | `docs/art_audio_resource_checklist.md` | 美术、音效、音乐交付清单 | 全员 |
| Pitch | `docs/pitch.md` | 对外展示用 | 设计师 |
| 开发规范 | `docs/rules.md`（本文件） | 编码 & 协作规范 | 全员 |

### 8.2 文档更新规则

- **代码与文档同步**: 修改了游戏机制 → 同步更新 `design.md`
- **实现偏离设计时**: 先讨论，再改文档，最后改代码（文档是设计权威）
- **新增系统时**: 在 `implementation.md` 中添加对应章节（AI 触发规则见 §6.5）
- **数值调整时**: 在 commit message 中记录旧值→新值
- **模块边界变化时**: 同步更新本文件 §1.4 和 `docs/sprint.md`
- **美术/音频需求变化时**: 同步更新 `docs/art_audio_resource_checklist.md`

---

## 9. 质量标准

### 9.1 代码可运行性

- **零崩溃底线**: 任何 commit 都不应引入启动即崩溃的 Bug
- **编辑器无报错**: 提交前确认 Godot 编辑器控制台无红色错误
- **空值防护**: 使用 `get_node_or_null()` 处理可能不存在的节点

### 9.2 性能意识

```gdscript
# ✅ 缓存引用
@onready var player := get_tree().get_first_node_in_group("player")

# ❌ 每帧查找
func _process(delta):
    var player = get_tree().get_first_node_in_group("player")  # 每帧调用！
```

- `_process` / `_physics_process` 中避免每帧遍历大量节点
- 噪音传播（`NoiseManager.emit_noise`）已做距离过滤，保持此优化
- NavigationAgent2D 路径查询已在 enemy_base 中封装，不要重复调用

### 9.3 调试规范

```gdscript
# 调试输出用 push_warning / push_error，不要用 print
push_warning("Enemy spawned at invalid position: %s" % str(pos))

# 临时调试用 print 必须在提交前删除
# print("DEBUG: erosion = ", player_erosion)  ← 提交前删除
```

---

## 10. 快速参考卡

### 10.1 常用模式速查

```gdscript
# 获取玩家
var player := get_tree().get_first_node_in_group("player")

# 发出噪音
NoiseManager.emit_noise(global_position, NoiseManager.Level.HIGH)

# 读取/修改侵蚀
var erosion := GameManager.player_erosion
GameManager.add_erosion(2.5)
GameManager.reduce_erosion(17.5)

# 获取侵蚀阶梯（0-4）
var tier := GameManager.get_erosion_tier()

# 切换游戏状态
GameManager.set_state(GameManager.State.EXTRACTING)

# 发射信号弹（玩家输入层调用，成功后进入 EXTRACTING）
var accepted := GameManager.fire_signal_flare(global_position)

# 登记击杀
GameManager.register_kill()
```

### 10.2 新增功能检查清单

- [ ] 代码遵循 §2 编码规范（类型标注、命名、注释）
- [ ] 新文件放在正确目录（§1）
- [ ] 已确认模块边界，不越界修改其他模块核心逻辑（§1.4）
- [ ] 跨模块调用符合依赖方向（§1.5）
- [ ] 新增 Group / 碰撞层已在 §3 登记
- [ ] 新增/修改公有接口已检查所有调用点
- [ ] 涉及设计变更已同步 `docs/design.md`
- [ ] **已按 §6.5 同步 `docs/implementation.md` 对应章节**
- [ ] 涉及任务分工或模块边界变化已同步 `docs/sprint.md`
- [ ] Commit message 遵循 §5.2 格式
- [ ] 编辑器运行无报错
- [ ] AI 生成代码已标注 `[AI-ASSISTED]`

---

*规范是为了让团队高效协作，而非束缚创造力。遇到规范不适用的场景，先讨论再决定。*
