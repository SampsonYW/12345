# 《余晖号》Afterglow Express

Godot 4.6 3D 正交斜俯视游戏 Demo。项目当前工程名仍为 `12345`，主入口场景为 `res://scenes/game_3d.tscn`。

玩法定位是 **Roguelite × 搜打撤**：玩家进入电磁废墟，破解容器、搜刮遗物、对抗失控机械体，并在风险失控前发射信号弹等待母车撤离。

## 当前内容

- 3D 玩家移动、瞄准、射击、冲刺与信号弹。
- 背包、仓库、物品数据、容器搜索与双向转移。
- 巡逻 / 休眠敌人 AI、噪音警戒、受击与击杀。
- 侵蚀值、时间压力、刷怪压力和撤离状态机。
- 母车甲板与远征地图双场景切换。
- POI 驱动的远征地图、可视视野、摄像机遮挡、HUD 弹层与 BGM 状态切换。

## 环境要求

- Godot 4.6.x
- Windows PowerShell（用于当前静态检查脚本）
- GDScript，无额外第三方插件依赖

## 运行项目

在 Godot 编辑器中打开本目录，或使用命令行：

```powershell
godot --editor --path .
```

直接运行主场景：

```powershell
godot --path .
```

## 操作

| 输入 | 动作 |
| --- | --- |
| `W/A/S/D` | 移动 |
| 鼠标左键 | 射击 |
| `Shift` | 冲刺 |
| `E` | 交互 / 搜索容器 |
| `Q` | 发射信号弹 |
| `B` | 背包 |
| `Esc` | 关闭弹层 |

## 项目结构

```text
scenes/              Godot 场景文件
scripts/             GDScript 逻辑
  managers/          GameManager、NoiseManager、WarehouseManager 等管理器
  player/            玩家、射击、生命、背包
  enemies/           敌人 AI
  items/             物品、容器、拾取物
  maps/              母车与远征地图、POI 构建脚本
  systems/           撤离、可视视野、BGM、摄像机遮挡
  ui/                HUD、背包、仓库、搜索弹层
resources/items/     ItemData 资源
assets/              美术、音频、视频素材
docs/                设计、实现、规则、计划文档
tests/               静态检查与 headless 运行时检查
```

## 测试与检查

静态检查：

```powershell
powershell -ExecutionPolicy Bypass -File tests\game_3d_static_checks.ps1
powershell -ExecutionPolicy Bypass -File tests\dev_a_static_checks.ps1
```

运行单个 headless runtime check：

```powershell
godot --headless --path . --script tests\game_3d_runtime_checks.gd
```

`tests/` 下的 `*_runtime_checks.gd` 都是 `SceneTree` 测试脚本，可按同样方式逐个运行。

## 文档入口

- `docs/pitch.md`：游戏概念、世界观与核心循环。
- `docs/design.md`：核心玩法设计。
- `docs/implementation.md`：当前代码架构、模块耦合与测试入口。
- `docs/rules.md`：开发规范、目录约定、AI 协作规则。
- `docs/map_design_plan.md`：远征地图与 POI 设计。
- `docs/art_audio_resource_checklist.md`：美术与音频资源清单。

## 开发注意

- 主玩法已经切到 3D，旧 2D 场景 / 脚本不应重新引入。
- 修改玩法、模块边界或测试入口时，同步更新 `docs/implementation.md`。
- 不要手动修改 `.import` 文件；它们由 Godot 自动生成。
- 不要随意变更 `project.godot` 中的 Input Map、碰撞层或 Autoload，除非需求明确覆盖这些内容。
