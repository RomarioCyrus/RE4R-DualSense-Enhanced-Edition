"""Audio-to-haptics prototype (docs/HAPTICS_FOOTSTEPS_TASK.md).

Converts a real extracted game sound into a haptic companion WAV, instead of
a synthesized fixed-frequency tone: downmix to mono, single-pole low-pass
filter (DualSense actuators respond mainly below ~300Hz -- everything above
that is felt as an undifferentiated buzz, not texture), then peak-normalize.
This is an offline preprocessing step, not a live filter -- output is a
plain WAV resolved the same way as the synthesized haptic_* files (SoundMap
identity/variant fallback), no C# change needed.

Usage:
    py tools/audio_to_haptic.py <input.wav> <output.wav> [cutoff_hz] [gain] [max_duration_ms]
"""
import wave
import struct
import sys

DEFAULT_CUTOFF_HZ = 220.0
DEFAULT_GAIN = 1.0

def read_wav_mono(path):
    with wave.open(path, "rb") as f:
        n_channels = f.getnchannels()
        sample_width = f.getsampwidth()
        sample_rate = f.getframerate()
        n_frames = f.getnframes()
        raw = f.readframes(n_frames)

    if sample_width != 2:
        raise ValueError(f"Only 16-bit PCM supported, got {sample_width*8}-bit")

    fmt = "<" + ("h" * (len(raw) // 2))
    samples = struct.unpack(fmt, raw)

    if n_channels == 1:
        mono = [s / 32768.0 for s in samples]
    else:
        mono = []
        for i in range(0, len(samples) - n_channels + 1, n_channels):
            frame_sum = sum(samples[i:i + n_channels])
            mono.append((frame_sum / n_channels) / 32768.0)

    return mono, sample_rate

def low_pass(samples, sample_rate, cutoff_hz):
    # Single-pole RC low-pass: simple, stable, no external deps. Good enough
    # for "keep only what an actuator can physically render" -- not trying
    # for audiophile filter quality here.
    import math
    dt = 1.0 / sample_rate
    rc = 1.0 / (2 * math.pi * cutoff_hz)
    alpha = dt / (rc + dt)
    out = [0.0] * len(samples)
    prev = 0.0
    for i, s in enumerate(samples):
        prev = prev + alpha * (s - prev)
        out[i] = prev
    return out

def normalize(samples, target_peak=0.95):
    peak = max((abs(s) for s in samples), default=0.0)
    if peak < 1e-6:
        return samples
    scale = target_peak / peak
    return [s * scale for s in samples]

def trim_silence(samples, sample_rate, threshold=0.02, tail_ms=15):
    # Drop leading silence and cap trailing silence -- extracted game SFX
    # often have a bit of lead-in/lead-out that just wastes haptic duration.
    start = 0
    for i, s in enumerate(samples):
        if abs(s) > threshold:
            start = i
            break
    end = len(samples)
    for i in range(len(samples) - 1, -1, -1):
        if abs(samples[i]) > threshold:
            end = min(len(samples), i + int(sample_rate * tail_ms / 1000.0))
            break
    return samples[start:end]

def write_wav_mono16(path, samples, sample_rate):
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        f.writeframes(bytes(frames))

def convert(in_path, out_path, cutoff_hz=DEFAULT_CUTOFF_HZ, gain=DEFAULT_GAIN, max_duration_ms=250):
    mono, sample_rate = read_wav_mono(in_path)
    filtered = low_pass(mono, sample_rate, cutoff_hz)
    trimmed = trim_silence(filtered, sample_rate)
    # Cap duration: extracted SFX often carry a long reverb/echo tail that
    # survives the low-pass filter as lingering low-frequency content --
    # felt as a smeared buzz instead of a punchy hit if left in. A haptic
    # pulse should stay short even if the source audio doesn't.
    max_samples = int(sample_rate * max_duration_ms / 1000.0)
    if len(trimmed) > max_samples:
        fade_samples = min(int(sample_rate * 0.02), max_samples // 4)
        trimmed = trimmed[:max_samples]
        for i in range(fade_samples):
            factor = 1.0 - (i / fade_samples)
            trimmed[max_samples - fade_samples + i] *= factor
    normalized = normalize(trimmed, target_peak=0.95 * gain)
    write_wav_mono16(out_path, normalized, sample_rate)
    duration_ms = 1000.0 * len(normalized) / sample_rate
    print(f"wrote {out_path}: {duration_ms:.0f}ms, cutoff={cutoff_hz}Hz, "
          f"from {in_path} ({len(mono)} samples @ {sample_rate}Hz)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    in_path = sys.argv[1]
    out_path = sys.argv[2]
    cutoff = float(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_CUTOFF_HZ
    gain = float(sys.argv[4]) if len(sys.argv) > 4 else DEFAULT_GAIN
    max_duration_ms = float(sys.argv[5]) if len(sys.argv) > 5 else 250
    convert(in_path, out_path, cutoff, gain, max_duration_ms)
