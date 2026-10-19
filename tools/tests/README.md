# Isolated control and navigation regression tests

These scripts run in a small Godot project containing a snapshot of Harness source and explicit fixture resource roots. Run them with a compatible Godot 4 executable. Local validation used `tools/pax-patch/gdre/gdre_tools.exe` (Godot 4.8 development build).

The resource locations matter: ownership checks read the actual script resource paths. In particular, keep the two QA fixture roots separate and place the native sound fixture at exactly `res://src/ui/Sound.gd`.

From the Harness repository root, prepare a fresh project in PowerShell:

```powershell
$HarnessRoot = (Get-Location).Path
$TestProject = Join-Path $env:TEMP ('pax-harness-tests-' + [guid]::NewGuid().ToString('N'))
$HarnessTarget = Join-Path $TestProject 'mods/pax_harness'
New-Item -ItemType Directory -Path $HarnessTarget,(Join-Path $HarnessTarget 'data') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $HarnessRoot 'src') -Destination $HarnessTarget -Recurse
Copy-Item -LiteralPath (Join-Path $HarnessRoot 'data/lang') -Destination (Join-Path $HarnessTarget 'data') -Recurse

$FixtureCopies = @(
    @('mod_window_logic.gd', 'mods/qa_window_logic/main.gd'),
    @('mod_window_theme.gd', 'mods/qa_window_theme/main.gd'),
    @('game_sound.gd', 'src/ui/Sound.gd')
)
foreach ($FixtureCopy in $FixtureCopies) {
    $Target = Join-Path $TestProject $FixtureCopy[1]
    New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $HarnessRoot ('tools/tests/fixtures/' + $FixtureCopy[0])) -Destination $Target
}

$Suites = @(
    'mod_window_tests',
    'native_failure_tests',
    'ui_navigation_target_tests',
    'stable_ref_tests',
    'stable_ref_runtime_tests',
    'static_owner_tests',
    'vision_retention_tests',
    'button_caption_tests',
    'overlay_caption_tests'
)
foreach ($Suite in $Suites) {
    Copy-Item -LiteralPath (Join-Path $HarnessRoot ('tools/tests/' + $Suite + '.gd')) -Destination $TestProject
}
@'
config_version=5
[application]
config/name="Harness isolated regression tests"
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $TestProject 'project.godot') -Encoding utf8
```

Set `$Godot` to the executable path, then run each script with separate output files:

```powershell
$Godot = 'C:/path/to/godot.exe'
foreach ($Suite in $Suites) {
    $Stdout = Join-Path $TestProject ($Suite + '.stdout.log')
    $Stderr = Join-Path $TestProject ($Suite + '.stderr.log')
    $Process = Start-Process -FilePath $Godot -ArgumentList @(
        '--headless', '--path', ('"' + $TestProject + '"'), '--script', ($Suite + '.gd')
    ) -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
    if (-not $Process.WaitForExit(45000)) {
        $Process.Kill()
        throw "Timed out: $Suite"
    }
    Get-Content -LiteralPath $Stdout
    if ($Process.ExitCode -ne 0 -or (Get-Item -LiteralPath $Stderr).Length -ne 0) {
        Get-Content -LiteralPath $Stderr
        throw "Failed: $Suite"
    }
}
```

Expected assertion counts are 24, 14, 32, 30, 9, 15, 26, 17 and 22 respectively. `stable_ref_runtime_tests` uses the real Runtime, Registry and ModAccess with fake provider callbacks. It checks warnings at three/five/eight unchanged reads and termination after eight reads, while ten changing native values remain observable and complete normally.

`vision_retention_tests` uses the real Runtime with fake provider/registry callbacks and a `scope.game_image_current(handle) -> bool` live-frame checker. It covers retention over read-only steps, delivered-frame validation, replacement captures, stale/absent checker behavior, invalidation during held compaction, image fallback, player references, image-token reservation before compaction, the context overflow guard, and descriptor-only saved state. It needs no additional fixtures or actual image files.

`button_caption_tests` covers Buttons with empty `text` and captions rendered by nested Labels/RichTextLabels. It checks searchable per-button context, parsed rich text, hidden/private/editable exclusions, stable refs across private changes, stale refs after visible caption changes, and preserved rejection of a foreign gameplay press callback. It uses the existing QA window fixture.

`overlay_caption_tests` reproduces sibling captions: a PanelContainer has exactly one direct Button and an IGNORE MarginContainer containing the rendered Labels. It checks separate rows, hidden/private/editable exclusions, two-button ambiguity, STOP/PASS sibling rejection, the PanelContainer requirement, bounded captions, current/stale refs and unchanged foreign press restrictions. It uses the same QA fixture. For an overlay-only change, the relevant execution gate is this suite plus button_caption, mod_window, stable_ref, static_owner and stable_ref_runtime.

For a parser-only check, use the same project and add `--check-only` to a `--script` invocation. The fixture suites use no network or real game profile. They validate the listed generic control behaviors; live mod compatibility requires separate acceptance testing.
