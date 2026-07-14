"""Generate original synthesized haptic WAV assets (docs/HAPTICS_FOOTSTEPS_TASK.md).

DualSense actuators are voice-coil motors -- felt intensity is driven mainly
by waveform frequency, not playback gain (a plain volume multiplier on one
WAV was confirmed barely perceptible in live testing 2026-07-11). Each
preset here is a gated low-frequency sine burst instead: soft=90Hz short
tap, normal=40Hz, strong=20Hz longer pulse.

100% original synthesized content, no Capcom audio. The release package ships
only the subset explicitly allowlisted in release/v1.0/RELEASE_MANIFEST.md;
some older A/B reference tones generated here remain development-only.

Usage:
    py tools/gen_haptic_wavs.py src/reframework/data/DualSenseEnhanced/sounds
"""
import wave
import struct
import math
import sys

SAMPLE_RATE = 48000

def gen_gated_burst(freq_hz, duration_s, gate_hz, gate_duty, gain, fade_ms=8):
    n = int(SAMPLE_RATE * duration_s)
    fade_n = int(SAMPLE_RATE * fade_ms / 1000.0)
    samples = []
    gate_period = SAMPLE_RATE / gate_hz if gate_hz > 0 else n
    for i in range(n):
        # Overall envelope: quick fade in/out to avoid clicks
        env = 1.0
        if i < fade_n:
            env = i / fade_n
        elif i > n - fade_n:
            env = (n - i) / fade_n
        # Gate: on/off pulsing within the burst (creates the "tap" texture)
        phase_in_period = (i % gate_period) / gate_period if gate_period > 0 else 0
        gate = 1.0 if phase_in_period < gate_duty else 0.0
        s = math.sin(2 * math.pi * freq_hz * i / SAMPLE_RATE)
        samples.append(gain * env * gate * s)
    return samples

def write_wav(path, samples):
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        f.writeframes(bytes(frames))

presets = {
    # name: (frequency Hz, duration s, gate Hz, gate duty, gain)
    # Toned down 2026-07-12: constant repetition (every step) made these
    # dominate perception even though each individual pulse isn't stronger
    # than a companion impact -- footsteps should read as background texture,
    # one-off events (parry, reload, etc) should stand out against them.
    "haptic_footstep_soft":   (90, 0.055, 40, 0.5, 0.35),
    "haptic_footstep":        (45, 0.065, 25, 0.55, 0.55),
    "haptic_footstep_strong": (25, 0.090, 16, 0.6, 0.75),

    # Companion haptics for existing speaker-audio events (docs/HAPTICS_FOOTSTEPS_TASK.md).
    # Heavy weighty impact: knife finisher.
    "haptic_impact_strong":   (15, 0.170, 12, 0.70, 1.0),
    # Parry: native RE4R has NO controller vibration for this at all, so
    # this is the strongest pulse in the whole system by design -- lower
    # frequency, longer, near-continuous gate (duty 0.85) instead of a
    # pulsy texture, maxed gain. Tuned 2026-07-12 after user feedback that
    # the shared impact_strong profile "не очень сильно ощущается" for parry.
    "haptic_parry":           (12, 0.220, 10, 0.85, 1.0),
    # Medium impact: knife hit / knife swing hit / knife finisher hit layer.
    "haptic_impact_medium":   (30, 0.100, 20, 0.60, 0.85),
    # Tactical click: aiming in (raising a weapon to sights).
    "haptic_aim_in":          (140, 0.035, 0, 1.0, 0.6),
    # Softer release click: aiming out (lowering from sights).
    "haptic_aim_out":         (110, 0.030, 0, 1.0, 0.45),
    # Dull thud: drawing/holstering a weapon.
    "haptic_draw":            (25, 0.110, 18, 0.55, 0.75),
    # Dry/sharp click: dry fire (empty gun) / last shot.
    "haptic_dry_fire":        (160, 0.025, 0, 1.0, 0.7),
    # Mechanical tap: reload start/insert/finish steps.
    "haptic_reload":          (60, 0.055, 30, 0.6, 0.7),
    # Gentle long pulse: healing.
    "haptic_heal":            (50, 0.180, 15, 0.5, 0.5),
    # Tiny tick: item/ammo pickup.
    "haptic_pickup":          (180, 0.020, 0, 1.0, 0.45),
}

if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    for name, (freq, dur, gate_hz, duty, gain) in presets.items():
        samples = gen_gated_burst(freq, dur, gate_hz, duty, gain)
        path = f"{outdir}/{name}.wav"
        write_wav(path, samples)
        print(f"wrote {path}: {freq}Hz, {dur*1000:.0f}ms, gate={gate_hz}Hz duty={duty}, gain={gain}")
