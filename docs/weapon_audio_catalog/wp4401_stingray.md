# Stingray (`wp4401`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete, preliminary |
| Gameplay validation | Regression found |
| Speaker implementation | Current mapping broken |
| Haptics implementation | Not implemented |
| Physical controller test | Tested; needs phase retest |

Candidate assets:
[`../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4401/`](../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4401/)

The meanings below are inferred from isolated listening. Attachment state,
surface routing, event layering, and timing remain unconfirmed until compared
with gameplay.

Current prototype mapping:

- start: `event_0227`;
- finish: `event_0231`.

Gameplay testing found the previous `event_0233` insertion cue to be
incorrect. It was removed from the runtime mapping, leaving only start and
finish. The latest test found this conservative mapping is now broken overall.
Do not continue tuning Stingray by subtraction; test its candidate phases
individually and rebuild the mapping from observed gameplay timing.

Live `postRequestInfo` capture (2025-06-27) of a normal reload found a
pre-tick sequence `event_0262 -> event_0242 -> event_0240 -> event_0252`;
`event_0233` did not fire at all. `event_0252` was tried as the insert cue
(weapon-gated route in `wwise_audio_router.lua`) but the user heard a
mechanical ratcheting/winding sound, not a magazine insertion -- matching
this catalog's own `event_0246` description, not `event_0252`'s. Rejected
and removed; no confirmed insert candidate exists yet.

## Identified events

| Representative WAV | Mechanical action | Likely gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0223_01_657701737.wav` | Concussive transient with metallic tail and reverberant decay | Unknown mechanical or composite event | Unresolved | 8/10 | 10/10 |
| `event_0227_01_352501047.wav` | Two-stage scraping slide ending in a spring-assisted forward slam | Manual action cycle | Bolt Rack | 7/10 | 9/10 |
| `event_0231_01_595098197.wav` | Tight internal metallic seating sound | Cartridge entering the chamber | Chamber | 6/10 | 6/10 |
| `event_0233_01_1060552214.wav` | Heavy insertion thud followed by a latch click | Magazine seated and locked | Reload Insert | 4/10 | 8/10 |
| `event_0236_01_712250523.wav` | Light brass ping followed by a secondary bounce | Casing contact on a hard surface | Shell Drop | 8/10 | 2/10 |
| `surface_0238_01_957355313.wav` | Bright brass clatter with a resonant ringing tail | Casing contact on a metallic surface | Shell Drop / Surface | 9/10 | 2/10 |
| `event_0240_01_778665027.wav` | Small metal component snapping into a notch | Fire-mode selector | Selector | 5/10 | 5/10 |
| `event_0242_01_461065523.wav` | Fast metallic snap | Safety disengaged | Safety | 5/10 | 4/10 |
| `event_0246_01_892528479.wav` | Rapid rhythmic ticking or ratcheting | Unique winding or adjustment mechanism | Misc | 9/10 | 6/10 |
| `event_0248_01_872283622.wav` | Dull, muffled brass impact with little ringing | Casing contact on a softer surface | Shell Drop | 7/10 | 2/10 |
| `event_0250_01_759650668.wav` | Tight pneumatic transient with gaseous hiss and little reverberation | Unknown attachment or mechanical event | Unresolved | 7/10 | 8/10 |
| `event_0252_01_899314204.wav` | Metallic click followed by a short hollow slide | Magazine release / ejection | Misc / Mag Eject | 6/10 | 4/10 |
| `event_0258_01_910095903.wav` | Hollow internal trigger-mechanism click without discharge | Dry fire | Misc / Dry Fire | 7/10 | 3/10 |
| `event_0260_01_747773148.wav` | Heavy clank and spring release ending in a locked state | Bolt locked back after the final shot | Bolt Rack / Empty Lock | 6/10 | 7/10 |
| `event_0262_01_27074555.wav` | Firm two-stage snap into a locked position | Safety engaged | Safety | 5/10 | 4/10 |

## Mechanical profile

```text
Stingray
├─ Unresolved
│  ├─ event_0223 — high-energy composite transient
│  └─ event_0250 — pneumatic / attachment-like transient
├─ Bolt Rack
│  ├─ event_0227 — full manual action cycle
│  └─ event_0260 — empty-magazine bolt lock
├─ Chamber
│  └─ event_0231 — cartridge seating
├─ Reload Insert
│  └─ event_0233 — magazine insertion and lock
├─ Shell Drop
│  ├─ event_0236 — hard-surface contact
│  ├─ event_0248 — soft-surface contact
│  └─ surface_0238 — metallic-surface contact
├─ Selector
│  └─ event_0240 — fire-mode selector
├─ Safety
│  ├─ event_0242 — safety off
│  └─ event_0262 — safety on
└─ Misc
   ├─ event_0246 — winding / adjustment mechanism
   ├─ event_0252 — magazine release
   └─ event_0258 — dry fire
```

## Event-group notes

The files above are representatives. The extracted manifest shows additional
WEM variants in several groups:

- `event_0227`: 9 unique assets;
- `surface_0238`: 8 unique assets;
- `event_0231`, `event_0240`, `event_0242`, `event_0248`, `event_0250`,
  `event_0258`, `event_0260`, and `event_0262`: 3 assets each;
- `event_0223`, `event_0233`, `event_0236`, and `event_0246`: one unique
  representative asset each.

Implementation should randomize within a confirmed event group rather than
treating only the reviewed representative as the complete event.

## Preliminary implementation candidates

### Speaker

- Dry-fire notification: `event_0258`.
- Magazine release and insertion pair: `event_0252` followed by `event_0233`.
- Manual action cycle: `event_0227`, potentially layered with the quieter
  chamber detail from `event_0231`.
- Casing detail: choose the matching surface group only if the game exposes
  reliable material context; otherwise use a conservative random variant.
- Safety and selector details: `event_0242`, `event_0262`, and `event_0240`.
- Do not implement `event_0223` or `event_0250` until their actual gameplay
  actions are known. Their previous unsuppressed/suppressed-shot labels were
  inferred from waveform character and are not valid for this candidate set.

### Haptics

- Manual bolt cycle: `event_0227` (9/10).
- Magazine insertion: `event_0233` (8/10).
- Empty-magazine bolt lock: `event_0260` (7/10).
- Ratcheting texture: `event_0246` (6/10), if its actual gameplay action can
  be identified.
- `event_0223` and `event_0250` retain high raw haptics scores, but are excluded
  from implementation candidates until reclassified.

## Open validation questions

1. Retest Stingray phase-by-phase with isolated runtime events instead of the
   current `start + finish` pair.
2. Determine which event actually belongs between reload start and close.
3. What non-gunshot gameplay actions trigger `event_0223` and `event_0250`?
4. Is `event_0260` the last-round bolt-lock cue, or another reload-state
   action?
5. Is `event_0231` audible independently, or always layered under
   `event_0227`?
6. Do `event_0236`, `event_0248`, and `surface_0238` represent hard, soft, and
   metallic materials, or different ejection/contact stages?
7. What exact weapon interaction triggers `event_0246`?
8. Are `event_0242` and `event_0262` truly opposite safety states?
