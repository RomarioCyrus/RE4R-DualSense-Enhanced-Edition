"""
audio_bridge.py — DualSense Speaker Bridge for RE4R
====================================================
Watches a JSON event file written by Lua (REFramework).
Plays matching audio files through the DualSense speaker device.

Requirements:
    pip install sounddevice soundfile numpy

Usage:
    python audio_bridge.py [--device "Wireless Controller"] [--events-file "path/to/events.json"] [--sounds-dir "path/to/sounds"]

The script auto-detects the DualSense speaker device by name.
Run with --list-devices to see all available audio output devices.
"""

import argparse
import json
import os
import sys
import time
import threading
import numpy as np

try:
    import sounddevice as sd
    import soundfile as sf
except ImportError:
    print("[AudioBridge] ERROR: Missing dependencies. Run: pip install sounddevice soundfile numpy")
    sys.exit(1)


# ─────────────────────────────────────────────
# Config defaults
# ─────────────────────────────────────────────

DEFAULT_EVENTS_FILE = "reframework/data/audio_events.json"
DEFAULT_SOUNDS_DIR  = "reframework/data/DualSenseEnhanced/sounds"
POLL_INTERVAL       = 0.05   # seconds between file checks (50ms)
DEVICE_KEYWORDS     = ["wireless controller", "dualsense", "dualshock"]


# ─────────────────────────────────────────────
# Device detection
# ─────────────────────────────────────────────

def find_dualsense_device():
    """Find DualSense speaker in Windows audio devices by keyword match."""
    devices = sd.query_devices()
    for i, dev in enumerate(devices):
        name_lower = dev["name"].lower()
        if dev["max_output_channels"] > 0:
            for kw in DEVICE_KEYWORDS:
                if kw in name_lower:
                    return i, dev["name"]
    return None, None


def list_devices():
    devices = sd.query_devices()
    print("\nAvailable output audio devices:")
    for i, dev in enumerate(devices):
        if dev["max_output_channels"] > 0:
            print(f"  [{i:2d}] {dev['name']}  (ch: {dev['max_output_channels']}, sr: {dev['default_samplerate']:.0f})")
    print()


# ─────────────────────────────────────────────
# Sound player
# ─────────────────────────────────────────────

class SoundPlayer:
    def __init__(self, device_index, sounds_dir, volume=0.8):
        self.device_index = device_index
        self.sounds_dir   = sounds_dir
        self.volume       = volume
        self._lock        = threading.Lock()
        self._current     = None

    def play(self, sound_name, interrupt=True):
        """Play a sound file by name (without extension). Non-blocking."""
        path = self._resolve(sound_name)
        if not path:
            print(f"[AudioBridge] Sound not found: {sound_name}")
            return

        def _run():
            try:
                data, samplerate = sf.read(path, dtype="float32")
                # Mono → stereo if needed
                if data.ndim == 1:
                    data = np.column_stack([data, data])
                data = data * self.volume
                with self._lock:
                    if interrupt and self._current:
                        sd.stop()
                    self._current = sound_name
                sd.play(data, samplerate=samplerate, device=self.device_index)
                sd.wait()
                with self._lock:
                    if self._current == sound_name:
                        self._current = None
            except Exception as e:
                print(f"[AudioBridge] Playback error ({sound_name}): {e}")

        threading.Thread(target=_run, daemon=True).start()

    def _resolve(self, name):
        """Find audio file, try .wav then .ogg."""
        for ext in (".wav", ".ogg", ".mp3", ".flac"):
            path = os.path.join(self.sounds_dir, name + ext)
            if os.path.exists(path):
                return path
        return None

    def stop(self):
        sd.stop()


# ─────────────────────────────────────────────
# Event file watcher
# ─────────────────────────────────────────────

class EventWatcher:
    """
    Watches a JSON file written by Lua.
    File format:
        {"event": "heal", "ts": 1234567890.123}
    
    Lua writes this file atomically with a new timestamp each event.
    Bridge detects new timestamp → plays matching sound.
    """

    def __init__(self, events_file, player, sound_map):
        self.events_file  = events_file
        self.player       = player
        self.sound_map    = sound_map   # {event_name: sound_name}
        self._last_ts     = None
        self._last_event  = None
        self._running     = False

    def start(self):
        self._running = True
        print(f"[AudioBridge] Watching: {self.events_file}")
        while self._running:
            self._check()
            time.sleep(POLL_INTERVAL)

    def stop(self):
        self._running = False

    def _check(self):
        try:
            if not os.path.exists(self.events_file):
                return
            with open(self.events_file, "r") as f:
                data = json.load(f)
            ts    = data.get("ts")
            event = data.get("event")
            if ts and ts != self._last_ts:
                self._last_ts    = ts
                self._last_event = event
                self._dispatch(event, data)
        except (json.JSONDecodeError, IOError):
            pass  # file mid-write, skip

    def _dispatch(self, event, data):
        sound = self.sound_map.get(event)
        if sound:
            print(f"[AudioBridge] Event: {event} → {sound}")
            self.player.play(sound)
        else:
            print(f"[AudioBridge] Unknown event: {event}")


# ─────────────────────────────────────────────
# Sound map: game event → sound file name
# Files go in sounds_dir, named accordingly
# ─────────────────────────────────────────────

SOUND_MAP = {
    # Healing
    "heal_spray":       "heal_spray",       # First Aid Spray
    "heal_herb":        "heal_herb",        # Herb use
    "heal_mixed":       "heal_mixed",       # Mixed herb

    # Combat
    "reload":           "reload",           # Reload complete
    "empty_mag":        "empty_click",      # Dry fire / empty
    "parry":            "parry",            # Knife parry
    "grab":             "grab",             # Enemy grab start

    # Items
    "item_pickup":      "item_pickup",      # Item picked up
    "item_combined":    "item_combine",     # Items combined

    # UI
    "save":             "typewriter",       # Typewriter save
    "merchant":         "merchant",         # Merchant appears
    "low_hp":           "heartbeat",        # Danger HP warning (looping)
}


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="DualSense Speaker Bridge for RE4R")
    parser.add_argument("--device",      type=str,   default=None,               help="Audio device name or index")
    parser.add_argument("--events-file", type=str,   default=DEFAULT_EVENTS_FILE, help="Path to JSON events file")
    parser.add_argument("--sounds-dir",  type=str,   default=DEFAULT_SOUNDS_DIR,  help="Directory with sound files")
    parser.add_argument("--volume",      type=float, default=0.8,                 help="Playback volume 0.0-1.0")
    parser.add_argument("--list-devices",action="store_true",                     help="List audio output devices and exit")
    args = parser.parse_args()

    if args.list_devices:
        list_devices()
        return

    # Find device
    if args.device is not None:
        try:
            device_index = int(args.device)
            device_name  = sd.query_devices(device_index)["name"]
        except ValueError:
            # String match
            devices = sd.query_devices()
            device_index = None
            device_name  = None
            for i, dev in enumerate(devices):
                if args.device.lower() in dev["name"].lower() and dev["max_output_channels"] > 0:
                    device_index = i
                    device_name  = dev["name"]
                    break
            if device_index is None:
                print(f"[AudioBridge] ERROR: Device '{args.device}' not found.")
                list_devices()
                sys.exit(1)
    else:
        device_index, device_name = find_dualsense_device()
        if device_index is None:
            print("[AudioBridge] ERROR: DualSense speaker not found. Is DSX running?")
            list_devices()
            sys.exit(1)

    print(f"[AudioBridge] Output device: [{device_index}] {device_name}")
    print(f"[AudioBridge] Sounds dir:    {args.sounds_dir}")
    print(f"[AudioBridge] Volume:        {args.volume}")

    player  = SoundPlayer(device_index, args.sounds_dir, args.volume)
    watcher = EventWatcher(args.events_file, player, SOUND_MAP)

    try:
        watcher.start()
    except KeyboardInterrupt:
        print("\n[AudioBridge] Stopped.")
        watcher.stop()


if __name__ == "__main__":
    main()
