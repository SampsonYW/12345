$ErrorActionPreference = "Stop"

function Assert-Contains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Message
	)
	$content = Get-Content -Raw -Encoding UTF8 $Path
	if ($content -notmatch $Pattern) {
		throw $Message
	}
}

function Assert-NotContains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Message
	)
	$content = Get-Content -Raw -Encoding UTF8 $Path
	if ($content -match $Pattern) {
		throw $Message
	}
}

$root = Split-Path -Parent $PSScriptRoot
$gameManager = Join-Path $root "scripts/managers/game_manager.gd"
$player = Join-Path $root "scripts/player/player_3d.gd"
$playerShooting = Join-Path $root "scripts/player/player_shooting_3d.gd"
$hud = Join-Path $root "scripts/ui/hud.gd"

Assert-NotContains `
	-Path $gameManager `
	-Pattern "add_erosion\(EROSION_RATE \* delta \* 100\.0\)" `
	-Message "Natural erosion growth must use percentage points per second, not multiply by 100."

Assert-Contains `
	-Path $gameManager `
	-Pattern "signal signal_flare_fired\(origin: Vector3\)" `
	-Message "GameManager must expose signal_flare_fired(origin) for extraction/HUD integration."

Assert-Contains `
	-Path $gameManager `
	-Pattern "func fire_signal_flare\(origin: Vector3\) -> bool:" `
	-Message "GameManager must expose fire_signal_flare(origin) for the player input layer."

Assert-Contains `
	-Path $player `
	-Pattern 'event\.is_action_pressed\("signal_flare"\)' `
	-Message "Player must listen for the signal_flare action."

Assert-Contains `
	-Path $player `
	-Pattern "NoiseManager\.emit_noise\(global_position, NoiseManager\.Level\.GLOBAL\)" `
	-Message "Signal flare must emit a global noise event from the player position."

Assert-Contains `
	-Path $playerShooting `
	-Pattern "func fire\(\) -> void:\s+if current_ammo <= 0:\s+return[\s\S]*current_ammo -= 1" `
	-Message "PlayerShooting.fire() must guard and consume ammo only for successful shots."

Assert-Contains `
	-Path $hud `
	-Pattern "GameManager\.state_changed\.connect\(_on_state_changed\)" `
	-Message "HUD must listen to GameManager state changes."

Assert-Contains `
	-Path $hud `
	-Pattern "GameManager\.signal_flare_fired\.connect\(_on_signal_flare_fired\)" `
	-Message "HUD must listen to signal flare events."

Write-Host "Dev A static checks passed."
