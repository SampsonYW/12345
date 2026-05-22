# 余晖号地图设计规划 (POI Map Design Plan)

> **最后更新**: 2026-05-23  
> **当前分支**: dev-new-map  
> **架构**: POI 驱动（每个 POI 自包含为 `scripts/maps/*_poi.gd`，由 expedition_map.gd 统一调度）
> **设计参考**: 喜盐茶室《精炼工坊》POI 关卡策划视频 (Bilibili BV1F4agztEhC)

---

## 0. 进度快照

### ✅ 已完成

- 视野锥（fog_of_war.gd → vision system）
- 架构迁移：旧 RISK_ZONE_DATA 常量 + .tscn 手摆 → POI_REGISTRY 驱动
- expedition_map.gd 加 `@tool`，编辑器可直接预览整张地图
- 编辑器拖动 → 一键 dump 回 .gd 的 workflow（PackedScene 包装 + POIDumpUtility）
- 自动重叠检测测试（`tests/poi_overlap_runtime_checks.gd`）+ 接入 run_godot_runtime_checks.ps1
- **Core Wreck POI**（HIGH，完整设计，49 障碍 + 5 容器 + 5 spawn）
- **South Approach POI**（LOW，完整设计，31 障碍 + 3 容器 + 2 spawn）
- **Frozen Depot POI**（HIGH，完整设计，42 障碍 + 5 容器 + 4 spawn）
- **Silent Array POI**（HIGH，完整设计，46 障碍 + 5 容器 + 4 spawn）
- **Black Yard POI**（HIGH，完整设计，41 障碍 + 5 容器 + 5 spawn）
- **Ash Outskirts POI**（LOW，完整设计，30 障碍 + 3 容器 + 2 spawn）
- **Broken Rail POI**（LOW，完整设计，34 障碍 + 3 容器 + 2 spawn）

整图：**7 POI · 279 obstacles · 29 containers · 24 spawns · 0 overlap · 12/12 tests pass**

### 🚧 待办

- [ ] 用户 F5 验证所有 POI 视觉/玩法效果
- [ ] 满意后：在 Godot 编辑器里 Ctrl+S 保存 expedition_map.tscn，把 .tscn 残留旧节点的清理落盘

---

## 1. 设计方法论（视频提炼，7 条原则）

| # | 原则 | 视频原话 / 含义 |
|---|------|---------------|
| 1 | 三要素框架 | 搜打撤地图 = 入口 + 资源区 + 出口 |
| 2 | 放射性布局 | 多个进出点 + 1 个核心资源点构成"放射性空间" |
| 3 | 主轴划分子区 | 用 N 个主轴把 POI 切成 ≈5 子区，每子区独立主题（高辨识度） |
| 4 | 公平进入 | 各入口到核心点的时间应**几乎相同** → 最优路线模糊化 |
| 5 | 中心高危 | 核心区"有无数角度能击倒冒进者"，防止熟练玩家直冲 |
| 6 | 多分支短岔路 | 利用"来都来了"心理 → 玩家逗留时间↑、决策点↑ |
| 7 | 环绕缓冲通道 | 外圈"绕过 POI"的通道：路过玩家退路 + 主流玩家迂回（"舒张感"） |

## 2. PvE 转化（余晖号特殊性）

视频 PvP 假设里的 3 种玩家 → 余晖号 PvE 中是**同一玩家的 3 个阶段**：

| 视频里 | 余晖号 |
|--------|--------|
| 探索玩家 | 第 1-3 次 Run（新手摸索） |
| 效率玩家 | 第 10+ 次 Run（熟练直奔高价值） |
| 路过玩家 | 撤离阶段（急着到安全位置等母车） |

每张地图需同时支持这 3 种行为。

---

## 3. 大地图布局

> **2026-05-23 紧凑化重排**：原 POI 中心被通过 `COMPACT_OFFSET` 平移到下面新位置（数据数组保持不动）。Core Wreck 不变作中央锚点。

```
                    北 Z=+150
        ┌──────────────────────────────────────────────────┐
        │  ◆ Frozen Depot           ◆ Silent Array         │  ← HIGH，距 SPAWN ~158m
        │   (-130, +90)              (+130, +90)           │
        │                                                   │
        │              ◆ Core Wreck                         │  ← HIGH+ 中央地标
        │              (0, +80)                             │     距 SPAWN ~80m
        │                                                   │
        │  ◇ Ash Outskirts          ◇ Broken Rail          │  ← LOW，距 SPAWN ~110m
        │   (-110, 0)                (+110, 0)             │
        │                                                   │
        │              ★ SPAWN (0, 0)                       │
        │              母车着陆 + 信号弹撤离                 │
        │                                                   │
        │              ◇ South Approach (0, -45)            │  ← LOW，距 SPAWN ~45m
        │                                                   │
        │              ◆ Black Yard (0, -115)               │  ← HIGH，距 SPAWN ~115m
        └──────────────────────────────────────────────────┘
                    南 Z=-150

  装饰填充（WastelandDecorationPOI）：POI 间空地散布 29 个 RUBBLE/PILLAR/BOX/DRUM
  整图：8 POI（7 主 + 1 装饰）· 308 obstacles · 29 containers · 24 spawns
```

**距离/紧凑度变化**：
- 主 POI 数量没变；中心彼此距离收缩 30-50m
- 各 POI 之间留 ~20-35m 战术走廊，对应"环绕通道"概念
- POI 之间空地填了 29 个装饰物，废土感更强

---

## 4. 已完成 POI 规格

### 4.1 Core Wreck（HIGH，完整）

- **位置**: (X=0, Z=+80)
- **大小**: 80×60m（≈3600 平米，对标视频参考值）
- **3 进出口**: 南 (0, +50) / 西 (-40, +80) / 东 (+40, +80)，距核心 ~25m（公平）
- **4 子区主题**:
  1. **南漏斗区**（Z 50-70）: 倾斜金属板 + 矮石堆，开放低掩体 + 狙击位
  2. **中央反应核心**（X ±15, Z 75-100）: 4 高细柱方阵 + 2 拱壁包围 + 3 容器
  3. **西压力舱**（X -40~-15）: 4 油罐组（视觉锚定）+ 倒下管道
  4. **东维护廊道**（X +15~+40）: 平行管道 + 集装箱节点
  5. **环绕通道**: 外圈 10m 内零散石堆，撤退迂回
- **障碍**: 49 个，7 种 mesh kind（BOX/LONG_BOX/TILTED_BOX/PILLAR/DRUM/WEDGE/RUBBLE）
- **容器**: 5（核心 3 个遗物组 + 压力舱 1 + 维护廊道 1）
- **Spawn**: 3 patrol + 2 dormant
- **文件**: `scripts/maps/core_wreck_poi.gd`

### 4.2 South Approach（LOW，最小骨架）

- **位置**: (0, -60)
- **大小**: 60×50m
- **主题**: 废弃磁轨（平行铁轨段视觉锚定）
- **障碍**: 8（3 铁轨 LONG_BOX + 2 BOX + 3 RUBBLE）
- **容器**: 3（弹药/电池/净化剂）
- **Spawn**: 2 patrol
- **状态**: 占位，未按视频方法论完整设计；可能后续重做或合并进 Black Yard
- **文件**: `scripts/maps/south_approach_poi.gd`

### 4.3 Frozen Depot（HIGH，完整）

- **位置**: (X=-180, Z=+100)
- **大小**: 70×60m
- **3 进出口**: 南 (-180, +70) / 北 (-180, +130) / 东 (-145, +100)，距核心 ~20-25m
- **4 子区主题**:
  1. **南入口仓储区**（Z 72-85）: 2 大集装箱地标 + 散货
  2. **中央迷宫**（Z 86-114）: 3 列南北墙 + 2 横向倒箱挡路（视频原则 6 多分支）
  3. **北侧保险库**（Z 115-128）: 3 高价值容器 + 3 冷冻管道地标（视频原则 5 中心高危）
  4. **东入口廊道**（X -160~-145）: 狭窄通道 + 中间障碍
  5. **环绕通道**: 外圈 7 个冰堆，撤退迂回
- **障碍**: 42 个（含外墙）
- **容器**: 5（北保险库 3 + 迷宫深处 1 + 南入口 1）
- **Spawn**: 2 patrol + 2 dormant
- **视觉主题**: 冰封色调（深蓝青集装箱 / 冰白储罐 / 银蓝管道 / 冰堆），跟 Core Wreck 暖锈色对比
- **文件**: `scripts/maps/frozen_depot_poi.gd`

### 4.4 Silent Array（HIGH，完整）

- **位置**: (X=+180, Z=+100)
- **大小**: 70×60m
- **3 进出口**: 南 (+180, +70) / 北 (+180, +130) / 西 (+145, +100)
- **5 子区主题**:
  1. **南入口荒原**（Z 72-85）: 散落天线碎片 + 倒下天线杆
  2. **天线塔林**（Z 86-108）: 14 根高细 PILLAR 网格 + 2 DRUM 底座（主视觉特征，视野阻断）
  3. **中央倒塌塔废墟**（Z 110-118）: 大型横向倒塔 + 混凝土塔基（横向掩体线）
  4. **北控制掩体**（Z 120-128）: 小型混凝土堡垒 + 3 高价值容器（视频原则 5 中心高危）
  5. **西入口廊道**（X 148-160）: 狭窄通道 + 中间障碍
  6. **环绕通道**: 外圈 7 个锈蚀碎片
- **障碍**: 46 个（含外墙）
- **容器**: 5（控制掩体 3 + 中央塔废墟 1 + 南入口 1）
- **Spawn**: 3 patrol + 1 dormant
- **视觉主题**: 绿色金属（深绿天线塔 / 棕红天线底座 / 灰混凝土碎片 / 锈蚀碎片）
- **跟 Frozen Depot 区分**: 天线阵 vs 集装箱迷宫；垂直 PILLAR 林 vs 水平 LONG_BOX 墙
- **文件**: `scripts/maps/silent_array_poi.gd`

---

## 5. 待办 POI 规划

每个 POI 应按视频方法论自包含设计：3 入口 + 1 核心 + 4-5 子区 + 环绕通道。

### 5.1 Black Yard（HIGH，南远）

- **位置**: 约 (0, -150)
- **大小**: ~80×50m
- **主题**: 碾碎磁轨车场 + 油罐
- **特色**: 大车厢残骸（开阔走廊）+ 油罐密集区对比；适合远射
- **入口**: 3（东/西/北）
- **目标**: ~50 障碍，4-5 容器，2 patrol + 3 dormant

### 5.2 Ash Outskirts（LOW，西）

- **位置**: 约 (-150, 0)
- **大小**: ~70×80m
- **主题**: 废墟 + 灰沙地面
- **特色**: 矮废墟墙构成开放迷宫；新手友好
- **入口**: 2-3
- **目标**: ~30 障碍，3 容器（含 1 净化剂），2 patrol

### 5.3 Broken Rail（LOW，东）

- **位置**: 约 (+150, 0)
- **大小**: ~70×60m
- **主题**: 倒伏铁轨 + 翻倒磁轨车厢
- **特色**: 平行铁轨形成天然走道
- **入口**: 2-3
- **目标**: ~30 障碍，3 容器，2 patrol

---

## 6. 架构

```
scripts/maps/
├── expedition_map.gd       @tool, POI_REGISTRY 驱动，_ready 清空 .tscn 残留 + build_pois
├── core_wreck_poi.gd       静态 builder + 数据数组
├── south_approach_poi.gd   同接口
└── (后续 *_poi.gd 同接口)
```

**POI 接口**：每个 POI 是 `class_name X extends RefCounted`，提供：

| 静态方法 | 职责 |
|---------|------|
| `get_zone_def() -> Dictionary` | 返回 {name, center, size, risk, enemy_density, container_density, high_value_weight} |
| `build_obstacles(parent) -> int` | 把障碍 StaticBody3D 加进 Obstacles 节点 |
| `build_containers(parent) -> int` | 把 container_3d.tscn 实例加进 Containers 节点 |
| `build_spawns(parent) -> int` | 把 Marker3D（命名 PatrolSpawn* / DormantSpawn*）加进 InitialSpawns |
| `build_zone_marker(parent)` | 在 RiskZones 下加地面色块（红=HIGH，绿=LOW） |
| `build_all(parents) -> Dictionary` | 一键调用上述全部 + 返回 zone def |

**expedition_map.gd._ready() 流程**:
1. `_clear_authored_content()` — 清空 .tscn 残留的 4 父容器子节点
2. `_build_pois()` — 遍历 POI_REGISTRY 调每个的 build_all
3. 收集 zone def 到 `_risk_zones` 供 `get_risk_zones()` / `get_zone_density_summary()` / `get_player_zone_info()` 查询

---

## 7. 加新 POI 流程

1. 复制 `south_approach_poi.gd` 改名（如 `frozen_depot_poi.gd`）
2. 改文件头注释 + `class_name` + `POI_CENTER` + `POI_SIZE`
3. 改 `get_zone_def()` 返回的 name/risk/density
4. 改 `OBSTACLES` / `CONTAINERS` / `SPAWNS` 数据数组
5. 在 `expedition_map.gd` 顶部加 `const FrozenDepotPOIScript := preload(...)`
6. 把它加进 `POI_REGISTRY` 数组
7. 在 Godot 编辑器打开 `expedition_map.tscn` 看 3D 预览
8. 跑 `tests/run_godot_runtime_checks.ps1` 验证 11/11 全绿
9. F5 进游戏走过去实地验证

---

## 8. 数值参考

| 参数 | 值 | 备注 |
|------|----|----|
| 玩家视野锥射程 | 14 m | 鼠标方向，可被侵蚀缩到 7m |
| 玩家近距感知圆 | 3.5 m | 360° |
| POI 标准大小 | 60×50 ~ 80×60 m | 对标视频 3000 平米 |
| POI 入口宽度 | 8 m | 可被一根 LONG_BOX 封堵 |
| 入口到核心距离 | ~25 m | 公平进入 |
| 障碍物间距 | 3-5 m | 玩家走两步就有遮挡 |
| LOW POI 障碍数 | 30-40 个 | 稀疏，新手友好 |
| HIGH POI 障碍数 | 45-55 个 | 密集，多狙击位 |
| LOW POI 容器数 | 3-4 个 | 弹药/电池为主 |
| HIGH POI 容器数 | 5-7 个 | 含遗物 + 净化剂 |
| HIGH POI patrol/dormant 比 | 1:1 | 增加意外性 |
| LOW POI patrol/dormant 比 | 全 patrol | 简单 |

---

## 9. 风险 & 决策记录

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-05-22 | 放弃随机程序生成路线（map-gen 分支） | 视觉效果差，固定地图 + 手工设计更可控 |
| 2026-05-23 | 选 POI 驱动而非纯手摆 .tscn | 数据数组易迭代，rules.md §6.3 不允许 AI 改 .tscn |
| 2026-05-23 | 给 expedition_map.gd 加 @tool | 编辑器预览整张地图，方便设计反馈 |
| 2026-05-23 | 6 zone 重新规划方位 | 旧布局区域重叠 + 无空间逻辑（用户反馈） |

---

*持续更新中。每完成一个 POI，更新 §0 进度快照 + §4 已完成列表。*
