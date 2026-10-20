param(
    [string]$GodotPath = 'C:\zdarova90210\game-projects\Godot_v4.7.2-stable_win64.exe',
    [switch]$Visual,
    [switch]$Realtime
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousDisplayTest = $env:EXTRACTION_TEST_DISPLAY
try {
    # Scope editor settings and user data to this validation process only.
    $env:APPDATA = Join-Path $projectRoot '.godot-home\Roaming'
    $env:LOCALAPPDATA = Join-Path $projectRoot '.godot-home\Local'
    $env:EXTRACTION_TEST_DISPLAY = '1'
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
        if ($process.ExitCode -ne 0 -or $log -match '(?m)(SCRIPT ERROR:|ERROR:|FAIL:|WARNING:)') {
            Write-Output $log
            throw "$Name failed (exit $($process.ExitCode)). See $logPath"
        }
        if ($Name -in @('gameplay', 'combat', 'combat_realtime', 'feedback', 'health_bar', 'ammo_feedback', 'active_reload', 'hud_menu', 'display', 'display_native') -and $log -notmatch 'RESULT: \d+ checks, 0 failures') {
            Write-Output $log
            throw "$Name checks did not reach completion. See $logPath"
        }
        if ($Name -eq 'visual' -and $log -notmatch 'Visual captures saved:') {
            Write-Output $log
            throw "Visual captures did not reach completion. See $logPath"
        }
        if ($Name -eq 'display_visual' -and $log -notmatch 'Display captures saved:') {
            Write-Output $log
            throw "Resolution captures did not reach completion. See $logPath"
        }
        $summary = [regex]::Match($log, 'RESULT: \d+ checks, 0 failures|(?:Visual|Display) captures saved:[^\r\n]*').Value
        if ($summary) { Write-Output "$Name - $summary" }
        else { Write-Output "$Name passed." }
    }

    Invoke-GodotCheck 'import' @('--headless', '--editor', '--import')
    Invoke-GodotCheck 'startup' @('--headless', '--quit-after', '120')
    Invoke-GodotCheck 'gameplay' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/gameplay_test.gd')
    Invoke-GodotCheck 'combat' @('--headless', '--fixed-fps', '60', '--quit-after', '3600', '--script', 'res://tests/combat_test.gd')
    Invoke-GodotCheck 'feedback' @('--headless', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/feedback_test.gd')
    Invoke-GodotCheck 'health_bar' @('--headless', '--fixed-fps', '60', '--quit-after', '600', '--script', 'res://tests/health_bar_test.gd')
    Invoke-GodotCheck 'ammo_feedback' @('--headless', '--fixed-fps', '60', '--quit-after', '600', '--script', 'res://tests/ammo_feedback_test.gd')
    Invoke-GodotCheck 'active_reload' @('--headless', '--fixed-fps', '60', '--quit-after', '2400', '--script', 'res://tests/active_reload_test.gd')
    Invoke-GodotCheck 'hud_menu' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/hud_menu_test.gd')
    Invoke-GodotCheck 'display' @('--headless', '--fixed-fps', '60', '--quit-after', '900', '--script', 'res://tests/display_test.gd')
    if ($Realtime) {
        Invoke-GodotCheck 'combat_realtime' @('--headless', '--max-fps', '60', '--quit-after', '3600', '--script', 'res://tests/combat_test.gd', '--', '--async-navigation')
    }
    if ($Visual) {
        Invoke-GodotCheck 'visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/visual_check.gd')
        Invoke-GodotCheck 'display_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/display_visual.gd')
        Invoke-GodotCheck 'display_native' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1200', '--script', 'res://tests/display_native_test.gd')
    }
    Write-Output 'All requested checks passed.'
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:EXTRACTION_TEST_DISPLAY = $previousDisplayTest
}
