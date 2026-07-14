Resident Evil 4 - DualSense Enhanced Edition v1.0.0
====================================================

Unofficial DualSense enhancement mod for Resident Evil 4 Remake (PC).
Brings native-feeling DualSense feedback to the game without replacing
any game files.

FEATURES
--------
- Adaptive triggers with per-weapon resistance profiles.
- Native gyro aim (no Steam Input required).
- Lightbar feedback: health gradient, damage/parry flashes, grab QTE,
  low-ammo and low-health pulses, menu/death handling.
- Player indicator LEDs as a low-ammo countdown.
- Mic LED effects synced with the lightbar pulses.
- Controller speaker audio: weapon reloads, draws, dry-fire, knife,
  QTE/UI and item pickup sounds. Healing items have distinct cues for
  herbs, spray, eggs, fish, viper and beetle. The distinct non-spray healing
  cues are original AI-generated mod assets; required game audio is extracted
  locally from YOUR OWN game files.
- Native controller-speaker initialization: no DSX, DualSenseY or other
  companion controller software is required for speaker playback.
- Enhanced Haptics (opt-in): sprint-only footsteps plus action pulses
  for parry, knife, dry-fire, aim, draw, healing and pickups. Includes
  a global strength slider plus Soft/Normal/Strong levels and an Off toggle for each category. Off by
  default - enable it in the Enhanced Haptics section of the
  REFramework menu.

REQUIREMENTS
------------
- Resident Evil 4 Remake (Steam, Windows).
- REFramework (latest RE4R release).
- Sony DualSense or DualSense Edge controller, connected over USB.
- Steam Input DISABLED for this game (the mod drives the controller
  natively; Steam Input would take over the device).
- Do not run DSX or other controller tools alongside this mod.

INSTALLATION
------------
1. Install REFramework for RE4R if you have not already.
2. Install this mod with Fluffy Mod Manager, or copy the contents of
   the package into the game folder manually.
3. Run setup_sounds.bat from the game folder ONCE. It extracts the
   required controller-speaker sounds from your local game archive
   (and supported DLC archives when present), then generates the local
   audio-derived haptic files, into:
     reframework\data\DualSenseEnhanced\sounds
   This package includes original AI-generated healing cues and synthesized
   haptic tones, but does not include any Capcom audio files.
   Sentinel Nine audio is optional and is skipped automatically when
   its DLC archive is not installed.
4. Start the game. The mod UI appears inside the REFramework menu
   (Insert key by default) under "DualSense Enhanced".

AUDIO MOD NOTICE
----------------
If you use audio mods that replace or modify re_chunk pak files,
disable them BEFORE running setup_sounds.bat, then re-enable them
after the extraction finishes. Audio replacement mods can prevent the
required sound banks from being found or converted.

NOTES
-----
- USB is the primary supported connection for v1.0.
- DSX compatibility is not claimed for v1.0.
- Gyro aim injects mouse movement while aiming, so the game may show
  keyboard/mouse button prompts during gyro use.

CREDITS
-------
- eRo - mod author.
- Eigeen / ree-pak-rs - ree-pak-cli (MIT License, Copyright (c) 2024 Eigeen).
- vgmstream contributors - audio conversion tooling.
- REFramework by praydog.
- Fluffy Mod Manager by FluffyQuack.

See THIRD_PARTY_LICENSES.txt for full license texts and notices.

This project is unofficial and is not affiliated with Capcom, Sony, or
the REFramework project. Resident Evil and DualSense names belong to
their respective owners.
