# Agent Task: Knife Action Sounds

> **STATUS: DONE for v1.0 (2026-07-07).** Full campaign knife set captured,
> routed, live-confirmed, and accepted by the project owner. See
> `WEAPON_AUDIO_STATUS.md` → "Character action sounds" for the final table,
> mechanics (parry suppression + 75 ms defer queue), and session notes.
> Open leftovers for a future session: Fighting Knife (wp5001) / Primal
> Knife (wp5006) swing+draw banks; grab/QTE finisher stab source
> (1828770915's WEMs are whooshes, not the stab); knife throw (not
> captured); water-material detection idea in IDEAS.md.
> Note: this task's premise changed during execution — the 2026-07-01 hit
> set (e115–e139) turned out to be dead in campaign and was replaced, and
> RE4R has no charged attack.

## Goal

Find and deploy sounds for RE4R knife actions (slash, stab, throw, stealth kill,
charged attack, finishing move) to the DualSense controller speaker.

The original knife capture (2026-07-01, Mercenaries, manual windows) covered
parry and generic hit events — events 0115-0141 in `ch_wp_knife_cm.bnk`. That
session targeted *hits during combat*, not the full knife action set. This task
extends coverage to throw, stealth kill, charge, and any other knife-action
events not yet in the router.

---

## Before you start — read mandatory context

Read these files first:
1. `docs/AGENTS.md` — full workflow (capture, extract, deploy, commit rules)
2. `docs/WEAPON_AUDIO_STATUS.md` → "Character action sounds" section

---

## What is already done — do not re-discover

All entries below are already in `src/reframework/autorun/DualSenseEnhanced/wwise_audio_router.lua`.
Do not re-route or re-capture them.

| Event ID | Name in router | Notes |
|---|---|---|
| `238514241` | `knife_e115` | hit sound, 4 WEM variants |
| `432163151` | `knife_e117` | hit sound, 5 WEM variants |
| `1417308040` | `knife_e123` | hit sound, 5 WEM variants |
| `1651038214` | `knife_e125` | hit sound, 2 WEM variants |
| `2078013350` | `knife_e129` | parry/clash B (3/7 parry windows) |
| `3412451043` | `knife_e133` | hit sound, 1 WEM variant |
| `3415105559` | `knife_e135` | parry/clash A (4/7 parry windows) |
| `3627701230` | `knife_e137` | hit sound, 3 WEM variants |
| `3781194556` | `knife_e139` | hit sound, 1 WEM variant |

Confirmed non-hits (removed 2026-07-01, do not re-add):
- `1058140391` (knife_e119) — non-hit, rejected
- `3964128804` (knife_e141) — non-hit, rejected

Bank: `ch_wp_knife_cm.bnk` — this is a *shared* knife bank (no weapon ID gate).
All knife routes have no `weapon_id` field.

---

## Target knife actions to capture

Priority order (most impactful first):

1. **Knife throw** — hold aim + press attack while knife is equipped. Distinctly
   different sound from a slash. Should produce a throw "whoosh" or release click.
2. **Stealth kill (kill from behind)** — approach undetected enemy from behind,
   press attack. Long animation, distinct stabbing sound.
3. **Charged slash** — hold attack button until Leon charges, then release.
   Heavier swing sound than normal slash.
4. **Finishing move** — press attack during enemy stagger/knockdown animation.
   May share a sound with stealth kill or charged — verify by comparing WEMs.
5. **Knife QTE / wrestling** — close-quarters grab by enemy → mash attack.
   Produces rapid quick hits that may map to existing events, but worth checking.

Slash and stab sounds likely correspond to the already-captured e115/e117/e123/
e125/e133/e137/e139 events. Start with the above; only revisit slash/stab if
you find uncovered events in the bank index.

---

## Capture methodology

Knife actions are **not** weapon state machine transitions, so the Sound Event
Diagnostics UI's auto-correlate mode will NOT label windows automatically for
them.

### Recommended: manual window in campaign mode (not Mercenaries)

1. In-game: equip knife, find an enemy group (Chapter 1-1 has abundant enemies).
2. In the Sound Event Diagnostics UI: use **Manual window** (the manual_Ns button).
3. For each action:
   a. Open a manual window (10s).
   b. Perform the action exactly once or twice.
   c. Close the window or let it expire.
   d. Repeat immediately for the same action 2-3 more times for confirmation.
4. Label your captures clearly in your notes (e.g. "manual 1 = throw", "manual 2 = stealth kill").

If a new build of `sound_event_diag.lua` supports knife hooks (e.g. via
`onHitDamageCheck` or a future attack-hook), auto-correlate can be extended —
but do not add hooks to the Lua source without confirming they don't break
existing weapon-state auto-correlate.

### Log file location

```
C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\reframework\data\DualSenseEnhanced\sound_event_ids.log
```

---

## Analysis workflow

```powershell
$py  = "$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe"
$log = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\reframework\data\DualSenseEnhanced\sound_event_ids.log"
$tool = "tools\extract_sounds\wwise_events.py"

# New candidates only (already-routed IDs are suppressed)
& $py $tool analyze $log

# See everything including ROUTED/NOISE/KNOWN-GENERIC
& $py $tool analyze $log --all
```

`analyze` output columns: `event_id | n | kind | wpn tag | window | status`

- `status = NEW in ch_wp_knife_cm.bnk` — actionable, investigate.
- `status = ROUTED -> knife_eNNN` — already in router, skip.
- `status = NOISE` — ambient, skip.
- Any event from `ch_wp_gun_cm.bnk` or `ch_cha0.bnk` — skip unless clearly
  knife-specific (ch_cha0 has stealth-kill *animation* cues that may or may
  not be the audio source).

**Cross-check:** run `analyze --all` and find the event IDs from `ch_wp_knife_cm.bnk`
that are NOT yet marked ROUTED. Those are uncovered knife bank events — they
are the candidates for throw/stealth/charge.

---

## Extraction and listening

```powershell
& $py $tool extract <event_id> --stem knife_throw --out tmp_wav
```

Output: `tmp_wav\knife_throw1.wav`, `tmp_wav\knife_throw2.wav`, ...

Listen to all variants before deciding if the sound is the right action. Knife
sounds are short (0.1-0.5s typically). Reject if:
- Clearly an impact/ricochet with no "action" character
- Identical WEMs to an already-routed event (check WEM IDs in source comment)
- Generic character-movement noise (not knife-specific)

---

## Naming convention

Use descriptive names matching the action, not just the bank event number:
- `knife_throw` — throw whoosh/release
- `knife_stealth` — stealth kill stab
- `knife_charge` — charged swing
- `knife_finish` — finishing move

If a captured event turns out to be another hit variant (shares WEMs with
e115/e117/etc.), name it `knife_eNNN` to stay consistent with existing entries.

---

## Router entry format

```lua
[EVENT_ID] = {
    event = "knife_throw",       -- WAV stem (FindVariants auto-discovers knife_throw1.wav, knife_throw2.wav, ...)
    cooldown = 0.20,             -- adjust based on action duration; throws are ~0.5-1s apart min
    source = "ch_wp_knife_cm.bnk event NNNN, WEMs: XXXXXXX/YYYYYYY; knife throw; live-confirmed YYYY-MM-DD",
},
```

No `weapon_id` field — knife sounds fire regardless of currently-equipped weapon.

Add new entries under the existing knife block, after the last `-- knife_e141 ...` comment.

---

## Deployment

1. WAV files → `src/reframework/data/DualSenseEnhanced/sounds/` (named `knife_throw1.wav` etc.)
2. Router entry → `src/reframework/autorun/DualSenseEnhanced/wwise_audio_router.lua`
3. `tools/deploy.ps1` — mirrors src/ to game folder + SHA256 verifies.
4. Reset Scripts in REFramework.
5. Test in-game: perform the action → sound fires on DualSense speaker.
6. After user live-confirms: run `wwise_events.py manifest` to update
   `tools/extract_sounds/sounds_manifest.json` (so release users can extract the new WAVs).
7. Commit: `audio: add knife throw/stealth/charge speaker sounds`

---

## What to update after confirming

- `docs/WEAPON_AUDIO_STATUS.md` → "Character action sounds" table: add new rows.
- `docs/CHANGELOG.md` → Unreleased section.
- Run `wwise_events.py manifest` + commit updated `sounds_manifest.json`.
