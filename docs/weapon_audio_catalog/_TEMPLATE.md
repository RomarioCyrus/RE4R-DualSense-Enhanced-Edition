# Weapon Name (`wp0000`)

## Status

| Stage | Status |
|---|---|
| Audio analysis | Not started |
| Gameplay validation | Not tested |
| Speaker implementation | Not implemented |
| Haptics implementation | Not implemented |
| Physical controller test | Not tested |

Candidate assets:
`../../speaker/extracted_ui_wavs/<candidate-directory>/wp0000/`

## Identified events

| Representative WAV | Mechanical action | Likely gameplay event | Category | Speaker | Haptics | Confidence |
|---|---|---|---|---:|---:|---|
| `event_0000_01_000000000.wav` | Description | Description | Category | 0/10 | 0/10 | Low |

## Mechanical profile

```text
Weapon Name
├─ Bolt Rack
├─ Chamber
├─ Reload Insert
├─ Shell Drop
├─ Selector
├─ Safety
├─ Trigger / Action
├─ Unresolved
└─ Misc
```

## Implementation candidates

- Reload start:
- Ammunition inserted:
- Reload completion:
- Post-shot action:
- Optional speaker details:
- Potential haptics layers:

## Validation notes

- Event meanings are inferred from isolated WAVs until checked in gameplay.
- Current candidate sets are not expected to contain primary gunshot audio;
  do not infer `Fire` from an explosive or pneumatic waveform alone.
- Record reused WEM Source IDs and composite events here.
- Record actual hook, timing, and physical controller results when implemented.
