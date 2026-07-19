<img width="1672" height="941" alt="Title" src="https://github.com/user-attachments/assets/54451d55-2c34-479d-9b98-1d7a348ec637" />

# Resident Evil 4 - DualSense Enhanced Edition

Resident Evil 4 Remake on PC ships with only a trimmed-down version of the
PS5's DualSense features. This mod expands that built-in support to PS5 level
and beyond: richer adaptive triggers, far wider haptics coverage, controller
speaker audio, full lightbar/LED logic, and gyro aim - which even the PS5
version does not have. It works alongside the game's own controller output
rather than replacing it.

No extra companion software, replaced game files, or redistributed Capcom
audio required. The required game sounds are extracted locally from your
own installed copy of Resident Evil 4 Remake.

> This is the official release and support repository. Installable packages
> are provided on the Releases page and Nexus Mods. The project source code is
> not distributed.

## Highlights

- **Adaptive Triggers** - tuned L2/R2 resistance for knife, pistols,
  shotguns, rifles, automatic weapons, and magnums. Overall and per-category
  strength use clear Light, Normal, and Strong levels. Empty magazines release
  the firing resistance instead of leaving R2 artificially loaded.
- **Gyro Aim** - native gyro-to-mouse aiming while the weapon is raised, with
  calibration, sensitivity controls, Invert Y, and Precision, PS5 Feel, Fast
  Flicks, and Stable profiles. The enabled-by-default prompt option keeps
  DualSense glyphs visible while aiming. Steam Input is not required.
- **Controller Lighting** - health gradient, damage/parry/grab flashes,
  low-health heartbeat, empty-magazine and reload feedback, menu/death
  handling, five-LED ammunition countdown, and Mic LED effects. RGB control
  can also be returned to the native game lightbar.
- **Controller Speaker Audio** - reloads, weapon draws, dry-fire and last-shot
  cues, knife and combat events, QTE/UI sounds, item pickups, and individual
  healing cues. Automatic DualSense detection and manual endpoint selection
  are supported. Output can be adjusted from 0% to 200%, with a soft limiter
  for boosted levels. A default-off experimental option can move verified
  healing, ordinary knife swings/impacts, and weapon-handling cues exclusively
  to the controller speaker while keeping gunshots, spatial combat sounds,
  parries, silent/stealth kills, and finishers in the main game mix. A
  separate default-off Secondary Output option mirrors normal speaker events
  to a second WASAPI device at the same time as the DualSense - useful for
  streaming setups, virtual audio cables, or extra desktop speakers - with
  its own independent volume. Enhanced Haptics is never mirrored there.
- **Enhanced Haptics (on by default)** - sprint footsteps for Leon, Ada, Ashley,
  Wesker, Luis, Krauser, and Hunk; parry, knife, dry-fire, aim, weapon draw,
  healing, category-specific pickup feedback, and a hot/cold treasure-
  proximity pulse with an adjustable detection distance; menu, inventory, crafting,
  document, and accessory navigation; plus continuous map rotation and zoom
  textures. Every category has an enable switch and Light, Normal, or Strong
  intensity.
- **Self-contained native helpers** - the release includes the required
  controller transport and audio bridge. DSX, DualSenseY, and similar
  controller applications are not required and should remain closed.
- **Privacy-safe support reports** - errors are recorded locally without
  telemetry. Optional Detailed Diagnostics and a sanitized support report are
  available from the mod's Settings section.

## Requirements

- Resident Evil 4 Remake for Steam on Windows.
- [REFramework](https://github.com/praydog/REFramework) for RE4R.
- DualSense or DualSense Edge. USB and DS5Dongle are tested and
  recommended; two controllers connected simultaneously have also been
  tested. Native Bluetooth is not supported -- RE4R itself does not run
  in native Bluetooth mode without an XInput wrapper.
- Steam Input disabled for Resident Evil 4.
- DSX and other applications that take control of the same controller closed.

## Installation

1. Install REFramework for Resident Evil 4 Remake.
2. Download the mod package from the Releases page or Nexus Mods.
3. Install it with Fluffy Mod Manager, or copy the package contents into the
   game directory.
4. Run `DualSenseEnhanced_SETUP_SOUNDS.bat` from the game directory once. It extracts the
   required controller-speaker sounds from your local game archives, generates
   the local audio-derived haptic files, and verifies the result.
5. Connect the controller, disable Steam Input, and start the game. USB is
   the recommended first setup path. Open the REFramework menu with Insert and
   select **DualSense Enhanced**.

Sentinel Nine audio is optional. When its DLC archive is not installed, those
sounds are skipped automatically and base-game setup still completes.

If an audio mod changes `re_chunk` archives, disable it before running
`DualSenseEnhanced_SETUP_SOUNDS.bat`, then enable it again after setup finishes.

## Configuration

- **Features** contains the five main feature switches.
- **Controller Lighting**, **Adaptive Triggers**, **Controller Speaker
  Audio**, **Enhanced Haptics**, and **Gyro Aim** contain their detailed
  controls.
- **Settings** contains autosave, manual save/reload, reset to defaults, and
  support-report controls.

## Troubleshooting and support

Check these first:

1. The controller was connected before starting the game; use USB first when
   troubleshooting.
2. Steam Input is disabled for Resident Evil 4.
3. REFramework loads and its menu opens.
4. `DualSenseEnhanced_SETUP_SOUNDS.bat` completed successfully.
5. DSX and other controller-management applications are closed.

For a reproducible mod error:

1. Open **DualSense Enhanced > Settings > Support**.
2. Enable **Detailed Diagnostics** only if the normal report is insufficient.
3. Reproduce the problem and select **Generate Support Report**.
4. Attach this file to the issue:

   `reframework/data/DualSenseEnhanced/support_report.txt`

The report is generated locally, sends no telemetry, and sanitizes personal
paths, usernames, and email addresses. Disable Detailed Diagnostics after the
test.

## Known limitations in v1.0

- USB and DS5Dongle are tested and recommended, including two controllers
  connected simultaneously. Native Bluetooth is not supported (RE4R does
  not run in native Bluetooth mode without an XInput wrapper).
- Controller speaker audio requires the one-time sound setup step.
- Parry has a generic clash-sound fallback for enemies/animations without a
  dedicated captured sound yet, so a few enemy types share that sound
  instead of a unique one. Weapon audio mapping is ongoing.

## Credits

- **RomarioCyrus** - creator and mod author.
- **Eigeen** - ree-pak-cli / ree-pak-rs.
- **WujekFoliarz** - duaLib.
- **vgmstream contributors** - audio conversion tooling.
- **praydog** - REFramework.
- **FluffyQuack** - Fluffy Mod Manager.

Third-party components retain their own licenses; see
`THIRD_PARTY_LICENSES.txt` in the release package.

This is an unofficial fan project and is not affiliated with or endorsed by
Capcom or Sony Interactive Entertainment. No Capcom or Sony audio assets are
redistributed. Original AI-generated healing cues and synthesized haptic tones
are included; required game audio is extracted locally from the user's own
installation.

## Support development

If you enjoy the mod, you can optionally support future development:

<a href="https://ko-fi.com/romariocyrus">
  <img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" alt="Support RomarioCyrus on Ko-fi" height="36">
</a>
