param(
    [string]$GodotPath = 'C:\zdarova90210\game-projects\Godot_v4.7.2-stable_win64.exe',
    [switch]$Visual
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
try {
    # Scope editor settings and user data to this validation process only.
    $env:APPDATA = Join-Path $projectRoot '.godot-home\Roaming'
    $env:LOCALAPPDATA = Join-Path $projectRoot '.godot-home\Local'
    $artifactDirectory = Join-Path $projectRoot 'artifacts'
    New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$artifactDirectory | Out-Null
    # Test captures are not game assets and must not be imported by Godot.
    New-Item -ItemType File -Force -Path (Join-Path $artifactDirectory '.gdignore') | Out-Null

    function Invoke-GodotCheck([string]$Name, [string[]]$CheckArguments) {
        $logPath = Join-Path $artifactDirectory "$Name.log"
        # Godot's GUI executable must be explicitly awaited on Windows.
        $arguments = @('--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $logPath + '"')) + $CheckArguments
        $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            throw "$Name timed out after 60 seconds. See $logPath"
        }
        $process.WaitForExit()
        $log = Get-Content -LiteralPath $logPath -Raw
        Write-Output $log
        if ($process.ExitCode -ne 0 -or $log -match '(?m)(SCRIPT ERROR:|ERROR:|FAIL:|WARNING:)') {
            throw "$Name failed (exit $($process.ExitCode)). See $logPath"
        }
        if ($Name -eq 'gameplay' -and $log -notmatch 'RESULT: \d+ checks, 0 failures') {
            throw "Gameplay checks did not reach completion. See $logPath"
        }
    }

    Invoke-GodotCheck 'import' @('--headless', '--editor', '--import')
    Invoke-GodotCheck 'startup' @('--headless', '--quit-after', '120')
    Invoke-GodotCheck 'gameplay' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/gameplay_test.gd')
    if ($Visual) {
        Invoke-GodotCheck 'visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--quit-after', '120', '--script', 'res://tests/visual_check.gd')
    }
    Write-Output 'All requested checks passed.'
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}
