# 《余晖号》美术与音乐资源清单

> **阶段**: 新内容 + 打磨（MVP 核心闭环已完成）。
> 面向 7 天 Demo 提交，当前重点是补齐资源、提升观感与反馈。

## 使用原则

- **P0 核心音效**: 必须覆盖射击、命中、受伤、敌人觉醒、破解、拾取、信号弹、撤离成功、死亡——支撑完整 Run 体验。
- **P1 闭环**: 开始/结算界面资源、BGM 三段衔接、事件系统反馈、小地图 UI。
- **P2 打磨**: 美术替换 placeholder、氛围音效、侵蚀视觉反馈、提交材料。
- **风格方向**: 3D 正交斜俯视低模/纸片风，近未来轻末世，主色调为翡翠绿、黄昏橙、暗灰金属。
- **推荐格式**: 短音效用 `.wav`，BGM 和长循环用 `.ogg`，图片用透明背景 `.png`，UI 可用 `.png` 或 Godot 控件样式资源。
- **推荐目录**:
  - `assets/models/`
  - `assets/materials/`
  - `assets/sprites/player/`
  - `assets/sprites/enemies/`
  - `assets/sprites/items/`
  - `assets/sprites/tiles/`
  - `assets/sprites/vfx/`
  - `assets/ui/`
  - `assets/audio/sfx/`
  - `assets/audio/bgm/`

---

## 美术资源清单

### 当前已实现（代码完成，使用 placeholder 占位）

| 模块 | 资源 | 当前状态 | 对接模块 |
|------|------|----------|----------|
| 主角 | 3D 占位 Mesh（移动/静止） | ✅ BoxMesh 占位 | `scenes/player_3d.tscn` |
| 武器 | 子弹 3D 发光体 | ✅ 小 BoxMesh + 发光材质 | `scenes/bullet_3d.tscn` |
| 敌人 | 巡逻型/休眠型 3D 占位 Mesh | ✅ BoxMesh + 警戒条/HP条 | `scenes/patrol_enemy_3d.tscn`、`dormant_enemy_3d.tscn` |
| 容器 | 通用容器 3D Mesh（破解前/中/后三色） | ✅ BoxMesh + 动态颜色材质 | `scenes/container_3d.tscn` |
| 物品 | 地面拾取物（4 类颜色区分） | ✅ 小 BoxMesh + 颜色代码 | `scenes/item_pickup_3d.tscn` |
| HUD | HP条/侵蚀条/弹药/负重/分数/信号弹 | ✅ Godot 控件程序化绘制 | `scripts/ui/hud.gd` |
| HUD | 破解读条进度条 | ✅ 程序化 ColorRect 条 | `scripts/ui/hud.gd` |
| HUD | 8 格背包槽 + 物品颜色标识 | ✅ Panel + ColorRect | `scripts/ui/hud.gd` |
| HUD | 开始界面/结算界面 | ✅ ColorRect 程序化 UI | `scripts/ui/hud.gd` |
| VFX | 信号弹标记 + 撤离信标 + 母车到达标记 | ✅ 3D 占位 marker | `Extraction` |
| VFX | 侵蚀→视野缩小（shader） | ✅ fog shader（仅侵蚀视野缩小） | `scripts/systems/fog_of_war.gd` |
| 地图 | 障碍物（废墟/残骸/管道） | ✅ 3D 占位 Mesh 已放置 | `scenes/expedition_map.tscn` |
| 地图 | 边界（电磁障壁占位） | ✅ 3D 占位 Mesh | 地图边界 |

### P0: 核心玩法必替换/新增

> 当前 placeholder 可跑通完整 Run，以下为提升可辨识性和反馈强度必需。

| 模块 | 资源 | 最低需求 | 用途 | 对接模块 |
|------|------|----------|------|----------|
| 主角 | 主角低模/纸片（替换 BoxMesh） | 1 个 Mesh 或 Sprite3D 图集 | 玩家视觉识别 | `scenes/player_3d.tscn` |
| 主角 | 主角移动动画 | 6-8 帧 | 360° 移动时播放 | `scripts/player/player_3d.gd` |
| 主角 | 主角冲刺动画或残影 | 4 帧或 1 张残影贴图 | 冲刺反馈 | `scripts/player/player_3d.gd` |
| 主角 | 主角受伤闪白/受击帧 | 1-2 帧 | 受击和无敌帧反馈 | `scripts/player/player_health.gd` |
| 武器 | 枪口火光 | 2-3 帧 | 射击瞬间反馈 | `scripts/player/player_shooting_3d.gd` |
| 武器 | 命中特效 | 2-4 帧 | 子弹命中敌人/障碍 | `scripts/player/bullet_3d.gd` |
| 敌人 | 巡逻型空闲/移动（替换 BoxMesh） | 各 4-6 帧 | 巡逻和追击辨识 | `scenes/patrol_enemy_3d.tscn` |
| 敌人 | 巡逻型攻击 | 3-5 帧 | 近身攻击提示 | `scripts/enemies/enemy_3d.gd` |
| 敌人 | 巡逻型死亡 | 4-6 帧或爆散贴图 | 击杀反馈 | `scripts/enemies/enemy_3d.gd` |
| 敌人 | 休眠型休眠态（替换 BoxMesh） | 1-2 帧 | 未觉醒状态识别 | `scenes/dormant_enemy_3d.tscn` |
| 敌人 | 休眠型觉醒/追击 | 4-6 帧 | 噪音唤醒后的追击 | `scripts/enemies/enemy_3d.gd` |
| 敌人 | 敌人警戒值头顶条 | ✅ 已实现（程序化 3D bar） | 警戒值升高可见 | `scripts/enemies/enemy_3d.gd` |
| 容器 | 普通容器关闭/打开外观（替换 BoxMesh） | 各 1 个 Mesh/Sprite3D | 搜刮主容器辨识 | `scenes/container_3d.tscn` |
| 容器 | 弹药箱关闭/打开外观 | 各 1 个 Mesh/Sprite3D、绿色区分 | 弹药补给辨识 | `resources/items/standard_ammo.tres` |
| 容器 | 医疗容器关闭/打开外观 | 各 1 个 Mesh/Sprite3D、白色+红十字 | 电池/净化剂来源辨识 | `resources/items/battery_small.tres` / `purifier.tres` |
| 物品 | 地面拾取物 4 类图标替换 | 收集品/弹药/电池/净化剂各 1 图标 | 掉落物可辨识 | `scenes/item_pickup_3d.tscn` |
| 物品 | 残响收集品图标 | 1-3 种 | 分数来源、背包显示 | `resources/items/relic_small.tres` |
| 物品 | 标准弹药图标 | 1 张 | 拾取和背包显示 | `resources/items/standard_ammo.tres` |
| 物品 | 能量电池图标 | 1 张 | 回复 HP | `resources/items/battery_small.tres` |
| 物品 | 净化剂图标 | 1 张 | 降低侵蚀 | `resources/items/purifier.tres` |
| 地图 | 3D 地面材质/低模块 | 4-8 张变体或 Mesh 材质 | 地图铺底替换 | `scenes/expedition_map.tscn` |
| 地图 | 高价值区地面标识 | 2-4 张变体 | 引导玩家探索风险区 | 地图场景 |
| 地图 | 边界/电磁障壁 VFX | 2-4 张或可平铺翡翠绿半透明素材 | 地图外圈视觉 | 地图边界 |
| VFX | 信号弹发射特效 | 4-8 帧 | 按 Q 发射信号弹 | `Extraction` |
| VFX | 撤离等待标识循环特效 | 1 套 | 撤离等待位置视觉 | `Extraction` |
| VFX | 母车剪影/低模 + 到达提示 | 1 个剪影 + 1 套提示特效 | 登车成功点 | `Extraction` |
| VFX | 侵蚀视觉叠加 | 2-3 档颜色/噪点 Overlay | 侵蚀越高画面越压迫 | HUD / 后处理 |

### P1: 打磨阶段新增功能资源

> 对应 `docs/polish_plan.md` 中的新增系统。

| 模块 | 资源 | 最低需求 | 用途 | 对接模块 |
|------|------|----------|------|----------|
| **小地图** | 玩家位置指示（绿色三角） | 1 个图标 | 小地图上标记玩家 | `scripts/ui/minimap.gd` **[新增]** |
| **小地图** | 刷怪点标记（红色小圆） | 1 个图标 | 小地图上标记刷怪点 | `scripts/ui/minimap.gd` **[新增]** |
| **小地图** | 障碍物样式（深灰方块） | 程序化即可 | 地图障碍物呈现 | `scripts/ui/minimap.gd` **[新增]** |
| **小地图** | 背景面板 | 1 张半透明面板或九宫格 | 小地图底板 | `scripts/ui/minimap.gd` **[新增]** |
| **警觉 UI** | 屏幕边缘红色三角指示器 | 上下左右 + 斜向共 8 向 | 觉醒敌人方向提示 | `scripts/ui/hud.gd` **[新增]** |
| **刷怪脉冲** | 屏幕边缘橙色三角指示器 | 上下左右 + 斜向共 8 向 | 新敌人刷出方向提示 | `scripts/ui/hud.gd` **[新增]** |
| **事件** | 事件通知弹窗/横幅 | 5 种事件各 1 个图标或文字样式 | 容器警报/EMP/潮汐等发生时 HUD 提示 | `scripts/managers/event_manager.gd` **[新增]** |
| **事件** | 封锁区域视觉 | 障碍物/屏障 + 开启动画 | 封锁区域开启事件 | `scenes/expedition_map.tscn` **[新增]** |
| **事件** | 紧急补给点标记 | 1 套闪烁标记 | 临时补给出现位置 | `scripts/managers/event_manager.gd` **[新增]** |
| 主角 | 死亡动画 | 6-8 帧或淡出特效 | 死亡后进入结算 | `scripts/player/player_health.gd` |
| UI | 开始界面标题字 | "余晖号"标题 Logo | 主菜单第一屏 | `scripts/ui/hud.gd` |
| UI | 结算数据图标 | 击杀、搜刮、侵蚀、存活时间 | Run 结果回顾 | `scripts/ui/hud.gd` |
| UI | 成功/死亡结果标识 | 各 1 张 | 区分撤离成功和死亡 | `scripts/ui/hud.gd` |
| 地图 | 地图装饰物 | 10-20 个 | 提升探索区域辨识度 | `scenes/expedition_map.tscn` |
| VFX | 屏幕震动辅助素材 | 边缘闪光/受击 vignette | 射击、受击手感 | HUD / 后处理 |

### P2: 提交前打磨

| 模块 | 资源 | 最低需求 | 用途 |
|------|------|----------|------|
| 主角 | 射击姿态 | 4-6 帧 | 提升战斗可读性 |
| 主角 | 冲刺残影多色版本 | 2-3 档 | 高侵蚀状态反馈 |
| 敌人 | 巡逻型受击帧 | 1-2 帧 | 命中反馈 |
| 敌人 | 休眠型觉醒过渡动画 | 6-8 帧 | 噪音唤醒更明显 |
| 容器 | 稀有容器外观 | 1-2 种 | 高价值区奖励感 |
| UI | 提交用封面图 | 1 张 16:9 | Game Jam 页面 |
| UI | 提交截图构图框 | 3-5 张截图建议 | 提交材料 |

---

## 音乐与音效资源清单

### BGM

| 优先级 | 资源 | 时长/循环 | 情绪 | 触发场景 |
|------|------|-----------|------|----------|
| P0 | 探索阶段 BGM | 60-120 秒无缝循环 | 空旷、神秘、低压 | Run 开始、普通探索 |
| P0 | 战斗阶段 BGM 或音乐层 | 45-90 秒无缝循环 | 紧张、机械、节奏增强 | 敌人追击或战斗密度升高 |
| P0 | 撤离阶段 BGM | 60-90 秒无缝循环 | 高压、倒计时、推进感 | 信号弹发射后等待母车 |
| P1 | 主菜单 BGM | 30-60 秒循环 | 温情、末世余晖感 | 开始界面 |
| P1 | 结算成功短乐句 | 3-6 秒 | 释放、完成感 | 撤离成功 |
| P1 | 死亡短乐句 | 3-6 秒 | 失落、低沉 | 玩家死亡 |
| P2 | 侵蚀高压音乐层 | 30-60 秒循环 | 不安、失真、压迫 | 侵蚀 75% 以上叠加 |

### P0 音效: 核心玩法反馈

| 模块 | 音效 | 数量 | 用途 | 触发点 |
|------|------|------|------|--------|
| 玩家 | 脚步声 | 3-5 个变体 | 移动反馈 | 移动中按步频播放 |
| 玩家 | 冲刺启动 | 1-2 个 | 冲刺瞬间反馈 | 按 `Shift` |
| 玩家 | 受伤 | 2-3 个变体 | 被敌人攻击 | `PlayerHealth.take_damage()` |
| 玩家 | 死亡 | 1 个 | HP 归零 | `GameManager.State.DEAD` |
| 武器 | 射击 | 2-4 个变体 | 开枪反馈 | `PlayerShooting.fire()` |
| 武器 | 空仓/无弹 | 1 个 | 弹药为 0 时提示 | 射击输入但无弹 |
| 武器 | 子弹命中敌人 | 2-3 个变体 | 命中确认 | `Bullet` 命中敌人 |
| 武器 | 子弹命中障碍 | 2-3 个变体 | 打到墙/障碍 | `Bullet` 命中障碍 |
| 武器 | 敌人死亡爆裂 | 2 个变体 | 击杀反馈 | `EnemyBase.die()` |
| 容器 | 破解开始 | 1 个 | 读条启动 | `Container.start_crack()` |
| 容器 | 破解循环 | 1 个可循环 | 长按破解过程 | 读条期间 |
| 容器 | 破解中断 | 1 个 | 松手/受击/离开范围 | `Container.interrupt()` |
| 容器 | 破解完成/打开 | 1-2 个 | 容器打开 | `Container.complete_crack()` |
| 容器 | 搜索揭示完成 | 1 个 | 物品格揭示完毕 **[新增]** | 搜索 UI 揭示 |
| 物品 | 拾取残响 | 2 个变体 | 收集品入包 | `Inventory.add_item()` |
| 物品 | 拾取弹药 | 1-2 个 | 弹药入包或补给 | 弹药物品使用 |
| 物品 | 使用能量电池 | 1 个 | 回复 HP | `Inventory.use_slot()` |
| 物品 | 使用净化剂 | 1 个 | 降低侵蚀 | `Inventory.use_slot()` |
| 物品 | 拾取失败提示 | 1 个 | 负重满/侵蚀满/背包满 | `pickup_blocked` |
| 敌人 | 警戒值升高提示 | 1-2 个 | 玩家感觉被注意到 | `receive_noise()` 达到高值 |
| 敌人 | 觉醒警报 | 2 个变体 | 休眠或巡逻敌人进入追击 | `EnemyBase.awaken()` |
| 敌人 | 攻击挥击/射击 | 2-3 个 | 敌人攻击动作 | 敌人攻击 |
| 敌人 | 受击 | 2-3 个变体 | 敌人被打中 | `EnemyBase.take_damage()` |
| 噪音 | 低噪音扩散 | 1 个 | 破解容器 | `NoiseManager.Level.LOW` |
| 噪音 | 中噪音扩散 | 1 个 | 冲刺 | `NoiseManager.Level.MEDIUM` |
| 噪音 | 高噪音扩散 | 1 个 | 开枪 | `NoiseManager.Level.HIGH` |
| 撤离 | 信号弹发射 | 1 个 | 发射撤离信号 | `signal_flare` |
| 撤离 | 全图警报/远处回应 | 1 个 | 撤离阶段开始 | `NoiseManager.Level.GLOBAL` |
| 撤离 | 母车接近 | 1 个长音效 | 等待结束前提示 | `Extraction` 倒计时结束 |
| 撤离 | 登车成功 | 1 个 | 撤离成功 | `GameManager.State.SUCCESS` |
| 刷怪 | 屏幕边缘脉冲方向音效 | 1-2 个 | 敌人从某方向涌入 **[新增]** | `SpawnManager.spawn_occurred` |
| 事件 | 容器警报 | 1 个 | 破解触发警报 **[新增]** | `EventManager` |
| 事件 | 紧急补给出现 | 1 个 | 临时补给点出现 **[新增]** | `EventManager` |
| 事件 | 电磁脉冲 | 1 个 | 区域断电/敌人觉醒 **[新增]** | `EventManager` |
| 事件 | 封锁区域开启 | 1 个 | 通道打开 **[新增]** | `EventManager` |
| 事件 | 敌人潮汐预警 | 1 个 | 某方向大量敌人涌入 **[新增]** | `EventManager` |

### P1 音效: UI 和流程

| 模块 | 音效 | 数量 | 用途 |
|------|------|------|------|
| UI | 按钮悬停 | 1 个 | 开始/结算界面 |
| UI | 按钮确认 | 1 个 | 开始游戏、重新开始 |
| UI | 面板弹出 | 1 个 | 结算界面出现 |
| UI | 分数滚动 | 1 个循环或短音 | 结算计分 |
| UI | 操作提示出现 | 1 个 | 新手提示 |
| HUD | 低血量警告 | 1 个循环或间歇音 | HP 低于 25% |
| HUD | 高侵蚀警告 | 1 个循环或间歇音 | 侵蚀高于 75% |
| HUD | 信号等待倒计时提示 | 1 个 | 母车即将到达 |

### P2 音效: 氛围和打磨

| 模块 | 音效 | 数量 | 用途 |
|------|------|------|------|
| 环境 | 远处电磁噪声 | 2-3 个循环 | 静默区氛围 |
| 环境 | 风声/废墟金属声 | 2-3 个循环 | 地图氛围 |
| 环境 | 高价值区低频脉冲 | 1 个循环 | 区域差异 |
| 敌人 | 远处机械移动 | 2-3 个 | 撤离阶段压迫感 |
| 敌人 | 休眠型低鸣 | 1 个循环 | 靠近休眠敌人时提示 |
| 侵蚀 | 视觉叠加同步噪声 | 2-3 档 | 侵蚀上升时压迫 |

---

## 每日资源交付顺序

> 当前阶段: 新内容 + 打磨（MVP 核心闭环已完成）。

| 时间 | Designer D 优先交付 | 目的 |
|------|--------------------|------|
| Day 5 (当前) | P0 音效核心链路（射击/命中/受伤/觉醒/破解/拾取/信号弹/撤离/死亡）、开始界面标题字、结算数据图标 | 完整 Run 体验有音效、开始到结算闭环 |
| Day 6 | 三段 BGM（探索/战斗/撤离）、事件系统音效（5 种）、刷怪脉冲音效、小地图 UI 元素、屏幕边缘方向指示 | 氛围与新增功能支持 |
| Day 7 | 美术 placeholder 替换（主角/敌人/容器 Mesh → 纸片 Sprite）、侵蚀视觉叠加、提交封面图/截图 | 打磨观感、准备提交 |

---

## 最低可交付标准

- P0 图片资源即使不是最终稿，也必须能清楚区分：玩家、巡逻敌人、休眠敌人、三类容器、四类物品、信号点、撤离点。
- P0 音效必须覆盖：射击、命中、受伤、敌人觉醒、破解、拾取、信号弹、撤离成功、死亡。
- BGM 至少需要三段：探索、战斗、撤离。若时间不足，用一段探索循环加一段撤离高压循环兜底。
- 新增系统（事件、小地图、警觉 UI、刷怪脉冲）至少需要可辨识的 UI 视觉元素和关键音效。
- 所有资源命名必须体现模块和用途，例如 `player_move_01.png`、`sfx_container_open.wav`、`bgm_extraction_loop.ogg`。
- 缺失的视觉资源一律用纯色几何 placeholder 代替，不能阻塞 Dev A/B/C 的主流程集成。
