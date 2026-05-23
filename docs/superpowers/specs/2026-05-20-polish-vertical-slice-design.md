# Polish Vertical Slice Redesign

## Goal

Move the project from "MVP completion" into a polished vertical slice: the player starts from a title screen, enters a playable Afterglow Express map, manages inventory and storage, launches into a much larger expedition map, searches containers through a dedicated UI, extracts or dies, then returns to the Afterglow Express map.

## Confirmed Direction

- The Afterglow Express is a real playable map, not a menu hub.
- The Afterglow Express should be medium-sized, about 3-5 screens.
- Implementation should follow a vertical-slice polish route rather than isolated MVP patches.
- End of a run returns to the Afterglow Express map.
- Opening any inventory/storage/search UI locks player movement.

## State Flow

1. **Title Screen**
   - Shows the game title.
   - Displays "click anywhere to start".
   - Any mouse click transitions to the Afterglow Express map.
   - It does not start a run directly.

2. **Afterglow Express Map**
   - A safe playable map with player movement enabled.
   - Contains at least four spatial zones:
     - cockpit/status area,
     - rest/common area,
     - warehouse interaction area,
     - departure hatch interaction area.
   - Ground or world-space hints explain:
     - `WASD` move,
     - `E` interact,
     - `Q` release extraction signal flare,
     - backpack key opens backpack UI.
   - Warehouse interaction opens storage UI.
   - Departure interaction requires holding `E`; only after the hold completes does the expedition map load.

3. **Expedition Map**
   - Replaces the current small map with an exploration map around 80 screens of play area.
   - The map is divided into low-risk and high-risk zones.
   - Low-risk zones have lower enemy density and lower-value containers.
   - High-risk zones have higher enemy density and more high-value containers.
   - Risk zoning must be visible through layout and placement, not just data tables.

4. **Run End**
   - Successful extraction or death shows a result screen.
   - Leaving the result screen returns to the Afterglow Express map, not the title screen and not directly into another run.

## Afterglow Express Map Design

The Afterglow Express is a small physical place the player returns to between runs. It is not a purely decorative menu. The initial implementation can use geometric placeholder art, but the layout must communicate function.

Required spaces:

- **Cockpit/status area**
  - Forward section of the map.
  - Can display destination/status flavor text.
  - No required interaction in this slice.

- **Rest/common area**
  - Central breathing space.
  - Helps the map feel like a vehicle, not two buttons in a room.
  - Can hold ground controls text.

- **Warehouse area**
  - Interact prompt appears when the player is in range.
  - Pressing `E` opens storage UI.

- **Departure hatch**
  - Interact prompt appears when the player is in range.
  - Holding `E` fills a progress indicator.
  - Releasing `E` before completion cancels departure.
  - Completion transitions into the expedition map.

## Storage And Backpack UI

Backpack contents must no longer be permanently visible on the HUD. The player must explicitly open a backpack/storage/search UI to inspect contents.

Shared rules:

- UI is semi-transparent and overlays the current scene.
- Opening UI locks player movement and combat inputs.
- Closing UI restores movement.
- The player's backpack is shown as a grid of item slots.
- Empty slots are visually distinct.
- Item icons may use the current colored placeholder visuals in this slice, but every slot must reserve stable icon/text space for later art.

Warehouse storage UI:

- Left side: player backpack grid.
- Right side: warehouse contents as rows in the form `Item Name x Quantity`.
- Warehouse items are not part of the run score until moved into the player's backpack and extracted from a run.
- Moving items supports drag-and-drop and a keyboard shortcut path. Both call the same transfer API.

Backpack-only UI:

- Opened by the backpack key.
- Shows only the player backpack grid and item details.
- Player cannot move while it is open.
- Existing quick-use keys can remain, but the HUD does not reveal item names outside this UI.

## Combat And World UI

Enemy overhead UI:

- Every active enemy has a readable red HP bar.
- Enemies with alert behavior have an orange alert bar.
- The HP bar is visible when the enemy is damaged, targeted, alert, chasing, or near the player.
- Dormant or unaware enemies show the alert bar when alert is above zero.
- The alert bar fills as noise accumulates and shrinks as alert decays.
- When an enemy awakens, the alert bar briefly flashes full, then either hides or becomes secondary to the HP bar.
- Patrol enemies still use the same HP/alert display rules; signal flare reactions must be visually readable through the alert/awakening feedback.
- Enemy overhead bars use stable dimensions and never resize the enemy body or collision.

World interaction prompts:

- Interactable objects show a world-space prompt only while the player is in range.
- Warehouse prompt: `E Open Storage`.
- Departure hatch prompt: `Hold E Depart`.
- Container prompt before opening: `Hold E Open`.
- Container prompt after opening/search UI is available: `E Search`.
- Hold interactions show a progress bar or ring near the prompt.
- Releasing the key before completion clears the progress indicator.
- Prompts must not appear through walls if a line-of-sight check is available for that interaction.

Run HUD:

- The HUD always shows HP, erosion, carried weight, ammo, signal state, and current risk-zone label.
- The HUD does not show backpack item names or container contents.
- Signal state displays at least: ready, fired, extraction waiting countdown, arrived/board.
- Risk-zone label displays low-risk or high-risk so players understand why enemy/container density changes.
- Temporary notifications cover blocked transfers, pickup failures, signal flare fired, extraction arrival, and death/extraction result handoff.

Extraction pressure UI:

- During extraction, a countdown remains visible.
- When enemies spawn outside view, the player receives a directional or edge pressure hint.
- The pressure hint is intentionally lightweight in the first slice: direction text or edge pulse is acceptable.
- Mother ship arrival creates a visible landing/boarding marker and a clear `E Board` prompt.

## Container Search UI

Opening a container is now a two-step interaction:

1. Hold `E` near the container to open it.
2. Opening the container displays a search UI and starts searching its contents.

Container search UI:

- Left side: player backpack grid.
- Right side: container contents.
- Container contents initially appear as unknown/unsearched entries.
- Each entry has a search duration based on item rarity.
- Higher rarity means longer search time.
- Each entry displays one of these states: unknown, searching, revealed, transferred.
- Searching state displays progress percentage or remaining time.
- Once an entry is searched, it reveals the item.
- Revealed items are not auto-picked up.
- The player must move items into the backpack by drag action or shortcut.
- If the backpack is full or overweight, transfer is blocked with feedback.
- Transfer failures display a short reason near the search UI and in the HUD notification area.

Transfer controls:

- Drag a revealed item from the container into a backpack slot.
- Press a visible shortcut on a revealed item to move it into the first valid backpack slot.
- Invalid transfer attempts show feedback and leave the item in the source container.

## Item And Rarity Rules

Current `ItemData` remains the source of truth for weight, score, ammo, healing, and purification.

Add explicit rarity/search-time data to item definitions:

- common: short search,
- uncommon: medium search,
- rare/high-value: long search.

Default mapping for existing items:

- ammo/battery: common,
- purifier: uncommon,
- relic/collectible with score value: rare by score tier.

The mapping is centralized in item/search code, and each resource can override it with explicit rarity data.

## Expedition Map Redesign

The current expedition map is too small for the intended search-and-extract loop. It expands to about 80 screens.

Map structure:

- Large walkable area around 80 camera screens.
- Spawn/start area is in a lower-risk region.
- Low-risk outer routes contain fewer enemies and more basic containers.
- High-risk interior or remote zones contain denser enemies and higher-value containers.
- Obstacles create route choices, partial sight blocks, and extraction defense positions.
- The map can be authored procedurally from data arrays or generated at runtime from zone definitions, but the result must be deterministic enough for tests.

Minimum zone data:

- zone name,
- center/size,
- risk level,
- enemy density,
- container density,
- high-value loot weight.

## Enemy And Extraction Polish

Signal flare and extraction must create pressure that is visible outside the player's immediate view.

Required behavior:

- Signal flare emits global noise.
- Patrol enemies are affected by the signal flare, not only dormant enemies.
- Signal flare wakes or redirects enemies toward the signal/extraction area.
- Extraction phase spawns enemies outside the player's view distance.
- Spawn points prefer locations outside current camera/view radius and not directly inside the visible area.
- Spawn pressure increases during extraction.
- Existing alive enemies redirect toward the signal point when they can receive the signal event.

## UI And Movement Locking

Movement lock is required for:

- warehouse UI,
- backpack UI,
- container search UI,
- result screen if it overlays a live scene.

Movement lock is handled through a single player/game-state interface, not by every UI directly disabling movement in different ways.

Required interface:

- `GameManager.ui_blocking_input: bool`, or
- `Player3D.set_input_locked(locked: bool)`.

The implementation plan must choose one of these interfaces and use it consistently for all blocking UI.

## Testing Expectations

Runtime checks must remain serial and memory guarded because previous Godot runs caused OOM.

Required automated coverage:

- Title click enters the Afterglow Express map, not the expedition map.
- Afterglow Express map contains warehouse and departure interaction points.
- Holding `E` on departure transitions to the expedition map.
- A run ending returns to the Afterglow Express map.
- Opening backpack/storage/search UI locks movement.
- Enemy HP bar appears and reflects damage.
- Enemy alert bar reflects alert accumulation and decay.
- World prompts appear only when the player is in range of warehouse, departure hatch, or container.
- Container opening does not auto-pickup items.
- Container entries start unknown, search over time, then reveal items.
- Item transfer requires an explicit player action.
- Search UI displays unknown, searching, revealed, and transferred states.
- Expedition map extents are much larger than the current map.
- High-risk zone has higher enemy/container density than low-risk zone.
- Extraction spawns enemies outside the visible radius.
- Signal flare affects patrol enemies.
- Extraction UI displays countdown, pressure hint, arrival marker, and boarding prompt.

Verification commands must include:

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_godot_runtime_checks.ps1 -TimeoutSeconds 60 -MaxWorkingSetMb 4096
powershell -ExecutionPolicy Bypass -File tests\game_3d_static_checks.ps1
powershell -ExecutionPolicy Bypass -File tests\dev_a_static_checks.ps1
git diff --check
```

## Implementation Boundaries

Respect existing module ownership where practical:

- `GameManager` handles state flow and high-level run transitions.
- `Player3D` handles movement, interaction input, and input locking.
- Inventory/storage/search data lives in player/items systems, not HUD-only code.
- HUD/UI displays and forwards explicit UI actions; it does not own loot generation.
- Enemy response and spawn pressure stay in enemy/spawn/extraction systems.
- The map root can orchestrate scene transitions and map construction.

## Deferred Polish

These items are outside the first polished vertical slice:

- Final art for the Afterglow Express interior.
- Full drag-and-drop with item ghost previews.
- Audio pass for warehouse/search/departure UI.
- Multiple expedition biomes.
- Persistent meta-progression outside a single session.

## Open Decisions Resolved

- Afterglow Express is a map, not a menu hub.
- Use medium Afterglow Express map, not tiny placeholder map.
- Proceed with vertical slice polish rather than UI-only or map-only polish.
- Return to Afterglow Express after every run end.
