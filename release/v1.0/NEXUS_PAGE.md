# Nexus Mods page copy — v1.0.0

Status: draft for the first public release. Paste-ready sections below.
BBCode blocks are for the Nexus description editor; plain sections are for
the corresponding Nexus form fields.

## Mod name

```text
DualSense Enhanced Edition
```

## Brief overview (Nexus summary field)

```text
Native DualSense feedback for RE4 Remake: adaptive triggers, gyro aim, lightbar and LED effects, mic LED, and controller speaker audio - no DSX required, no game files replaced.
```

## Description (BBCode)

```bbcode
[size=4][b]DualSense Enhanced Edition[/b][/size]

Brings native-feeling DualSense feedback to Resident Evil 4 Remake on PC. The mod drives the controller directly - no DSX, no Steam Input, and no replaced game files.

[size=3][b]Features[/b][/size]
[list]
[*][b]Adaptive triggers[/b] - per-weapon L2/R2 resistance profiles with global intensity presets (Off / Native Only / Light / Enhanced / Strong).
[*][b]Gyro aim[/b] - native gyro-to-mouse aiming with calibration, presets (Precision, PS5 Feel, Fast Flicks, Stable), and L2-gated activation. Works without Steam Input.
[*][b]Lightbar feedback[/b] - health gradient, damage and parry flashes, grab QTE flashes, low-health heartbeat, empty-magazine pulse, proper menu/death handling. Or hand the lightbar back to the game with one click.
[*][b]Player indicator LEDs[/b] - the 5 LEDs below the touchpad count down your remaining ammo when the magazine runs low.
[*][b]Mic LED[/b] - pulses in lockstep with the lightbar on empty ammo and critical health.
[*][b]Controller speaker audio[/b] - weapon reloads, draws, dry-fire, last-shot cues, knife hits, QTE and inventory UI sounds, item pickups and more play through the controller speaker. Herbs, spray, three egg types, three fish types, viper and rhinoceros beetle each receive an appropriate healing cue.
[*][b]No companion controller app required[/b] - the mod initializes the native speaker route itself. DSX, DualSenseY and similar tools are not needed and should remain closed.
[*][b]Enhanced Haptics (opt-in)[/b] - sprint-only footsteps and action pulses for parry, knife, dry-fire, aim, draw, healing and pickups through the DualSense actuators. Includes a global strength slider plus Soft, Normal and Strong levels with an Off toggle for every category; footsteps stay deliberately subtler than combat feedback. Off by default - enable it in the Enhanced Haptics section.
[/list]

[size=3][b]Support Development[/b][/size]
If you enjoy the mod and want to support continued development, testing and future DualSense features:

[url=https://ko-fi.com/romariocyrus][img]https://storage.ko-fi.com/cdn/kofi5.png?v=6[/img][/url]

[size=3][b]No Capcom audio is redistributed.[/b][/size]
The package includes original AI-generated custom healing cues and synthesized haptic tones. After installing, run [b]setup_sounds.bat[/b] once from the game folder; it extracts the required Capcom sounds from your own game files into the mod's sound folder. The package also ships the required open-source extraction tools (see bundled third-party licenses).

[size=3][b]Requirements[/b][/size]
[list]
[*]Resident Evil 4 Remake (Steam).
[*][url=https://www.nexusmods.com/residentevil42023/mods/12]REFramework[/url] (latest RE4R build).
[*]DualSense or DualSense Edge controller connected over [b]USB[/b].
[*][b]Steam Input disabled[/b] for RE4R (the mod talks to the controller natively).
[*]Do [b]not[/b] run DSX or other controller tools together with this mod.
[/list]

[size=3][b]Installation[/b][/size]
[list=1]
[*]Install REFramework.
[*]Install this mod with Fluffy Mod Manager (or extract the ZIP into the game folder manually).
[*]Run [b]setup_sounds.bat[/b] from the game folder once. It extracts the required sounds, generates the local audio-derived haptic files, and verifies the result afterwards.
[*]Sentinel Nine audio is optional. If its DLC pak is not installed, those sounds are skipped automatically and base-game setup still succeeds.
[*]Disable Steam Input for the game, connect the DualSense over USB, and start the game. Settings live in the REFramework menu (Insert key) under [b]DualSense Enhanced[/b].
[/list]

[b]Using audio mods?[/b] If any mod replaces re_chunk pak files, disable it before running setup_sounds.bat and re-enable it afterwards - otherwise the extraction may not find the required sound banks.

[size=3][b]Known issues[/b][/size]
[list]
[*]Gyro aim injects mouse movement, so the game may temporarily show keyboard/mouse button prompts while gyro is active.
[*]Controller speaker audio requires the one-time setup_sounds.bat run.
[*]v1.0 targets USB. Bluetooth, DSX compatibility modes, DS5 dongles, and multi-controller setups are not yet claimed as supported.
[/list]

[size=3][b]Credits[/b][/size]
[list]
[*]Eigeen - [url=https://github.com/eigeen/ree-pak-rs]ree-pak-cli[/url] (MIT License).
[*][url=https://github.com/vgmstream/vgmstream]vgmstream[/url] contributors - audio conversion.
[*]WujekFoliarz - [url=https://github.com/WujekFoliarz/duaLib]duaLib[/url] (MIT License).
[*]praydog - [url=https://github.com/praydog/REFramework]REFramework[/url].
[*]FluffyQuack - Fluffy Mod Manager.
[/list]

Unofficial fan project. Not affiliated with Capcom or Sony. No Capcom or Sony assets are included; original AI-generated mod audio ships with the package, while Capcom game audio is extracted locally from your own installation.
```

## FAQ (BBCode, for a forum sticky or description tail)

```bbcode
[size=3][b]FAQ[/b][/size]

[b]Q: Do I need DSX?[/b]
A: No. The mod drives the controller natively. Do not run DSX alongside it - they fight over the controller and break haptics and LEDs.

[b]Q: Triggers / gyro / speaker do nothing.[/b]
A: Check, in order: controller connected over USB before starting the game; Steam Input disabled for RE4R; REFramework installed and its menu opens; you ran setup_sounds.bat once; load into gameplay (the native transport arms after a save is loaded, not in the main menu).

[b]Q: setup_sounds.bat reports missing files or errors.[/b]
A: An audio mod probably modified your re_chunk pak files. Disable audio mods, run setup_sounds.bat again, then re-enable them. Verify game files in Steam if it still fails.

[b]Q: Does Bluetooth work?[/b]
A: v1.0 is tested over USB. Bluetooth is not claimed as supported yet.

[b]Q: The game shows keyboard/mouse prompts when I aim with gyro.[/b]
A: Known v1.0 behavior - gyro injects mouse movement. Disable gyro if the prompt flicker bothers you.

[b]Q: Where are the settings?[/b]
A: REFramework menu (Insert key by default) -> DualSense Enhanced. Press Save in the Config section to persist changes.

[b]Q: I don't feel any haptics / footstep rumble.[/b]
A: Enhanced Haptics is off by default. Enable it in the Enhanced Haptics section, adjust Global Strength, choose Soft/Normal/Strong for the category, and make sure its checkbox is enabled. Footsteps only fire while sprinting and are intentionally weaker than action feedback.

[b]Q: Is this safe for my save / online?[/b]
A: The mod does not touch save files or game archives. RE4R is a single-player game.
```

## Changelog (Nexus changelog tab)

```text
1.0.0
- First public release.
- Adaptive triggers with per-weapon profiles and intensity presets.
- Native gyro aim with calibration and presets (no Steam Input).
- Lightbar: HP gradient, damage/parry/grab flashes, low-HP and empty-mag pulses, native lightbar handover option.
- Player indicator LED ammo countdown and synced Mic LED effects.
- Controller speaker audio: weapon reloads, draws, dry-fire, last-shot, knife set, QTE/inventory UI, pickups, and per-item healing cues.
- Native speaker initialization with no DSX or companion controller app required.
- Enhanced Haptics (opt-in): sprint-only footsteps and action pulses with Global Strength plus Soft/Normal/Strong and Off controls per category.
- Local sound extraction via setup_sounds.bat (no Capcom audio redistributed).
```

## Permissions notes (Nexus form)

- Uploads to other sites: not allowed without permission.
- Conversion/modification: ask first.
- Asset use: bundled third-party tools keep their own licenses (see
  THIRD_PARTY_LICENSES.txt); no Capcom/Sony assets included. Original mod
  audio remains subject to the author's permissions.
