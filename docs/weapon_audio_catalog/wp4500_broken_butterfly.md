# Broken Butterfly (`wp4500`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Complete, interpretation requires revision |
| Gameplay validation | Reload and post-shot action identified |
| Speaker implementation | Implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Confirmed |

Candidate assets:
[`../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4500/`](../../speaker/extracted_ui_wavs/rifle_magnum_candidates/wp4500/)

## Interpretation warning

The supplied listening analysis correctly describes the acoustic shapes, but
incorrectly identifies the weapon as a pump-action shotgun. `wp4500` is the
Broken Butterfly magnum. Therefore references to a pump forearm, shotgun
shells, a magazine tube, and a shotgun breech are not treated as established
mechanical meanings.

Until the events are compared with the in-game Broken Butterfly animation,
the two large sliding actions are classified neutrally as **action
open/close**, while insertion sounds remain **reload phases**. They may
represent opening and closing the top-break frame, cylinder/extractor
movement, cartridge insertion, or a speedloader interaction.

Current runtime mapping:

- start: Handcannon `event_0226_01_173506914` reused as cartridge/cylinder
  ejection;
- insert: `event_0195`;
- finish: `event_0193`.
- post-shot action: `event_0197` variants.

Manual gameplay review identified `event_0197` as a post-shot action rather
than a reload-insert family. It has been removed from reload randomization and
now plays about one second after a shot.

Gameplay testing confirmed that the close/cock cue was perceptibly late when
driven by generic reload-state exit. The runtime now schedules `event_0193`
from the final ammunition increase when the cylinder reaches full capacity,
with only a short synchronization offset. Partial reload completion retains
the generic fallback. The latest in-game pass confirmed this feels ideal.

## Identified events

| Representative WAV | Acoustic / mechanical observation | Preliminary gameplay event | Category | Speaker | Haptics |
|---|---|---|---|---:|---:|
| `event_0187_01_12349786.wav` | Quick high-pitched metallic double-click | Small latch, safety, or release control | Control / Latch | 6/10 | 4/10 |
| `event_0191_01_996537474.wav` | Heavy sharp movement rearward with a metallic clack | Revolver action or frame opening | Reload Open | 9/10 | 9/10 |
| `event_0193_01_181396534.wav` | Forward metallic movement ending in a solid lock | Revolver action or frame closing | Reload Close | 9/10 | 8/10 |
| `event_0195_01_13816708.wav` | Hollow sliding scrape ending in a firm click | Cartridge, cylinder, extractor, or loader interaction | Reload Insert A | 8/10 | 6/10 |
| `event_0197_01_259382769.wav` | Hollow mechanical action with friction timing | Mechanical action after a shot | Post-shot Action | 8/10 | 6/10 |
| `event_0199_01_665110711.wav` | Crisp internal mechanical snap | Hammer fall, cocking, trigger reset, or dry fire | Hammer / Trigger | 7/10 | 7/10 |
| `event_0201_01_17198620.wav` | Soft shifting rattle of metal and grip material | Equip, aim, or general weapon handling | Misc / Handling | 5/10 | 3/10 |
| `event_0207_01_19215185.wav` | Deep mechanical lock or heavy insertion | Cylinder/frame lock or major reload seating phase | Reload Lock | 8/10 | 8/10 |
| `event_0209_01_902972499.wav` | Short distinct metallic snap | Latch, hammer, or safety-like control | Control / Latch | 6/10 | 5/10 |

## Preliminary mechanical profile

```text
Broken Butterfly
├─ Reload Open
│  └─ event_0191 — heavy action/frame opening
├─ Reload Close
│  └─ event_0193 — action/frame closing and lock
├─ Reload Insert
│  ├─ event_0195 — reload interaction A
│  └─ event_0197 — reload interaction B
├─ Reload Lock
│  └─ event_0207 — heavy seating or lock
├─ Hammer / Trigger
│  └─ event_0199 — hammer, trigger, or dry-fire snap
├─ Control / Latch
│  ├─ event_0187 — small double-click
│  └─ event_0209 — single mechanical snap
└─ Misc
   └─ event_0201 — equip or handling foley
```

This structure deliberately replaces the supplied `Bolt Rack`, `Chamber`,
`Safety`, and `Selector` labels where those labels depended on the incorrect
shotgun identification.

## Event-group notes

The reviewed files are representatives. The extraction manifest reports:

- `event_0191`, `event_0193`, `event_0195`, and `event_0209`: one unique WEM
  each;
- `event_0187`, `event_0199`, `event_0201`, and `event_0207`: three unique WEM
  variants each;
- `event_0197`: four unique WEM variants.

`event_0195` and `event_0197` are separate Wwise event groups. Similar sound
and inferred purpose do not prove that they form one round-robin container.
They may represent separate reload stages, first/subsequent cartridge logic,
different reload states, or two actions that happen close together.

Likewise, `event_0191` and `event_0193` acoustically form an open/close pair,
but they remain two independently timed events rather than one composite Wwise
event.

## Preliminary implementation candidates

### Speaker

- Strong reload open/close pair: `event_0191` and `event_0193`.
- Reload insertion detail: `event_0195` and `event_0197`, only after their
  separate gameplay timings are identified.
- Heavy lock/seating accent: `event_0207`.
- Hammer or dry-fire cue: `event_0199`.
- Small control details: `event_0187` and `event_0209`, after determining their
  actual animation states.
- Handling foley `event_0201` is low priority and may clutter the mix.

### Haptics

- Action/frame opening: `event_0191` (9/10).
- Action/frame closing: `event_0193` (8/10).
- Heavy reload lock: `event_0207` (8/10).
- Hammer/trigger snap: `event_0199` (7/10), potentially useful as a sharp
  trigger-break impulse.
- Reload interactions: `event_0195` and `event_0197` (6/10).

## Open validation questions

1. Which Broken Butterfly animation phases correspond to `event_0191` and
   `event_0193`: top-break opening/closing, extractor travel, or another
   action?
2. Confirm the provisional one-second delay for the newly identified
   `event_0197` post-shot action.
3. Is `event_0207` the final frame/cylinder lock, a speedloader action, or
   cartridge seating?
4. Does `event_0199` represent hammer cocking, hammer fall, trigger reset, or
   dry fire?
5. What controls or latches trigger `event_0187` and `event_0209`?
6. Confirm that no primary firing-discharge event is expected in this
   mechanical candidate set.
