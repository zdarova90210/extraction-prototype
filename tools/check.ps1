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
$previousProgressTest = $env:EXTRACTION_TEST_PROGRESS
$previousAudioTest = $env:EXTRACTION_TEST_AUDIO
try {
    # Scope editor settings and user data to this validation process only.
    $env:APPDATA = Join-Path $projectRoot '.godot-home\Roaming'
    $env:LOCALAPPDATA = Join-Path $projectRoot '.godot-home\Local'
    $env:EXTRACTION_TEST_DISPLAY = '1'
    $env:EXTRACTION_TEST_PROGRESS = '1'
    $env:EXTRACTION_TEST_AUDIO = '1'
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
        if ($Name -in @('forest_dusk', 'gameplay', 'combat', 'combat_realtime', 'balance', 'balance_realtime', 'tactics', 'tactics_realtime', 'circling', 'circling_realtime', 'developer', 'loot', 'loot_slots', 'ground_loot', 'quick_discard', 'loot_tooltip', 'loot_glass', 'progress', 'stash_migration', 'raid_cycle', 'progress_writer', 'progress_reader', 'raid_visual', 'feedback', 'combat_audio', 'raid_audio', 'ambience', 'lamp', 'health_bar', 'ammo_feedback', 'active_reload', 'healing', 'healing_visual', 'footsteps', 'footstep_audio', 'interaction', 'interaction_audio', 'hud_menu', 'audio_settings', 'display', 'display_native') -and $log -notmatch 'RESULT: \d+ checks, 0 failures') {
            Write-Output $log
            throw "$Name checks did not reach completion. See $logPath"
        }
        if ($Name -eq 'forest_audio' -and $log -notmatch 'RESULT: \d+ checks, 0 failures') {
            throw "Forest audio checks did not reach completion. See $logPath"
        }
        if ($Name -in @('character_lab', 'actor_integration', 'watchman', 'watchman_visual', 'character_leg_shape_visual', 'obstacles', 'obstacles_realtime') -and $log -notmatch 'RESULT: \d+ checks, 0 failures') {
            throw "Character lab checks did not reach completion. See $logPath"
        }
        if ($Name -in @('visual', 'forest_dusk_visual', 'footstep_visual', 'character_lab_visual', 'character_directions_visual', 'character_gait_visual', 'character_leg_shape_visual') -and $log -notmatch 'Visual captures saved:') {
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
    Invoke-GodotCheck 'character_lab' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/character_lab/lab_test.gd')
    Invoke-GodotCheck 'watchman' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/watchman_visual_test.gd')
    Invoke-GodotCheck 'actor_integration' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/actor_integration_test.gd')
    Invoke-GodotCheck 'gameplay' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/gameplay_test.gd')
    Invoke-GodotCheck 'combat' @('--headless', '--fixed-fps', '60', '--quit-after', '3600', '--script', 'res://tests/combat_test.gd')
    Invoke-GodotCheck 'balance' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/balance_test.gd')
    Invoke-GodotCheck 'tactics' @('--headless', '--fixed-fps', '60', '--quit-after', '2400', '--script', 'res://tests/tactics_test.gd')
    Invoke-GodotCheck 'circling' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/circling_test.gd')
    Invoke-GodotCheck 'developer' @('--headless', '--fixed-fps', '60', '--quit-after', '1200', '--script', 'res://tests/developer_test.gd')
    Invoke-GodotCheck 'forest_dusk' @('--headless', '--fixed-fps', '60', '--quit-after', '2400', '--script', 'res://tests/forest_dusk_test.gd')
    Invoke-GodotCheck 'obstacles' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/obstacle_rules_test.gd')
    Invoke-GodotCheck 'loot' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/loot_test.gd')
    Invoke-GodotCheck 'loot_slots' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/loot_slots_test.gd')
    Invoke-GodotCheck 'ground_loot' @('--headless', '--fixed-fps', '60', '--quit-after', '2400', '--script', 'res://tests/ground_loot_test.gd')
    Invoke-GodotCheck 'quick_discard' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/quick_discard_test.gd')
    Invoke-GodotCheck 'progress' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/progress_test.gd')
    Invoke-GodotCheck 'stash_migration' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/stash_migration_test.gd')
    Invoke-GodotCheck 'raid_cycle' @('--headless', '--fixed-fps', '60', '--quit-after', '3000', '--script', 'res://tests/raid_cycle_test.gd')
    Invoke-GodotCheck 'progress_writer' @('--headless', '--fixed-fps', '60', '--quit-after', '300', '--script', 'res://tests/progress_restart_test.gd', '--', '--write-profile')
    Invoke-GodotCheck 'progress_reader' @('--headless', '--fixed-fps', '60', '--quit-after', '300', '--script', 'res://tests/progress_restart_test.gd')
    Invoke-GodotCheck 'feedback' @('--headless', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/feedback_test.gd')
    Invoke-GodotCheck 'combat_audio' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/combat_audio_test.gd')
    Invoke-GodotCheck 'raid_audio' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/raid_audio_test.gd')
    Invoke-GodotCheck 'ambience' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/ambience_test.gd')
    Invoke-GodotCheck 'lamp' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1200', '--script', 'res://tests/lamp_test.gd')
    Invoke-GodotCheck 'health_bar' @('--headless', '--fixed-fps', '60', '--quit-after', '600', '--script', 'res://tests/health_bar_test.gd')
    Invoke-GodotCheck 'ammo_feedback' @('--headless', '--fixed-fps', '60', '--quit-after', '600', '--script', 'res://tests/ammo_feedback_test.gd')
    Invoke-GodotCheck 'active_reload' @('--headless', '--fixed-fps', '60', '--quit-after', '2400', '--script', 'res://tests/active_reload_test.gd')
    Invoke-GodotCheck 'healing' @('--headless', '--fixed-fps', '60', '--quit-after', '4200', '--script', 'res://tests/healing_test.gd')
    Invoke-GodotCheck 'footsteps' @('--headless', '--fixed-fps', '60', '--quit-after', '2400', '--script', 'res://tests/footstep_test.gd')
    Invoke-GodotCheck 'footstep_audio' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/footstep_audio_test.gd')
    Invoke-GodotCheck 'forest_audio' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/forest_audio_test.gd')
    Invoke-GodotCheck 'interaction' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '3600', '--script', 'res://tests/interaction_test.gd')
    Invoke-GodotCheck 'interaction_audio' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/interaction_audio_test.gd')
    Invoke-GodotCheck 'hud_menu' @('--headless', '--fixed-fps', '60', '--quit-after', '1800', '--script', 'res://tests/hud_menu_test.gd')
    Invoke-GodotCheck 'audio_settings' @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/audio_settings_test.gd')
    Invoke-GodotCheck 'display' @('--headless', '--fixed-fps', '60', '--quit-after', '900', '--script', 'res://tests/display_test.gd')
    if ($Realtime) {
        Invoke-GodotCheck 'obstacles_realtime' @('--headless', '--max-fps', '60', '--script', 'res://tests/obstacle_rules_test.gd', '--', '--async-navigation')
        Invoke-GodotCheck 'combat_realtime' @('--headless', '--max-fps', '60', '--quit-after', '3600', '--script', 'res://tests/combat_test.gd', '--', '--async-navigation')
        Invoke-GodotCheck 'balance_realtime' @('--headless', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/balance_test.gd', '--', '--async-navigation')
        Invoke-GodotCheck 'tactics_realtime' @('--headless', '--max-fps', '60', '--quit-after', '2400', '--script', 'res://tests/tactics_test.gd', '--', '--async-navigation')
        Invoke-GodotCheck 'circling_realtime' @('--headless', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/circling_test.gd', '--', '--async-navigation')
    }
    if ($Visual) {
        Invoke-GodotCheck 'character_leg_shape_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/character_lab/leg_shape_visual.gd')
        Invoke-GodotCheck 'watchman_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/watchman_visual.gd')
        Invoke-GodotCheck 'character_lab_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/character_lab/lab_visual.gd')
        Invoke-GodotCheck 'character_directions_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/character_lab/direction_visual.gd')
        Invoke-GodotCheck 'character_gait_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/character_lab/gait_visual.gd')
        Invoke-GodotCheck 'loot_glass' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/loot_glass_test.gd')
        # This long capture owns its exit; render-frame counts can outpace its
        # physics waits. Keep all cases and the wall-clock timeout above.
        Invoke-GodotCheck 'forest_dusk_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--fixed-fps', '60', '--script', 'res://tests/forest_dusk_visual.gd')
        Invoke-GodotCheck 'visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/visual_check.gd')
        Invoke-GodotCheck 'loot_tooltip' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/loot_tooltip_test.gd')
        Invoke-GodotCheck 'raid_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1800', '--script', 'res://tests/raid_visual.gd')
        Invoke-GodotCheck 'healing_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/healing_visual.gd')
        Invoke-GodotCheck 'footstep_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/footstep_visual.gd')
        Invoke-GodotCheck 'display_visual' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '900', '--script', 'res://tests/display_visual.gd')
        Invoke-GodotCheck 'display_native' @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--max-fps', '60', '--quit-after', '1200', '--script', 'res://tests/display_native_test.gd')
    }
    Write-Output 'All requested checks passed.'
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:EXTRACTION_TEST_DISPLAY = $previousDisplayTest
    $env:EXTRACTION_TEST_PROGRESS = $previousProgressTest
    $env:EXTRACTION_TEST_AUDIO = $previousAudioTest
}
