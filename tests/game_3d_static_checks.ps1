$ErrorActionPreference = "Stop"

function Assert-FileExists {
	param([string]$Path, [string]$Message)
	if (-not (Test-Path $Path)) {
		throw $Message
	}
}

function Assert-FileNotExists {
	param([string]$Path, [string]$Message)
	if (Test-Path $Path) {
		throw $Message
	}
}

function Assert-Contains {
	param([string]$Path, [string]$Pattern, [string]$Message)
	$content = Get-Content -Raw -Encoding UTF8 $Path
	if ($content -notmatch $Pattern) {
		throw $Message
	}
}

function Assert-NotContains {
	param([string]$Path, [string]$Pattern, [string]$Message)
	$content = Get-Content -Raw -Encoding UTF8 $Path
	if ($content -match $Pattern) {
		throw $Message
	}
}

$root = Split-Path -Parent $PSScriptRoot

$removed2DPaths = @(
	"scenes/game.tscn",
	"scenes/player.tscn",
	"scenes/bullet.tscn",
	"scenes/container.tscn",
	"scenes/item_pickup.tscn",
	"scenes/patrol_enemy.tscn",
	"scenes/dormant_enemy.tscn",
	"scripts/game.gd",
	"scripts/player/player.gd",
	"scripts/player/player_shooting.gd",
	"scripts/player/bullet.gd",
	"scripts/player/signal_flare_marker.gd",
	"scripts/items/container.gd",
	"scripts/items/item_pickup.gd",
	"scripts/enemies/enemy_base.gd",
	"scripts/enemies/patrol_enemy.gd",
	"scripts/enemies/dormant_enemy.gd"
)

foreach ($path in $removed2DPaths) {
	Assert-FileNotExists `
		-Path (Join-Path $root $path) `
		-Message "Obsolete 2D file should be removed: $path"
}

Assert-Contains `
	-Path (Join-Path $root "project.godot") `
	-Pattern 'run/main_scene="res://scenes/game_3d.tscn"' `
	-Message "Project main scene must point at the new 3D scene."

Assert-FileExists `
	-Path (Join-Path $root "scenes/game_3d.tscn") `
	-Message "3D main scene must exist."

Assert-FileExists `
	-Path (Join-Path $root "scenes/player_3d.tscn") `
	-Message "3D player scene must exist."

Assert-FileExists `
	-Path (Join-Path $root "scripts/game_3d.gd") `
	-Message "3D game root script must exist."

Assert-FileExists `
	-Path (Join-Path $root "scripts/player/player_3d.gd") `
	-Message "3D player controller must exist."

Assert-FileExists `
	-Path (Join-Path $root "scripts/player/player_shooting_3d.gd") `
	-Message "3D shooting script must exist."

Assert-FileExists `
	-Path (Join-Path $root "scenes/patrol_enemy_3d.tscn") `
	-Message "3D patrol enemy scene must exist."

Assert-FileExists `
	-Path (Join-Path $root "scenes/dormant_enemy_3d.tscn") `
	-Message "3D dormant enemy scene must exist."

Assert-FileExists `
	-Path (Join-Path $root "scripts/items/container_3d.gd") `
	-Message "3D container script must exist."

Assert-Contains `
	-Path (Join-Path $root "scenes/game_3d.tscn") `
	-Pattern 'type="Camera3D"' `
	-Message "3D scene must include a Camera3D."

Assert-Contains `
	-Path (Join-Path $root "scenes/player_3d.tscn") `
	-Pattern 'type="CharacterBody3D"' `
	-Message "3D player scene must use CharacterBody3D."

Assert-Contains `
	-Path (Join-Path $root "scripts/game_3d.gd") `
	-Pattern 'const PATROL_ENEMY_SCENE := preload\("res://scenes/patrol_enemy_3d.tscn"\)' `
	-Message "3D game must preload the patrol enemy scene."

Assert-Contains `
	-Path (Join-Path $root "scripts/game_3d.gd") `
	-Pattern 'const DORMANT_ENEMY_SCENE := preload\("res://scenes/dormant_enemy_3d.tscn"\)' `
	-Message "3D game must preload the dormant enemy scene."

Assert-Contains `
	-Path (Join-Path $root "scripts/player/player_3d.gd") `
	-Pattern 'event\.is_action_pressed\("signal_flare"\)' `
	-Message "3D player must support the signal_flare action."

Assert-Contains `
	-Path (Join-Path $root "scripts/managers/noise_manager.gd") `
	-Pattern "func _to_noise_position\(value: Variant\) -> Vector3:" `
	-Message "NoiseManager must normalize 3D positions for noise propagation."

Assert-NotContains `
	-Path (Join-Path $root "scripts/managers/noise_manager.gd") `
	-Pattern "Vector2|Node2D" `
	-Message "NoiseManager should not keep obsolete 2D position compatibility."

Assert-Contains `
	-Path (Join-Path $root "scripts/player/player_shooting_3d.gd") `
	-Pattern "var _bullet_pool: Array\[Area3D\]" `
	-Message "3D shooting must maintain a bullet pool to avoid first-shot allocation stutter."

Assert-NotContains `
	-Path (Join-Path $root "scripts/player/player_shooting_3d.gd") `
	-Pattern "func fire\\(\\) -> void:[\\s\\S]*bullet_scene\\.instantiate\\(\\)" `
	-Message "PlayerShooting3D.fire() must reuse pooled bullets instead of instantiating on fire."

Assert-Contains `
	-Path (Join-Path $root "scripts/player/player_shooting_3d.gd") `
	-Pattern "func fire\(\) -> void:\s+if current_ammo <= 0:\s+return[\s\S]*current_ammo -= 1" `
	-Message "PlayerShooting3D.fire() must guard and consume ammo only for successful shots."

Assert-Contains `
	-Path (Join-Path $root "scripts/ui/hud.gd") `
	-Pattern "func _process\(delta: float\) -> void:[\s\S]*_bind_player_refs\(\)" `
	-Message "HUD must retry player binding because the 3D player is spawned at runtime."

Assert-Contains `
	-Path (Join-Path $root "scripts/ui/hud.gd") `
	-Pattern "func _bind_player_refs\(\) -> void:[\s\S]*_player_shooting\.ammo_changed\.connect\(_on_ammo_changed\)" `
	-Message "HUD must connect to PlayerShooting.ammo_changed after the player exists."

Write-Host "3D static checks passed."
