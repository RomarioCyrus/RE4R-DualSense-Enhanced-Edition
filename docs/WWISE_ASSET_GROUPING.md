# Wwise Asset Grouping

## Confirmed finding

Candidate filenames use this format:

```text
event_<event-index>_<variant-index>_<wem-source-id>.wav
```

Example:

```text
event_0216_01_317025046.wav
event_0222_01_317025046.wav
```

The trailing number (`317025046`) is the Wwise WEM Source ID referenced by the
generated TXTP. It identifies a specific underlying audio asset.

Therefore:

- matching WEM Source IDs mean the events reference the same recording;
- files with matching IDs should also be byte-identical after equivalent
  conversion;
- different WEM Source IDs inside one Random Container are variations of the
  same event/action;
- one event may combine or reuse assets from several other events.

## Confirmed surface-event pattern

Manual review across the current weapon banks found that `surface_*` event
groups consistently contain shell or casing impacts routed for different
materials, including metal, stone, dirt, wood, and other hard or soft
surfaces.

These events are strong controller-speaker candidates because their short,
localized transients remain clear without competing with the main weapon mix.
The material mapping should still be preserved when possible; random playback
without surface context does not reproduce the original Wwise routing.

## Examples

### Riot Gun

```text
event_0216/317025046
event_0222/317025046
```

`event_0222` reuses the bolt-rack asset from `event_0216`. It also references
assets used by the magazine-insertion event, indicating that it is likely a
composite reload event.

### Skull Shaker

```text
event_0209/512036038
event_0233/512036038
```

Both events reuse the exact same bolt-rack recording. They are not separate
round-robin variants unless their event containers also reference additional,
different WEM Source IDs.

## Correct analysis levels

Use three distinct levels:

1. **WEM asset** — one concrete recording, identified by WEM Source ID.
2. **Event group** — a Wwise event/container that may randomly select multiple
   WEM assets.
3. **Mechanical category** — inferred gameplay meaning such as Bolt Rack,
   Chamber, Reload Insert, Shell Drop, Selector, or Safety.

Do not collapse all matching mechanical categories into one asset group.
Preserve the event structure because timing, volume, randomization, layering,
and game-state switches may differ even when events reuse the same WEM.

## Recommended workflow

1. Parse every unnamed TXTP event.
2. Extract its referenced WEM Source IDs.
3. Deduplicate identical WEM IDs inside each event.
4. Build a reverse index:

   ```text
   WEM Source ID -> all referencing events
   ```

5. Listen to each unique WEM asset once.
6. Classify the asset's mechanical sound.
7. Classify each event separately as:
   - random container;
   - layered/composite event;
   - alias/reuse event;
   - surface-switch event.
8. Retain event-to-asset mappings for implementation timing.

## Confidence

- **WEM ID identity:** confirmed/high confidence from TXTP structure and
  byte-hash comparisons.
- **Mechanical meaning:** inferred until validated against gameplay timing.
- **Whether two events are aliases or composites:** determined from the full
  set of WEM references in each TXTP, not from one matching ID alone.
