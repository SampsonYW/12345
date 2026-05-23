# Godot Scenes Editor-Editable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn all embedded code-defined scenes and models into standard Godot `.tscn` files, allowing them to be fully configured in the Godot Editor.

**Architecture:** Create new scenes (`expedition_map.tscn`, `signal_flare_marker.tscn`, `mothership_extraction_marker.tscn`, `extraction_signal_beacon.tscn`) and update pre-existing scene templates (`enemy_3d.tscn`, `patrol_enemy_3d.tscn`, `dormant_enemy_3d.tscn`). Modify the runtime logic in scripts (`game_3d.gd`, `spawn_manager.gd`, `extraction.gd`, `player_3d.gd`, `enemy_3d.gd`, `container_3d.gd`, `item_pickup_3d.gd`) to load these scenes or reuse/duplicate pre-existing materials instead of constructing meshes from scratch.

**Tech Stack:** Godot Engine 4 (GDScript, TSNC files).

---

## Proposed Changes

### Task 1: Create Signal Flare & Extraction Markers Scenes
We will extract the dynamic signal flare and extraction marker geometry into individual `.tscn` files.

**Files:**
- Create: `scenes/signal_flare_marker.tscn`
- Create: `scenes/mothership_extraction_marker.tscn`
- Create: `scenes/extraction_signal_beacon.tscn`

- [ ] **Step 1.1: Create signal_flare_marker.tscn**
  Write file content for `scenes/signal_flare_marker.tscn`:
  ```tscn
  [gd_scene format=3 uid="uid://signalflaremarker01"]

  [sub_resource type="CylinderMesh" id="CylinderMesh_beam"]
  top_radius = 0.16
  bottom_radius = 0.16
  height = 7.5

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_beam"]
  albedo_color = Color(1, 0.28, 0.12, 0.72)
  transparency = 1
  emission_enabled = true
  emission = Color(1, 0.22, 0.08, 1)

  [node name="SignalFlareMarker" type="Node3D"]

  [node name="SignalBeam" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.75, 0)
  mesh = SubResource("CylinderMesh_beam")
  material_override = SubResource("StandardMaterial3D_beam")

  [node name="SignalLight" type="OmniLight3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0)
  light_color = Color(1, 0.32, 0.12, 1)
  light_energy = 3.0
  omni_range = 8.0
  ```

- [ ] **Step 1.2: Create mothership_extraction_marker.tscn**
  Write file content for `scenes/mothership_extraction_marker.tscn`:
  ```tscn
  [gd_scene format=3 uid="uid://mothershipextractionmarker01"]

  [sub_resource type="CylinderMesh" id="CylinderMesh_landing"]
  top_radius = 3.5
  bottom_radius = 3.5
  height = 0.12
  radial_segments = 48

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_landing"]
  albedo_color = Color(0.1, 0.55, 0.5, 1)
  roughness = 0.65
  emission_enabled = true
  emission = Color(0, 0.9, 0.8, 1)
  emission_energy_multiplier = 0.35

  [sub_resource type="CylinderMesh" id="CylinderMesh_beam"]
  top_radius = 0.32
  bottom_radius = 0.32
  height = 4.2
  radial_segments = 48

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_beam"]
  albedo_color = Color(0.1, 0.85, 0.78, 0.45)
  roughness = 0.65
  transparency = 1
  emission_enabled = true
  emission = Color(0, 1, 0.85, 1)
  emission_energy_multiplier = 1.6

  [sub_resource type="BoxMesh" id="BoxMesh_hull"]
  size = Vector3(5.8, 0.75, 2.4)

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_hull"]
  albedo_color = Color(0.54, 0.58, 0.62, 1)
  roughness = 0.65
  emission_enabled = true
  emission = Color(0.2, 0.9, 0.85, 1)
  emission_energy_multiplier = 0.25

  [sub_resource type="BoxMesh" id="BoxMesh_ramp"]
  size = Vector3(2, 0.2, 2.8)

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_ramp"]
  albedo_color = Color(0.24, 0.32, 0.34, 1)
  roughness = 0.65
  emission_enabled = true
  emission = Color(0, 0.75, 0.7, 1)
  emission_energy_multiplier = 0.2

  [node name="MothershipExtractionMarker" type="Node3D"]

  [node name="LandingPad" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.06, 0)
  mesh = SubResource("CylinderMesh_landing")
  material_override = SubResource("StandardMaterial3D_landing")

  [node name="SignalBeam" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.1, 0)
  mesh = SubResource("CylinderMesh_beam")
  material_override = SubResource("StandardMaterial3D_beam")

  [node name="MothershipHull" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 4.8, 0)
  mesh = SubResource("BoxMesh_hull")
  material_override = SubResource("StandardMaterial3D_hull")

  [node name="BoardingRamp" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.05, 1.85)
  mesh = SubResource("BoxMesh_ramp")
  material_override = SubResource("StandardMaterial3D_ramp")

  [node name="ExtractionLight" type="OmniLight3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 0)
  light_color = Color(0, 1, 0.85, 1)
  light_energy = 4.0
  omni_range = 9.0
  ```

- [ ] **Step 1.3: Create extraction_signal_beacon.tscn**
  Write file content for `scenes/extraction_signal_beacon.tscn`:
  ```tscn
  [gd_scene format=3 uid="uid://extractionsignalbeacon01"]

  [sub_resource type="CylinderMesh" id="CylinderMesh_pending_landing"]
  top_radius = 2.4
  bottom_radius = 2.4
  height = 0.08
  radial_segments = 48

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_pending_landing"]
  albedo_color = Color(0.08, 0.35, 0.32, 0.8)
  roughness = 0.65
  transparency = 1
  emission_enabled = true
  emission = Color(0, 0.7, 0.62, 1)
  emission_energy_multiplier = 0.25

  [sub_resource type="CylinderMesh" id="CylinderMesh_pending_beam"]
  top_radius = 0.18
  bottom_radius = 0.18
  height = 2.8
  radial_segments = 48

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_pending_beam"]
  albedo_color = Color(0.1, 0.85, 0.78, 0.3)
  roughness = 0.65
  transparency = 1
  emission_enabled = true
  emission = Color(0, 1, 0.85, 1)
  emission_energy_multiplier = 1.0

  [node name="ExtractionSignalBeacon" type="Node3D"]

  [node name="PendingLandingPad" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.04, 0)
  mesh = SubResource("CylinderMesh_pending_landing")
  material_override = SubResource("StandardMaterial3D_pending_landing")

  [node name="PendingSignalBeam" type="MeshInstance3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.4, 0)
  mesh = SubResource("CylinderMesh_pending_beam")
  material_override = SubResource("StandardMaterial3D_pending_beam")
  ```

- [ ] **Step 1.4: Commit scenes**
  Run: `git add scenes/*.tscn`
  Commit: `git commit -m "feat: add flare and extraction visual scenes"`

---

### Task 2: Update Player & Extraction Scripts
Modify scripts to load the newly created scenes instead of programmatically building nodes.

**Files:**
- Modify: `scripts/player/player_3d.gd`
- Modify: `scripts/systems/extraction.gd`

- [ ] **Step 2.1: Update player_3d.gd**
  Load `scenes/signal_flare_marker.tscn` and instantiate it in `_spawn_signal_flare_marker()`:
  ```diff
  -func _spawn_signal_flare_marker() -> void:
  -	var marker := Node3D.new()
  -	marker.name = "SignalFlareMarker"
  -	marker.global_position = global_position
  -
  -	var beam := MeshInstance3D.new()
  -	beam.name = "SignalBeam"
  -	var mesh := CylinderMesh.new()
  -	mesh.top_radius = 0.16
  -	mesh.bottom_radius = 0.16
  -	mesh.height = 7.5
  -	beam.mesh = mesh
  -	beam.position = Vector3(0.0, 3.75, 0.0)
  -
  -	var material := StandardMaterial3D.new()
  -	material.albedo_color = Color(1.0, 0.28, 0.12, 0.72)
  -	material.emission_enabled = true
  -	material.emission = Color(1.0, 0.22, 0.08, 1.0)
  -	beam.material_override = material
  -	marker.add_child(beam)
  -
  -	var light := OmniLight3D.new()
  -	light.name = "SignalLight"
  -	light.position = Vector3(0.0, 2.0, 0.0)
  -	light.light_color = Color(1.0, 0.32, 0.12, 1.0)
  -	light.light_energy = 3.0
  -	light.omni_range = 8.0
  -	marker.add_child(light)
  +const FLARE_MARKER_SCENE := preload("res://scenes/signal_flare_marker.tscn")
  +
  +func _spawn_signal_flare_marker() -> void:
  +	var marker := FLARE_MARKER_SCENE.instantiate() as Node3D
  +	marker.global_position = global_position
  ```

- [ ] **Step 2.2: Update extraction.gd**
  Load extraction scenes and instantiate them:
  ```diff
  +const MOTHERSHIP_MARKER_SCENE := preload("res://scenes/mothership_extraction_marker.tscn")
  +const SIGNAL_BEACON_SCENE := preload("res://scenes/extraction_signal_beacon.tscn")
  +
   func _spawn_marker() -> void:
   	if _marker != null and is_instance_valid(_marker):
   		return
   
  -	_marker = Node3D.new()
  -	_marker.name = "MothershipExtractionMarker"
  +	_marker = MOTHERSHIP_MARKER_SCENE.instantiate() as Node3D
   	add_child(_marker)
   	_marker.global_position = _landing_position
  -
  -	_add_cylinder(_marker, "LandingPad", Vector3(0.0, 0.06, 0.0), 3.5, 0.12, _make_material(Color(0.1, 0.55, 0.5, 1.0), Color(0.0, 0.9, 0.8, 1.0), 0.35))
  -	_add_cylinder(_marker, "SignalBeam", Vector3(0.0, 2.1, 0.0), 0.32, 4.2, _make_material(Color(0.1, 0.85, 0.78, 0.45), Color(0.0, 1.0, 0.85, 1.0), 1.6))
  -	_add_box(_marker, "MothershipHull", Vector3(0.0, 4.8, 0.0), Vector3(5.8, 0.75, 2.4), _make_material(Color(0.54, 0.58, 0.62, 1.0), Color(0.2, 0.9, 0.85, 1.0), 0.25))
  -	_add_box(_marker, "BoardingRamp", Vector3(0.0, 1.05, 1.85), Vector3(2.0, 0.2, 2.8), _make_material(Color(0.24, 0.32, 0.34, 1.0), Color(0.0, 0.75, 0.7, 1.0), 0.2))
  -
  -	var light := OmniLight3D.new()
  -	light.name = "ExtractionLight"
  -	light.position = Vector3(0.0, 2.5, 0.0)
  -	light.light_color = Color(0.0, 1.0, 0.85, 1.0)
  -	light.light_energy = 4.0
  -	light.omni_range = 9.0
  -	_marker.add_child(light)
   
   func _spawn_waiting_beacon() -> void:
   	if _marker != null and is_instance_valid(_marker):
   		return
  -	_marker = Node3D.new()
  -	_marker.name = "ExtractionSignalBeacon"
  +	_marker = SIGNAL_BEACON_SCENE.instantiate() as Node3D
   	add_child(_marker)
   	_marker.global_position = _landing_position
  -	_add_cylinder(_marker, "PendingLandingPad", Vector3(0.0, 0.04, 0.0), 2.4, 0.08, _make_material(Color(0.08, 0.35, 0.32, 0.8), Color(0.0, 0.7, 0.62, 1.0), 0.25))
  -	_add_cylinder(_marker, "PendingSignalBeam", Vector3(0.0, 1.4, 0.0), 0.18, 2.8, _make_material(Color(0.1, 0.85, 0.78, 0.30), Color(0.0, 1.0, 0.85, 1.0), 1.0))
  ```

- [ ] **Step 2.3: Verify runtime checks**
  Run: `powershell -File tests/run_godot_runtime_checks.ps1`
  Expected: All checks pass (including Extraction & Flare)

- [ ] **Step 2.4: Commit changes**
  Run: `git commit -am "refactor: load flare and extraction markers from scene files"`

---

### Task 3: Create & Configure Fog of War Scene
Extract the vision disc mesh/material structure from code into a `.tscn` file.

**Files:**
- Create: `scenes/fog_of_war.tscn`
- Create: `scenes/explored_marker.tscn`
- Modify: `scripts/systems/fog_of_war.gd`
- Modify: `scripts/game_3d.gd`

- [ ] **Step 3.1: Create fog_of_war.tscn**
  Write file content for `scenes/fog_of_war.tscn`:
  ```tscn
  [gd_scene load_steps=4 format=3 uid="uid://fogofwar000001"]

  [ext_resource type="Script" path="res://scripts/systems/fog_of_war.gd" id="1_fogofwar"]

  [sub_resource type="CylinderMesh" id="CylinderMesh_vision"]
  top_radius = 1.0
  bottom_radius = 1.0
  height = 0.025
  radial_segments = 64

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_vision"]
  albedo_color = Color(0.5, 0.95, 0.75, 0.2)
  roughness = 0.9
  transparency = 1
  emission_enabled = true
  emission = Color(0.1, 0.8, 0.45, 1)
  emission_energy_multiplier = 0.18

  [node name="FogOfWar" type="Node3D"]
  script = ExtResource("1_fogofwar")

  [node name="ExploredTrail" type="Node3D" parent="."]

  [node name="VisionDisc" type="MeshInstance3D" parent="."]
  mesh = SubResource("CylinderMesh_vision")
  material_override = SubResource("StandardMaterial3D_vision")
  ```

- [ ] **Step 3.2: Create explored_marker.tscn**
  Write file content for `scenes/explored_marker.tscn`:
  ```tscn
  [gd_scene format=3 uid="uid://exploredmarker0001"]

  [sub_resource type="CylinderMesh" id="CylinderMesh_trail"]
  top_radius = 1.0
  bottom_radius = 1.0
  height = 0.025
  radial_segments = 64

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_trail"]
  albedo_color = Color(0.42, 0.58, 0.46, 0.11)
  roughness = 0.9
  transparency = 1
  emission = Color(0, 0, 0, 1)
  emission_energy_multiplier = 0.0

  [node name="ExploredMarker" type="MeshInstance3D"]
  mesh = SubResource("CylinderMesh_trail")
  material_override = SubResource("StandardMaterial3D_trail")
  ```

- [ ] **Step 3.3: Update fog_of_war.gd**
  Load nodes from scene and instantiate `explored_marker.tscn` at runtime:
  ```diff
  +const EXPLORED_MARKER_SCENE := preload("res://scenes/explored_marker.tscn")
  +
   func _build_nodes() -> void:
  -	_trail_parent = Node3D.new()
  -	_trail_parent.name = "ExploredTrail"
  -	add_child(_trail_parent)
  -
  -	_vision_disc = MeshInstance3D.new()
  -	_vision_disc.name = "VisionDisc"
  -	_vision_disc.mesh = _make_disc_mesh()
  -	_vision_disc.material_override = _make_material(Color(0.5, 0.95, 0.75, 0.20), Color(0.1, 0.8, 0.45, 1.0), 0.18)
  -	add_child(_vision_disc)
  +	_trail_parent = get_node_or_null("ExploredTrail") as Node3D
  +	if _trail_parent == null:
  +		_trail_parent = Node3D.new()
  +		_trail_parent.name = "ExploredTrail"
  +		add_child(_trail_parent)
  +
  +	_vision_disc = get_node_or_null("VisionDisc") as MeshInstance3D
  +	if _vision_disc == null:
  +		_vision_disc = MeshInstance3D.new()
  +		_vision_disc.name = "VisionDisc"
  +		_vision_disc.mesh = _make_disc_mesh()
  +		_vision_disc.material_override = _make_material(Color(0.5, 0.95, 0.75, 0.20), Color(0.1, 0.8, 0.45, 1.0), 0.18)
  +		add_child(_vision_disc)
   
   func _add_trail_marker(world_position: Vector3) -> void:
   	if _trail_parent == null:
   		return
  -	var marker := MeshInstance3D.new()
  -	marker.name = "ExploredMarker"
  -	marker.mesh = _make_disc_mesh()
  -	marker.material_override = _make_material(Color(0.42, 0.58, 0.46, 0.11), Color(0.0, 0.0, 0.0, 1.0), 0.0)
  +	var marker := EXPLORED_MARKER_SCENE.instantiate() as MeshInstance3D
   	var radius := maxf(_current_radius * trail_radius_scale, min_radius)
   	marker.scale = Vector3(radius, 1.0, radius)
   	_trail_parent.add_child(marker)
   	marker.global_position = _ground_position(world_position, 0.025)
  ```

- [ ] **Step 3.4: Update game_3d.gd to instantiate fog_of_war.tscn**
  ```diff
  +const FOG_OF_WAR_SCENE := preload("res://scenes/fog_of_war.tscn")
  +
   func _add_fog_of_war() -> void:
   	var existing := get_node_or_null("FogOfWar") as Node3D
   	if existing != null:
   		_fog_of_war = existing
   		return
  -	var fog := Node3D.new()
  -	fog.name = "FogOfWar"
  -	fog.set_script(FOG_OF_WAR_SCRIPT)
  +	var fog := FOG_OF_WAR_SCENE.instantiate() as Node3D
   	add_child(fog)
   	_fog_of_war = fog
  ```

- [ ] **Step 3.5: Run tests and commit**
  Run: `powershell -File tests/run_godot_runtime_checks.ps1`
  Run: `git add scenes/fog_of_war.tscn scenes/explored_marker.tscn`
  Commit: `git commit -am "feat: extract fog of war to scene file"`

---

### Task 4: Move HP & Alert Bars to Enemy Scenes
Integrate `AlertBar` and `HpBar` node structures directly into the enemy scene files.

**Files:**
- Modify: `scenes/enemy_3d.tscn`
- Modify: `scenes/patrol_enemy_3d.tscn`
- Modify: `scenes/dormant_enemy_3d.tscn`
- Modify: `scripts/enemies/enemy_3d.gd`

- [ ] **Step 4.1: Modify enemy_3d.tscn**
  Add AlertBar and HpBar to `scenes/enemy_3d.tscn`:
  ```diff
  @@ -29,2 +29,29 @@
   material_override = SubResource("StandardMaterial3D_enemy")
   
  +[sub_resource type="BoxMesh" id="BoxMesh_alert_back"]
  +size = Vector3(1, 0.08, 0.04)
  +[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_alert_back"]
  +albedo_color = Color(0.04, 0.05, 0.05, 0.9)
  +roughness = 0.5
  +transparency = 1
  +[sub_resource type="BoxMesh" id="BoxMesh_alert_fill"]
  +size = Vector3(1, 0.052, 0.048)
  +[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_alert_fill"]
  +albedo_color = Color(1, 0.65, 0.12, 1)
  +roughness = 0.5
  +emission_enabled = true
  +emission = Color(1, 0.35, 0.05, 1)
  +emission_energy_multiplier = 0.8
  +
  +[sub_resource type="BoxMesh" id="BoxMesh_hp_back"]
  +size = Vector3(1, 0.08, 0.04)
  +[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_hp_back"]
  +albedo_color = Color(0.04, 0.04, 0.04, 0.9)
  +roughness = 0.5
  +transparency = 1
  +[sub_resource type="BoxMesh" id="BoxMesh_hp_fill"]
  +size = Vector3(1, 0.052, 0.048)
  +[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_hp_fill"]
  +albedo_color = Color(0.95, 0.08, 0.05, 1)
  +roughness = 0.5
  +emission_enabled = true
  +emission = Color(1, 0.04, 0.02, 1)
  +emission_energy_multiplier = 0.65
  +
  +[node name="AlertBar" type="Node3D" parent="."]
  +transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.65, 0)
  +
  +[node name="AlertBack" type="MeshInstance3D" parent="AlertBar"]
  +mesh = SubResource("BoxMesh_alert_back")
  +material_override = SubResource("StandardMaterial3D_alert_back")
  +
  +[node name="AlertFill" type="MeshInstance3D" parent="AlertBar"]
  +transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -0.01)
  +mesh = SubResource("BoxMesh_alert_fill")
  +material_override = SubResource("StandardMaterial3D_alert_fill")
  +
  +[node name="HpBar" type="Node3D" parent="."]
  +transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.82, 0)
  +
  +[node name="HpBack" type="MeshInstance3D" parent="HpBar"]
  +mesh = SubResource("BoxMesh_hp_back")
  +material_override = SubResource("StandardMaterial3D_hp_back")
  +
  +[node name="HpFill" type="MeshInstance3D" parent="HpBar"]
  +transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -0.01)
  +mesh = SubResource("BoxMesh_hp_fill")
  +material_override = SubResource("StandardMaterial3D_hp_fill")
   ```

- [ ] **Step 4.2: Modify patrol_enemy_3d.tscn**
  Add the same AlertBar/HpBar elements to `scenes/patrol_enemy_3d.tscn`.
  (Same diff contents as Step 4.1 added to `patrol_enemy_3d.tscn`).

- [ ] **Step 4.3: Modify dormant_enemy_3d.tscn**
  Add the same AlertBar/HpBar elements to `scenes/dormant_enemy_3d.tscn`.
  (Same diff contents as Step 4.1 added to `dormant_enemy_3d.tscn`).

- [ ] **Step 4.4: Update enemy_3d.gd**
  Access AlertBar/HpBar nodes from the scene instead of dynamically creating them:
  ```diff
   func _ensure_alert_bar() -> void:
   	var existing := get_node_or_null("AlertBar")
   	if existing is Node3D:
   		_alert_bar = existing as Node3D
   	elif existing == null:
   		_alert_bar = Node3D.new()
   		_alert_bar.name = "AlertBar"
   		_alert_bar.position = Vector3(0.0, 1.65, 0.0)
   		add_child(_alert_bar)
   	if _alert_bar != null:
   		_ensure_alert_bar_meshes()
  +		if _alert_bar_fill != null and _alert_bar_fill.material_override != null:
  +			_alert_bar_fill.material_override = _alert_bar_fill.material_override.duplicate()
   
   func _ensure_hp_bar() -> void:
   	var existing := get_node_or_null("HpBar")
   	if existing is Node3D:
   		_hp_bar = existing as Node3D
   	elif existing == null:
   		_hp_bar = Node3D.new()
   		_hp_bar.name = "HpBar"
   		_hp_bar.position = Vector3(0.0, 1.82, 0.0)
   		add_child(_hp_bar)
   	if _hp_bar != null:
   		_ensure_hp_bar_meshes()
  +		if _hp_bar_fill != null and _hp_bar_fill.material_override != null:
  +			_hp_bar_fill.material_override = _hp_bar_fill.material_override.duplicate()
   
   func _ensure_alert_bar_meshes() -> void:
   	var back := _alert_bar.get_node_or_null("AlertBack") as MeshInstance3D
   	if back == null:
   		back = MeshInstance3D.new()
   		back.name = "AlertBack"
   		back.mesh = _make_alert_box_mesh(Vector3(ALERT_BAR_WIDTH, ALERT_BAR_HEIGHT, ALERT_BAR_DEPTH))
   		back.material_override = _make_alert_material(Color(0.04, 0.05, 0.05, 0.9), Color(0.0, 0.0, 0.0, 1.0), 0.0)
   		_alert_bar.add_child(back)
   
   	_alert_bar_fill = _alert_bar.get_node_or_null("AlertFill") as MeshInstance3D
   	if _alert_bar_fill == null:
   		_alert_bar_fill = MeshInstance3D.new()
   		_alert_bar_fill.name = "AlertFill"
   		_alert_bar_fill.mesh = _make_alert_box_mesh(Vector3(ALERT_BAR_WIDTH, ALERT_BAR_HEIGHT * 0.65, ALERT_BAR_DEPTH * 1.2))
   		_alert_bar_fill.material_override = _make_alert_material(Color(1.0, 0.65, 0.12, 1.0), Color(1.0, 0.35, 0.05, 1.0), 0.8)
   		_alert_bar_fill.position.z = -0.01
   		_alert_bar.add_child(_alert_bar_fill)
   
   func _ensure_hp_bar_meshes() -> void:
   	var back := _hp_bar.get_node_or_null("HpBack") as MeshInstance3D
   	if back == null:
   		back = MeshInstance3D.new()
   		back.name = "HpBack"
   		back.mesh = _make_alert_box_mesh(Vector3(HP_BAR_WIDTH, HP_BAR_HEIGHT, HP_BAR_DEPTH))
   		back.material_override = _make_alert_material(Color(0.04, 0.04, 0.04, 0.9), Color(0.0, 0.0, 0.0, 1.0), 0.0)
   		_hp_bar.add_child(back)
   
   	_hp_bar_fill = _hp_bar.get_node_or_null("HpFill") as MeshInstance3D
   	if _hp_bar_fill == null:
   		_hp_bar_fill = MeshInstance3D.new()
   		_hp_bar_fill.name = "HpFill"
   		_hp_bar_fill.mesh = _make_alert_box_mesh(Vector3(HP_BAR_WIDTH, HP_BAR_HEIGHT * 0.65, HP_BAR_DEPTH * 1.2))
   		_hp_bar_fill.material_override = _make_alert_material(Color(0.95, 0.08, 0.05, 1.0), Color(1.0, 0.04, 0.02, 1.0), 0.65)
   		_hp_bar_fill.position.z = -0.01
   		_hp_bar.add_child(_hp_bar_fill)
  ```

- [ ] **Step 4.5: Run tests and commit**
  Run: `powershell -File tests/run_godot_runtime_checks.ps1`
  Commit: `git commit -am "refactor: place enemy alert/hp bars directly in scene files"`

---

### Task 5: Avoid Overwriting Editor Materials
Modify container and pickup scripts to duplicate and modify existing materials rather than replacing them completely.

**Files:**
- Modify: `scripts/items/container_3d.gd`
- Modify: `scripts/items/item_pickup_3d.gd`

- [ ] **Step 5.1: Update container_3d.gd**
  Duplicate material in `_ready()` and modify it in `_set_visual_color()`:
  ```diff
   func _ready() -> void:
   	_interact_area.body_entered.connect(_on_body_entered)
   	_interact_area.body_exited.connect(_on_body_exited)
  +	if _visual.material_override != null:
  +		_visual.material_override = _visual.material_override.duplicate()
   	_set_visual_color(Color(0.64, 0.52, 0.27, 1.0))
  ...
   func _set_visual_color(color: Color) -> void:
  -	var material := StandardMaterial3D.new()
  -	material.albedo_color = color
  -	material.roughness = 0.84
  -	_visual.material_override = material
  +	if _visual.material_override is StandardMaterial3D:
  +		_visual.material_override.albedo_color = color
  ```

- [ ] **Step 5.2: Update item_pickup_3d.gd**
  Duplicate material and modify albedo/emission:
  ```diff
   func _ready() -> void:
   	body_entered.connect(_on_body_entered)
  +	if _visual.material_override != null:
  +		_visual.material_override = _visual.material_override.duplicate()
   	_update_visual()
  ...
   func _update_visual() -> void:
   	if item_data == null:
   		return
   	var color := Color(0.9, 0.9, 0.9, 1.0)
   	match item_data.type:
   		ItemDataResource.Type.COLLECTIBLE:
   			color = Color(0.95, 0.65, 0.25, 1.0)
   		ItemDataResource.Type.AMMO:
   			color = Color(0.4, 0.6, 0.95, 1.0)
   		ItemDataResource.Type.BATTERY:
   			color = Color(0.35, 0.85, 0.45, 1.0)
   		ItemDataResource.Type.PURIFIER:
   			color = Color(0.35, 0.85, 0.85, 1.0)
  -	var material := StandardMaterial3D.new()
  -	material.albedo_color = color
  -	material.emission_enabled = true
  -	material.emission = color * 0.2
  -	_visual.material_override = material
  +	if _visual.material_override is StandardMaterial3D:
  +		_visual.material_override.albedo_color = color
  +		_visual.material_override.emission_enabled = true
  +		_visual.material_override.emission = color * 0.2
  ```

- [ ] **Step 5.3: Run tests and commit**
  Run: `powershell -File tests/run_godot_runtime_checks.ps1`
  Commit: `git commit -am "refactor: preserve editor material overrides on containers and pickups"`

---

### Task 6: Create Expedition Map Scene & Wire It
Pre-place ground, obstacles, risk zones, containers, and initial enemy spawn markers in a `.tscn` file, and load/assign them in `game_3d.gd` and `spawn_manager.gd`.

**Files:**
- Create: `scenes/expedition_map.tscn`
- Modify: `scripts/items/container_3d.gd`
- Modify: `scripts/game_3d.gd`
- Modify: `scripts/managers/spawn_manager.gd`

- [ ] **Step 6.1: Add export var risk to container_3d.gd**
  Modify `scripts/items/container_3d.gd` to export `risk`:
  ```diff
   @export var loot_table: Array[ItemDataResource] = []
  +@export var risk: String = "low"
   @export var base_crack_time: float = 2.0
  ```

- [ ] **Step 6.2: Create expedition_map.tscn**
  Create `scenes/expedition_map.tscn` laying out the 3D map elements:
  (Ground, 8 Obstacles, 4 Zones, 8 Containers, and 8 InitialSpawns markers).
  Complete `.tscn` code for `scenes/expedition_map.tscn`:
  ```tscn
  [gd_scene load_steps=22 format=3 uid="uid://expeditionmap00001"]

  [ext_resource type="PackedScene" path="res://scenes/container_3d.tscn" id="1_container"]
  [ext_resource type="Resource" path="res://resources/items/relic_small.tres" id="2_relic"]
  [ext_resource type="Resource" path="res://resources/items/standard_ammo.tres" id="3_ammo"]
  [ext_resource type="Resource" path="res://resources/items/battery_small.tres" id="4_battery"]
  [ext_resource type="Resource" path="res://resources/items/purifier.tres" id="5_purifier"]

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_ground"]
  albedo_color = Color(0.13, 0.18, 0.13, 1)
  roughness = 0.9

  [sub_resource type="BoxMesh" id="BoxMesh_ground"]
  size = Vector3(480, 0.1, 240)

  [sub_resource type="BoxShape3D" id="BoxShape3D_ground"]
  size = Vector3(480, 0.1, 240)

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_obstacle"]
  albedo_color = Color(0.28, 0.27, 0.25, 1)
  roughness = 0.82

  [sub_resource type="BoxMesh" id="BoxMesh_obs0"]
  size = Vector3(18, 1.5, 7)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs0"]
  size = Vector3(18, 1.5, 7)

  [sub_resource type="BoxMesh" id="BoxMesh_obs1"]
  size = Vector3(11, 1.4, 16)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs1"]
  size = Vector3(11, 1.4, 16)

  [sub_resource type="BoxMesh" id="BoxMesh_obs2"]
  size = Vector3(24, 1.2, 5)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs2"]
  size = Vector3(24, 1.2, 5)

  [sub_resource type="BoxMesh" id="BoxMesh_obs3"]
  size = Vector3(13, 1.5, 13)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs3"]
  size = Vector3(13, 1.5, 13)

  [sub_resource type="BoxMesh" id="BoxMesh_obs4"]
  size = Vector3(9, 1.8, 27)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs4"]
  size = Vector3(9, 1.8, 27)

  [sub_resource type="BoxMesh" id="BoxMesh_obs5"]
  size = Vector3(22, 1.5, 8)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs5"]
  size = Vector3(22, 1.5, 8)

  [sub_resource type="BoxMesh" id="BoxMesh_obs6"]
  size = Vector3(14, 1.3, 18)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs6"]
  size = Vector3(14, 1.3, 18)

  [sub_resource type="BoxMesh" id="BoxMesh_obs7"]
  size = Vector3(18, 1.7, 12)
  [sub_resource type="BoxShape3D" id="BoxShape3D_obs7"]
  size = Vector3(18, 1.7, 12)

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_low_zone"]
  albedo_color = Color(0.12, 0.23, 0.16, 0.32)
  roughness = 0.9
  transparency = 1

  [sub_resource type="StandardMaterial3D" id="StandardMaterial3D_high_zone"]
  albedo_color = Color(0.35, 0.1, 0.12, 0.34)
  roughness = 0.9
  transparency = 1

  [sub_resource type="BoxMesh" id="BoxMesh_zone_outskirts"]
  size = Vector3(192, 0.03, 210)

  [sub_resource type="BoxMesh" id="BoxMesh_zone_rail"]
  size = Vector3(176, 0.03, 182)

  [sub_resource type="BoxMesh" id="BoxMesh_zone_yard"]
  size = Vector3(184, 0.03, 214)

  [sub_resource type="BoxMesh" id="BoxMesh_zone_wreck"]
  size = Vector3(120, 0.03, 92)

  [node name="ExpeditionMap" type="Node3D"]

  [node name="Ground" type="StaticBody3D" parent="."]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.05, 0)
  collision_layer = 4
  collision_mask = 0

  [node name="GroundVisual" type="MeshInstance3D" parent="Ground"]
  mesh = SubResource("BoxMesh_ground")
  material_override = SubResource("StandardMaterial3D_ground")

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Ground"]
  shape = SubResource("BoxShape3D_ground")

  [node name="Obstacles" type="Node3D" parent="."]

  [node name="Obstacle0" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -72, 0.75, -30)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle0"]
  shape = SubResource("BoxShape3D_obs0")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle0"]
  mesh = SubResource("BoxMesh_obs0")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle1" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -42, 0.7, 32)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle1"]
  shape = SubResource("BoxShape3D_obs1")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle1"]
  mesh = SubResource("BoxMesh_obs1")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle2" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -6, 0.6, -52)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle2"]
  shape = SubResource("BoxShape3D_obs2")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle2"]
  mesh = SubResource("BoxMesh_obs2")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle3" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 28, 0.75, 22)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle3"]
  shape = SubResource("BoxShape3D_obs3")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle3"]
  mesh = SubResource("BoxMesh_obs3")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle4" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 64, 0.9, -10)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle4"]
  shape = SubResource("BoxShape3D_obs4")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle4"]
  mesh = SubResource("BoxMesh_obs4")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle5" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 96, 0.75, 48)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle5"]
  shape = SubResource("BoxShape3D_obs5")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle5"]
  mesh = SubResource("BoxMesh_obs5")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle6" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -126, 0.65, 52)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle6"]
  shape = SubResource("BoxShape3D_obs6")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle6"]
  mesh = SubResource("BoxMesh_obs6")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Obstacle7" type="StaticBody3D" parent="Obstacles"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 142, 0.85, -54)
  collision_layer = 4
  collision_mask = 0

  [node name="CollisionShape3D" type="CollisionShape3D" parent="Obstacles/Obstacle7"]
  shape = SubResource("BoxShape3D_obs7")

  [node name="MeshInstance3D" type="MeshInstance3D" parent="Obstacles/Obstacle7"]
  mesh = SubResource("BoxMesh_obs7")
  material_override = SubResource("StandardMaterial3D_obstacle")

  [node name="Zones" type="Node3D" parent="."]

  [node name="AshOutskirtsZone" type="MeshInstance3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -132, 0.015, 0)
  mesh = SubResource("BoxMesh_zone_outskirts")
  material_override = SubResource("StandardMaterial3D_low_zone")

  [node name="AshOutskirtsLabel" type="Label3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 0.422618, -0.906308, 0, 0.906308, 0.422618, -132, 0.08, 0)
  modulate = Color(0.92, 0.88, 0.72, 1)
  text = "Ash Outskirts  LOW"
  font_size = 32

  [node name="BrokenRailZone" type="MeshInstance3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 8, 0.015, -22)
  mesh = SubResource("BoxMesh_zone_rail")
  material_override = SubResource("StandardMaterial3D_low_zone")

  [node name="BrokenRailLabel" type="Label3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 0.422618, -0.906308, 0, 0.906308, 0.422618, 8, 0.08, -22)
  modulate = Color(0.92, 0.88, 0.72, 1)
  text = "Broken Rail  LOW"
  font_size = 32

  [node name="BlackYardZone" type="MeshInstance3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 132, 0.015, 8)
  mesh = SubResource("BoxMesh_zone_yard")
  material_override = SubResource("StandardMaterial3D_high_zone")

  [node name="BlackYardLabel" type="Label3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 0.422618, -0.906308, 0, 0.906308, 0.422618, 132, 0.08, 8)
  modulate = Color(0.92, 0.88, 0.72, 1)
  text = "Black Yard  HIGH"
  font_size = 32

  [node name="CoreWreckZone" type="MeshInstance3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 32, 0.015, 66)
  mesh = SubResource("BoxMesh_zone_wreck")
  material_override = SubResource("StandardMaterial3D_high_zone")

  [node name="CoreWreckLabel" type="Label3D" parent="Zones"]
  transform = Transform3D(1, 0, 0, 0, 0.422618, -0.906308, 0, 0.906308, 0.422618, 32, 0.08, 66)
  modulate = Color(0.92, 0.88, 0.72, 1)
  text = "Core Wreck  HIGH"
  font_size = 32

  [node name="Containers" type="Node3D" parent="."]

  [node name="Container1" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -172, 0, -58)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("3_ammo"), ExtResource("4_battery")])
  risk = "low"

  [node name="Container2" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -116, 0, 44)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("4_battery")])
  risk = "low"

  [node name="Container3" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -28, 0, -36)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("3_ammo"), ExtResource("2_relic")])
  risk = "low"

  [node name="Container4" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 34, 0, -72)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("4_battery"), ExtResource("3_ammo")])
  risk = "low"

  [node name="Container5" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 96, 0, -42)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("2_relic"), ExtResource("2_relic"), ExtResource("3_ammo")])
  risk = "high"

  [node name="Container6" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 148, 0, 38)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("5_purifier"), ExtResource("2_relic")])
  risk = "high"

  [node name="Container7" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 46, 0, 72)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("2_relic"), ExtResource("5_purifier"), ExtResource("3_ammo")])
  risk = "high"

  [node name="Container8" parent="Containers" instance=ExtResource("1_container")]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 12, 0, 96)
  loot_table = Array[Resource("res://scripts/items/item_data.gd")]([ExtResource("2_relic"), ExtResource("2_relic"), ExtResource("5_purifier")])
  risk = "high"

  [node name="InitialSpawns" type="Node3D" parent="."]

  [node name="PatrolSpawn1" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -58, 0, -28)

  [node name="PatrolSpawn2" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18, 0, 44)

  [node name="DormantSpawn1" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 34, 0, -46)

  [node name="DormantSpawn2" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -92, 0, 62)

  [node name="PatrolSpawn3" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 96, 0, -36)

  [node name="PatrolSpawn4" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 132, 0, 42)

  [node name="DormantSpawn3" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 48, 0, 78)

  [node name="DormantSpawn4" type="Marker3D" parent="InitialSpawns"]
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 154, 0, -68)
  ```

- [ ] **Step 6.3: Update game_3d.gd to instantiate and load expedition_map.tscn**
  ```diff
  +const EXPEDITION_MAP_SCENE := preload("res://scenes/expedition_map.tscn")
  +
   func _ensure_map_roots() -> void:
   	_afterglow_map = $World.get_node_or_null("AfterglowMap") as Node3D
   	if _afterglow_map == null:
   		_afterglow_map = AFTERGLOW_MAP_SCENE.instantiate() as Node3D
   		_afterglow_map.name = "AfterglowMap"
   		$World.add_child(_afterglow_map)
   
   	_expedition_map = $World.get_node_or_null("ExpeditionMap") as Node3D
   	if _expedition_map == null:
  -		_expedition_map = Node3D.new()
  +		_expedition_map = EXPEDITION_MAP_SCENE.instantiate() as Node3D
   		_expedition_map.name = "ExpeditionMap"
   		$World.add_child(_expedition_map)
  +
  +	# Wire preplaced containers inside the scene to the global _containers group
  +	var map_containers = _expedition_map.get_node_or_null("Containers")
  +	if map_containers != null and _containers != null:
  +		for child in map_containers.get_children():
  +			map_containers.remove_child(child)
  +			_containers.add_child(child)
  +			if child.has_signal("cracked") and not child.cracked.is_connected(_on_container_cracked):
  +				child.cracked.connect(_on_container_cracked)
  +			# Ensure the risk metadata matches for runtime compatibility
  +			if "risk" in child:
  +				child.set_meta("risk", child.risk)
  ```

- [ ] **Step 6.4: Update game_3d.gd build/procedural fallbacks**
  Bypass procedural generation when scene is loaded:
  ```diff
   func _build_expedition_map() -> void:
  +	if _expedition_map.scene_file_path != "":
  +		return
   	_resize_ground_for_expedition()
  ```

- [ ] **Step 6.5: Update spawn_manager.gd**
  Seed initial enemies from the scene markers if available:
  ```diff
   func seed_initial_enemies() -> void:
   	if _initial_spawned:
   		return
   	_initial_spawned = true
  +
  +	var map = get_node_or_null("../World/ExpeditionMap")
  +	var initial_spawns = map.get_node_or_null("InitialSpawns") if map != null else null
  +	if initial_spawns != null:
  +		for spawn in initial_spawns.get_children():
  +			if spawn is Node3D:
  +				var is_dormant = spawn.name.to_lower().contains("dormant")
  +				var scene = _dormant_scene if is_dormant else _patrol_scene
  +				_spawn_fixed(scene, spawn.global_position)
  +		return
  +
   	_spawn_fixed(_patrol_scene, Vector3(-58.0, 0.0, -28.0))
  ```

- [ ] **Step 6.6: Run tests and commit**
  Run: `powershell -File tests/run_godot_runtime_checks.ps1`
  Run: `git add scenes/expedition_map.tscn`
  Commit: `git commit -am "feat: migrate expedition map, obstacles, containers, and spawn markers to scene file"`

---

### Task 7: Final verification
Perform cleanup checks and ensure all static/runtime tests run successfully.

- [ ] **Step 7.1: Verify static and runtime tests**
  Run: `powershell -File tests/dev_a_static_checks.ps1`
  Run: `powershell -File tests/game_3d_static_checks.ps1`
  Run: `powershell -File tests/run_godot_runtime_checks.ps1`
  Expected: All checks pass!
