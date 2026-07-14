# Blacktail (`wp4003`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete |
| Gameplay validation | Confirmed (reload, dry fire, last shot) |
| Speaker implementation | `start + insert + finish`, all Wwise-gated except start |
| Physical controller test | Confirmed |

Source review package:
[`../../speaker/review_packages/handguns_wp4000_wp4004_deduplicated_v1/wp4003_Blacktail/`](../../speaker/review_packages/handguns_wp4000_wp4004_deduplicated_v1/wp4003_Blacktail/)

## Implemented reload mapping

| Runtime phase | Source event | Interpretation |
|---|---|---|
| `wp4003_reload_start*` | `execReloadStart` hook | Magazine release |
| `wp4003_reload_insert*` | Wwise `event_0268` (ID `3172553005`), gated by `weapon_id=4003` only | Magazine fully seated |
| `wp4003_reload_finish*` | Wwise `event_0254` (ID `1774673807`) | Reload finish |

`reload_start` timing is driven by the existing
`execReloadStart` hook. `reload_insert` is driven directly by the confirmed
Wwise event ID in `wwise_audio_router.lua`, **not** by ammo-count polling —
see "Fixed bug" below for why.

## Fixed bug: insert sound missing when mag was already full

If the player fires only the externally-chambered extra round (ammo
10/9 -> 9/9, magazine itself still full) and then reloads, the previous
ammo-delta-based insert trigger in `ammo_led.lua` never fired: total ammo
never increases in this case (the round just moves from magazine to chamber),
so `ammo_delta > 0` was never true and the reload's `window` never even
transitioned from `reload_start` to `reload_insert` in diagnostics. Confirmed
via live capture on 2025-06-27: `event_0268` (Wwise ID `3172553005`) still
fired in the normal position (between `event_0264` and `event_0246`) even
though ammo stayed at 9/9 the whole reload. Fixed by moving `wp4003_reload_insert`
to a direct Wwise-event route in `wwise_audio_router.lua` (weapon-gated only,
no ammo condition), and removing the `insert` key from `wp4003`'s entry in
`audio_feedback.lua`'s `RELOAD_EVENTS_BY_WEAPON` so the old ammo-delta path no
longer double-fires it.

## Runtime-confirmed reload events (2025-06-27, `postRequestInfo` capture)

Captured via live `soundlib.SoundManager.postRequestInfo` during repeated real
tactical reloads (weapon gated, ammo-state gated). Order was stable across
every captured reload session:

```text
wp4003_reload_start (hook)
  -> event_0264 (Wwise ID 2857560191)
  -> event_0246 (Wwise ID 814494088)
wp4003_reload_insert (ammo increase)
```

`event_0264` and `event_0246` were also tested against a separate aim/lower
control session (5 repeated aim-and-lower cycles, no reload) and produced
**zero** false positives — both are reload-exclusive for this weapon.

The previous by-ear `event_0256` mapping for reload-start is **disproven**: it
never fired in any of the captured live reload sessions and has been removed.
`event_0268`, previously catalogued as the insert/seat candidate, did fire
once during a reload_start window, but `event_0264`/`event_0246` are the
stable, repeatable, reload-exclusive pair and are preferred going forward.

## Rejected candidate: `event_0274` is not reload-specific

`event_0274` (Wwise ID `3406633596`) appeared to coincide with reload finish
in early captures, but a dedicated control test (5x aim-in/aim-out with no
reload at all) fired `event_0274` repeatedly with **no** reload context. It is
a general weapon-lowering/aim-exit cue, not a reload-finish event, and must
not be used as a reload cue. It is documented separately as a confirmed
general hook (see `MEMORY.md`) for possible future use (e.g. auto-disabling
gyro on aim exit).

## Dry fire and last shot (2025-06-27)

- **Dry fire**: `event_0256` (Wwise ID `1962329062`) — originally catalogued
  as reload-start by ear (and disproven above), a clean ammo=0 trigger-pull
  capture confirmed it is exclusively the dry-fire sound, with its own
  dedicated WAV (not shared with reload, unlike `wp4000`/`wp4001`).
- **Last shot** (the shot that empties the magazine): `event_0272` (Wwise ID
  `3376360896`), gated to `ammo=0`.

## Reload order candidates (legacy, unconfirmed)

These were not seen in any live capture and remain unconfirmed by-ear
candidates only:

1. `event_0258` — magazine alignment/reload initiation.
2. `event_0266` — magazine entering the magwell.
3. `event_0268` — magazine catch/seat (fired once during reload_start; needs
   more captures before promotion).
4. `event_0262`, `event_0276` — possible slide/action events; keep unmapped
   until tactical-versus-empty reload comparison.

## Classification correction

`event_0244` exposes material-switched branches and 17 unique decoded WAVs.
It belongs to the surface/impact family and should not be treated as a safety
toggle from the representative WAV alone.

## Validation checklist

1. Test tactical and empty reloads separately.
2. `event_0264`/`event_0246` order and reload-exclusivity confirmed via live
   hook capture plus a dedicated aim/lower control test.
3. Check whether the intermediate `event_0258`/`event_0266` layers are audible
   enough to justify a future composite WAV.
4. Identify which, if any, remaining action event belongs to empty reload only.
