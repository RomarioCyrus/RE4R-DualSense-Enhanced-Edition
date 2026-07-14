# Matilda (`wp4004`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete |
| Gameplay validation | Confirmed (reload finish, dry fire); insert/start not yet re-verified against the already-full re-chamber edge case |
| Speaker implementation | `start + insert + finish` |
| Physical controller test | Confirmed |

Source review package:
[`../../speaker/review_packages/handguns_wp4000_wp4004_deduplicated_v1/wp4004_Matilda/`](../../speaker/review_packages/handguns_wp4000_wp4004_deduplicated_v1/wp4004_Matilda/)

## Implemented reload mapping

| Runtime phase | Source event | Interpretation |
|---|---|---|
| `wp4004_reload_start*` | `execReloadStart` hook | Magazine release |
| `wp4004_reload_insert*` | Wwise `event_0238` (ID `929678675`), gated by `weapon_id=4004` only | Magazine seated |
| `wp4004_reload_finish*` | Wwise `event_0268` (ID `4245683861`) | Reload finish |

The previous by-ear `event_0230`/`event_0234` start/insert mapping was
replaced after live `postRequestInfo` capture (2025-06-27): the pre-tick
sequence was actually `event_0254 -> event_0262 -> event_0238`, with
`event_0238` firing last (~0.38s before the tick). `event_0234` is reused
below as the dry-fire ID — it is a different action context, not the old
insert candidate.

**Caution:** `event_0268` (reload finish) was also observed firing during a
dry-fire trigger pull at `ammo=0`, not just after a real reload. The runtime
route therefore uses a handler (`AUDIO.play_wp4004_reload_finish_event`) that
only emits the finish WAV when `ammo > 0`, instead of a plain weapon-gated
event route.

## Dry fire (2025-06-27)

`event_0234` (Wwise ID `554267755`), gated to `ammo=0`. No confirmed
last-shot candidate yet — only generic/unresolved IDs were seen at the
1->0 ammo transition in the capture taken so far.

## Legacy candidates (unconfirmed/superseded)

| Event | Preliminary interpretation | Runtime |
|---|---|---|
| `event_0230` | Previously catalogued as magazine removal/start | Superseded by the `execReloadStart` hook |
| `event_0232` | Initial magazine seating | Unmapped intermediate |
| `event_0244` | Slide/bolt forward | Unmapped |
| `event_0246` | Hammer cock | Unmapped |
| `event_0262` | Heavy action cycle | Fires in the pre-tick sequence, not used as insert |

`event_0252` is a 17-asset material/surface family, not a single generic shell
drop.

## Validation checklist

1. Test the already-full re-chamber edge case (extra chambered round) for
   `wp4004_reload_insert`, matching the fix already confirmed on
   `wp4000`/`wp4001`/`wp4002`/`wp4003`.
2. Identify a confirmed last-shot candidate (none found yet).
3. Check whether stock/no-stock or burst-stock configuration changes the
   reload animation and sound sequence.
