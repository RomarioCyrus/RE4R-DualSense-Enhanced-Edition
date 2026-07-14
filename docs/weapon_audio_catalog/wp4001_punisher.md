# Punisher (`wp4001`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete, preliminary |
| Gameplay validation | Confirmed (normal + already-full edge case) |
| Speaker implementation | `start + insert`, insert via confirmed Wwise event |
| Physical controller test | Confirmed |

Source review package:
[`../../speaker/review_packages/handguns_wp4000_wp4004_deduplicated_v1/wp4001_Punisher/`](../../speaker/review_packages/handguns_wp4000_wp4004_deduplicated_v1/wp4001_Punisher/)

## Implemented reload mapping

| Runtime phase | Source event | Interpretation |
|---|---|---|
| `wp4001_reload_start*` | `execReloadStart` hook | Magazine release |
| `wp4001_reload_insert*` | Wwise `event_0260` (ID `2748519654`), gated by `weapon_id=4001` only | Magazine fully seated |
| `wp4001_reload_finish*` | Wwise `event_0254` (ID `1524268397`) | Reload finish, fires ~0.2s after the insert tick |

`reload_insert`/`reload_finish` are driven directly by confirmed Wwise event
IDs in `wwise_audio_router.lua`, not by ammo-count polling — see
"Fixed bug" below.

## Dry fire and last shot (2025-06-27)

- **Dry fire** is a confirmed two-stage sequence, heard by the user as a
  single click: `event_0252` (Wwise ID `1509391672`) then `event_0240`
  (Wwise ID `712539726`), both gated to `ammo=0`. `event_0240` was
  previously dismissed as an unused late `reload_finish`-window event; it is
  reused here as dry-fire stage 2 since it only fires there when `ammo=0`.
- **Last shot** (the shot that empties the magazine) reuses `event_0234`
  (Wwise ID `122774918`) — the same ID/WAV already used for the
  hook-triggered `reload_start` — gated to `ammo=0`, the same reuse pattern
  as `wp4000`'s dry-fire/reload-start sharing.

## Fixed bug: insert sound missing when mag was already full

Same bug family as `wp4000`/`wp4003`: the previous ammo-delta-based insert
trigger never fired when the player only re-chambers the externally-loaded
extra round (ammo stays at 12/12 the whole reload). Confirmed via live
`postRequestInfo` capture on 2025-06-27 across both a normal reload (11->12)
and the already-full edge case (12/12): a stable, ammo-independent trio fires
every time in `reload_start`:

```text
event_0244 (Wwise ID 824052433)
  -> event_0246 (Wwise ID 1308186371)
  -> event_0260 (Wwise ID 2748519654)
```

`event_0260` fires last, immediately before the ammo tick in the normal case,
and was confirmed present even in the 12/12 edge case where ammo never
changes. It replaces the old ammo-delta `wp4001_reload_insert` trigger.
Physically confirmed on the controller speaker by the user for both the
normal and edge-case reload.

`event_0240` (Wwise ID `712539726`) was also captured, but fires nearly a
second later in the `reload_finish` window — a separate, later mechanical
action (not the magazine-seat moment); not used.

## Reload order candidates (legacy, unconfirmed)

The following by-ear candidates were not seen in live capture and remain
unconfirmed:

1. `event_0234` — magazine release (previously used for `reload_start`;
   replaced by the `execReloadStart` hook, which is ammo-independent by
   design).
2. `event_0238` — magazine extraction.
3. `event_0242` — magazine seating/lock.

## Classification correction

`event_0236` has material-switched TXTP branches (`default`, `iron`, `Water`,
`Wood`) and 17 unique decoded assets. It should be treated as a
surface/impact family, not as a single bolt-rack sound.

## Validation checklist

1. Test a normal tactical reload with ammunition still chambered.
2. Test a reload from empty.
3. Confirm the start cue is not triggered by aim/equip transitions.
4. Confirm the insert cue lands on the magazine-seat animation.
5. Determine whether `event_0246` is empty-reload-only.
