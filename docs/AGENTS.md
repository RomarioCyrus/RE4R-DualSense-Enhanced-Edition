# AGENTS.md — RE4R DualSense Mod

> **How to use this file**: at the start of any new agent session working
> on this project, read this file plus `MEMORY.md` (confirmed working
> state) and `BUGS.md`/`TASKS_FOR_CODEX.md` (open work) before touching
> code. If you're the user starting a new agent, just say "read
> docs/AGENTS.md and docs/MEMORY.md first" — don't re-explain the
> workflow or conventions below, they're already written down here.
> Specific findings (Wwise IDs, confirmed mappings, per-weapon state) live
> in `MEMORY.md`/`CHANGELOG.md`, not here — this file is about *how* to
> work, not *what* has been found so far.

## Project

Resident Evil 4 Remake DualSense enhancement mod using:
- REFramework (Lua scripting)
- Native `DualSenseEnhancedTransport.exe` + duaLib/hidapi for adaptive
  triggers, gyro, player indicators, lightbar, Mic LED, and haptics mode
- `DualsenseAudioBridge.exe` (NAudio/WASAPI) for controller-speaker audio and
  four-channel Enhanced Haptics playback
- Optional legacy DSX-compatible payload source kept for development history;
  DSX/`DSX_UDPClient.exe` is not part of the supported or packaged v1.0 path
- DualSense lightbar, adaptive triggers, gyro, player indicator (5 LEDs), Mic
  LED, controller speaker, and opt-in Enhanced Haptics

Primary goal: provide native-feeling DualSense feedback on PC without Steam
Input, DSX, or a companion controller application.

## Machine paths

| Resource | Path |
|---|---|
| **RE4R game root** | `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4` |
| **REFramework autorun** | `<RE4R root>\reframework\autorun\DualSenseEnhanced\` |
| **REFramework data / sounds** | `<RE4R root>\reframework\data\DualSenseEnhanced\sounds\` |
| **Audio bridge exe** | `<RE4R root>\reframework\data\DualSenseEnhanced\DualsenseAudioBridge.exe` |
| **Native transport exe** | `<RE4R root>\reframework\data\DualSenseEnhanced\DualSenseEnhancedTransport.exe` |
| **Project repo** | `$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project\` |
| **FusionTools (extracted banks)** | `<FusionTools-RE4R-root>\` |
| **REtool + pak list** | `<REtool-root>\` · pak list: `<REtool-root>\RE4_Release_Pak.list` |

Note: game folder path contains a double space before `BIOHAZARD` — always quote it in shell commands.

## File Structure

### Deployed to game folder

```
<RE4R root>/
└── reframework/
    ├── autorun/
    │   ├── DualSenseEnhanced.lua              ← main loader + unified REFramework UI
    │   └── DualSenseEnhanced/
    │       ├── weapon_equip_core.lua   ← weapon/ammo polling
    │       ├── feedback_writer.lua     ← LED bus + output selection
    │       ├── dualib_trigger_ipc.lua  ← native command-file transport
    │       ├── native_feedback.lua     ← RE4R lightbar ownership
    │       ├── native_gyro.lua         ← gyro settings/config writer
    │       ├── audio_feedback.lua      ← speaker/haptics event emission
    │       ├── wwise_audio_router.lua  ← confirmed Wwise event routing
    │       ├── item_ids.lua            ← item classification
    │       ├── player_movement.lua     ← sprint state for footstep haptics
    │       ├── hp_led.lua              ← HP gradient, danger blink, heal lerp
    │       ├── ammo_led.lua            ← empty mag blink, ammo indicator
    │       ├── mic_led.lua             ← unified Mic LED state
    │       ├── events_led.lua          ← gameplay/event lifecycle
    │       └── settings.lua            ← persistence/autosave
    └── data/
        ├── RE4R_WeaponData.lua         ← weapon ID/type lookup table
        └── DualSenseEnhanced/
            ├── weapon_trigger_profiles.lua
            ├── DualsenseAudioBridge.exe
            ├── DualSenseEnhancedTransport.exe
            ├── duaLib.dll / hidapi.dll
            └── sounds/
```

### Project repo (this folder)

```
Dualsense DSX RE4R Project/
├── docs/               ← agent rules, status, research, changelog
├── src/reframework/    ← canonical Lua/runtime/data source
├── speaker/            ← C# bridge, native transport, duaLib source/builds
├── tools/              ← deploy verification, release sync, sound extractor
├── release/v1.0/       ← curated package policy and public release copy
├── README.txt          ← in-package user README
├── setup_sounds.bat    ← user-facing local audio extraction entrypoint
└── THIRD_PARTY_LICENSES.txt
```

## Module Responsibilities

| File | Responsibility | Touch? |
|---|---|---|
| `DualSenseEnhanced.lua` | Loader + unified imgui UI | Yes |
| `feedback_writer.lua` | LED bus, payload writing, per-frame tick, Mic LED instruction (HP return fade removed 2025-06-29) | Yes |
| `settings.lua` | Save/load all persisted UI state to `RE4R_DualSense_settings.lua`; autosave tick | Yes |
| `native_feedback.lua` | Native-game lightbar ownership backend (post-update hook enforcement, Capcom hook blocking) | Yes |
| `dualib_trigger_ipc.lua` | Native weapon mapping → duaLib command-file bridge; owns triggers, indicators, lightbar, Mic LED, and haptics mode via IPC | Yes |
| `trigger_intensity.lua` | Adaptive trigger preset/global/per-class intensity scaling applied to `dualib_trigger_ipc.lua` effects; never touches `weapon_trigger_profiles.lua` | Yes |
| `native_gyro.lua` | Native gyro-to-mouse settings, presets, invert/activation mode -> `DualSenseEnhanced/native_gyro.json` | Yes |
| `hp_led.lua` | HP gradient, danger blink, heal lerp, death/gameplay gate | Yes |
| `ammo_led.lua` | Empty mag blink, ammo indicator LEDs, Mic LED ammo effects | Yes |
| `events_led.lua` | Event hooks, gameplay/death/Continue recovery | Yes |
| `audio_feedback.lua` | Speaker/haptics event emission, per-item healing/pickup mapping, weapon audio profiles | Yes |
| `wwise_audio_router.lua` | Always-on confirmed Wwise event ID -> audio event routing | Yes |
| `item_ids.lua` | Item ID normalization/classification for pickup and healing routing | Yes |
| `player_movement.lua` | Confirmed sprint-state polling for footstep haptics gating | Yes |
| `sound_event_diag.lua` | Opt-in Wwise event logger and confirmed event-ID route experiments | Diagnostics |
| `mic_led.lua` | Mic LED state through unified payload writer | Yes |
| `debug_led.lua` | Diagnostics, remove in release | Optional |
| `weapon_equip_core.lua` | Weapon/ammo data polling and inventory-controller fallback | Modify carefully |
| `weapon_equip_ui.lua` | Trigger enable/reload UI | Yes (own rewrite, no longer third-party code) |
| `weapon_trigger_profiles.lua` | Trigger profiles per weapon type | Yes (own rewrite, 2025-06-29; tune via the `profile()`/`l2_*`/`r2_*` helpers) |

## v1.0 UI Direction

- The REFramework UI is native-first for v1.0. Do not expose legacy DSX
  compatibility controls in the normal user-facing panel unless that path is
  explicitly retested for release.
- Keep the first screen simple and ordered: `Status`, `Global Preset`,
  `Quick Controls`, `Lightbar`, `Adaptive Triggers`, `Controller Speaker
  Audio`, `Enhanced Haptics`, `Gyro Aim`, then `Advanced` last.
- `Quick Controls` intentionally mirrors the master switches in the detailed
  sections. It must say so explicitly and include Enhanced Haptics; do not add
  a second independent state variable for any quick toggle.
- `Global Preset` currently has `Immersive (Default)` and `Custom`.
  `Minimal` is intentionally not shown until its behavior is designed.
- `Lightbar` has two user-facing modes: `Enhanced Mod Lightbar` and
  `Native Game Lightbar`. The latter must release RGB lightbar ownership back
  to the game instead of silently continuing to write custom colors.
- Put detailed color/timing, trigger class, audio event, gyro sensitivity, and
  diagnostics controls under collapsed advanced/debug sections.
- User-facing strength controls should use percentages or named levels rather
  than raw `0.0-2.0` floats. Mode buttons must visibly mark the selected mode.
- Keep release copy concise: no internal channel numbers, source-doc paths, or
  hard-coded status claims presented as live detection.
- Do not load separate legacy UI panels such as `weapon_equip_ui.lua` or
  `debug_led.lua` from the main loader for v1.0; their old payload/UDP/debug
  wording is not part of the release UI.
- Enhanced Haptics (channels 3/4, `docs/HAPTICS_FOOTSTEPS_TASK.md`) **ships in
  v1.0** as of the 2026-07-11 release decision (supersedes the earlier
  2026-07-07 "stopped/blocked, dev-only" note kept in that doc for history).
  Covers footsteps (sprint-gated, real-audio) plus parry/knife/dry-fire/aim/
  draw/heal/pickup companion pulses, a live continuous global intensity slider
  (`HapticPlayer.cs`'s low-pass filter, not preset WAVs), plus per-category
  strength multipliers and toggles — all under the consolidated "Enhanced Haptics" UI section, opt-in/
  default-off, reachable outside `RELEASE_BUILD` gating. DOES sync to the
  `Release v1.0` checkout (`player_movement.lua` and `audio_feedback.lua`'s
  companion routing are release-tracked modules; `movement_diag.lua` is the
  one dev-only debug tool in this feature and stays `RELEASE_BUILD`-gated).

## Do Not Break

- DSX payload writing (`feedback_writer.lua` write path).
- LED source bus priority system.
- `tick_led_sources()` per-frame timer (must stay in `re.on_application_entry`).
- HP colour during gameplay.
- Low HP blinking.
- Death → lightbar black, ammo indicator off, Mic LED off, adaptive triggers zeroed (L2/R2 no resistance).
- Main menu → no HP LED on first launch.
- Grab QTE lifecycle (`LargeActionSign_Grab3GuiBehavior` hooks).
- Parry detection (`onHitParry` hook).
- Damage detection (`onHitDamageCheck` hook).
- `onStartInGame` reset + immediate HP/ammo output enable.
- Ammo indicator 5 LEDs (via duaLib `scePadSetPlayerIndicators` in native mode; via DSX `type=3` in custom mode).
- Mic LED empty-ammo pulse and reload-finish effects — synced to the lightbar pulse phase via `AMMO.empty_pulse_active`/`empty_pulse_on` and `LED.danger_pulse_on`; the Mic LED must never use duaLib's firmware Breathing mode for these because it runs on its own timing and cannot stay in lockstep.
- `ever_started_in_game` guard in `events_led.lua`: `adaptive_gameplay_signal()` must only fire after `onStartInGame` has triggered at least once in the current load; it must reset to `false` on every gameplay→menu transition so the guard re-arms for subsequent loads in the same session.
- Repeated death/Continue recovery.
- Separation between the audio bridge and external DSX UDP client.
- Native launcher plugin and single-instance bridge mutex.
- Automatic bridge shutdown with `re4.exe`.
- Native duaLib delayed-start boundary: never open the controller before the
  Lua `trigger_transport.ready` marker written after `onStartInGame`.
- Native gyro must share that same delayed duaLib watcher. Do not launch a
  second HID owner for IMU input or write DualSense output reports from the
  gyro path.

## Deploy Hygiene (multi-agent / multi-turn safety)

This project is edited by more than one AI agent across sessions (Codex,
Claude, others), and within a single session a file is often edited across
several turns before being deployed. The single most expensive recurring
bug class here is **silent deploy drift**: a source file in `src/...` gets
edited, the in-game copy under `<RE4R root>/reframework/...` does not, and
nothing errors -- the old code just keeps running and every later fix looks
like it "didn't work" until someone notices the file timestamps/hashes
don't match. This cost a full multi-turn debugging detour on 2025-06-29
(mic LED via duaLib: `dualib_trigger_ipc.lua` was edited to add the mic
field, but only the UI checkbox file and a different module got redeployed
afterward; three separate "still doesn't work" reports happened before a
full hash sweep caught it).

- Run `tools/verify_deploy.ps1` (hashes every deployed Lua file under
  `src/reframework/autorun` and `src/reframework/data` against its deployed
  copy and reports `MISSING`/`MISMATCH`)
  before declaring any Lua feature ready to test, and again if a feature
  "still doesn't work" after a fix you were confident in -- don't re-guess
  at the logic before ruling out drift.
- Treat this as the default verification step for *any* deployed artifact,
  not just Lua: also applies to the C# trigger transport `.exe`, the
  `duaLib.dll` fork, and `DualsenseAudioBridge.exe`/`SoundMap.cs` (see the
  existing per-step sha256 requirement in the Wwise deployment workflow
  below -- that workflow's discipline should be the norm, not a special
  case for audio).
- For `duaLib.dll`, verify the release-output copy itself is the intended
  native build before trusting `tools/verify_deploy.ps1`. A post-refactor
  2026-07-02 regression had the game folder and release-output matching the
  older 2026-06-26 trigger-only DLL, so `verify_deploy.ps1` was green while
  physical lightbar output was still suppressed. The confirmed lightbar build
  is copied from `speaker/DualSenseEnhancedTransport/third_party/build_out/duaLib.dll`
  before deploy.
- After editing a file across multiple turns, re-diff/hash *every* touched
  file before wrapping up, not just the one most recently edited -- editing
  file A then B then A again means a deploy done after editing B alone can
  silently miss A's latest change.
- Runtime/UI state (checkboxes backed by Lua globals such as
  `IPC.indicators_enabled`) resets to its in-code default on every
  `Reset Scripts` and on every game restart unless it is both (a) wired
  into `settings.lua`'s save/load *and* (b) the user has actually pressed
  the **Save** button in the Config UI section. `SETTINGS.load()` runs
  automatically on script load; `SETTINGS.save()` does not run
  automatically anywhere. When a toggle "won't stay on," check both halves
  before assuming the toggle's own logic is broken.
- Any Lua module that registers a persistent REFramework callback/hook/tick
  **must be safe across `Reset Scripts`**. `re.on_application_entry(...)`
  callbacks and `sdk.hook(...)` handlers can outlive the Lua module instance
  that registered them, so a script reload can leave old generations writing
  alongside the new one. Mandatory pattern for every per-frame writer or
  transport-facing module: increment a module-specific generation counter on
  load (for example `_G.DualSenseEnhancedTriggerIpcGeneration`), make every
  callback return immediately when it is not the current generation, and emit
  an explicit safe reset/off command on module load when the module controls
  hardware state. This is non-optional for controller output paths such as
  `dualib_trigger_ipc.lua`, `native_feedback.lua`, audio/event emitters, ammo
  indicators, Mic LED, and any future haptics/gyro transport. Confirmed bug
  class (2026-07-04): after `Reset Scripts`, stale `dualib_trigger_ipc.lua`
  callbacks can compete with the new generation and revive L2/gyro drift or
  stuck haptics because gyro and adaptive triggers share the same delayed
  duaLib transport.
- Don't assume background-process state from memory -- verify with
  `tasklist`/`Get-Process` and a fresh log tail before reasoning about why
  something didn't apply. The external trigger watcher
  (`DualSenseEnhancedTransport.exe`) is spawned by
  `DualsenseAudioBridge.exe` only when `trigger_transport.ready` flips to
  `"ready"`, and is single-instance via a named mutex -- a stale/leftover
  process silently blocks a new one from applying your latest deploy.
- When multiple agents (or multiple sessions of the same agent) touch this
  project concurrently, `MEMORY.md`/`AGENTS.md`/`CHANGELOG.md` can change
  underneath you mid-session. Re-read the relevant section before editing
  it rather than assuming your last-read copy is still current -- line
  numbers and surrounding content do shift.

## Text Encoding Hygiene (BOM / Mojibake)

Confirmed bug class (2026-07-04): a large batch of tracked text files (Lua,
C#, C, Markdown, `.gitignore`) picked up a stray UTF-8 BOM (`EF BB BF`) and/or
mojibake on em-dashes, arrows, and box-drawing characters (`—` → `вЂ”`,
`→` → `в†’`, `│`/`├`/`─`/`└` → `в”‚`/`в”њ`/`в”Ђ`/`в””`) with no intended content
change. Byte-level inspection showed the exact signature of UTF-8 text being
misread as Windows-1251 (the Cyrillic code page) and re-saved as UTF-8 --
e.g. the UTF-8 bytes for `—` (`E2 80 94`) reinterpreted one-byte-at-a-time
as CP1251 characters (`в`, `Ђ`, `”`) and then written back out as UTF-8 for
those three characters. This is consistent with a tool running under Windows
PowerShell 5.1 on a Russian-locale (CP1251 "ANSI") machine touching these
files without an explicit UTF-8 encoding: PowerShell 5.1's `-Encoding utf8`
on `Set-Content`/`Out-File` always adds a BOM (unlike PowerShell 7's
`utf8NoBOM`), and any read/write path that isn't UTF-8-explicit on this
machine round-trips through the system code page instead.

- When bulk-editing text files from PowerShell (renames, find/replace across
  many files, etc.), read and write with explicit UTF-8, no BOM:
  `[System.IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)` to read, and
  `[System.IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))`
  to write. Do not rely on `Get-Content`/`Set-Content`/`Out-File` default
  encoding on Windows PowerShell 5.1 for any file containing non-ASCII
  characters (em-dashes, arrows, box-drawing tree diagrams).
- Before staging a batch of edited text files, scan for both symptoms:
  `grep -rlP "[\x80-\xFF]" <files>` to find non-ASCII bytes, then check the
  first 3 bytes of each changed file for a BOM (`EF BB BF`). A real
  mojibake hit reads as Cyrillic-looking garbage in an otherwise-English
  file (`вЂ”`, `в†’`, `в”‚`) -- not to be confused with genuinely correct
  UTF-8 (proper `—`/`→`/box-drawing characters, or actual non-English
  content elsewhere in the repo).
- If a diff on an otherwise-untouched file shows *only* a BOM addition or
  only a mojibake substitution with no real content change, that file has no
  actual edit -- strip the noise and confirm the diff goes empty before
  deciding whether it needs to be committed at all.

## Commit Rules

- Keep commits small and reviewable. Do not commit the whole dirty worktree
  just because it currently runs.
- Never mix these categories in one commit unless the user explicitly asks for
  a squash:
  - runtime bug fix;
  - namespace/refactor migration;
  - audio bridge / C# bridge change;
  - weapon audio tuning;
  - documentation sync;
  - generated/package/release artifacts.
- Before committing, run `git status --short` and list the staged files for the
  user.
- Prefer `git add -p` or explicit file staging. Do not use `git add .` in this
  project unless the user explicitly approves.
- If the working tree already contains unrelated changes, preserve them and
  stage only the files needed for the current commit.
- For large rename/refactor work, commit it separately before feature/fix
  commits. Example: `DualsenseX -> DualSenseEnhanced` namespace migration must
  not be mixed with endpoint picker, weapon audio tuning, or docs cleanup.
- For runtime fixes, include only the source/runtime files required for the fix
  and the minimal docs update if already confirmed.
- For unconfirmed gameplay tuning, do not include status docs that claim it is
  confirmed. Use "test patch" wording until live controller testing confirms
  it.
- Every commit message should start with a clear type/scope, for example:
  - `fix(dualib): guard trigger IPC against script reload`
  - `refactor(runtime): rename DualsenseX namespace to DualSenseEnhanced`
  - `feat(audio): add manual WASAPI endpoint selection`
  - `fix(audio): tune Red9 and Skull Shaker reload tails`
  - `docs: sync endpoint and lightbar test status`
- If a change fixes a `Reset Scripts` bug, the commit must mention reload
  safety/generation guards in the message or body.
- Do not commit deployed game-folder copies unless this repository intentionally
  tracks them. Deployment verification should be documented, not committed as
  external runtime state.
- Before staging, check changed text files for stray BOM/mojibake noise (see
  "Text Encoding Hygiene" above) -- do not commit encoding corruption
  alongside a real change just because it was already sitting in the diff.
- Do not end a session with completed, working changes left uncommitted.
  Confirmed bug class (2026-07-04): the separate release checkout had 86
  modified/new files sitting uncommitted -- including gyro drift-correction
  and lightbar/mic-light work that turned out to be genuinely valuable, not
  scratch work -- with no record of why. It was one accidental `rm -rf` away
  from being lost, and there was no way to tell from git alone whether it was
  finished or abandoned. If a change works, commit it (small and reviewable,
  per the rules above) before considering the task done. If it's unfinished
  at session end, either commit it as an explicit `wip:` commit or write down
  in a handoff doc exactly what's uncommitted and why -- don't just leave it
  sitting in the working tree with no explanation for the next session or
  agent to find.

## Deployment Scripts

Four scripts cover the full dev → release → game workflow. All live in `tools/`.

| Script | When to use |
|---|---|
| `deploy.ps1` | Deploy dev source (`src/reframework/`) to the game folder for normal dev work. Hash-verifies after copy. Use `-RestartBridge` when `DualsenseAudioBridge.exe` or `SoundMap.cs` changed. |
| `verify_deploy.ps1` | Read-only hash check: source vs game folder. Run when a change "still doesn't work" before re-diagnosing logic. |
| `backup_game_mod.ps1` | Snapshot all currently deployed mod files from the game folder into `deployment_backups/<timestamp>-{dev\|release}/`. Skips `*.wav`. Run **before** switching the game folder between dev and release. |
| `deploy_release.ps1` | Copy the staged release package (built by `build_release_package.ps1`) into the game folder. Hard-fails if `re4.exe` is running or `RELEASE_BUILD != true` in the staged loader. Preserves `sounds/` if user already has extracted WAVs. |

**Release deploy workflow (in order):**

```powershell
# 1. Save the current dev deployment
& .\tools\backup_game_mod.ps1

# 2. Deploy release to game folder
& .\tools\deploy_release.ps1
# → Reset Scripts in REFramework, or restart the game
```

**Return to dev after release testing:**

```powershell
& .\tools\backup_game_mod.ps1   # optional: snapshot the release state
& .\tools\deploy.ps1             # restore dev source to game folder
```

`build_release_package.ps1` must be run first (from dev checkout) to assemble the staging folder that `deploy_release.ps1` reads from. `sync_to_release.ps1` must be run before that to bring the release checkout up to date with dev.

## Coding Rules

- Use `pcall` around all RE Engine calls.
- Never assume a singleton, method, or field exists — always check nil.
- `flush()` must be defined before any function that calls it (Lua scoping).
- Do not call `tick_led_sources()` inside `apply_for_weapon()` — it runs per-frame already.
- Keep changes minimal and isolated to the relevant module.
- Do not add UDP or `payload.json` handling to `DualsenseAudioBridge.exe`.
- `DSX_UDPClient.exe` is this project's own build (see
  `speaker/DualsenseAudioBridge/experimental-dsx-client/`). Do not swap in
  a different UDP client implementation without a reproducible frametime
  comparison against the current one.
- Do not use Lua `os.execute`.
- DSX must remain running for Custom DSX mode.
- Exception: native-controller research must run with DSX closed and Steam
  Input disabled so RE4R can see `via.hid.VendorNativeDualSenseDevice`.
- Do not run DSX alongside RE4R native DualSense mode. DSX competes for HID
  output ownership, suppresses native haptics, and causes LED state flicker.
- The audio-only WASAPI bridge may still play controller-speaker WAVs in
  native DualSense mode because it does not need DSX or write HID reports.
- Confirmed Wwise event-ID routes should use `soundlib.SoundManager.postRequestInfo`
  for timing and emit extracted WAV events through `audio_events.json`.
  `onEndOfEvent` is late and should be used only for catalog/confirmation.
- Keep confirmed always-on Wwise mappings in `wwise_audio_router.lua`; keep
  manual capture, noisy candidate logging, and hook exploration in
  `sound_event_diag.lua`.
- Native adaptive-trigger work must use the separate
  `docs/DUALIB_HID_BRANCH.md` plan. Do not resume direct
  `share.hid.Device.setAdaptiveTriggerFeedback` or PlayerManager L2 probes.
- Existing DSX weapon/event mappings are the source of trigger intent. The
  confirmed duaLib branch replaces only trigger output and keeps its
  trigger-only output-field suppression.
- Direct HID is not automatically conflict-free: DualSense output is a
  compound report. Require state merging or one report owner before integration.
- Any new opt-in UI checkbox/toggle backed by a Lua global (e.g.
  `IPC.indicators_enabled`, `IPC.lightbar_enabled`, `IPC.mic_enabled`) must
  be wired into `settings.lua`'s save/load in the same change that adds the
  checkbox. Confirmed bug class (2025-06-29): `IPC.lightbar_enabled` and
  `IPC.mic_enabled` were added to the UI without touching `settings.lua`,
  so every `Reset Scripts` (or game restart) silently reset them to
  `false` while `IPC.enabled`/`indicators_enabled` (already wired)
  survived. The user re-checked the box and still saw no effect because
  they were debugging the wrong layer first. Do not add a toggle without
  also adding its persistence in the same patch.
- After any fix: update `CHANGELOG.md`.
- After discovering a new working hook: update `docs/game_events.md` and `MEMORY.md`.
- After fixing a bug: remove it from `BUGS.md` or mark resolved.
- **Never call `write_lightbar("resetLightBarColor")` (or the game's own
  `resetLightBarColor()` method) when releasing lightbar ownership.** That
  call permanently resets Capcom's own cached color with nothing to restore
  it, because Capcom only calls `set_LightBarColor` again on its *own* state
  changes (not continuously). The correct release is: set `NATIVE.owns_lightbar
  = false`, clear `cached_color`/`last_written_color`, and let Capcom's next
  natural call repaint. Calling `resetLightBarColor` leaves the lightbar stuck
  black permanently until the next Capcom-owned state change. Hardware-confirmed
  bug (2025-06-30); three call sites removed from `native_feedback.lua`.
- `IPC.lightbar_enabled` (duaLib lightbar via watcher IPC) is confirmed
  working in hardware isolation and in gameplay (lightbar pulses, Mic LED
  synced, `Blocked Capcom lightbar calls` counter climbs, native_feedback.lua
  write path goes idle). It is opt-in and defaults off. The earlier session
  finding that "Capcom always wins" was confounded by `AllowLedColor` being
  unconditionally forced false in `readDualsense.cpp`'s trigger-only guard
  block (same bug class as `AllowMuteLight`). After adding
  `controller.lightBarOverrideEnabled` and wiring it into that guard, the
  duaLib lightbar path works. Both `IPC.lightbar_enabled` and `IPC.mic_enabled`
  must be wired into `settings.lua`'s save/load (done; confirmed pattern to
  follow for any future `IPC.*` flag).
- **`EVENTS.in_game` stays `true` during player death** — do not rely on it
  to gate death-state output. Use `EVENTS.player_dead` (set in `events_led.lua`
  death detection, cleared in `begin_pending_gameplay_enable` and menu exit)
  for per-frame gates that must be off during the death screen.
  `NATIVE.death_blackout` is the parallel flag in `native_feedback.lua` for
  lightbar enforcement.
- **`NATIVE.loading_blackout` and `NATIVE.death_blackout`** both cause
  `apply_lightbar` to write `0,0,0` and hold ownership regardless of LED bus
  contents. When either is true the post-update hook enforces black every frame.
  Never set both permanently; always pair with a clear in the matching recovery
  path (`onStartInGame` for loading, `begin_pending_gameplay_enable` for death).
- `pulse_push_interval` (default 2) and `pulse_steps` (default 12) exist on
  both `AMMO` and `LED` tables to throttle the LED-bus push and quantize
  brightness for the continuous sine pulses. Do not bypass or remove these
  throttles: without them, the managed `share.hid.Device` write path and
  `device_update_post_hook` enforcement fire thousands of times per session
  instead of dozens, causing real gameplay stutter (hardware-confirmed,
  2025-06-29). Phase still advances every frame for correct pacing; only
  the actual LED bus push/`flush()` is gated.

## LED Priority Rules

Higher number = higher priority = wins over lower sources.

```
100  parry flash
 90  grab QTE white flash / black rest
 85  finisher / Fatal Kick
 84  hookshot
 80  damage flash
 50  hp_heal lerp
 20  ammo_empty blink
  2  menu dim
  1  hp_gradient / hp_danger
```

Death and menu cleanup must call `DualSenseEnhancedFeedback.clear_led()` on all gameplay sources explicitly.

## Verification Checklist

After any change test:

1. Launch → main menu → no green HP LED.
2. Load save → HP LED appears with correct colour.
3. Heal → smooth blue→HP colour fade ~4 seconds.
4. Take damage → damage flash, returns to HP colour.
5. Get grabbed → Cross flashes white, rests black, and stops immediately when QTE closes.
6. Parry → blue/white flash, overrides grab.
7. Die → lightbar instantly black, ammo indicator off, Mic LED off, L2/R2 no resistance.
8. Return to main menu from gameplay → all effects clear, Capcom blue lightbar restored.
9. Die and press Continue repeatedly → HP, ammo indicator, Mic LED, and adaptive triggers recover.
10. Event effect ends → HP returns with configured 10% to 100% fade.
11. Reload/restart game → no stale state.
12. Audio change → test physical controller output and distinguish implemented
    profiles from gameplay-confirmed profiles.
13. Native backend → DSX closed, Steam Input disabled, USB DualSense; verify
    native Capcom haptics remain active with custom lightbar and triggers.
14. Native gyro → enable in the `Native Gyro` UI, save, restart RE4R, hold the
    controller still during calibration, then verify L2-gated gyro aim and
    right-stick camera control do not jitter against each other.
15. Gyro presets → pick each of Precision/PS5 Feel/Fast Flicks/Stable, confirm
    sliders update and the preset stays selected; move any slider afterwards
    and confirm the label switches to `Custom`.
16. Adaptive trigger presets → cycle Off/Native Only/Light/Enhanced/Strong in
    the `Adaptive Trigger Preset` UI with native mode + duaLib IPC enabled;
    confirm `Off`/`Native Only` stop duaLib trigger writes (IPC status goes
    idle) and `Light`/`Strong` audibly/physically change resistance without
    breaking native haptics, lightbar, or controller-speaker audio.
17. duaLib player indicators → native mode, `IPC.indicators_enabled` on;
    confirm silent above `AMMO.warn_threshold`, counts down below it, and
    the first LED blinks on the last bullet.
18. duaLib Mic LED → native mode, `IPC.mic_enabled` on; confirm it stays
    off on a full magazine, pulses on empty ammo in lockstep with the
    `ammo_empty` lightbar pulse (not duaLib's independent Breathing
    timing), and the same lockstep sync holds for the `hp_danger` low-HP
    heartbeat pulse.
19. Continuous LED pulses (`ammo_empty`, `hp_danger`) → confirm both look
    smooth (no hard on/off blink) and watch the Config UI's "Lightbar
    writes"/"Post-update lightbar enforces" counters during an extended
    empty-mag or low-HP session; they should grow slowly, not in the
    thousands within seconds. If they spike again, check
    `pulse_push_interval`/`pulse_steps` weren't bypassed before assuming a
    new regression.
20. After any Lua or WAV change, run `tools/deploy.ps1` (copies all
    `src/reframework/` to the game folder, then verifies hashes). Only
    after this completes clean should you tell the user to press
    **Reset Scripts** in-game. Do not ask the user to do manual copying.

## Controller Backends

Treat these as separate operating modes:

| Mode | Steam Input / DSX | Expected behavior |
|---|---|---|
| Custom DSX | Enabled / running | Custom LEDs and adaptive triggers; native RE4R DualSense haptics are not reliable |
| Native DualSense | Disabled / closed | Native haptics, custom lightbar, controller speaker, and delayed duaLib triggers |

- Do not promise a simultaneous DSX/native hybrid. Testing in RE4R and
  Spider-Man Remastered shows DSX can partially break native
  audio/triggers/haptics even without a game-specific mod.
- An opt-in `Native Game API (EXPERIMENTAL)` backend is implemented but not
  hardware-confirmed. It calls `share.hid.Device` inside RE4R instead of
  writing HID reports or using DualSenseEnhancedFeedback.
- RE4R's own native adaptive-trigger calls caused a confirmed game crash and
  remain disabled. The separate external duaLib transport is the confirmed
  native trigger path; player indicators (`scePadSetPlayerIndicators`) and
  Mic LED (`scePadSetMicLight`) are hardware-confirmed via the same duaLib
  watcher as of 2025-06-29 — they are no longer DSX-only.
- Custom LED effects (DSX mode) remain available; native mode is the preferred
  project experience for users without DualSenseEnhancedFeedback.
- Native gyro-to-mouse without Steam Input is implemented as an opt-in native
  module. It uses the shared delayed duaLib watcher, L2/focus gating, startup
  calibration, X pitch / inverted-Z yaw, and right-stick arbitration. It may
  still switch RE4R's visible prompts to keyboard/mouse while injecting mouse
  deltas, so keep it isolated from stable DSX LED/audio behavior.

## Weapon Audio Rules

- **Check `docs/WEAPON_AUDIO_STATUS.md` first** for per-weapon completion
  status (start/insert/finish/dry-fire/last-shot/draw/aim-in/aim-out) before
  starting new weapon-audio work. Update it whenever a role's status
  changes for any weapon.
- Maintained profiles live in `docs/weapon_audio_catalog/`.
- Confirmed reload audio: SG-09 R, W-870, Riot Gun, Striker, Skull Shaker, SR
  M1903, Broken Butterfly, and Handcannon. W-870's delayed post-shot pump
  timing is also confirmed and should be preserved.
- Stingray regressed after the conservative correction and must be retested
  phase-by-phase before another mapping patch. CQBR is improved but missing
  part of its reload sequence. Killer7 remains a prototype awaiting gameplay
  testing.
- Do not promote `Unresolved`, `surface_*`, selector, safety, or post-shot
  candidates into runtime mappings without validation.
- `surface_*` groups are confirmed material-routed casing/shell impacts, but
  require reliable material context to reproduce the original routing.
- Numbered WAVs are selected randomly with immediate-repeat avoidance.

## Wwise Event Capture & Deployment Workflow

This is the established, repeatable workflow for adding new confirmed
Wwise-event audio routes (reload stages, dry-fire, last-shot, draw/equip,
aim-in/aim-out, UI sounds, etc.). Follow it without re-deriving it from
scratch.

### Preferred tooling: wwise_events.py

`tools/extract_sounds/wwise_events.py` is the primary tool for all capture
analysis and WEM extraction. Do not read logs manually — use this tool.

**Python path on this machine:**
```
$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe
```
`python` / `python3` shell aliases do not work; always use the full path.

**Log file path (in game folder, not AppData):**
```
C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\reframework\data\DualSenseEnhanced\sound_event_ids.log
```

**Subcommands:**

```powershell
# Analyze a capture log — shows only actionable new candidates by default
& "$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe" `
  tools/extract_sounds/wwise_events.py analyze "<log_path>"

# --all shows everything including routed/noise/generic (useful for debugging)
& "...\python.exe" tools/extract_sounds/wwise_events.py analyze "<log>" --all

# Extract WEMs for an event ID and convert to WAV
& "...\python.exe" tools/extract_sounds/wwise_events.py extract <event_id> `
  --stem <name> --out <output_dir>
```

**analyze output columns:** `event_id | n (occurrences) | kind | wpn tag | window | status`

- `kind`: `candidate` = fired within window; `preroll` = was already firing when window opened
- `window`: the auto-correlate label — `draw`, `shot`, `last_shot`, `reload_start`,
  `reload_insert`, `reload_finish`, `reload_request`, `manual`
- `status`: `NEW in ch_wpNNNN.bnk` = actionable; `ROUTED` = already in router;
  `NOISE` = known noise floor; `KNOWN-GENERIC` = confirmed cross-weapon generic

**Key analysis patterns:**

- An event from `ch_wpNNNN.bnk` appearing **only** in `last_shot` window is
  a last_shot candidate. If it also appears in `shot` windows with the same
  count as total shots fired → fires on every shot → not last_shot-specific → ➖
- `ch_wp_gun_cm.bnk` = shared generic gun sounds, not weapon-specific; skip.
- Bank contamination: if previous weapon's bank appears in current weapon's
  capture (e.g. ch_wp4102.bnk events during ch_wp4402 work), it's preroll
  noise from switching — ignore those entries.
- One event appearing on both aim_in and aim_out = shared sound; route once,
  label as `aim_in`, note shared in source comment.

### Capture methodology

1. **Preferred: Auto-correlate mode** — in the Sound Event Diagnostics UI,
   enable "Auto-correlate (Option 2)". It opens capture windows automatically
   with action labels (`draw`, `shot`, `last_shot`, `reload_start`, etc.) based
   on weapon state transitions. One session per weapon (~1 min): quick-select
   → aim-in/out ×2 → shots until empty → dry-fire × 2 → full reload. This
   gives labeled windows for every role in one pass.

   **Manual window** (`manual_1s` / `manual`) is a fallback for fine-grained
   single-action captures or when auto-correlate misses a short event.

2. Run `wwise_events.py analyze <log>` on the captured log. The tool filters
   noise, marks already-routed IDs, and attributes each candidate to its weapon
   bank. Output is a compact table of actionable new candidates only.

3. A long, fixed list of IDs recur in almost every capture regardless of
   weapon or action — these are ambient/footstep/cloth noise, not weapon
   audio. Known noise-floor IDs include (not exhaustive, growing):
   `807178836`, `1332518089`, `2250845221`, `2250845243`, `2453452847`,
   `2718174961`, `3052338289`, `3328592937`, `3397245785`, `3418362288`,
   `194540406`, `1166837647`/`1166837648`/`1166837649`, `2086827955`,
   `1857863324`, `1401815104`, `2095290572`, `3545586723`,
   `2756336461`/`2756336463` (and other ID pairs differing by 1-3 — treat
   near-identical IDs as the same noise family, likely stereo/instance
   variants). The tool already knows this list — manual cross-checking is
   only needed if the tool is unavailable.

4. If exactly one non-noise candidate appears in a clean window, it can be
   trusted without a repeat capture. If multiple non-noise candidates
   appear, or the result is ambiguous, get at least one more capture and
   require the same ID(s) in the same relative order before trusting it.

5. **Critical failure mode seen repeatedly this project**: a candidate
   found for one role (e.g. "draw/equip stage N") can turn out to be a
   *generic* weapon-lowering/aim-exit cue that also fires on a plain
   aim-in/aim-out with no draw involved at all (confirmed for Blacktail
   `event_0274`, Stingray `event_0262`, SR M1903 `event_0252`, Sentinel
   Nine's rejected "finish" candidate). Before trusting any newly-mapped
   ID, especially ones tied to weapon switching/lowering animations, do a
   dedicated clean aim-in/aim-out test to rule this out. If it turns out
   to be generic, re-route it to the correct role instead of disabling it.

6. Cross-reference confirmed IDs against the extracted Wwise bank before
   deploying. Use `wwise_events.py extract` (preferred) or targeted
   extraction with `ree-pak-cli.exe` — never extract the whole pak:
   ```
   ree-pak-cli.exe unpack -p DSE_Required_Banks.list -i <pak> -o <outDir> -f "ch_wpNNNN" --skip-unknown
   ```
   This extracts only the 1-2 matching bank files from the pak, not the
   full 55 GB archive. Add any new weapon bank paths to
   `tools/extract_sounds/DSE_Required_Banks.list` first.

   **Pak location note** (confirmed 2026-07-05): most weapon banks are in
   `re_chunk_000.pak`. The Sentinel Nine (wp6000) is an exception — its
   bank is in `re_dlc_stm_2109308.pak` (the 2 MB DLC stub). Always try
   the main pak first, then DLC paks, then patch paks if not found. DLC
   pak IDs: 2109300 (Separate Ways 10 GB), 2109307-2109310 (smaller DLC).

   After extraction rename `.sbnk.1.x64` to `.bnk`, then parse the HIRC
   section to find type=4 events by ID and walk the action→container→SFX
   chain. Sound SFX objects (type=2) store the AudioFileId at data[9..12]
   (not data[8]). Extract matching WEMs from the `_media.bnk` DIDX section
   and convert with `vgmstream-cli.exe`.

   **Naming convention**: `ao_` prefix = Separate Ways DLC banks, `ch_` =
   base campaign/Mercenaries banks. UI sounds use `ch_ui_ingame.bnk`, not
   the DLC `ao_ui_*` equivalents. Generic/shared character-level cues (e.g.
   quick-select confirm, weapon-grab on switch) live in `ch_cha0.bnk`.
   Banks cached in `$env:USERPROFILE\AppData\Local\Temp\re4r_txtp_regen\bnk\`
   — check there first before re-extracting.

### Deployment steps (every single change, no exceptions)

1. Edit `wwise_audio_router.lua` and/or `audio_feedback.lua` in `src/...`.
2. Name the new event's WAV file identically to the event name (e.g. event
   `wp4503_dry_fire` → `wp4503_dry_fire.wav`) — **no `SoundMap.cs` edit or
   C# rebuild needed** for this common case (see "`SoundMap.cs` no longer
   needs a rebuild..." above). Only edit `SoundMap.cs` (and then rebuild
   per step 3) if the event name must differ from the WAV stem.
3. If `SoundMap.cs` (or any other C# file) changed: `dotnet publish
   ./DualsenseAudioBridge.csproj -c Release -r win-x64 --self-contained
   true --no-restore -o ./bin/Release/net6.0-windows/win-x64/publish-fixed`,
   then stop the running `DualsenseAudioBridge.exe` (PowerShell
   `Get-Process ... | Stop-Process -Force`), copy the new exe over the
   deployed one, restart it (`Start-Process`). This is the self-contained
   single-file build meant for distribution; it takes ~10-15s per rebuild
   even for a one-line change (relinks/trims/compresses the whole .NET
   runtime every time).

   **Fast path for rapid C# iteration** (e.g. several SoundMap.cs tweaks
   in a row during a capture session): publish with the `Dev` profile
   instead -- `dotnet publish ./DualsenseAudioBridge.csproj -c Release
   -p:PublishProfile=Dev -o ./bin/Release/net6.0-windows/win-x64/publish-dev`.
   This is framework-dependent (no single-file packing/compression), ~2s
   instead of ~10-15s, but produces a **folder** of files (exe + .dll +
   NAudio.*.dll + .runtimeconfig.json), not one exe -- copy the whole
   `publish-dev` folder's contents into
   `<game>/reframework/data/DualSenseEnhanced/` (not just the exe) for it to run.
   Switch back to the normal self-contained publish-fixed build (and
   redeploy just the single exe, removing the extra dev DLLs) before
   considering the work done/shippable -- don't leave the game folder in
   the framework-dependent dev state.
4. Run `tools/deploy.ps1` — it mirrors the full `src/reframework/` tree
   to the game folder and then calls `verify_deploy.ps1` to hash-check
   every file. A deploy is not done until `deploy.ps1` exits green
   ("All deployed files match source."). **No manual copying.**
5. Tell the user to press **Reset Scripts** in-game for Lua changes to
   take effect (the C# bridge picks up WAV-only changes without a reset,
   but a Reset Scripts never hurts and is the single safe signal to give).
6. Do not deploy speculative/unconfirmed IDs, and do not deploy at all if
   the user has explicitly asked to hold off and batch changes — wait for
   an explicit go-ahead.

### Keeping sounds_manifest.json up to date (release prerequisite)

WAV files are gitignored (Capcom assets). Users extract them at install time
via `setup_sounds.bat` → `setup_sounds.ps1`, which reads
`tools/extract_sounds/sounds_manifest.json` (committed to the repo).
The manifest maps `{wav_stem} → {bank_pak, bank_file, wem_id}` and covers
every sound the mod needs. **It must be regenerated after routing new Wwise
events**, otherwise users on a fresh install cannot extract the new sounds.

**When to run:**
After adding any `event = "..."` entry to `wwise_audio_router.lua` (draws,
aim sounds, dry-fire, last-shot, post-shot, etc.), run:

```powershell
& "$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe" `
  tools/extract_sounds/wwise_events.py manifest
```

This reads all `event = ...` entries from the router, walks the HIRC chain
for each event ID to find WEM IDs, and merges new entries into
`sounds_manifest.json` without touching existing hook-based reload entries.
Commit the updated `sounds_manifest.json` as part of the audio deploy commit.

**What it covers:**
- All Wwise-event-routed sounds (`event = "..."` in `wwise_audio_router.lua`):
  draw stages, aim_in/aim_out, dry_fire, last_shot, postshot, reload stages
  that use Wwise events rather than hooks, knife sounds.
- Numbered variants auto-expanded: event `wp4201_draw` with 3 WEMs →
  entries `wp4201_draw1`, `wp4201_draw2`, `wp4201_draw3`.

**What it does NOT cover (manual MANIFEST.csv → build_manifest.ps1 pipeline):**
- Hook-based reload sounds (`handler = "..."` entries in the router, such as
  SG-09 R/Punisher/Red9/Blacktail/Matilda/TMP/Broken Butterfly/Handcannon/
  Bolt Thrower reload starts). These are already in `sounds_manifest.json`
  and don't change unless the hook-based set changes.
- The `qte` UI sound and any sounds from `ch_cha0.bnk`/`ch_ui_ingame.bnk`
  (character or UI banks) — their HIRC banks must be in the local bank cache
  at `%LOCALAPPDATA%\Temp\re4r_txtp_regen\bnk\` for the tool to process them.
  If they're missing from the cache, the tool reports them as skipped and they
  need manual entries (with WEM ID from targeted extraction).

**Prerequisites:**
- `tools/extract_sounds/event_bank_index.json` must be current
  (run `wwise_events.py index` if new weapon banks were downloaded).
- The bank cache (`%LOCALAPPDATA%\Temp\re4r_txtp_regen\bnk\`) must contain
  both `ch_wpNNNN.bnk` and `ch_wpNNNN_media.bnk` for each weapon being
  processed — these are the renamed `.sbnk.1.x64` files from the pak.

**DSE_Required_Banks.list:**
`tools/extract_sounds/DSE_Required_Banks.list` enumerates which bank files
`setup_sounds.ps1` extracts from `re_chunk_000.pak`. If a new weapon bank
is used that isn't listed, add its `_media.sbnk.1.x64` pak path to this file
before committing `sounds_manifest.json`.

### Event delivery architecture

`audio_feedback.lua`'s `emit()` writes to `audio_events.json` as an
**append-only NDJSON log** (one JSON object per line, opened in append
mode, truncated only on script load) — not a single overwritten file. The
C# `EventWatcher` tracks a byte offset and reads only newly-appended lines
per `FileSystemWatcher` notification. This is a deliberate fix for a real
bug: with the old overwrite-single-file design, two emits close together
could be coalesced by the OS into one `FileSystemWatcher` notification,
and since each write fully replaced the file, the earlier event was
silently lost (intermittent missed dry-fire sounds, etc.). Do not revert
to single-file overwrite. If extending the event payload format, keep it
single-line JSON (no embedded newlines).

### `SoundMap.cs` no longer needs a rebuild for the common case (fixed 2025-06-28)

Almost every newly-confirmed Wwise event used to need a new `SoundMap.cs`
`Dictionary` entry, each requiring a full `dotnet publish` + process
kill/restart cycle, even though nearly all entries were a pure 1:1 identity
mapping (event name == WAV stem). `SoundMap.Resolve()` now falls back to
treating the event name itself as the WAV stem when there's no explicit
`_map` entry. **Adding a new event/sound now means: drop the WAV file next
to the others in `reframework/data/DualSenseEnhanced/sounds/`, named exactly like
the event name (e.g. event `wp4503_dry_fire` → file `wp4503_dry_fire.wav`)
— no `SoundMap.cs` edit, no rebuild, no bridge restart.**

Only touch `SoundMap.cs` when the event name needs to differ from the WAV
stem: aliases (e.g. `radio_test` → `heal_herb`), or multiple named
candidate WAVs that aren't simple numbered variants of the same stem
(numbered variants like `wp4000_draw2.wav` are already auto-discovered by
`FindVariants`'s regex without any map entry). Existing identity entries
in `_map` were left in place (harmless, just redundant) rather than
cleaned up — don't be confused into thinking an entry is required for a
new sound to work; test the no-map-entry path first.

## Preferred Codex Workflow

1. Read `AGENTS.md`, `MEMORY.md`, `BUGS.md`, `TASKS_FOR_CODEX.md`, `docs/game_events.md`.
2. Inspect relevant source files before editing.
3. Explain root cause before making changes.
4. Apply minimal patch.
5. Update `CHANGELOG.md` and any relevant docs.
