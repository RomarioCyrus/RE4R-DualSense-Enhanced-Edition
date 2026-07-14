# CQBR (`wp4402`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete, preliminary |
| Gameplay validation | Reload phases manually identified; retest pending |
| Speaker implementation | Three-phase mapping implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Confirmed improved, incomplete |

Candidate assets:
[`../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4402/`](../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4402/)

The meanings below are inferred from isolated listening. Event timing,
surface routing, layering, and exact weapon-state transitions remain
unconfirmed until compared with gameplay.

Current runtime mapping:

- start: `event_0206`;
- insert: `wp4401 event_0252_01_899314204`;
- finish/bolt rack: `wp4401 event_0248_01_872283622`.

The previous `event_0210` finish family was correctly rejected as weapon
draw/equip audio. Manual gameplay comparison then identified the two
cross-bank WAVs above as the missing magazine-insert and final bolt-rack
phases. Their source-bank mismatch is preserved in the catalog manifest.

## Identified events

| Representative WAV | Mechanical action | Likely gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0199_01_730193871.wav` | Tactical fabric rustle and light gear movement | Idle handling, body movement, or entering aim | Misc / Handling | 2/10 | 3/10 |
| `event_0203_01_337051184.wav` | Light metallic rattle with stock or sling movement | Equip, unequip, or sling adjustment | Misc / Equip | 3/10 | 4/10 |
| `event_0206_01_760795310.wav` | Heavy charging handle pulled rearward and driven forward under spring tension | Full manual action cycle | Bolt Rack | 8/10 | 9/10 |
| `event_0210_01_165175237.wav` | Localized high-frequency metallic click | Weapon draw/equip cue in current gameplay test | Misc / Equip | 7/10 | 6/10 |
| `event_0216_01_492895662.wav` | Dull resonant insertion followed by a rigid lock click | Magazine seated past the catch | Reload Insert | 6/10 | 8/10 |
| `surface_0214_01_521211021.wav` | Hollow brass bounce with surface-dependent reflections | Casing contact on a distinct surface | Shell Drop / Surface | 9/10 | 4/10 |
| `event_0222_01_732794500.wav` | Hollow brass impact followed by secondary bounces | Casing contact on a hard surface | Shell Drop | 9/10 | 4/10 |
| `event_0226_01_997463616.wav` | Deliberate two-stage mechanical click through a detent | Semi/automatic fire-mode selector | Selector | 5/10 | 7/10 |
| `event_0231_01_604281456.wav` | Short, firm, localized mechanical click | Safety toggle | Safety | 5/10 | 6/10 |
| `event_0235_01_4124683.wav` | High-amplitude transient with rapid mechanical cycling | Possible post-shot bolt cycle; exact source unresolved | Unresolved / Post-shot | 10/10 | 10/10 |

## Mechanical profile

```text
CQBR
├─ Unresolved
│  └─ event_0235 — possible post-shot bolt cycle
├─ Bolt Rack
│  └─ event_0206 — full charging-handle cycle
├─ Chamber
│  └─ event_0210 — cartridge seating
├─ Reload Insert
│  └─ event_0216 — magazine insertion and lock
├─ Shell Drop
│  ├─ event_0222 — hard-surface casing contact
│  └─ surface_0214 — surface-routed casing contact
├─ Selector
│  └─ event_0226 — fire-mode selector
├─ Safety
│  └─ event_0231 — safety toggle
└─ Misc
   ├─ event_0199 — idle handling / gear movement
   └─ event_0203 — equip or sling adjustment
```

## Event-group notes

The reviewed files are representatives. The extraction manifest reports:

- `event_0199`, `event_0206`, and `event_0222`: one unique WEM each;
- `event_0203`, `event_0210`, `event_0216`, and `event_0231`: three unique
  WEM variants each;
- `surface_0214`: eight unique surface assets;
- `event_0226`: nine unique assets;
- `event_0235`: three extracted files referencing only one unique WEM.

The three `event_0235` files must not be treated as round-robin variants. They
are duplicate references to the same source asset. The earlier `Fire`
classification was based on waveform character and is considered incorrect
for this candidate set.

The unusually large `event_0226` group may represent selector variations,
layering, or another switched mechanical family. Its exact role requires
gameplay validation before all nine assets are randomized together.

## Preliminary implementation candidates

### Speaker

- Charging-handle cycle: `event_0206`.
- Chamber accent: `event_0210`, only if it is independently audible rather
  than already embedded in the charging-handle event.
- Magazine insertion: `event_0216`.
- Casing detail: `event_0222`, or `surface_0214` when reliable material context
  becomes available.
- Selector and safety details: `event_0226` and `event_0231`.
- Do not implement `event_0235` until comparison with the original CQBR mix
  determines whether it is post-shot bolt cycling or another high-energy
  event.
- Ambient handling events `event_0199` and `event_0203` are low priority and
  may make the speaker mix unnecessarily busy.

### Haptics

- Charging-handle pull and return: `event_0206` (9/10).
- Magazine insertion: `event_0216` (8/10).
- Fire selector: `event_0226` (7/10).
- Chamber and safety actions: `event_0210` and `event_0231` (6/10).
- `event_0235` retains a 10/10 raw haptics score but is excluded from
  implementation candidates until reclassified.

## Open validation questions

1. Retest the new magazine-insert and bolt-rack timing in game.
2. Does `event_0206` occur only during reload, or also during another manual
   chambering action?
3. Is `event_0210` a separately timed chamber layer or part of the composite
   bolt-rack sound?
4. Does `event_0226` truly represent the fire selector, and why does its event
   group contain nine unique WEM assets?
5. Is `event_0231` used for both safety states or only one transition?
6. Is `event_0222` a generic casing impact while `surface_0214` is selected by
   material context?
7. Are `event_0199` and `event_0203` tied to aim/equip transitions strongly
   enough to justify speaker or haptic output?
8. Is `event_0235` post-shot bolt cycling, another high-energy mechanical
   event, or an exceptional firing-layer asset in this bank?
