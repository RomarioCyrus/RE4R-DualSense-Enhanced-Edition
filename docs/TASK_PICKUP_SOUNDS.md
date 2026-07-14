# TASK: Item Pickup Speaker Sounds

**STATUS: COMPLETE** (commit `5827578`, 2026-07-07)

## Goal

Play game-accurate sounds through the DualSense controller speaker when Leon
picks up items (ammo, healing, grenades/resources, treasure, pesetas, key
items).

## Wwise Architecture

All item pickup sounds route through a single Wwise event:

```
play_CH_GUI_INVENTORY_UNIQUE_01   (event hash 1993283240)
  └── event index 0608 in ch_ui_ingame.bnk
       ├── switch group ch_swg_inventory_get   (hash 1126121208)
       │     ├── sws_file  (2542587695) — document/file items
       │     ├── sws_item  (3784438988) — general items (ammo, healing, treasure …)
       │     ├── sws_quest (4140822417) — key items
       │     └── sws_wep   (3431959819) — weapons
       └── sub-switch (varies by sws branch)
             sws_item sub-switch: ch_swg_inventory_get_item_id (hash 1701241282)
             sws_quest sub-switch: unknown (hash 4228267689)
```

**All 49 WEMs are pre-extracted** in
`speaker/extracted_ui_wavs/pickup_event_0608/`.  
Source bank: `ch_ui_ingame_media.sbnk.1.x64` in `re_chunk_000.pak`.

> Note: These events do NOT appear in `soundlib.SoundManager.postRequestInfo`
> log captures — they are dispatched by a different Wwise path. Discovery was
> done by decoding Wwise FNV-1 hashes and cross-referencing the pre-extracted
> manifest.csv.

## Wwise FNV-1 Hash Algorithm

Wwise uses FNV-1 (**multiply-first**, not FNV-1a):

```csharp
uint h = 2166136261;
foreach (char c in name.ToLower())
    h = h * 16777619u ^ (byte)c;
```

FNV-1a (`h = (h ^ byte) * prime`) gives wrong values.

## sm-Category to Switch Value Mapping

| sm-category prefix | Wwise sub-switch value | Item type |
|---|---|---|
| sm70 | 2243173724 / 2243173726 | ammo |
| sm71 | 725949002 / 742726716 | healing (herbs / spray) |
| sm74_538 | 3515363129 | metal/resources/gunpowder |
| sm74_554 | 3548918291 | pesetas (small amount) |
| sm77 | 835149310 / 835149311 | pesetas variants |
| sm75 | (unknown) | unidentified |
| sws_quest | 3344420081 | key items |
| sws_wep | various | weapons (not used for our stems) |

Treasure items (spinel etc.) share sub-switch range 3465030267 within sws_item.

## Deployed Sound Stems

14 WAV files deployed to `src/reframework/data/DualSenseEnhanced/sounds/`:

| Stem | WEM ID | Category |
|---|---|---|
| pickup_ammo1.wav | 36691463 | ammo pickup |
| pickup_ammo2.wav | 353251818 | ammo pickup (variant) |
| pickup_healing1.wav | 1004557122 | herb pickup |
| pickup_healing2.wav | 176534758 | herb/spray pickup |
| pickup_treasure1.wav | 22654158 | treasure pickup |
| pickup_treasure2.wav | 406294708 | treasure pickup (variant) |
| pickup_metal1.wav | 180017805 | metal/resource/grenade pickup |
| pickup_metal2.wav | 321203379 | metal/resource/grenade pickup (variant) |
| pickup_pesetas1.wav | 98248705 | pesetas (base) |
| pickup_pesetas2.wav | 592087920 | pesetas (small amount) |
| pickup_pesetas3.wav | 712012922 | pesetas (variant) |
| pickup_key_item1.wav | 147472790 | key item pickup |
| pickup_key_item2.wav | 628594652 | key item pickup (variant) |
| pickup_key_item3.wav | 1004331266 | key item pickup (variant) |

Identity fallback in `SoundMap.Resolve()` finds these automatically — no
explicit `_map` entries required.

## Lua Routing (audio_feedback.lua)

`PICKUP_EVENT_BY_CATEGORY` maps item category to event stem:

```lua
local PICKUP_EVENT_BY_CATEGORY = {
    ammo       = "pickup_ammo",
    healing    = "pickup_healing",
    resources  = "pickup_metal",
    grenades   = "pickup_metal",
    knives     = "pickup_metal",
    valuables  = "pickup_treasure",
    key_items  = "pickup_key_item",
}
```

Per-item overrides in `PICKUP_EVENT_BY_ID` handle pesetas (item ID 124000000)
and Small Key.

## Bug Fixed: SoundMap.cs Stale Aliases

Before this task, `SoundMap._map` contained explicit entries pointing to
non-existent WAV stems:

```csharp
["pickup_ammo"]    = new[] { "ammo_pickup" },           // no such file
["pickup_treasure"] = new[] { "treasure_regular_pickup" }, // no such file
// etc.
```

These blocked the identity fallback. All stale pickup aliases were removed;
the bridge was rebuilt (`publish-fixed` output).

## Source Files

| File | Purpose |
|---|---|
| `speaker/extracted_ui_wavs/pickup_event_0608/` | 49 source WAVs + manifest.csv |
| `speaker/extracted_ui_wavs/INVENTORY_PICKUP_EVENT_MAP.csv` | sm-category to WEM mapping |
| `tools/extract_sounds/sounds_manifest.json` | extraction manifest (14 entries added) |
| `src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua` | Lua routing |
| `speaker/DualsenseAudioBridge/SoundMap.cs` | C# sound resolution (stale aliases removed) |

## Known Limitations / Future Work

- `sm75_*` items not identified — unknown item type, no WAV assigned.
- Weapon pickup sounds (`sws_wep`) not routed — weapons are handled by the
  dedicated weapon-equip flow.
- Treasure sub-categories (special vs. regular) not distinguished — both use
  `pickup_treasure`. See treasure fix task for details.
