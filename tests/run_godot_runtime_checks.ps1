param(
	[string]$GodotPath = "",
	[int]$TimeoutSeconds = 90,
	[int]$MaxWorkingSetMb = 4096
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$testsRoot = Join-Path $root "tests"
$runtimeChecks = Get-ChildItem -LiteralPath $testsRoot -Filter "*_runtime_checks.gd" |
	Sort-Object Name |
	ForEach-Object { $_.FullName.Substring($root.Length + 1) }

if ($runtimeChecks.Count -eq 0) {
	throw "No runtime check scripts found in $testsRoot"
}

function Resolve-GodotConsolePath {
	param([string]$RequestedPath)

	if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
		if (Test-Path $RequestedPath) {
			return (Resolve-Path $RequestedPath).Path
		}
		throw "Godot console executable not found: $RequestedPath"
	}

	foreach ($searchRoot in @($root, $testsRoot)) {
		$candidate = Get-ChildItem -LiteralPath $searchRoot -File -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -match "^(godot|godot4)([._-]?console)?\.exe$" -or $_.Name -match "^Godot_v.*(_console)?\.exe$" } |
			Sort-Object @{ Expression = { if ($_.Name -match "console") { 0 } else { 1 } } }, Name |
			Select-Object -First 1
		if ($null -ne $candidate) {
			return $candidate.FullName
		}
	}

	$envCandidates = @($env:GODOT_BIN, $env:GODOT_PATH) |
		Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
	foreach ($candidate in $envCandidates) {
		if (Test-Path $candidate) {
			return (Resolve-Path $candidate).Path
		}
	}

	foreach ($commandName in @("godot", "godot4", "godot.console", "godot4_console")) {
		$command = Get-Command $commandName -ErrorAction SilentlyContinue
		if ($null -ne $command) {
			return $command.Source
		}
	}

	throw "Godot console executable not found. Put Godot in the project root/tests folder, pass -GodotPath, set GODOT_BIN/GODOT_PATH, or add Godot to PATH."
}

$resolvedGodotPath = Resolve-GodotConsolePath -RequestedPath $GodotPath

function Invoke-GodotRuntimeCheck {
	param([string]$ScriptPath)

	$stdout = Join-Path $env:TEMP ("godot-runtime-" + [Guid]::NewGuid().ToString("N") + ".out.log")
	$stderr = Join-Path $env:TEMP ("godot-runtime-" + [Guid]::NewGuid().ToString("N") + ".err.log")
	$args = @("--headless", "--path", $root, "--script", $ScriptPath)
	$process = Start-Process `
		-FilePath $resolvedGodotPath `
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
