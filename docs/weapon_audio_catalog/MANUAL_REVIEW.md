# Weapon Audio Manual Review

Manual listening corrections take precedence over automated acoustic
classification in the per-weapon profiles.

## Confirmed global findings

- `surface_*` assets consistently represent shell or casing impacts routed by
  material.
- Observed materials include hard floor, metal grating, stone, dirt, and wood.
- Shell Drop classification is highly reliable across the reviewed weapons.
- Bolt Rack, Chamber, Reload Insert, Magazine Insert, and Magazine Release
  classifications are generally reliable.
- Fire, Safety, Selector, Misc, and unique weapon-specific mechanics require
  manual or in-game verification.
- Numeric filename suffixes are WEM Source IDs. Identical IDs identify reuse of
  the same underlying recording.
- Separate Wwise event folders can reuse WEMs or compose several actions.

## Corrected events

| Bank | Weapon | Event | Manual classification | Status |
|---|---|---|---|---|
| `wp4000` | SG-09 R | `event_0232` | Magazine release | Plausible; gameplay timing pending |
| `wp4000` | SG-09 R | `event_0234` | Magazine extraction | Plausible; gameplay timing pending |
| `wp4000` | SG-09 R | `event_0238` | Magazine alignment / initial insertion | Plausible; gameplay timing pending |
| `wp4000` | SG-09 R | `event_0240` | Magazine seated and locked | Strong manual candidate |
| `wp4000` | SG-09 R | `event_0244` | Slide rearward | Strong manual candidate |
| `wp4000` | SG-09 R | `event_0246` | Cartridge feed / chambering | Plausible; gameplay timing pending |
| `wp4000` | SG-09 R | `event_0248` | Slide forward / lock | Strong manual candidate |
| `wp4000` | SG-09 R | `event_0252` | High-energy unresolved transient; not accepted as Fire | Needs verification |
| `wp4400` | SR M1903 | `event_0237` | Metal impact / possible Shell Drop | Manual correction; exact source pending |
| `wp4400` | SR M1903 | `event_0252` | Raise weapon / enter aim state | Manual correction |
| `wp4400` | SR M1903 | `event_0254` | Scope magnification / range adjustment | Manually confirmed |
| `wp4402` | CQBR | `event_0235` | Possible post-shot bolt cycle or other high-energy event | Needs verification |
| `wp4501` | Killer7 | `event_0228` | Hammer cock after reload | Manual correction |
| `wp4501` | Killer7 | `event_0236` | Bolt/slide cycle after shot | Manual correction |
| `wp4502` | Handcannon | `event_0228` | Weapon equip or hammer impact | Needs verification |

## Implementation guidance

- Treat `surface_*` as high-priority controller-speaker candidates.
- Preserve material-specific variants when the game exposes reliable surface
  context.
- If material context is unavailable, avoid implying that random selection
  reproduces the original surface routing.
- Prefer manually corrected meanings over waveform-only AI labels.
- Keep unresolved events out of runtime mappings until their gameplay timing
  is observed.
