# Design Spec: Make Scenes and Models Editable in Godot Editor

This design details how to extract procedurally generated 3D meshes, collision geometry, and markers into separate Godot `.tscn` scene files. Doing so allows the designer to edit materials, textures, sizes, and layout positions directly within the Godot editor, while maintaining runtime functionality and passing all static/runtime tests.

## 1. Goal

Eliminate code-embedded scenes and models, turning them into scenes that can be opened, visualised, and modified inside the Godot Editor.

## 2. Proposed Changes

### A. Expedition Map Scene (`scenes/expedition_map.tscn`)
We will create a new scene containing:
- **Ground**: A `StaticBody3D` with size `(480, 0.1, 240)` at `(0, -0.05, 0)` matching `EXPEDITION_BOUNDS`.
- **Obstacles**: All 8 obstacles currently defined in `game_3d.gd` (`OBSTACLE_DATA`) placed as `StaticBody3D` nodes with custom mesh/collision sizes matching the positions and bounds.
- **Risk Zones**: The 4 risk zones represented as visual `MeshInstance3D` boxes and `Label3D` markers.
- **Containers**: The 8 container locations instantiated using `res://scenes/container_3d.tscn`, with their positions, `loot_table` resource arrays, and a new `@export var risk` string (value `"low"` or `"high"`) configured in the inspector.
- **InitialSpawns**: A container `Node3D` with `Marker3D` nodes placed at the 8 initial enemy spawn points. Their names (e.g. `PatrolSpawn1`, `DormantSpawn1`) will designate whether they spawn a patrol or dormant enemy.

In `game_3d.gd`:
- We will preload `scenes/expedition_map.tscn` as `EXPEDITION_MAP_SCENE`.
- In `_ensure_map_roots()`, we will instantiate this scene for `_expedition_map`.
- At runtime, `_build_expedition_map()` will return early if `_expedition_map.scene_file_path` is not empty, bypassing the procedural creation of obstacles, zones, ground, and containers.
- To maintain test compatibility, we will reparent the container nodes from `_expedition_map/Containers` to `_containers` (`Entities/Containers`) when the scene starts.

### B. Initial Enemy Spawns from Map Markers
In `spawn_manager.gd`:
- `seed_initial_enemies()` will search for a `InitialSpawns` child node inside `ExpeditionMap`.
- If found, it will spawn the initial patrol/dormant enemies at the positions of the child `Marker3D` nodes (matching the type based on the marker's name containing `"dormant"` or `"patrol"`).
- If not found (fallback), it will use the original hardcoded positions.

### C. Signal Flare and Mothership Extraction Visual Scenes
We will extract procedurally constructed meshes into three new scenes:
1. `scenes/signal_flare_marker.tscn`:
   - Contains a `Node3D` root.
   - Cylinder `SignalBeam` mesh with transparency, emissive material, and size.
   - `OmniLight3D` named `SignalLight` with range and energy.
2. `scenes/mothership_extraction_marker.tscn`:
   - Root `Node3D`.
   - `LandingPad` (Cylinder), `SignalBeam` (Cylinder), `MothershipHull` (Box), `BoardingRamp` (Box), and `ExtractionLight` (OmniLight3D).
3. `scenes/extraction_signal_beacon.tscn`:
   - Root `Node3D`.
   - `PendingLandingPad` (Cylinder) and `PendingSignalBeam` (Cylinder).

In `player_3d.gd`:
- Preload `res://scenes/signal_flare_marker.tscn` and instantiate it in `_spawn_signal_flare_marker()`.

In `extraction.gd`:
- Preload the mothership and beacon scenes and instantiate them instead of programmatically constructing boxes and cylinders.

### D. Enemy Alert and HP Bars
In `enemy_3d.tscn` (and patrol/dormant enemy scene variants):
- Pre-place the node structure:
  - `AlertBar` (Node3D) -> `AlertBack` (MeshInstance3D), `AlertFill` (MeshInstance3D)
  - `HpBar` (Node3D) -> `HpBack` (MeshInstance3D), `HpFill` (MeshInstance3D)
- Update `enemy_3d.gd` to fetch these nodes using `@onready` (or fallback to dynamic creation if missing, for safety).
- Do not recreate the materials via `StandardMaterial3D.new()` if they exist; instead, duplicate the existing material to avoid affecting other instances, and adjust the albedo color/emissive multiplier dynamically.

### E. Container & Pickup Dynamic Materials
In `container_3d.gd` and `item_pickup_3d.gd`:
- Instead of setting a new `StandardMaterial3D` instance which overrides all editor configurations, we will duplicate the existing `material_override` (if standard material) in `_ready()`, and then dynamically modify only its albedo color (and emission for pickups).

## 3. Verification Plan
- Run static checks: `powershell -File tests/dev_a_static_checks.ps1` and `powershell -File tests/game_3d_static_checks.ps1`.
- Run runtime checks: `powershell -File tests/run_godot_runtime_checks.ps1`. All tests must pass.
