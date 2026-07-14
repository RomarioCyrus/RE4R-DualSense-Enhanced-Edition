# AUDIO_MEMORY.md - Stable Bridge State

## Confirmed Architecture

```text
audio_feedback.lua -> audio_events.json -> DualsenseAudioBridge.exe -> WASAPI
feedback_writer.lua -> payload.json -> external DSX_UDPClient.exe -> DSX
```

`DualsenseAudioBridge.exe` contains no UDP or `payload.json` code.
`DSX_UDPClient.exe` is a separate process built from this repository's
`speaker/DualsenseAudioBridge/experimental-dsx-client/DSX_UDPClient_Test.c`.

The native REFramework launcher starts both processes. The audio bridge follows
the `re4.exe` lifetime, while a launcher-owned Windows Job Object stops the UDP
client when REFramework unloads.

## Decision Record

- The unified audio/UDP bridge caused stutters.
- The separate custom `DualsenseDsxBridge` still caused stutters.
- The existing `DSX_UDPClient.exe` was tested in the same setup without those
  stutters.
- The custom DSX bridge and its build artifacts were therefore removed.

## Audio Bridge Behavior

- Watches only `audio_events.json`.
- Opens WASAPI only for a mapped sound event.
- Disposes playback after the sound completes.
- Supports runtime device and volume from each audio event.
- Supports exact Windows WASAPI endpoint routing through `device_id` in
  `audio_events.json`. The bridge resolves playback by endpoint ID first,
  then legacy friendly-name fragment, then automatic DualSense detection.
- Writes active render endpoints to
  `reframework/data/DualSenseEnhanced/audio_devices.json` for the REFramework
  UI. The UI exposes `Auto DualSense`, `Manual Endpoint`, and
  `Legacy Presets`.
- Manual endpoint selection is implemented, deployed, and live-tested with a
  connected controller. The UI lists active endpoints, `Next` switches between
  them, and `Test Speaker` plays through the selected endpoint, including
  non-controller Windows output devices. Two-controller routing remains a
  dedicated follow-up test.
- Supports numbered random variants such as `parry2.wav`, `parry_2.wav`, and
  `parry-v2.wav`, avoiding an immediate repeat when alternatives exist.
- `Test Speaker` uses the confirmed `parry` event as a universal endpoint
  smoke test. The old `heal_herb` smoke-test event was removed because the
  current runtime no longer ships the old heal WAV family.
- Confirmed event sources include manual UI test, healing, parry, Grab-QTE
  input, and universal item pickup.
- Fatal Kick uses three randomized composite WAVs with immediate-repeat
  avoidance. Each combines common transient + critical layer A, then critical
  layer B after a short delay; the unwanted critical long layer is excluded.

## Weapon Audio

- Maintained analysis/status index:
  `docs/weapon_audio_catalog/README.md`.
- Physically confirmed foundations: SG-09 R reload, Riot Gun reload, W-870
  per-shell reload and ordinary delayed post-shot pump, Striker, Skull Shaker,
  SR M1903, Broken Butterfly, and Handcannon. Several of these mappings were
  refined from a later manual sound-to-animation pass and require retesting.
- Active correction targets: Stingray regressed after the conservative mapping
  change, and CQBR is improved but missing part of its reload sequence.
- Prototype pending first gameplay validation: Killer7.
- Conservative prototypes pending first gameplay validation: Punisher, Red9,
  Blacktail, and Matilda.
- Reload session start uses `PlayerEquipment.execReloadStart` (or `execReload`
  fallback) plus `PlayerBaseContext` reload-state confirmation.
- Ammo increases emit insert sounds. Stable reload-state exit emits finish only
  when the weapon profile defines one; Broken Butterfly and Skull Shaker use
  the final full-ammo increase for more accurate close/cock timing.
- The rifle/magnum deployment adds 47 deduplicated WAVs. The handgun prototype
  pass adds 21 runtime WAVs across `wp4001`-`wp4004`.
- `surface_*`, unresolved, selector/safety, and extra post-shot candidates are
  intentionally excluded from these conservative first-pass mappings.
- Material-switched handgun groups with 17 decoded assets are also treated as
  surface/impact families, even when one representative WAV was initially
  labeled as a mechanical action.
- W-870 and SR M1903 remember a bolt/pump cycle skipped after the last shot and
  emit it when the next reload ends. Handcannon follows the same deferred
  post-shot rule.
- Broken Butterfly and Skull Shaker have independent delayed post-shot event
  families.
- Cross-bank reuse is allowed when manual gameplay comparison confirms the
  WAV: CQBR currently uses two `wp4401` sources, Skull Shaker one `wp4102`
  source, and Broken Butterfly reuses Handcannon `event_0226`.
- Wwise event-ID routing is now confirmed for timing-sensitive weapon audio:
  `soundlib.SoundManager.postRequestInfo` exposes `RequestInfo.get_EventId`
  before playback, while `onEndOfEvent` is only a late confirmation path.
  SG-09 R dry fire maps `event_id=2330373695` (`wp4000` `event_0260`) to
  `wp4000_dry_fire`, is gated to weapon `4000` with `ammo=0`, and was
  confirmed in game with synchronized controller-speaker playback.
- Confirmed Wwise routes live in `wwise_audio_router.lua`. The diagnostic
  `sound_event_diag.lua` remains opt-in and should not own always-on playback.

## Item Pickup Audio

`DropItem.onAcceptPickup` is matched back to a short-lived `DropItem` cache by
`ContextID`, providing the raw and normalized item ID.

Pickup diagnostics are disabled by default now that external item/weapon lookup
databases are available. The hook still resolves items and emits sounds; raw
IDs, ContextID arguments, and per-pickup Event Monitor entries appear only
when diagnostics are manually enabled for the current session.

Current sound mapping:

- ammo -> `ammo_pickup*`
- pesetas -> `pesseta*`
- healing pickup -> `pickup_sound*`
- resources / grenades / disposable knives -> `metal_pickup_unconfirmed*`
- valuables -> `treasure_regular_pickup*`
- Small Key -> `key_item_pickup*`

## BSOD Finding

Microsoft WinDbg analysis of `061926-18437-01.dmp` identified
`nssvpd.sys`, Nefarius Virtual Gamepad Emulation Bus G2 2.62.0.0, as the
faulting kernel module. The dump and analysis remain under `diagnostics`.

## Current Artifacts

- `dist/audio-portable/DualsenseAudioBridge.exe`
- `dist/audio-compact/DualsenseAudioBridge.exe`
- `launcher/DualsenseAudioBridgeLauncher.dll`

## Test Results

- Audio project publishes successfully without UDP classes.
- Launcher race test starts exactly one audio process and one UDP client.
- The auto-started UDP client stops when the launcher host exits.
- Physical controller-speaker playback is confirmed for manual UI, healing,
  parry, pickup, fatal kick, knife hit, SG-09 R reload, Riot Gun reload, and
  W-870 per-shell reload, Striker, Skull Shaker, SR M1903, Broken Butterfly,
  and Handcannon.
- The latest bridge with expanded weapon mappings was published with
  `--no-restore`, deployed, hash-checked, and smoke-tested. Remaining weapon
  profiles still require gameplay validation.
- Controller-speaker event WAV playback is confirmed with RE4R native DualSense
  mode and DSX closed, including after the patched duaLib trigger transport.
  Windows test tone, `Play Test Sound`, and mapped in-game audio remained
  audible. If this regresses, start with `Play Test Sound`, then inspect the
  bridge log and active Windows WASAPI endpoint before changing mappings or
  playback code.
- Live endpoint loopback/audio-to-haptics was physically confirmed in the
  DSX-managed configuration, including directional response and no noticeable
  latency with music/voice disabled.
- The same actuator output is silent in RE4R native DualSense vibration mode,
  even though the 48 kHz four-channel endpoint opens successfully.
- One-shot and five-report/200 ms audio-haptics HID selection tests on
  DualSense Edge did not restore reliable actuator playback.
- Current decision: retain the event-based speaker bridge and manually extend
  its extracted WAV mappings later. Wwise event-ID routing through
  `postRequestInfo` is a confirmed way to trigger extracted WAVs at the right
  time; direct live game-mix/SFX-bus routing and native audio-to-haptics
  coexistence remain deferred.
