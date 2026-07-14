# Riot Gun (`wp4101`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete |
| Gameplay validation | Reload start and per-shell insertion confirmed |
| Speaker implementation | Implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Confirmed; unnecessary finish cue removed |

Candidate assets:
[`../../speaker/extracted_ui_wavs/shotgun_reload_candidates/wp4101/`](../../speaker/extracted_ui_wavs/shotgun_reload_candidates/wp4101/)

## Identified events

| Representative WAV | Mechanical action | Likely gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0214_01_247182102.wav` | Solid insertion followed by a retention click | Per-shell reload insertion | Reload Insert | 7/10 | 8/10 |
| `event_0216_01_317025046.wav` | Abrasive metal-on-metal movement rearward | Action/bolt rearward | Bolt Rack | 8/10 | 9/10 |
| `event_0220_01_828425958.wav` | Heavy resonant forward slam | Action closing and chambering | Chamber | 8/10 | 10/10 |
| `event_0222_01_317025046.wav` | Composite event reusing rack and insertion assets | Composite reload action | Reload Composite | 8/10 | 9/10 |
| `surface_0224_01_192374051.wav` | Hollow spent-shell impact | Material-routed casing/hull contact | Shell Drop / Surface | 9/10 | 3/10 |
| `event_0226_01_753758914.wav` | Firm friction click seating the shell/loading mechanism | Alternate per-shell insertion detail | Reload Insert | 6/10 | 7/10 |
| `event_0232_01_391923643.wav` | High-frequency mechanical snick | Small control; exact role unverified | Control / Unresolved | 9/10 | 4/10 |
| `event_0234_01_250545872.wav` | Quick isolated mechanical click | Lock, safety, or dry-fire-related control | Control / Unresolved | 9/10 | 4/10 |

## Mechanical profile

```text
Riot Gun
├─ Reload Insert
│  ├─ event_0214 — per-shell insertion
│  └─ event_0226 — alternate seating detail
├─ Action
│  ├─ event_0216 — rearward movement
│  └─ event_0220 — forward close / chamber
├─ Reload Composite
│  └─ event_0222 — reused rack and insertion assets
├─ Shell Drop
│  └─ surface_0224 — material-routed hull contact
└─ Controls / Unresolved
   ├─ event_0232 — small mechanical control
   └─ event_0234 — lock/safety-like click
```

## Event-group notes

- `event_0214`, `event_0220`, and `event_0234`: three variants each.
- `event_0216`: four variants.
- `event_0226`: nine variants.
- `surface_0224`: eight material-routed variants.
- `event_0232`: one WEM.
- `event_0222` contains seven assets reused from `event_0216` and
  `event_0214`; it is a composite, not a unique sound family.

## Runtime mapping

- Reload start and per-shell insertion are implemented and physically tested.
- The previously mapped reload-finish cue was removed after gameplay testing
  showed that the original game does not play a separate final sound there.
- Surface impacts and small control events are not implemented.

## Next validation

1. A distinct reload-end/bolt-rack WAV has not yet been identified. Preserve
   the current start + insert mapping until a candidate is confirmed.
2. Determine whether `event_0214` and `event_0226` are separate insertion
   phases or alternate reload states.
2. Identify `event_0232` and `event_0234` in the original animation/audio mix.
3. Add surface-routed shell impacts when material context is available.
