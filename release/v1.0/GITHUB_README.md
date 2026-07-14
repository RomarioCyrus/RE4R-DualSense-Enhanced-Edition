# Resident Evil 4 - DualSense Enhanced Edition

Unofficial DualSense enhancement mod for Resident Evil 4 Remake (PC).
Drives the controller natively - no DSX, no Steam Input, no replaced game
files, and no redistributed Capcom assets.

> This file is the GitHub-facing README draft for the public release repo.
> The Nexus page copy lives in `NEXUS_PAGE.md`; the in-package readme is the
> top-level `README.txt`.

## Features

- **Adaptive triggers** - per-weapon L2/R2 resistance profiles with global
  intensity presets (Off / Native Only / Light / Enhanced / Strong).
- **Gyro aim** - native gyro-to-mouse aiming with startup calibration,
  presets (Precision, PS5 Feel, Fast Flicks, Stable), and L2-gated
  activation. Works without Steam Input.
- **Lightbar feedback** - health gradient, damage/parry/grab flashes,
  low-health heartbeat, empty-magazine pulse, menu/death handling, and a
  one-click handover back to the game's native lightbar.
- **Player indicator LEDs** - low-ammo countdown on the 5 LEDs under the
  touchpad.
- **Mic LED** - pulses in lockstep with the lightbar on empty ammo and
  critical health.
- **Controller speaker audio** - weapon reloads, draws, dry-fire, last-shot
  cues, knife hits, QTE/inventory UI sounds, and item pickups play through the
  controller speaker. Healing items have distinct cues for herbs, spray,
  three egg types, three fish types, viper, and rhinoceros beetle. The custom
  non-spray healing cues are original AI-generated mod assets; required game
  audio is extracted locally from the user's own files.
- **Native speaker initialization** - the mod configures the DualSense speaker
  route itself, so DSX, DualSenseY, and other companion controller software
  are not required.
- **Enhanced Haptics (opt-in)** - sprint-only footsteps and companion pulses
  for parry, knife, dry-fire, aim, draw, healing, and pickups through the
  DualSense actuators. Includes a global strength slider plus
  Soft/Normal/Strong levels and an Off toggle for each category. Footsteps are intentionally subtler than action
  feedback. Off by default.

## Support Development

If you enjoy the mod and want to support continued development, testing, and
future DualSense features:

<a href="https://ko-fi.com/romariocyrus">
  <img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" alt="Support romariocyrus on Ko-fi" height="36">
</a>

## Requirements

- Resident Evil 4 Remake (Steam, Windows).
- [REFramework](https://github.com/praydog/REFramework) (latest RE4R build).
- DualSense or DualSense Edge controller over **USB**.
- Steam Input disabled for RE4R; no DSX or other controller tools running.

## Installation

1. Install REFramework.
2. Install the release package with Fluffy Mod Manager, or copy its contents
   into the game folder.
3. Run `setup_sounds.bat` from the game folder once. It extracts the required
   controller-speaker sounds from your local `re_chunk_000.pak` (and the
   Sentinel Nine DLC pak when present) into
   `reframework/data/DualSenseEnhanced/sounds/`, generates the local
   audio-derived haptic files, and verifies the result.
   Sentinel Nine audio is skipped automatically when its DLC pak is absent;
   the rest of sound setup still completes normally.
4. Start the game; settings are in the REFramework menu under
   **DualSense Enhanced**.

If audio mods replace or modify `re_chunk` pak files, disable them before
running `setup_sounds.bat` and re-enable them afterwards.

## Architecture

- **REFramework Lua** (`reframework/autorun/DualSenseEnhanced*`) detects game
  state (HP, ammo, weapon, events) and writes feedback commands.
- **DualSenseEnhancedTransport.exe** owns the native controller output path -
  adaptive triggers, gyro input, player indicators, Mic LED, and optional
  lightbar - through a modified [duaLib](https://github.com/WujekFoliarz/duaLib)
  and [HIDAPI](https://github.com/libusb/hidapi).
- **DualsenseAudioBridge.exe** plays extracted WAV cues on the controller
  speaker and four-channel haptic content through WASAPI (NAudio). It also
  performs the one-shot native speaker-route initialization, and launches and
  exits together with the game via a small REFramework plugin launcher.
- **setup_sounds.ps1** performs targeted extraction with
  [ree-pak-cli](https://github.com/eigeen/ree-pak-rs) and converts audio with
  [vgmstream](https://github.com/vgmstream/vgmstream), driven by a committed
  manifest of required Wwise banks/WEM IDs.

## Known issues (v1.0)

- Gyro aim injects mouse movement, so the game may show keyboard/mouse
  prompts while gyro is active.
- Controller speaker audio requires the one-time `setup_sounds.bat` run.
- v1.0 targets USB; Bluetooth, DSX compatibility modes, DS5 dongles, and
  multi-controller setups are not yet claimed as supported.

## Credits

- **eRo** - mod author.
- **Eigeen** - ree-pak-cli / ree-pak-rs (MIT License).
- **WujekFoliarz** - duaLib (MIT License).
- **vgmstream contributors** - audio conversion tooling.
- **praydog** - REFramework.
- **FluffyQuack** - Fluffy Mod Manager.

## License and disclaimers

Third-party components keep their own licenses - see
`THIRD_PARTY_LICENSES.txt`. This project is unofficial and is not affiliated
with, endorsed by, or sponsored by Capcom or Sony Interactive Entertainment.
No Capcom or Sony assets are redistributed. The package contains original
AI-generated healing cues and synthesized haptic tones; Capcom game audio is
extracted locally from the user's own installed game files.
