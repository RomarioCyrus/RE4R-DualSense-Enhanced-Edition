# Agent Task: Find Wwise Event IDs for Item Pickups

> **Scope**: discovery only — find the event IDs, extract WAVs to `tmp_wav\`,
> report findings. Do NOT wire routes in `wwise_audio_router.lua` or deploy
> WAVs to `src/`. A separate task (`TASK_PICKUP_SOUNDS.md`) covers deployment.

## Context

The DualSense mod plays sounds on the controller speaker when Leon picks up
items. The hook is already wired in
`src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua` (function
`install_pickup_hooks`, around L806). It intercepts `chainsaw.DropItem.onAcceptPickup`,
resolves the item's category, and calls `emit("pickup_ammo")` /
`emit("pickup_treasure")` etc.

The problem: no WAV files exist for those stem names. Only `pickup_sound.wav`
(a legacy test file) is present in `src/.../sounds/`. To create the WAVs we
need the Wwise event IDs that fire during item pickups so we can extract audio
from the game's pak files.

**Your job:** capture a session, identify the event IDs, extract the audio,
and report which IDs are usable for which pickup category.

---

## Read first

```
docs/AGENTS.md       ← machine paths, deploy rules, Python/tool paths
docs/TASK_PICKUP_SOUNDS.md  ← full context on what stems are needed and why
```

Key paths (also in AGENTS.md):
- **Repo root**: `$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project\`
- **Python**: `$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe`
- **Wwise tool**: `tools\extract_sounds\wwise_events.py` (run from repo root)
- **Sound event log**: `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\reframework\data\DualSenseEnhanced\sound_event_ids.log`
- **Deploy script**: `tools\deploy.ps1`

---

## Step 1 — Enable pickup diagnostics

In `src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua`, line 47:
```lua
AUDIO.pickup_debug_enabled = false
```
Change to `true`. This makes the mod log every pickup to the REFramework
Monitor panel: item name, category, resolved stem, event played.

Deploy and ask the user to Reset Scripts in REFramework before starting the
capture.

```powershell
Set-Location "$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project"
& tools\deploy.ps1
```

---

## Step 2 — Capture session (user does this in-game)

Tell the user to:
1. Open a **manual window** (10–15 s) in Sound Event Diagnostics UI.
2. Pick up **one or two items** of that category.
3. Close the window or let it expire.
4. Repeat for each category in the list below.

Categories to cover (in order, each in its own manual window):

| Window | Action | Category → expected stem |
|---|---|---|
| 1 | Pick up **handgun ammo** from a barrel or enemy drop | `ammo` → `pickup_ammo` |
| 2 | Pick up a **green herb** | `healing` → `pickup_healing` |
| 3 | Pick up a **hand grenade** | `grenades` → `pickup_metal` |
| 4 | Pick up **gunpowder** or **Resources (L)** | `resources` → `pickup_metal` |
| 5 | Pick up a **spinel** or **gem** (enemy drop or map) | `valuables` → `pickup_treasure` |
| 6 | Pick up **pesetas** (gold coins from a crate or enemy) | ID-specific → `pickup_pesetas` |
| 7 | Pick up any **key item** (Hexagonal Emblem, keycard, etc.) | `key_items` → currently no sound |

If an opportunity for a **combat knife floor pickup** arises, add an 8th
window. That covers the `knives` category (also mapped to `pickup_metal`).

**Important:** enemy-drop ammo is the easiest target — most enemies drop it.
Check that the sound event log is being written (file modification time updates
after each window close).

---

## Step 3 — Analyze the log

```powershell
Set-Location "$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project"
$py  = "$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe"
$log = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\reframework\data\DualSenseEnhanced\sound_event_ids.log"

& $py tools\extract_sounds\wwise_events.py analyze $log
& $py tools\extract_sounds\wwise_events.py analyze $log --all
```

**What to look for:**
- Event IDs that appear **only inside pickup windows** (window label = the
  window you opened just before picking up the item).
- IDs marked `UNKNOWN bank` are expected — `event_bank_index.json` only covers
  weapon banks; pickup sounds live in a different bank.
- IDs marked `NOISE` (fire constantly regardless of window) → skip.
- IDs marked `ROUTED` → already handled by the weapon router → skip unless
  they also appear in pickup windows (would be a coincidence worth noting).

Cross-reference windows: if the same event ID appears in the ammo window AND
the herb window, it is probably a single generic pickup jingle shared across
categories. That is fine — document it and extract once; the audio_feedback.lua
mapping will route it to different stems.

---

## Step 4 — Extract candidates

For each candidate event ID:

```powershell
$py = "$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe"
Set-Location "$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project"

& $py tools\extract_sounds\wwise_events.py extract <EVENT_ID> --stem pickup_candidate_<N> --out tmp_wav
```

The extractor searches all `.bnk` files in the game pak and prints the source
bank name on success. Note that bank name — it will need to be added to
`tools/extract_sounds/DSE_Required_Banks.list` in the deployment task.

Listen to `tmp_wav\pickup_candidate_<N>*.wav` (ask the user to audition them).
Reject if:
- Clearly ambient / UI beep unrelated to pickup
- Silent or 0-length
- More than ~1.5 s long (probably a music sting, not a pickup cue)

---

## Step 5 — Report findings

After extraction, compile and report:

### Per-category table

| Category | Stem | Event ID(s) seen in window | Bank | WAV files extracted | Notes |
|---|---|---|---|---|---|
| ammo | pickup_ammo | `XXXXXXXXX` | `ch_???.bnk` | `pickup_candidate_1*.wav` | ... |
| healing | pickup_healing | `XXXXXXXXX` | ... | ... | ... |
| grenades | pickup_metal | (same as resources?) | ... | ... | shared event? |
| resources | pickup_metal | ... | ... | ... | ... |
| valuables | pickup_treasure | ... | ... | ... | ... |
| pesetas | pickup_pesetas | ... | ... | ... | ... |
| key_items | pickup_key_item | ... | ... | ... | no stem wired yet |

### Additional answers needed

1. **Is there one shared pickup event for all categories, or per-category events?**
   (If shared: one WAV source for everything; if per-category: distinct sounds.)

2. **What bank do the pickup events come from?**
   (Likely `ch_ui_ingame.bnk`, `ch_se.bnk`, or a dedicated item bank.)

3. **How many WEM variants per event?**
   (If 3+, pick the best 1–3 for the stem.)

4. **Does any window show no new event IDs?**
   (Would mean the pickup fires no Wwise event and we need a different hook or
   a Lua-side synthetic sound instead of an extracted WAV.)

---

## Step 6 — Cleanup (before finishing)

Reset `AUDIO.pickup_debug_enabled` back to `false` in `audio_feedback.lua` L47,
deploy, ask user to Reset Scripts.

Do NOT commit `AUDIO.pickup_debug_enabled = true` — it floods the Monitor log
during normal play.

---

## What this task does NOT do

- Does not add entries to `wwise_audio_router.lua` (pickup sounds go through
  `audio_feedback.lua`'s `emit()`, not the Wwise router).
- Does not copy WAVs to `src/reframework/data/DualSenseEnhanced/sounds/`.
- Does not update `sounds_manifest.json`.

Those steps are in `docs/TASK_PICKUP_SOUNDS.md`, which picks up from this
task's findings.
