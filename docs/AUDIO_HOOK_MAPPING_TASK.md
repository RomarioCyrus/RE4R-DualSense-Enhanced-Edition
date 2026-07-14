# Audio Hook Mapping Task

Priority: build a reliable Wwise event ID -> extracted WAV / future haptics
mapping pipeline for RE4R weapon actions.

## Current Confirmed Baseline

The working low-latency hook is:

```text
soundlib.SoundManager.postRequestInfo
```

Use it as the primary timing source. Its managed `RequestInfo` argument exposes
`get_EventId` before the game sound finishes.

Late confirmation hook:

```text
soundlib.SoundManager.onEndOfEvent
```

This is useful for logging and catalog confirmation only. It is too late for
synchronized playback or haptics. In the SG-09 R dry-fire test,
`postRequestInfo` saw the event at `953.538`, playback was written at `953.541`,
and `onEndOfEvent` arrived at `954.086`.

Rejected / low-value path:

```text
via.simplewwise.Driver.callbackGlobal
```

It fired early during tests, but exposed callback flags rather than a useful
event ID.

## First Confirmed Mapping

| Weapon | Context | Wwise event ID | Extracted group | Runtime event | Status |
|---|---|---:|---|---|---|
| SG-09 R (`wp4000`) | dry fire / empty trigger, `ammo=0` | `2330373695` | `event_0260` | `wp4000_dry_fire` | Confirmed in game and on controller speaker |

The route is gated by weapon ID and ammo:

```text
weapon_id = 4000
ammo = 0
event_id = 2330373695
audio_event = wp4000_dry_fire
```

## Important Runtime Files

Main loader:

```text
src/reframework/autorun/DualSenseEnhanced.lua
```

Confirmed always-on Wwise routes:

```text
src/reframework/autorun/DualSenseEnhanced/wwise_audio_router.lua
```

Manual Wwise capture and investigation:

```text
src/reframework/autorun/DualSenseEnhanced/sound_event_diag.lua
```

Audio event writer:

```text
src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua
```

Bridge sound whitelist:

```text
speaker/DualsenseAudioBridge/SoundMap.cs
```

Runtime sound folder:

```text
src/reframework/data/DualSenseEnhanced/sounds/
```

Game deployment paths:

```text
<RE4R>/reframework/autorun/DualSenseEnhanced.lua
<RE4R>/reframework/autorun/DualSenseEnhanced/wwise_audio_router.lua
<RE4R>/reframework/autorun/DualSenseEnhanced/sound_event_diag.lua
<RE4R>/reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe
<RE4R>/reframework/data/DualSenseEnhanced/sounds/
```

Known local RE4R path in this workspace:

```text
C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4
```

## Separation Of Responsibilities

Keep these responsibilities separate:

- `wwise_audio_router.lua`: always-on confirmed mappings only.
- `sound_event_diag.lua`: manual windows, logging, hook discovery, noisy capture.
- `audio_feedback.lua`: emits named audio events into `audio_events.json`.
- `DualsenseAudioBridge.exe`: watches `audio_events.json` and plays mapped WAVs
  through NAudio/WASAPI.
- `SoundMap.cs`: whitelist of named events to WAV filename stems.

Do not put permanent playback logic back into `sound_event_diag.lua`.

## Mapping Workflow

1. Confirm logging is enabled in `Sound Event Diagnostics`.
2. Clear the sound log.
3. Open a short manual window (`Open 1s` or `Open 5s`).
4. Perform exactly one target action in game.
5. Read:

```text
<RE4R>/reframework/data/DualSenseEnhanced/sound_event_ids.log
<RE4R>/reframework/data/DualSenseEnhanced/sound_event_diag.log
```

6. Find event IDs from `postRequestInfo` first.
7. Cross-check late `onEndOfEvent` IDs only as confirmation.
8. Map the candidate ID to extracted TXT/WAV assets.
9. Add a temporary route only after weapon/ammo/context gating is understood.
10. Test by ear on the controller speaker.
11. If confirmed, move it to `wwise_audio_router.lua` and document it.

## TXT/WAV Lookup Notes

`txtp` helps as an ID dictionary and extracted asset pointer. It does not
replace runtime hook testing.

Use runtime event IDs for timing and context. Use TXT/WAV extraction to answer:

- which Wwise event group the ID belongs to;
- which WAV variants are available;
- whether the sound is a reload layer, dry fire, shell, chamber, surface, or
  unresolved mechanical action.

Do not trust waveform-only labels over in-game timing.

## Next Mapping Priorities

1. SG-09 R reload detail IDs:
   - magazine release;
   - magazine extraction;
   - magazine seating;
   - chamber / slide movement.
2. Dry-fire IDs for other handguns:
   - Punisher;
   - Red9;
   - Blacktail;
   - Matilda.
3. Shotgun actions:
   - shell insert;
   - pump/open/close;
   - last-shot deferred pump behavior.
4. Rifle and magnum post-shot / chamber actions.
5. Future haptics coupling:
   - use the same confirmed Wwise IDs as timing triggers;
   - do not attempt live SFX-bus/audio-to-haptics routing in the stable path.

## Implementation Pattern

Add confirmed routes to `wwise_audio_router.lua`:

```lua
local event_map = {
    [2330373695] = {
        event = "wp4000_dry_fire",
        weapon_id = 4000,
        ammo = 0,
        cooldown = 0.20,
        source = "wp4000 event_0260 dry fire",
    },
}
```

For a new sound event, also add it to `SoundMap.cs`:

```csharp
["wp4000_dry_fire"] = new[] { "wp4000_dry_fire" },
```

Then ensure a matching WAV exists in:

```text
reframework/data/DualSenseEnhanced/sounds/
```

## Build And Deploy Checklist

For Lua-only route changes:

1. Copy updated Lua files into the game REFramework autorun folder.
2. Verify SHA-256 source/runtime match.
3. In game, use `Reset Scripts`.
4. Test without opening a manual diagnostic window.

For bridge `SoundMap.cs` changes:

1. Publish:

```powershell
dotnet publish .\DualsenseAudioBridge.csproj `
  -c Release -r win-x64 --self-contained true --no-restore `
  -o .\bin\Release\net6.0-windows\win-x64\publish-fixed
```

2. Close RE4R if `DualsenseAudioBridge.exe` is locked.
3. Copy the new EXE to:

```text
<RE4R>/reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe
```

4. Verify SHA-256 source/runtime match.

Known benign build warnings from the current environment:

- `net6.0-windows` is EOL.
- NuGet vulnerability feed can be unreachable due restricted network.

The publish can still succeed with `--no-restore`.

## Required Documentation Updates

When a mapping is confirmed, update:

- `docs/CHANGELOG.md`
- `docs/game_events.md`
- `docs/AUDIO_MEMORY.md`
- `docs/MEMORY.md`
- `docs/weapon_audio_catalog/README.md`
- relevant weapon profile under `docs/weapon_audio_catalog/`

Mark these states separately:

- extracted / identified;
- implemented;
- deployed;
- confirmed in game;
- confirmed on controller speaker;
- haptics implemented or not implemented.

## Current Test Command Notes

`git` was not available in PATH during the latest session, so do not rely on
`git status` unless PATH is fixed.

Use PowerShell `Get-FileHash -Algorithm SHA256 -LiteralPath ...` for deployment
parity checks.

## Safety Rules

- Do not add UDP or `payload.json` handling to `DualsenseAudioBridge.exe`.
- Do not reintroduce the removed custom `DualsenseDsxBridge`.
- Do not make `sound_event_diag.lua` own always-on playback again.
- Do not treat `onEndOfEvent` as a low-latency output hook.
- Do not mark a mapping confirmed from extraction alone.
- Preserve the existing event-based extracted-WAV speaker bridge as the stable
  baseline.
