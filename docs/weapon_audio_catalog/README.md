# Weapon Audio Catalog

Structured listening notes for RE4R weapon Wwise banks.

Each weapon has its own Markdown profile. Profiles preserve three separate
levels:

1. WEM asset / representative WAV;
2. Wwise event group;
3. inferred mechanical or gameplay action.

Matching filename suffixes are WEM Source IDs. See
[`../WWISE_ASSET_GROUPING.md`](../WWISE_ASSET_GROUPING.md) before treating
matching files as separate variations.

Manual listening corrections are tracked in
[`MANUAL_REVIEW.md`](MANUAL_REVIEW.md) and take precedence over preliminary
automated classifications.

## Candidate-set scope

The current weapon candidate sets were prepared primarily for mechanical,
reload, and handling analysis. They are not generally expected to contain the
primary gunshot audio.
If isolated listening makes an asset resemble an unsuppressed or suppressed
shot, classify it as **Unresolved / Mechanical Composite** until its actual
in-game event is identified. Do not add a `Fire` category from waveform
character alone.

## Status legend

- **Analyzed** — WAVs were reviewed and assigned preliminary meanings.
- **Gameplay-validated** — timing and meaning were checked against the game.
- **Implemented** — the event is emitted by the mod.
- **Controller-validated** — physical DualSense speaker or haptics output was
  tested.

An analyzed profile is not automatically gameplay-validated or implemented.

## Weapon profiles

| Bank | Weapon | Class | Profile status | Runtime status |
|---|---|---|---|---|
| `wp4000` | [SG-09 R](wp4000_sg09r.md) | Handgun | Gameplay-validated | Implemented and controller-tested |
| `wp4001` | [Punisher](wp4001_punisher.md) | Handgun | Analyzed | Conservative prototype; test pending |
| `wp4002` | [Red9](wp4002_red9.md) | Handgun | Analyzed | Conservative prototype; test pending |
| `wp4003` | [Blacktail](wp4003_blacktail.md) | Handgun | Analyzed | Conservative prototype; test pending |
| `wp4004` | [Matilda](wp4004_matilda.md) | Handgun | Analyzed | Conservative prototype; test pending |
| `wp4100` | [W-870](wp4100_w870.md) | Shotgun | Reload/pump validated; last-shot branch added | Implemented; branch retest pending |
| `wp4101` | [Riot Gun](wp4101_riot_gun.md) | Shotgun | Analyzed; reload validated | Implemented and controller-tested |
| `wp4102` | [Striker](wp4102_striker.md) | Shotgun | Gameplay-validated | Implemented and controller-tested |
| `wp4400` | [SR M1903](wp4400_sr_m1903.md) | Rifle | Post-shot and last-shot behavior identified | Updated branch; retest pending |
| `wp4401` | [Stingray](wp4401_stingray.md) | Rifle | Regression found | Current mapping broken; needs phase retest |
| `wp4402` | [CQBR](wp4402_cqbr.md) | Assault rifle | Three reload phases identified | Updated; retest pending |
| `wp4500` | [Broken Butterfly](wp4500_broken_butterfly.md) | Magnum | Reload and post-shot phases identified | Updated; retest pending |
| `wp4501` | [Killer7](wp4501_killer7.md) | Magnum | Start/insert identified | Corrected; retest pending |
| `wp4502` | [Handcannon](wp4502_handcannon.md) | Magnum | Reload and post-shot phases identified | Updated; retest pending |
| `wp6001` | [Skull Shaker](wp6001_skull_shaker.md) | Shotgun | Start/end reclassified; post-shot identified | Updated; retest pending |

## Archived source catalogs

The original combined shotgun notes remain in
[`../../speaker/extracted_ui_wavs/shotgun_reload_candidates/SHOTGUN_EVENT_CATALOG.md`](../../speaker/extracted_ui_wavs/shotgun_reload_candidates/SHOTGUN_EVENT_CATALOG.md).
The individual profiles above are now the maintained versions.

## Curated listening catalog

Runtime WAV copies for manual listening are cataloged under
[`../../speaker/weapon_sound_catalog_v2/`](../../speaker/weapon_sound_catalog_v2/).
This directory is intentionally separate from the live flat runtime
`sounds/` folder because `DualsenseAudioBridge` resolves event names directly
to WAV families. The catalog groups files by weapon and by confirmed order:

- `reload/` for confirmed or partially confirmed reload-order sounds;
- `misc/` for confirmed non-reload weapon sounds, such as delayed post-shot
  actions;
- `unconfirmed/` for rejected, unused, regressed, prototype, or not-yet-mapped
  files.

Use
[`../../speaker/weapon_sound_catalog_v2/MANIFEST.csv`](../../speaker/weapon_sound_catalog_v2/MANIFEST.csv)
to trace each friendly catalog filename back to the flat runtime WAV and the
original extracted source WAV.

## Runtime Wwise ID Findings

Runtime Wwise event IDs are treated as gameplay evidence only after an
in-game/controller test. The first confirmed route is SG-09 R dry fire:

| Weapon | Wwise event ID | Hook | Runtime event | Status |
|---|---|---|---|---|
| SG-09 R (`wp4000`) | `2330373695` | `soundlib.SoundManager.postRequestInfo` | `wp4000_dry_fire` | Confirmed, synchronized controller-speaker playback |

## File naming

Use:

```text
wp<bank-id>_<weapon-name>.md
```

Start new profiles from [`_TEMPLATE.md`](_TEMPLATE.md).
