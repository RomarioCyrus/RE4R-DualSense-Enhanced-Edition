# Striker (`wp4102`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete |
| Gameplay validation | Confirmed after finish-cue removal |
| Speaker implementation | Implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Confirmed |

Candidate assets:
[`../../speaker/extracted_ui_wavs/shotgun_reload_candidates/wp4102/`](../../speaker/extracted_ui_wavs/shotgun_reload_candidates/wp4102/)

## Identified events

| Representative WAV | Mechanical action | Likely gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0204_01_509726862.wav` | Heavy action drawn rearward against spring tension | Reload/action opening phase | Bolt Rack | 4/10 | 8/10 |
| `event_0206_01_805219552.wav` | Rapid forward movement ending in a hard lock | Reload/action closing phase | Chamber / Lock | 5/10 | 9/10 |
| `event_0208_01_469445976.wav` | Hollow insertion followed by a retention click | Per-shell reload insertion | Reload Insert | 3/10 | 6/10 |
| `event_0212_01_569717610.wav` | Small crisp mechanical tick | Small control; exact role unverified | Control / Unresolved | 7/10 | 3/10 |
| `surface_0214_01_883303723.wav` | Light spent-shell impact on a material surface | Surface-routed shell contact | Shell Drop / Surface | 9/10 | 1/10 |
| `event_0218_01_637252005.wav` | Minor spring and attachment movement | Ready/handling foley | Misc / Handling | 2/10 | 2/10 |

## Mechanical profile

```text
Striker
├─ Reload / Action
│  ├─ event_0204 — rearward action
│  └─ event_0206 — forward lock
├─ Reload Insert
│  └─ event_0208 — per-shell insertion
├─ Shell Drop
│  └─ surface_0214 — material-routed hull contact
├─ Control / Unresolved
│  └─ event_0212 — small mechanical tick
└─ Handling
   └─ event_0218 — readiness / idle foley
```

## Event-group notes

- `event_0204`: nine variants.
- `event_0206`: fourteen variants.
- `event_0208`: four variants.
- `event_0212`: three variants.
- `surface_0214`: eight material-routed variants.
- `event_0218`: one WEM.

## Runtime mapping

- Start and insertion phases are present in the runtime mapping.
- Gameplay testing found the final `event_0206` cue to be extra, so the
  runtime no longer emits a separate finish event.
- The active source WAV families correspond to `event_0204` and `event_0208`.
- Latest gameplay pass confirmed this corrected mapping feels ideal.
- Surface and control events are not implemented.

## Next validation

1. Preserve the current start + insert mapping.
2. Identify `event_0212`.
3. Add material-routed shell impacts later.
