# Handcannon (`wp4502`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete, interpretation requires revision |
| Gameplay validation | Reload and post-shot phases manually identified |
| Speaker implementation | Implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Confirmed |

Candidate assets:
[`../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4502/`](../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4502/)

## Interpretation warning

Handcannon is a revolver. The supplied analysis describes a detachable
magazine, magazine catch, magwell, slide/bolt, and fire selector; those
mechanisms do not match this weapon.

The acoustic observations and scores remain useful, but the reload events are
classified neutrally as revolver-action phases until they are synchronized
with the in-game animation. Plausible actions include frame or cylinder
opening, extractor movement, cartridge removal/insertion, cylinder movement,
and frame/cylinder closing.

The candidate set is not expected to contain primary gunshot audio.
`event_0228` is therefore unresolved rather than `Fire`.

Current runtime mapping:

- start/cylinder cartridge ejection: `event_0226`;
- insert: `event_0202`;
- finish: `event_0224`;
- post-shot action: `event_0218` variants.

The former `event_0214` finish remains rejected. Manual gameplay comparison
identified the correct finish as `event_0224` and the correct opening/ejection
sound as `event_0226`. `event_0218` now plays as the post-shot action; after
the last shot it is deferred until the following reload completes.

## Identified events

| Representative WAV | Acoustic / mechanical observation | Preliminary gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0198_01_876293965.wav` | Sharp metallic click followed by a short sliding movement | Release, opening, extraction, or unloading phase | Reload Phase A | 7/10 | 6/10 |
| `event_0202_01_735519259.wav` | Heavy insertion thud followed by a locking click | Cartridge/loader insertion or major reload seating phase | Reload Phase B | 6/10 | 8/10 |
| `event_0204_01_987335422.wav` | Heavy drawn-out metallic scrape ending at a hard stop | Revolver action moving open, rearward, or through extraction | Reload Phase C | 8/10 | 9/10 |
| `event_0214_01_659425846.wav` | Aggressive metallic movement ending in a forward lock | Revolver action closing or locking | Reload Phase D | 9/10 | 10/10 |
| `event_0216_01_615525484.wav` | Light high-pitched metallic snap | Small latch, release, or lockwork control | Control / Latch | 5/10 | 4/10 |
| `event_0218_01_347360899.wav` | Isolated mechanical action under tension | Post-shot action | Post-shot Action | 6/10 | 5/10 |
| `event_0220_01_504764003.wav` | Bright ringing metallic impact with a long decay | Cartridge case or loose metal component contacting a surface | Drop / Impact A | 10/10 | 3/10 |
| `event_0222_01_96139898.wav` | High-pitched metallic impact with shorter decay | Cartridge case or loose component impact | Drop / Impact B | 9/10 | 3/10 |
| `event_0224_01_704322535.wav` | Duller mechanical/brass-like impact | Reload closing/end action | Reload Finish | 9/10 | 3/10 |
| `event_0226_01_173506914.wav` | Multiple loose metallic elements moving together | Cartridge ejection from cylinder / reload start | Cylinder Eject | 3/10 | 2/10 |
| `event_0228_01_818105505.wav` | High-energy mechanical impact | Weapon equip or hammer impact | Misc / Hammer (Unverified) | 10/10 | 10/10 |

## Preliminary mechanical profile

```text
Handcannon
├─ Reload / Revolver Action
│  ├─ event_0198 — release, opening, or extraction phase
│  ├─ event_0202 — insertion or seating phase
│  ├─ event_0204 — heavy action movement
│  └─ event_0214 — closing or locking action
├─ Control / Latch
│  └─ event_0216 — small mechanical snap
├─ Hammer / Trigger
│  └─ event_0218 — tensioned lockwork click
├─ Drop / Impact
│  ├─ event_0220 — bright impact A
│  ├─ event_0222 — bright impact B
│  └─ event_0224 — duller impact C
├─ Handling
│  └─ event_0226 — gear / weapon movement
└─ Unresolved
   └─ event_0228 — weapon equip or hammer impact
```

## Event-group notes

The reviewed files are representatives. The extraction manifest reports:

- `event_0198`: five unique WEM variants;
- `event_0204`, `event_0216`, `event_0218`, and `event_0222`: three unique
  WEM variants each;
- `event_0214`: two unique WEM variants;
- `event_0202`, `event_0220`, `event_0224`, `event_0226`, and `event_0228`:
  one unique WEM each.

`event_0220`, `event_0222`, and `event_0224` are separate Wwise event groups.
Their similar brass-impact character does not establish a shared round-robin
container. They may correspond to different materials, stages, objects, or
gameplay states.

The supplied final table adds an erroneous `_2` suffix to the `event_0228`
representative filename; that suffixed file does not exist. The confirmed file is
`event_0228_01_818105505.wav`.

## Preliminary implementation candidates

### Speaker

- High-value reload sequence candidates: `event_0198`, `event_0202`,
  `event_0204`, and `event_0214`, after their animation phases are identified.
- Hammer or lockwork click: `event_0218`.
- Small latch/control detail: `event_0216`.
- Drop/impact details: `event_0220`, `event_0222`, and `event_0224`, only after
  determining whether they represent ejected cases, loose cartridges, or
  another component.
- Handling foley `event_0226` is low priority.
- Do not implement `event_0228` until gameplay confirms whether it is weapon
  equip or hammer impact.

### Haptics

- Closing/locking action: `event_0214` (10/10).
- Heavy action movement: `event_0204` (9/10).
- Insertion/seating phase: `event_0202` (8/10).
- Release/opening/extraction phase: `event_0198` (6/10).
- Hammer/lockwork click: `event_0218` (5/10).
- `event_0228` retains a 10/10 raw score but is excluded until the equip/hammer
  distinction is resolved.

## Open validation questions

1. Which Handcannon reload animation phases correspond to `event_0198`,
   `event_0202`, `event_0204`, and `event_0214`?
2. Is `event_0216` a cylinder/frame release, extractor control, or another
   latch?
3. Is `event_0218` hammer cocking, trigger reset, dry fire, or another internal
   lockwork action?
4. What objects or surfaces produce `event_0220`, `event_0222`, and
   `event_0224`?
5. Is `event_0228` weapon equip or hammer impact?
