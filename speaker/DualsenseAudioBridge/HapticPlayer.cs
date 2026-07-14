using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace DualsenseAudioBridge;

/// <summary>
/// Plays haptic one-shots on channels 3/4 of the DualSense's 4-channel
/// WASAPI endpoint (the left/right voice-coil actuators). Channels 1/2
/// stay silent so the existing stereo speaker playback is unaffected.
///
/// The actuators only respond while the controller is held in audio-haptics
/// vibration mode; in RE4R native mode that requires the duaLib transport's
/// opt-in haptics-mode selection (see DualSenseEnhancedTransport
/// --test-haptics-mode and the Haptics command-file field). Without it this
/// output opens fine but produces no physical response — confirmed by the
/// DualSenseHapticsProbe experiments.
///
/// Uses one persistent shared-mode WasapiOut with a mixer so a footstep
/// cadence doesn't pay device-open cost per event. The mixer stays silent
/// between one-shots.
/// </summary>
public sealed class HapticPlayer : IDisposable
{
    private const int SampleRate = 48000;
    private const int Channels = 4;
    private static readonly TimeSpan FailedInitCooldown = TimeSpan.FromSeconds(5);

    private readonly string _defaultDevice;
    private readonly float _defaultVolume;
    private readonly object _lock = new();
    private readonly Dictionary<string, CachedHapticSound> _soundCache =
        new(StringComparer.OrdinalIgnoreCase);

    private WasapiOut? _output;
    private MixingSampleProvider? _mixer;
    private MMDevice? _device;
    private DateTime _lastFailedInit = DateTime.MinValue;
    private bool _nextSideLeft = true;

    public HapticPlayer(string defaultDevice = "", float defaultVolume = 0.6f)
    {
        _defaultDevice = defaultDevice;
        _defaultVolume = Math.Clamp(defaultVolume, 0f, 1f);
    }

    public enum Side
    {
        Left,
        Right,
        Both
    }

    // Live intensity -> low-pass cutoff/gain mapping (docs/HAPTICS_FOOTSTEPS_TASK.md).
    // DualSense's channel-3/4 actuators are voice-coil motors -- felt
    // intensity is driven mainly by waveform frequency, not playback gain
    // (confirmed: a plain volume-only slider was barely perceptible in
    // testing). Filtering the real extracted SFX live at the cutoff this
    // slider implies gives a genuinely continuous intensity control, instead
    // of switching between a handful of pre-baked WAV variants.
    private const float MinCutoffHz = 130f;
    private const float MaxCutoffHz = 380f;
    private const float MinIntensityGain = 0.45f;
    private const float MaxIntensityGain = 1.0f;
    private const float DefaultIntensity = 0.6f;

    /// <summary>
    /// Play a haptic WAV routed to both actuators.
    /// </summary>
    public void Play(string filePath, float? volume = null, float? intensity = null) =>
        Play(filePath, volume, Side.Both, intensity);

    /// <summary>
    /// Play a haptic WAV alternating between the left and right actuator on
    /// successive calls (footstep left/right feel).
    /// </summary>
    public void PlayAlternating(string filePath, float? volume = null, float? intensity = null)
    {
        Side side;
        lock (_lock)
        {
            side = _nextSideLeft ? Side.Left : Side.Right;
            _nextSideLeft = !_nextSideLeft;
        }
        Play(filePath, volume, side, intensity);
    }

    public void Play(string filePath, float? volume, Side side, float? intensity = null)
    {
        if (!File.Exists(filePath))
        {
            Console.WriteLine($"[Haptic] File not found: {filePath}");
            return;
        }

        lock (_lock)
        {
            if (!EnsureOutputLocked())
                return;

            CachedHapticSound sound;
            try
            {
                if (!_soundCache.TryGetValue(filePath, out sound!))
                {
                    sound = CachedHapticSound.Load(filePath, SampleRate);
                    _soundCache[filePath] = sound;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Haptic] Cannot load {Path.GetFileName(filePath)}: {ex.Message}");
                return;
            }

            var clampedIntensity = Math.Clamp(intensity ?? DefaultIntensity, 0f, 1f);
            var cutoffHz = MinCutoffHz + (MaxCutoffHz - MinCutoffHz) * (1f - clampedIntensity);
            var intensityGain = MinIntensityGain + (MaxIntensityGain - MinIntensityGain) * clampedIntensity;
            var gain = Math.Clamp(volume ?? _defaultVolume, 0f, 1f) * intensityGain;
            _mixer!.AddMixerInput(new QuadRouteSampleProvider(sound, side, gain, cutoffHz));
        }
    }

    /// <summary>
    /// Add a plain sine test tone on the selected actuator(s). Used by the
    /// --test-haptic stand test; does not require any WAV to be deployed.
    /// </summary>
    public bool PlayTestTone(
        Side side,
        float frequency = 80f,
        float durationSeconds = 4f,
        float gain = 0.5f)
    {
        var left = side is Side.Left or Side.Both ? gain : 0f;
        var right = side is Side.Right or Side.Both ? gain : 0f;
        return PlayToneOnChannels(
            new[] { 0f, 0f, left, right }, frequency, durationSeconds);
    }

    /// <summary>
    /// Sine test tone on channel 2 only — the controller speaker feed per
    /// DualSenseY-v2's working USB passthrough (channel 1 is written as
    /// silence there, channels 3/4 are the actuators). Audible sound
    /// additionally requires the speaker audio route and volume to have been
    /// initialized (DualSenseEnhancedTransport --test-speaker-init).
    /// </summary>
    public bool PlaySpeakerTestTone(
        float frequency = 440f,
        float durationSeconds = 4f,
        float gain = 0.5f) =>
        PlayToneOnChannels(
            new[] { 0f, gain, 0f, 0f }, frequency, durationSeconds);

    private bool PlayToneOnChannels(
        float[] channelGains,
        float frequency,
        float durationSeconds)
    {
        lock (_lock)
        {
            if (!EnsureOutputLocked())
                return false;
            _mixer!.AddMixerInput(
                new QuadToneSampleProvider(channelGains, frequency, durationSeconds));
            return true;
        }
    }

    /// <summary>Must be called while holding <see cref="_lock"/>.</summary>
    private bool EnsureOutputLocked()
    {
        if (_output is { PlaybackState: PlaybackState.Playing })
            return true;

        if (DateTime.UtcNow - _lastFailedInit < FailedInitCooldown)
            return false;

        DisposeOutputLocked();

        try
        {
            _device = string.IsNullOrWhiteSpace(_defaultDevice)
                ? DeviceFinder.FindDualSense()
                : DeviceFinder.FindByName(_defaultDevice);
            if (_device is null)
            {
                Console.WriteLine("[Haptic] DualSense endpoint not found.");
                _lastFailedInit = DateTime.UtcNow;
                return false;
            }

            // Mixer inputs use the plain IEEE-float 4-channel format
            // (MixingSampleProvider rejects Extensible), while the wave
            // provider handed to WASAPI re-presents the same samples under
            // the quadraphonic WAVEFORMATEXTENSIBLE descriptor the DualSense
            // driver requires (plain 4-channel IEEE float is rejected with
            // E_INVALIDARG — confirmed by DualSenseHapticsProbe).
            _mixer = new MixingSampleProvider(
                WaveFormat.CreateIeeeFloatWaveFormat(SampleRate, Channels))
            {
                ReadFully = true
            };
            _output = new WasapiOut(_device, AudioClientShareMode.Shared, true, 50);
            _output.Init(new ExtensibleQuadFloatWaveProvider(_mixer));
            _output.Play();
            Console.WriteLine($"[Haptic] 4-channel output open: {_device.FriendlyName}");
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Haptic] Cannot open 4-channel output: {ex.Message}");
            DisposeOutputLocked();
            _lastFailedInit = DateTime.UtcNow;
            return false;
        }
    }

    /// <summary>Must be called while holding <see cref="_lock"/>.</summary>
    private void DisposeOutputLocked()
    {
        try { _output?.Stop(); } catch { }
        _output?.Dispose();
        _output = null;
        _mixer = null;
        _device?.Dispose();
        _device = null;
    }

    public void Dispose()
    {
        lock (_lock)
        {
            DisposeOutputLocked();
            _soundCache.Clear();
        }
    }
}

/// <summary>
/// A haptic WAV fully decoded to 48 kHz float samples, cached so repeated
/// footsteps don't re-read and re-decode the file.
/// </summary>
public sealed class CachedHapticSound
{
    public float[] Samples { get; }
    public int Channels { get; }

    private CachedHapticSound(float[] samples, int channels)
    {
        Samples = samples;
        Channels = channels;
    }

    public static CachedHapticSound Load(string filePath, int targetSampleRate)
    {
        using var reader = new AudioFileReader(filePath);
        ISampleProvider source = reader;
        if (reader.WaveFormat.SampleRate != targetSampleRate)
            source = new WdlResamplingSampleProvider(reader, targetSampleRate);

        var channels = source.WaveFormat.Channels;
        var all = new List<float>(targetSampleRate * channels);
        var buffer = new float[targetSampleRate * channels];
        int read;
        while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
            all.AddRange(buffer.Take(read));
        return new CachedHapticSound(all.ToArray(), channels);
    }
}

/// <summary>
/// Routes a cached mono/stereo haptic sound into a 4-channel frame:
/// channels 1/2 silent, channel 3 = left actuator, channel 4 = right.
/// </summary>
internal sealed class QuadRouteSampleProvider : ISampleProvider
{
    private const int Channels = 4;
    private const int SampleRate = 48000;

    private readonly CachedHapticSound _sound;
    private readonly HapticPlayer.Side _side;
    private readonly float _gain;
    private readonly float _filterAlpha;
    private int _sourceFrame;
    private float _filterPrevLeft;
    private float _filterPrevRight;

    public QuadRouteSampleProvider(
        CachedHapticSound sound,
        HapticPlayer.Side side,
        float gain,
        float cutoffHz)
    {
        _sound = sound;
        _side = side;
        _gain = gain;
        // Single-pole RC low-pass, live per-sample -- same math as
        // tools/audio_to_haptic.py / generate_haptics.ps1's offline filter,
        // but with a cutoff that can vary continuously per play call instead
        // of needing a separate pre-baked WAV per intensity step.
        var dt = 1.0 / SampleRate;
        var rc = 1.0 / (2 * Math.PI * Math.Max(20f, cutoffHz));
        _filterAlpha = (float)(dt / (rc + dt));
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(SampleRate, Channels);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(float[] buffer, int offset, int count)
    {
        var sourceChannels = _sound.Channels;
        var totalFrames = _sound.Samples.Length / sourceChannels;
        var requestedFrames = count / Channels;
        var frames = Math.Min(requestedFrames, totalFrames - _sourceFrame);
        if (frames <= 0)
            return 0;

        for (var i = 0; i < frames; i++)
        {
            var sourceOffset = (_sourceFrame + i) * sourceChannels;
            var rawLeft = _sound.Samples[sourceOffset];
            var rawRight = sourceChannels >= 2
                ? _sound.Samples[sourceOffset + 1]
                : rawLeft;

            _filterPrevLeft += _filterAlpha * (rawLeft - _filterPrevLeft);
            _filterPrevRight += _filterAlpha * (rawRight - _filterPrevRight);
            var left = _filterPrevLeft;
            var right = _filterPrevRight;

            float outLeft;
            float outRight;
            switch (_side)
            {
                case HapticPlayer.Side.Left:
                    outLeft = 0.5f * (left + right);
                    outRight = 0f;
                    break;
                case HapticPlayer.Side.Right:
                    outLeft = 0f;
                    outRight = 0.5f * (left + right);
                    break;
                default:
                    outLeft = left;
                    outRight = right;
                    break;
            }

            var target = offset + (i * Channels);
            buffer[target] = 0f;
            buffer[target + 1] = 0f;
            buffer[target + 2] = outLeft * _gain;
            buffer[target + 3] = outRight * _gain;
        }

        _sourceFrame += frames;
        return frames * Channels;
    }
}

/// <summary>
/// Finite sine tone routed to the 4-channel frame by per-channel gains
/// (actuators on 3/4, speaker feed on 2), with a short fade-in/out envelope
/// to avoid actuator clicks.
/// </summary>
internal sealed class QuadToneSampleProvider : ISampleProvider
{
    private const int SampleRate = 48000;
    private const int Channels = 4;

    private readonly float[] _channelGains;
    private readonly float _frequency;
    private readonly long _totalFrames;
    private long _frame;

    public QuadToneSampleProvider(
        float[] channelGains,
        float frequency,
        float durationSeconds)
    {
        if (channelGains.Length != Channels)
            throw new ArgumentException(
                $"Expected {Channels} channel gains, got {channelGains.Length}.");
        _channelGains = channelGains;
        _frequency = frequency;
        _totalFrames = (long)(SampleRate * durationSeconds);
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(SampleRate, Channels);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(float[] buffer, int offset, int count)
    {
        var requestedFrames = count / Channels;
        var frames = (int)Math.Min(requestedFrames, _totalFrames - _frame);
        if (frames <= 0)
            return 0;

        for (var i = 0; i < frames; i++)
        {
            var progress = (double)_frame / Math.Max(1, _totalFrames);
            var sample = (float)(
                Math.Sin(2.0 * Math.PI * _frequency * _frame / SampleRate) *
                Envelope(progress));

            var target = offset + (i * Channels);
            for (var channel = 0; channel < Channels; channel++)
                buffer[target + channel] = sample * _channelGains[channel];
            _frame++;
        }

        return frames * Channels;
    }

    private static double Envelope(double progress)
    {
        const double fadeFraction = 0.04;
        if (progress < fadeFraction)
            return progress / fadeFraction;
        if (progress > 1.0 - fadeFraction)
            return (1.0 - progress) / fadeFraction;
        return 1.0;
    }
}

/// <summary>
/// Presents 4-channel IEEE-float samples under the quadraphonic
/// WAVEFORMATEXTENSIBLE descriptor. NAudio's standard converters reject
/// Extensible encoding, and the DualSense WASAPI driver rejects the plain
/// non-extensible 4-channel IEEE-float format (both confirmed by the
/// DualSenseHapticsProbe experiment this is derived from).
/// </summary>
internal sealed class ExtensibleQuadFloatWaveProvider : IWaveProvider
{
    private readonly ISampleProvider _source;
    private float[] _sampleBuffer = Array.Empty<float>();

    public ExtensibleQuadFloatWaveProvider(ISampleProvider source)
    {
        _source = source;
        WaveFormat = new WaveFormatExtensible(
            source.WaveFormat.SampleRate,
            32,
            source.WaveFormat.Channels);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(byte[] buffer, int offset, int count)
    {
        var samplesRequested = count / sizeof(float);
        if (_sampleBuffer.Length < samplesRequested)
            _sampleBuffer = new float[samplesRequested];

        var samplesRead = _source.Read(_sampleBuffer, 0, samplesRequested);
        var bytesRead = samplesRead * sizeof(float);
        Buffer.BlockCopy(_sampleBuffer, 0, buffer, offset, bytesRead);
        return bytesRead;
    }
}
