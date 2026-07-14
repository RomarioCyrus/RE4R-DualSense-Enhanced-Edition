# Skull Shaker (`wp6001`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete |
| Gameplay validation | Reload start reclassified; post-shot action identified |
| Speaker implementation | Implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Confirmed |

Candidate assets:
[`../../speaker/extracted_ui_wavs/shotgun_reload_candidates/wp6001/`](../../speaker/extracted_ui_wavs/shotgun_reload_candidates/wp6001/)

## Identified events

| Representative WAV | Mechanical action | Likely gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0209_01_512036038.wav` | Heavy metallic pull and release | Lever/action opening phase | Action Open | 7/10 | 8/10 |
| `surface_0211_01_129226797.wav` | Dull material-routed shell impact | Spent-shell contact on a muted surface | Shell Drop / Surface | 3/10 | 5/10 |
| `event_0215_01_461761241.wav` | Hollow movement ending in a locking click | Lever/action closing and chamber lock | Action Close / Chamber | 6/10 | 7/10 |
| `event_0219_01_215698335.wav` | Distinct sharp double-click | Small control; exact role unverified | Control / Unresolved | 8/10 | 4/10 |
| `event_0223_01_797401471.wav` | Friction movement followed by a retention snap | Per-shell reload insertion | Reload Insert | 5/10 | 9/10 |
| `event_0227_01_55759997.wav` | Subtle isolated mechanical click | Safety/latch-like control | Control / Unresolved | 7/10 | 3/10 |
| `event_0229_01_490839256.wav` | High-pitched brass or shell impact | Shell ejection/contact | Shell Drop | 9/10 | 2/10 |
| `event_0231_01_856477786.wav` | Sharp internal mechanism snap | Hammer fall or dry fire | Hammer / Dry Fire | 6/10 | 6/10 |
| `event_0233_01_512036038.wav` | Composite event reusing action-open and insertion assets | Composite reload/action event | Action Composite | 7/10 | 8/10 |

## Mechanical profile

```text
Skull Shaker
├─ Lever / Action
│  ├─ event_0209 — action open
│  └─ event_0215 — action close / chamber lock
├─ Reload Insert
│  └─ event_0223 — per-shell insertion
├─ Action Composite
│  └─ event_0233 — reused open and insertion assets
├─ Shell Drop
│  ├─ event_0229 — shell contact/ejection
│  └─ surface_0211 — material-routed shell impact
├─ Hammer / Dry Fire
│  └─ event_0231 — internal hammer/trigger snap
└─ Controls / Unresolved
   ├─ event_0219 — double-click
   └─ event_0227 — isolated latch-like click
```

## Event-group notes

- `event_0209`: three variants.
- `event_0215`: nine variants.
- `event_0223` and `event_0227`: three variants each.
- `event_0229`: five variants.
- `surface_0211`: eight material-routed variants.
- `event_0219` and `event_0231`: one WEM each.
- `event_0233` combines six assets reused from `event_0209` and `event_0223`.
  Do not play it together with both source events for the same action.

## Runtime mapping

- No sound is currently emitted at generic reload start.
- Per-shell insertion still uses the confirmed `event_0233` insertion assets.
- The former reload-start `event_0233` action assets are now emitted as the
  reload-end family because manual gameplay review identified the current
  start sound as an ending action.
- Cross-bank `wp4102 event_0204_07_520888437` is used as the newly identified
  post-shot action with a provisional one-second delay.
- The former `event_0215` finish family is no longer used by runtime.

## Next validation

1. Retest the new no-start/insert/end mapping.
2. Tune the provisional post-shot delay if necessary.
3. Identify `event_0219` and `event_0227`.
4. Add material-routed shell impacts later.
