# Polish Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the polished vertical slice confirmed in `docs/superpowers/specs/2026-05-20-polish-vertical-slice-design.md`.

**Architecture:** Keep the existing `scenes/game_3d.tscn` root and add explicit location flow inside `GameManager`: title, Afterglow Express map, expedition map, and result handoff. `game_3d.gd` becomes the map orchestrator, while reusable UI behavior stays in `hud.gd` and inventory/search data stays in item/player systems.

**Tech Stack:** Godot 4.6.2, GDScript, existing headless runtime checks via `tests/run_godot_runtime_checks.ps1` with memory guard.

---

## File Map

- Modify `scripts/managers/game_manager.gd`: add location flow, UI input lock, return-to-Afterglow helpers.
- Modify `scripts/game_3d.gd`: build/switch title, Afterglow Express map, and large expedition map; add risk zones, interaction points, and map metadata getters.
- Modify `scripts/player/player_3d.gd`: allow Afterglow movement, block movement/combat while UI is open, backpack key handling.
- Modify `scripts/player/player_shooting_3d.gd`: respect UI input lock.
- Modify `scripts/player/inventory.gd`: add explicit transfer/query helpers for UI and container search.
- Modify `scripts/items/item_data.gd`: add rarity/search duration data.
- Modify `scripts/items/container_3d.gd`: replace auto pickup spawning with open/search state and explicit transfer API.
- Modify `scripts/enemies/enemy_3d.gd`: add HP bar, signal reaction entrypoint, and expose alert/HP UI state.
- Modify `scripts/managers/spawn_manager.gd`: spawn outside visible radius and expose pressure direction/status.
- Modify `scripts/systems/extraction.gd`: notify spawn manager and enemies about signal point; expose pressure/boarding prompt data.
- Modify `scripts/ui/hud.gd`: title click flow, Afterglow HUD, storage/backpack/search overlays, prompts, risk label, pressure hints.
- Add tests:
  - `tests/polish_flow_runtime_checks.gd`
  - `tests/inventory_ui_runtime_checks.gd`
  - `tests/container_search_runtime_checks.gd`
  - `tests/expedition_map_runtime_checks.gd`
  - `tests/extraction_pressure_runtime_checks.gd`

## Task 1: State Flow And Afterglow Map

**Files:**
- Modify: `scripts/managers/game_manager.gd`
- Modify: `scripts/game_3d.gd`
- Modify: `scripts/player/player_3d.gd`
- Modify: `scripts/ui/hud.gd`
- Test: `tests/polish_flow_runtime_checks.gd`

- [ ] **Step 1: Write failing flow test**

Create `tests/polish_flow_runtime_checks.gd` with checks:

```gdscript
extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	var manager: Node = root.get_node_or_null("GameManager")
	var hud := scene.get_node_or_null("UI/HUD")
	_expect(manager != null, "GameManager exists")
	_expect(hud != null, "HUD exists")
	_expect(manager.get("current_location") == manager.Location.TITLE, "Boot starts at title location")
	_expect(scene.has_method("get_active_map_name"), "Game3D exposes active map name")
	_expect(scene.get_active_map_name() == "title", "Game starts on title overlay, not expedition")
	hud._on_title_clicked()
	await process_frame
	_expect(manager.get("current_location") == manager.Location.AFTERGLOW, "Title click enters Afterglow map")
	_expect(scene.get_active_map_name() == "afterglow", "Afterglow map is active after title click")
	_expect(scene.get_node_or_null("World/AfterglowMap/WarehousePoint") != null, "Afterglow has warehouse point")
	_expect(scene.get_node_or_null("World/AfterglowMap/DeparturePoint") != null, "Afterglow has departure point")
	manager.set_state(manager.State.DEAD)
	await process_frame
	if hud.has_method("_return_to_home_from_result"):
		hud._return_to_home_from_result()
	await process_frame
	_expect(manager.get("current_location") == manager.Location.AFTERGLOW, "Result returns to Afterglow map")
	_finish(scene)

func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if _failures.is_empty():
		print("Polish flow runtime checks passed.")
		quit(0)
	for failure in _failures:
		push_error(failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
```

- [ ] **Step 2: Run RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_godot_runtime_checks.ps1 -TimeoutSeconds 60 -MaxWorkingSetMb 4096
```

Expected: fails because `current_location`, `get_active_map_name()`, and Afterglow map nodes do not exist.

- [ ] **Step 3: Implement location flow**

Add to `game_manager.gd`:

```gdscript
signal location_changed(location: Location)
signal ui_blocking_changed(blocked: bool)

enum Location { TITLE, AFTERGLOW, EXPEDITION }

var current_location: Location = Location.TITLE
var ui_blocking_input: bool = false

func set_location(location: Location) -> void:
	if current_location == location:
		return
	current_location = location
	location_changed.emit(location)

func enter_afterglow() -> void:
	reset_run()
	set_location(Location.AFTERGLOW)

func begin_expedition() -> void:
	start_run()
	set_location(Location.EXPEDITION)

func return_to_afterglow() -> void:
	reset_run()
	set_location(Location.AFTERGLOW)

func set_ui_blocking_input(blocked: bool) -> void:
	if ui_blocking_input == blocked:
		return
	ui_blocking_input = blocked
	ui_blocking_changed.emit(blocked)
```

Update `game_3d.gd` to create `World/AfterglowMap` with four zones and interaction points, keep expedition content under `World/ExpeditionMap`, and expose:

```gdscript
func get_active_map_name() -> String:
	match GameManager.current_location:
		GameManager.Location.TITLE:
			return "title"
		GameManager.Location.AFTERGLOW:
			return "afterglow"
		GameManager.Location.EXPEDITION:
			return "expedition"
	return "unknown"
```

Update `hud.gd` title overlay click to call `GameManager.enter_afterglow()` through `_on_title_clicked()`.

- [ ] **Step 4: Run GREEN**

Run the memory guarded runtime suite. Expected: `Polish flow runtime checks passed.`

## Task 2: Movement Lock And Interaction Prompts

**Files:**
- Modify: `scripts/player/player_3d.gd`
- Modify: `scripts/player/player_shooting_3d.gd`
- Modify: `scripts/game_3d.gd`
- Modify: `scripts/ui/hud.gd`
- Test: `tests/inventory_ui_runtime_checks.gd`

- [ ] **Step 1: Write failing movement/prompt test**

Create `tests/inventory_ui_runtime_checks.gd` checking:

```gdscript
extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	var manager: Node = root.get_node_or_null("GameManager")
	var hud := scene.get_node_or_null("UI/HUD")
	var player := scene.get_node_or_null("Entities/Player3D")
	manager.enter_afterglow()
	await process_frame
	_expect(player.has_method("is_input_locked"), "Player exposes input lock state")
	_expect(not player.is_input_locked(), "Player is unlocked on Afterglow map")
	_expect(hud.has_method("open_backpack"), "HUD can open backpack overlay")
	hud.open_backpack()
	await process_frame
	_expect(manager.ui_blocking_input, "Opening backpack blocks input")
	_expect(player.is_input_locked(), "Opening backpack locks player movement")
	_expect(hud.has_method("close_blocking_overlay"), "HUD can close blocking overlays")
	hud.close_blocking_overlay()
	await process_frame
	_expect(not manager.ui_blocking_input, "Closing backpack clears input block")
	_expect(not player.is_input_locked(), "Closing backpack unlocks player")
	_expect(hud.has_method("get_prompt_text"), "HUD exposes current prompt")
	scene.set_player_near_afterglow_point("warehouse")
	await process_frame
	_expect(hud.get_prompt_text().find("Storage") >= 0, "Warehouse prompt appears in range")
	_finish(scene)

func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if _failures.is_empty():
		print("Inventory UI runtime checks passed.")
		quit(0)
	for failure in _failures:
		push_error(failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
```

- [ ] **Step 2: Run RED**

Expected: fails because blocking overlay methods and input lock API do not exist.

- [ ] **Step 3: Implement lock and prompts**

Use `GameManager.set_ui_blocking_input()` as the single lock source. Add `Player3D.is_input_locked()` and have movement/input return early when locked. Add HUD methods `open_backpack()`, `open_storage()`, `close_blocking_overlay()`, `get_prompt_text()`, and prompt setters called by `game_3d.gd`.

- [ ] **Step 4: Run GREEN**

Run guarded runtime checks and static checks.

## Task 3: Storage And Backpack UI

**Files:**
- Modify: `scripts/ui/hud.gd`
- Modify: `scripts/player/inventory.gd`
- Test: `tests/inventory_ui_runtime_checks.gd`

- [ ] **Step 1: Extend failing test**

Extend `tests/inventory_ui_runtime_checks.gd` to assert:

```gdscript
hud.open_storage()
await process_frame
_expect(hud.get_node_or_null("StorageOverlay") != null, "Storage overlay exists")
_expect(hud.get_node_or_null("StorageOverlay/BackpackGrid") != null, "Storage UI has backpack grid")
_expect(hud.get_node_or_null("StorageOverlay/WarehouseList") != null, "Storage UI has warehouse list")
_expect(hud.get_visible_backpack_item_names().size() > 0, "Backpack item names only exist inside overlay")
hud.close_blocking_overlay()
_expect(hud.get_visible_backpack_item_names().is_empty(), "HUD hides backpack item names outside overlay")
```

- [ ] **Step 2: Run RED**

Expected: fails because storage overlay/query methods do not exist.

- [ ] **Step 3: Implement storage overlay**

Build a semi-transparent `StorageOverlay` in `hud.gd` with `BackpackGrid` and `WarehouseList`, using static starting warehouse quantities from `GameManager` or HUD-local storage data for this vertical slice. Ensure no item names are shown in normal HUD.

- [ ] **Step 4: Run GREEN**

Run guarded runtime suite.

## Task 4: Container Search UI

**Files:**
- Modify: `scripts/items/item_data.gd`
- Modify: `scripts/items/container_3d.gd`
- Modify: `scripts/player/inventory.gd`
- Modify: `scripts/ui/hud.gd`
- Test: `tests/container_search_runtime_checks.gd`

- [ ] **Step 1: Write failing search test**

Create `tests/container_search_runtime_checks.gd` checking container entries start unknown, search over time, reveal items, and do not auto-pickup until explicit transfer.

- [ ] **Step 2: Run RED**

Expected: fails because containers still spawn pickups automatically.

- [ ] **Step 3: Implement search model**

Add `rarity`, `get_search_time()`, and container entry state methods. Change `_complete_crack()` to emit/open search UI instead of spawning pickups. Add explicit transfer method `transfer_revealed_item(index, inventory)`.

- [ ] **Step 4: Run GREEN**

Run guarded runtime suite.

## Task 5: Expedition Map Risk Zones

**Files:**
- Modify: `scripts/game_3d.gd`
- Modify: `scripts/managers/spawn_manager.gd`
- Test: `tests/expedition_map_runtime_checks.gd`

- [ ] **Step 1: Write failing map test**

Create `tests/expedition_map_runtime_checks.gd` asserting map extents cover about 80 screens, risk zones exist, high-risk zones have greater enemy/container density, and HUD risk label can be queried.

- [ ] **Step 2: Run RED**

Expected: fails because current map is small and lacks zone metadata.

- [ ] **Step 3: Implement large map**

Expand expedition ground/obstacle/container/enemy generation from deterministic zone data. Add `get_expedition_bounds()`, `get_risk_zones()`, `get_zone_density_summary()`, and player risk-zone updates.

- [ ] **Step 4: Run GREEN**

Run guarded runtime suite.

## Task 6: Extraction Pressure And Enemy UI

**Files:**
- Modify: `scripts/enemies/enemy_3d.gd`
- Modify: `scripts/managers/spawn_manager.gd`
- Modify: `scripts/systems/extraction.gd`
- Modify: `scripts/ui/hud.gd`
- Test: `tests/extraction_pressure_runtime_checks.gd`
- Existing test: `tests/enemy_ai_runtime_checks.gd`

- [ ] **Step 1: Write failing pressure/UI test**

Create `tests/extraction_pressure_runtime_checks.gd` asserting signal flare affects patrol enemies, extraction spawns outside visible radius, HUD shows countdown/pressure/boarding prompt, and enemy HP bar reflects damage.

- [ ] **Step 2: Run RED**

Expected: fails because patrol enemies are not explicitly redirected by signal and HP bar is not complete.

- [ ] **Step 3: Implement pressure and enemy bars**

Add `receive_signal_flare(origin)` to enemies, HP bar mesh/UI update, spawn manager outside-view selection, and HUD pressure prompt fed by spawn/extraction data.

- [ ] **Step 4: Run GREEN**

Run guarded runtime suite.

## Final Verification And Review

- [ ] **Step 1: Run full guarded runtime**

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_godot_runtime_checks.ps1 -TimeoutSeconds 60 -MaxWorkingSetMb 4096
```

- [ ] **Step 2: Run static checks**

```powershell
powershell -ExecutionPolicy Bypass -File tests\game_3d_static_checks.ps1
powershell -ExecutionPolicy Bypass -File tests\dev_a_static_checks.ps1
git diff --check
```

- [ ] **Step 3: Confirm no headless Godot remains**

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } | Select-Object Id,ProcessName,WorkingSet64,Path
```

- [ ] **Step 4: Request code review**

Use the `requesting-code-review` workflow. Review focus:

- spec coverage,
- runtime crash risk,
- UI input lock correctness,
- container search no-auto-pickup,
- large map/risk density correctness,
- extraction pressure outside-view spawning,
- Godot memory/process safety.
