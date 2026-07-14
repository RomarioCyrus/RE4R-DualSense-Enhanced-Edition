# Killer7 (`wp4501`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete, interpretation requires revision |
| Gameplay validation | Start and insert manually identified; retest pending |
| Speaker implementation | Corrected two-phase mapping |
| Haptics implementation | Not implemented |
| Physical controller test | Not tested |

Candidate assets:
[`../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4501/`](../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4501/)

## Interpretation warning

Killer7 is a magazine-fed semiautomatic magnum handgun. The supplied analysis
correctly identifies many acoustic shapes, but its references to an
under-barrel mechanism, alternate heavy action, loose rounds entering an
auxiliary loading gate, and a secondary shell type do not match the weapon.

The current candidate sets are also not expected to contain primary gunshot
audio. Manual review corrected `event_0228` to hammer cock after reload and
`event_0236` to the post-shot bolt/slide cycle.

Current runtime mapping:

- start/magazine extraction: `event_0238` variants;
- insert/end: `event_0224` variants;
- no generic finish cue.

The old start was incorrect and the old finish produced an unrelated sound.
Both have been removed from runtime emission.

## Identified events

| Representative WAV | Acoustic / mechanical observation | Preliminary gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0210_01_756497617.wav` | Sharp localized metallic click with a release transient | Magazine release catch | Magazine Release | 7/10 | 6/10 |
| `event_0212_01_338924612.wav` | Low-mid handling resonance, fabric movement, and light metal clink | Aim, equip, or posture adjustment | Misc / Handling | 3/10 | 4/10 |
| `event_0214_01_511026552.wav` | Deep insertion thud followed by an internal lock | Magazine seated in the grip | Magazine Insert | 6/10 | 8/10 |
| `event_0216_01_151545836.wav` | High-friction metal movement rearward ending at a hard stop | Slide pulled rearward | Slide Rearward | 8/10 | 9/10 |
| `event_0218_01_422967852.wav` | Fast forward metal slam with a ringing decay | Slide released forward / chambering | Slide Forward / Chamber | 9/10 | 9/10 |
| `event_0220_01_542468377.wav` | Light two-stage detent click | Safety or another small control | Safety / Control | 8/10 | 5/10 |
| `event_0224_01_815442869.wav` | Tight isolated mechanical insertion click | Magazine insertion at reload end | Magazine Insert | 7/10 | 6/10 |
| `event_0226_01_314123221.wav` | Bright brass impact and bounce | Cartridge case contacting a rigid surface | Shell Drop | 10/10 | 3/10 |
| `event_0228_01_426892030.wav` | Hollow percussive mechanical transient | Hammer cock after reload | Hammer Cock | 5/10 | 8/10 |
| `event_0232_01_32408838.wav` | Muted handling rustle and friction | Holster, aim, or lowered-weapon transition | Misc / Handling | 2/10 | 3/10 |
| `event_0236_01_878112439.wav` | Strong mechanical cycle following discharge | Post-shot bolt/slide cycle | Bolt Rack / Post-shot | 4/10 | 10/10 |
| `event_0238_01_1054751906.wav` | Heavy hollow movement with a dense metallic strike | Magazine extraction / reload start | Magazine Extract | 9/10 | 2/10 |
| `event_0242_01_1066306132.wav` | Rhythmic spring-loaded metallic click under tension | Unknown loading or weapon-adjustment action | Unresolved Mechanism 1 | 7/10 | 6/10 |
| `event_0244_01_1012888036.wav` | Heavy gritty sliding movement with sustained friction | Unknown heavy action moving in one direction | Unresolved Mechanism 2 | 8/10 | 8/10 |
| `event_0246_01_635025450.wav` | Solid immediate metallic closure and latch | Unknown heavy action closing or locking | Unresolved Mechanism 3 | 8/10 | 7/10 |

## Preliminary mechanical profile

```text
Killer7
├─ Magazine
│  ├─ event_0210 — magazine release
│  └─ event_0214 — magazine insertion and lock
├─ Slide / Chamber
│  ├─ event_0216 — slide rearward
│  └─ event_0218 — slide forward / chambering
├─ Hammer / Trigger
│  ├─ event_0224 — internal lockwork click
│  └─ event_0228 — hammer cock after reload
├─ Post-shot Action
│  └─ event_0236 — bolt/slide cycle after shot
├─ Safety / Control
│  └─ event_0220 — small detent control
├─ Shell Drop
│  └─ event_0226 — brass contact
├─ Handling
│  ├─ event_0212 — handling layer A
│  └─ event_0232 — handling layer B
└─ Unresolved
   ├─ event_0238 — heavy dropped-object interaction
   ├─ event_0242 — tensioned mechanical sequence
   ├─ event_0244 — heavy sliding sequence
   └─ event_0246 — heavy closing / locking sequence
```

## Event-group notes

The reviewed files are representatives. The extraction manifest reports:

- `event_0210`, `event_0224`, `event_0226`, `event_0232`, `event_0236`,
  `event_0238`, and `event_0246`: three unique WEM variants each;
- `event_0214`: two unique WEM variants;
- `event_0244`: four unique WEM variants;
- `event_0216`, `event_0220`, `event_0228`, and `event_0242`: one unique WEM
  each;
- `event_0212` and `event_0218`: three extracted references but only one
  unique WEM in each event group.

`event_0212` and `event_0232` have similar handling characteristics but are
separate Wwise event groups. Similar frequency content does not establish a
shared round-robin relationship.

`event_0216` and `event_0218` plausibly form a rearward/forward slide sequence,
but remain independently timed Wwise events.

`event_0242`, `event_0244`, and `event_0246` may form a sequence, but the
proposed auxiliary mechanism does not exist on Killer7. Their actual source
animation must be identified before implementation.

## Preliminary implementation candidates

### Speaker

- Magazine release and insertion: `event_0210` followed by `event_0214`.
- Slide rearward and forward: `event_0216` followed by `event_0218`.
- Hammer/trigger detail: `event_0224`.
- Hammer cock after reload: `event_0228`.
- Post-shot mechanical cycle: `event_0236`.
- Brass contact: randomized variants from `event_0226`.
- Safety/control click: `event_0220`, after confirming its actual state.
- Handling events `event_0212` and `event_0232` are low priority.
- Do not implement `event_0238` or the `event_0242–0246` sequence until they
  are reclassified.

### Haptics

- Slide rearward and forward: `event_0216` and `event_0218` (9/10).
- Magazine insertion: `event_0214` (8/10).
- Unresolved heavy slide: `event_0244` (8/10), excluded until identified.
- Hammer/trigger and magazine release: `event_0224` and `event_0210` (6/10).
- Post-shot bolt/slide cycle: `event_0236` (10/10).
- Hammer cock after reload: `event_0228` (8/10).

## Open validation questions

1. Are `event_0216` and `event_0218` the standard reload slide-open and
   slide-release phases?
2. Does `event_0220` represent Killer7's safety, another control, or an
   animation-only lock?
3. Is `event_0224` hammer cocking, trigger reset, dry fire, or another lockwork
   action?
4. What object or component produces `event_0238`?
5. Which real Killer7 animation produces the apparent `event_0242–0246`
   mechanical sequence?
