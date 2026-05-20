param(
	[string]$GodotPath = "C:\Users\chengqi\Downloads\Godot_v4.6.2-stable_win64_console.exe",
	[int]$TimeoutSeconds = 90,
	[int]$MaxWorkingSetMb = 4096
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$runtimeChecks = @(
	"tests\mvp_runtime_checks.gd",
	"tests\game_3d_runtime_checks.gd",
	"tests\dev_a_runtime_checks.gd",
	"tests\hud_input_runtime_checks.gd",
	"tests\enemy_ai_runtime_checks.gd",
	"tests\noise_manager_runtime_checks.gd",
	"tests\polish_flow_runtime_checks.gd",
	"tests\inventory_ui_runtime_checks.gd",
	"tests\container_search_runtime_checks.gd",
	"tests\expedition_map_runtime_checks.gd",
	"tests\extraction_pressure_runtime_checks.gd"
)

if (-not (Test-Path $GodotPath)) {
	throw "Godot console executable not found: $GodotPath"
}

function Invoke-GodotRuntimeCheck {
	param([string]$ScriptPath)

	$stdout = Join-Path $env:TEMP ("godot-runtime-" + [Guid]::NewGuid().ToString("N") + ".out.log")
	$stderr = Join-Path $env:TEMP ("godot-runtime-" + [Guid]::NewGuid().ToString("N") + ".err.log")
	$args = @("--headless", "--path", $root, "--script", $ScriptPath)
	$process = Start-Process `
		-FilePath $GodotPath `
		-ArgumentList $args `
		-WorkingDirectory $root `
		-WindowStyle Hidden `
		-RedirectStandardOutput $stdout `
		-RedirectStandardError $stderr `
		-PassThru

	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$peakWorkingSetMb = 0.0
	while (-not $process.HasExited) {
		Start-Sleep -Milliseconds 250
		$process.Refresh()
		$workingSetMb = [Math]::Round($process.WorkingSet64 / 1MB, 1)
		$peakWorkingSetMb = [Math]::Max($peakWorkingSetMb, $workingSetMb)
		if ($workingSetMb -gt $MaxWorkingSetMb) {
			Stop-Process -Id $process.Id -Force
			throw "$ScriptPath exceeded memory cap: ${workingSetMb}MB > ${MaxWorkingSetMb}MB"
		}
		if ((Get-Date) -gt $deadline) {
			Stop-Process -Id $process.Id -Force
			throw "$ScriptPath timed out after ${TimeoutSeconds}s"
		}
	}
	$process.WaitForExit()
	$process.Refresh()

	$outText = Get-Content -Raw -ErrorAction SilentlyContinue $stdout
	$errText = Get-Content -Raw -ErrorAction SilentlyContinue $stderr
	if ($null -eq $outText) {
		$outText = ""
	}
	if ($null -eq $errText) {
		$errText = ""
	}
	Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue

	$exitCode = $process.ExitCode
	if ($null -eq $exitCode) {
		if ($errText.Trim().Length -gt 0 -or $outText -notmatch "checks passed\.") {
			throw "$ScriptPath finished but the verifier could not read its exit code.`n$outText`n$errText"
		}
	} elseif ($exitCode -ne 0) {
		throw "$ScriptPath failed with exit code $exitCode`n$outText`n$errText"
	}
	$combinedText = "$outText`n$errText"
	if ($errText.Trim().Length -gt 0 -or $combinedText -match "(?m)^(SCRIPT ERROR|ERROR):") {
		throw "$ScriptPath emitted Godot errors despite exit code $exitCode`n$outText`n$errText"
	}
	$trimmed = $outText.Trim()
	if ($trimmed.Length -gt 0) {
		Write-Host $trimmed
	}
	Write-Host "$ScriptPath peak working set: ${peakWorkingSetMb}MB"
}

foreach ($check in $runtimeChecks) {
	Invoke-GodotRuntimeCheck -ScriptPath $check
}

Write-Host "Godot runtime checks passed with memory guard (${MaxWorkingSetMb}MB cap)."
