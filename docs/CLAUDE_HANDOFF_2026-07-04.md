# Claude Code Handoff - 2026-07-04

Canonical dev checkout:

```text
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project
```

Release copy is staging only. Do not continue feature/runtime commits there:

```text
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project - Release v1.0
```

## Operating Rules

- Work only in the canonical dev checkout unless the user explicitly says otherwise.
- Preserve the dirty worktree. Do not reset, delete, or revert unrelated user changes.
- Do not use `git add .`.
- Keep commit boundaries narrow:
  - runtime Lua fixes;
  - namespace/refactor;
  - audio bridge C#/C changes;
  - weapon audio tuning/catalog docs;
  - release packaging/tools;
  - docs status sync.
- Before each commit, report staged files and verify the staged set contains only the intended paths.
- Do not commit generated release artifacts, deployment backups, game-folder copies, or unreviewed tools unless explicitly requested.
- Treat implemented/compiled separately from hardware-confirmed.
- The recurring git warning about `$env:USERPROFILE/.config/git/ignore` permission is known and has not blocked commits.

## What Was Just Completed

The recent work split the DualSenseEnhanced runtime cleanup into small commits.
Current latest commits:

```text
df4a01f docs: update DualSenseEnhanced naming and workflow notes
83eb6ff refactor(ui): update remaining feedback wording
f12ca7f feat(audio): expand pickup item ID catalog
cf6b902 feat(diagnostics): add Wwise event pre-roll buffer
a01ac12 feat(audio): add radio ring playback handler
fe20366 feat(runtime): add master feedback enable switch
1a5a058 refactor(runtime): remove obsolete HP resume fade path
5cc5973 fix(native): apply lightbar brightness through feedback bus
490d94b fix(runtime): expose weapon mapping load diagnostics
2c09ba3 refactor(runtime): rename feedback writer alias to FEEDBACK
24ed561 fix(native): preserve lightbar blackout ownership across script reload
d83de50 fix(runtime): sync ammo and mic LED pulse state
9a78b82 refactor(runtime): track remaining DualSenseEnhanced modules
```

Runtime Lua status after the last runtime/UI commits was clean under:

```text
src/reframework/autorun/DualSenseEnhanced
```

The following runtime changes are committed and should be treated as baseline:

- `feedback_writer.lua` alias `DSX` -> `FEEDBACK`.
- mapping diagnostics in `feedback_writer.lua`.
- lightbar brightness multiplier in feedback bus.
- obsolete HP resume fade path removed/neutralized.
- master feedback enable switch added.
- ammo/HP smooth pulse state and Mic LED sync state.
- lightbar blackout ownership/reload behavior.
- missing and remaining `DualSenseEnhanced` runtime modules tracked.
- radio ring playback handler.
- Wwise diagnostic pre-roll buffer.
- pickup item ID catalog expansion.
- remaining UI/debug feedback wording cleanup.

## Current Dirty Worktree Buckets

Last checked `git status --short` still showed these broad dirty groups.
Re-check live status before acting.

### Release/packaging/tooling

```text
 M .gitignore
?? THIRD_PARTY_LICENSES.txt
?? setup_sounds.bat
?? tools/
?? deployment_backups/
?? src/reframework/data/
```

Likely release package / extractor / licensing / generated data work.
Do not mix with runtime or C# bridge commits.

### Docs/status sync still dirty

```text
 M docs/AGENTS.md
 M docs/AUDIO_HOOK_MAPPING_TASK.md
 M docs/CODEX_PROMPTS.md
 M docs/DUALIB_HID_BRANCH.md
 M docs/IDEAS.md
 M docs/RADIO_DIALOGUE_TASK.md
 M docs/TASKS_FOR_CODEX.md
 M docs/game_events.md
?? docs/NATIVE_HAPTICS_AUDIO_TASK.md
?? docs/WEAPON_AUDIO_STATUS.md
```

Important: these are not all simple namespace changes. Some mix:

- deployment hygiene;
- commit workflow rules;
- hardware-confirmed status notes;
- cutscene suppression moved to ideas;
- native haptics/audio handoff;
- endpoint/lightbar/gyro status;
- mojibake/BOM cleanup.

Do not whole-file commit these without review. The previous clean docs commit
only included narrow naming/path hunks from:

```text
docs/AUDIO_CODEX_PROMPTS.md
docs/AUDIO_HOOK_MAPPING_TASK.md
docs/CODEX_PROMPTS.md
speaker/BUILD.md
speaker/DualsenseAudioBridge/experimental-dsx-client/README.md
speaker/DualSenseEnhancedTransport/README.md
```

### Weapon audio catalog/docs

```text
 M docs/weapon_audio_catalog/wp4000_sg09r.md
 M docs/weapon_audio_catalog/wp4001_punisher.md
 M docs/weapon_audio_catalog/wp4002_red9.md
 M docs/weapon_audio_catalog/wp4003_blacktail.md
 M docs/weapon_audio_catalog/wp4004_matilda.md
 M speaker/weapon_sound_catalog/MANIFEST.csv
 M speaker/weapon_sound_catalog/README.md
 M speaker/weapon_sound_catalog_v2/MANIFEST.csv
 M speaker/weapon_sound_catalog_v2/README.md
 M speaker/extracted_ui_wavs/PRELIMINARY_CATALOG.md
```

Likely weapon audio catalog/status work. Keep separate from runtime and bridge commits.

### Audio bridge / endpoint / launcher / C# and C

```text
 M speaker/DualsenseAudioBridge/BridgeConfig.cs
 M speaker/DualsenseAudioBridge/DualsenseAudioBridge.csproj
 M speaker/DualsenseAudioBridge/SoundMap.cs
 M speaker/DualsenseAudioBridge/experimental-dsx-client/DSX_UDPClient_Test.c
 M speaker/DualsenseAudioBridge/experimental-dsx-client/README.md
 M speaker/DualsenseAudioBridge/launcher/DualsenseAudioBridgeLauncher.c
?? speaker/DualsenseAudioBridge/launcher-nativeaot/
```

Keep this as a separate bridge/launcher commit family.

### Native trigger/gyro transport

```text
 M speaker/DualSenseEnhancedTransport/CommandFile.cs
 M speaker/DualSenseEnhancedTransport/DuaLibBackend.cs
 M speaker/DualSenseEnhancedTransport/GyroMotionSample.cs
 M speaker/DualSenseEnhancedTransport/GyroMouseMapper.cs
 M speaker/DualSenseEnhancedTransport/Program.cs
 M speaker/DualSenseEnhancedTransport/README.md
```

Keep separate from docs and Lua runtime. Watch for behavior vs docs/status splits.

### Audio Lua rename outside runtime tree

```text
 D speaker/audio_dsx.lua
?? speaker/audio_feedback.lua
 M speaker/audio_bridge.py
 M speaker/launch_bridge.bat
```

Likely speaker-side audio namespace rename / bridge path work. Review as its own commit.

## Known Exclusions From Previous Work

Do not stage these accidentally with docs/runtime cleanup:

```text
docs/weapon_audio_catalog/*
docs/WEAPON_AUDIO_STATUS.md
docs/NATIVE_HAPTICS_AUDIO_TASK.md
speaker/weapon_sound_catalog*
speaker/extracted_ui_wavs/*
C#/C source files
tools/
src/reframework/data/
.gitignore
THIRD_PARTY_LICENSES.txt
setup_sounds.bat
deployment_backups/
```

## Recommended Next Steps

1. Re-run:

```powershell
git status --short
git diff --stat
```

2. Pick one clean bucket only.

Suggested next buckets:

- docs status sync, but only after reviewing `docs/AGENTS.md`, `docs/TASKS_FOR_CODEX.md`, `docs/IDEAS.md`, `docs/game_events.md`, `docs/DUALIB_HID_BRANCH.md`;
- audio bridge endpoint/launcher C# changes;
- native trigger/gyro transport changes;
- release packaging/extractor tools;
- weapon audio catalog docs.

3. If committing docs, avoid committing mojibake/BOM noise blindly. Several docs contain broken characters such as `вЂ”`, `в†’`, or BOM at first line. Either normalize as a dedicated cleanup or avoid those hunks.

4. If touching deployed runtime or package output, use `tools/verify_deploy.ps1` only when the user asks to deploy/verify against the game folder. Do not deploy silently.

## Ready-To-Paste Prompt For Claude Code

```text
You are working in the canonical dev checkout:
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project

Do not work in:
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project - Release v1.0

First read:
- docs/CLAUDE_HANDOFF_2026-07-04.md
- docs/AGENTS.md
- docs/TASKS_FOR_CODEX.md

Then run:
git status --short
git log --oneline -n 25
git diff --stat

Preserve the dirty worktree. Do not reset or revert user changes. Do not use git add .

Recent runtime cleanup has already been committed through:
df4a01f docs: update DualSenseEnhanced naming and workflow notes

Runtime Lua under src/reframework/autorun/DualSenseEnhanced was clean after the latest runtime/UI commits. Remaining dirty work is docs/status, bridge/transport C#/C, release packaging/tools, weapon audio catalogs, and speaker-side audio namespace work.

Pick one bucket at a time. Before any commit, report staged files and verify the staged set contains only the intended paths.
```

