using NAudio.Wave;
using NAudio.Dsp;

namespace DualSenseHapticsProbe;

/// <summary>
/// Converts float samples to an IWaveProvider without replacing the source
/// WAVEFORMATEXTENSIBLE descriptor. NAudio's standard ToWaveProvider helper
/// rejects Extensible encoding even when its subformat is IEEE float.
/// </summary>
internal sealed class ExtensibleFloatWaveProvider : IWaveProvider
{
    private readonly ISampleProvider _source;
    private float[] _sampleBuffer = Array.Empty<float>();

    public ExtensibleFloatWaveProvider(ISampleProvider source)
    {
        _source = source;
        WaveFormat = source.WaveFormat;

        if (WaveFormat.BitsPerSample != 32)
            throw new ArgumentException("Source must use 32-bit float samples.");
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

internal sealed class HapticToneSampleProvider : ISampleProvider
{
    private const int SampleRate = 48000;
    private const int Channels = 4;

    private readonly ToneSide _side;
    private readonly float _frequency;
    private readonly float _gain;
    private readonly bool _swap;
    private readonly long _totalFrames;
    private long _frame;

    public HapticToneSampleProvider(
        ToneSide side,
        float frequency,
        float durationSeconds,
        float gain,
        bool swap)
    {
        _side = side;
        _frequency = frequency;
        _gain = gain;
        _swap = swap;
        _totalFrames = (long)(SampleRate * durationSeconds);
        // DualSense exposes a quadraphonic WAVEFORMATEXTENSIBLE endpoint.
        // A plain 4-channel IEEE WaveFormat is rejected by its WASAPI driver
        // with E_INVALIDARG even though the sample rate/channel count match.
        WaveFormat = new WaveFormatExtensible(SampleRate, 32, Channels);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(float[] buffer, int offset, int count)
    {
        var requestedFrames = count / Channels;
        var remainingFrames = _totalFrames - _frame;
        var frames = (int)Math.Min(requestedFrames, remainingFrames);

        for (var i = 0; i < frames; i++)
        {
            var progress = (double)_frame / Math.Max(1, _totalFrames);
            var fade = Envelope(progress);
            var sample = (float)(
                Math.Sin(2.0 * Math.PI * _frequency * _frame / SampleRate) *
                _gain *
                fade);

            var left = _side is ToneSide.Left or ToneSide.Both ? sample : 0f;
            var right = _side is ToneSide.Right or ToneSide.Both ? sample : 0f;
            if (_swap)
                (left, right) = (right, left);

            var target = offset + (i * Channels);
            buffer[target] = 0f;
            buffer[target + 1] = 0f;
            buffer[target + 2] = left;
            buffer[target + 3] = right;
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

internal sealed class StereoDownmixSampleProvider : ISampleProvider
{
    private readonly ISampleProvider _source;
    private readonly int _inputChannels;
    private float[] _sourceBuffer = Array.Empty<float>();

    public StereoDownmixSampleProvider(ISampleProvider source)
    {
        _source = source;
        _inputChannels = source.WaveFormat.Channels;
        if (_inputChannels <= 0)
            throw new ArgumentException("Source must expose at least one channel.");
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(
            source.WaveFormat.SampleRate,
            2);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(float[] buffer, int offset, int count)
    {
        var requestedFrames = count / 2;
        var needed = requestedFrames * _inputChannels;
        if (_sourceBuffer.Length < needed)
            _sourceBuffer = new float[needed];

        var read = _source.Read(_sourceBuffer, 0, needed);
        var frames = read / _inputChannels;

        for (var frame = 0; frame < frames; frame++)
        {
            var sourceOffset = frame * _inputChannels;
            float left;
            float right;
            if (_inputChannels == 1)
            {
                left = right = _sourceBuffer[sourceOffset];
            }
            else
            {
                left = _sourceBuffer[sourceOffset];
                right = _sourceBuffer[sourceOffset + 1];
            }

            var target = offset + (frame * 2);
            buffer[target] = left;
            buffer[target + 1] = right;
        }

        return frames * 2;
    }
}

internal sealed class HapticLoopbackSampleProvider : ISampleProvider
{
    public const int OutputSampleRate = 48000;
    private const int OutputChannels = 4;

    private readonly ISampleProvider _source;
    private readonly HapticDspSettings _settings;
    private readonly bool _swap;
    private readonly BiQuadFilter? _highPassLeft;
    private readonly BiQuadFilter? _highPassRight;
    private readonly BiQuadFilter? _lowPassLeft;
    private readonly BiQuadFilter? _lowPassRight;

    private float[] _sourceBuffer = Array.Empty<float>();
    private float _fastEnvelopeLeft;
    private float _fastEnvelopeRight;
    private float _slowEnvelopeLeft;
    private float _slowEnvelopeRight;
    private float _gateEnvelopeLeft;
    private float _gateEnvelopeRight;

    public HapticLoopbackSampleProvider(
        ISampleProvider source,
        HapticDspSettings settings,
        bool swap)
    {
        if (source.WaveFormat.Channels != 2)
            throw new ArgumentException("Haptic loopback input must be stereo.");
        if (source.WaveFormat.SampleRate != OutputSampleRate)
            throw new ArgumentException("Haptic loopback input must be 48 kHz.");

        _source = source;
        _settings = settings;
        _swap = swap;

        if (settings.HighPassHz > 0)
        {
            _highPassLeft = BiQuadFilter.HighPassFilter(
                OutputSampleRate,
                settings.HighPassHz,
                0.7071f);
            _highPassRight = BiQuadFilter.HighPassFilter(
                OutputSampleRate,
                settings.HighPassHz,
                0.7071f);
        }

        if (settings.LowPassHz > 0 &&
            settings.LowPassHz < OutputSampleRate / 2f)
        {
            _lowPassLeft = BiQuadFilter.LowPassFilter(
                OutputSampleRate,
                settings.LowPassHz,
                0.7071f);
            _lowPassRight = BiQuadFilter.LowPassFilter(
                OutputSampleRate,
                settings.LowPassHz,
                0.7071f);
        }

        WaveFormat = new WaveFormatExtensible(
            OutputSampleRate,
            32,
            OutputChannels);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(float[] buffer, int offset, int count)
    {
        var requestedFrames = count / OutputChannels;
        var needed = requestedFrames * 2;
        if (_sourceBuffer.Length < needed)
            _sourceBuffer = new float[needed];

        var read = _source.Read(_sourceBuffer, 0, needed);
        var frames = read / 2;

        for (var frame = 0; frame < frames; frame++)
        {
            var inputLeft = _sourceBuffer[frame * 2];
            var inputRight = _sourceBuffer[(frame * 2) + 1];

            var left = Filter(inputLeft, _highPassLeft, _lowPassLeft);
            var right = Filter(inputRight, _highPassRight, _lowPassRight);

            left = Shape(
                left,
                ref _fastEnvelopeLeft,
                ref _slowEnvelopeLeft,
                ref _gateEnvelopeLeft);
            right = Shape(
                right,
                ref _fastEnvelopeRight,
                ref _slowEnvelopeRight,
                ref _gateEnvelopeRight);
            if (_swap)
                (left, right) = (right, left);

            var target = offset + (frame * OutputChannels);
            buffer[target] = 0f;
            buffer[target + 1] = 0f;
            buffer[target + 2] = left;
            buffer[target + 3] = right;
        }

        return frames * OutputChannels;
    }

    private static float Filter(
        float sample,
        BiQuadFilter? highPass,
        BiQuadFilter? lowPass)
    {
        if (highPass != null)
            sample = highPass.Transform(sample);
        if (lowPass != null)
            sample = lowPass.Transform(sample);
        return sample;
    }

    private float Shape(
        float sample,
        ref float fastEnvelope,
        ref float slowEnvelope,
        ref float gateEnvelope)
    {
        var magnitude = MathF.Abs(sample);
        fastEnvelope = SmoothEnvelope(
            fastEnvelope,
            magnitude,
            _settings.FastAttackMs,
            _settings.FastReleaseMs);
        slowEnvelope = SmoothEnvelope(
            slowEnvelope,
            magnitude,
            _settings.SlowAttackMs,
            _settings.SlowReleaseMs);

        var transientRatio = Math.Clamp(
            (fastEnvelope - slowEnvelope) / MathF.Max(slowEnvelope, 0.001f),
            0f,
            1f);
        var transientGain = _settings.TailLevel +
                            (_settings.TransientBoost * transientRatio);

        var gateTarget = magnitude >= _settings.Gate ? 1f : 0f;
        var gateMs = gateTarget > gateEnvelope
            ? _settings.GateAttackMs
            : _settings.GateReleaseMs;
        var gateCoefficient = TimeCoefficient(gateMs);
        gateEnvelope = gateTarget +
                       (gateCoefficient * (gateEnvelope - gateTarget));

        sample *= _settings.Gain * transientGain * gateEnvelope;
        return MathF.Tanh(sample * _settings.LimiterDrive);
    }

    private static float SmoothEnvelope(
        float current,
        float target,
        float attackMs,
        float releaseMs)
    {
        var coefficient = TimeCoefficient(target > current ? attackMs : releaseMs);
        return target + (coefficient * (current - target));
    }

    private static float TimeCoefficient(float milliseconds)
    {
        if (milliseconds <= 0f)
            return 0f;
        return MathF.Exp(-1f / (0.001f * milliseconds * OutputSampleRate));
    }
}

internal sealed record HapticDspSettings(
    string Name,
    float Gain,
    float Gate,
    float HighPassHz,
    float LowPassHz,
    float TransientBoost,
    float TailLevel,
    float FastAttackMs,
    float FastReleaseMs,
    float SlowAttackMs,
    float SlowReleaseMs,
    float GateAttackMs,
    float GateReleaseMs,
    float LimiterDrive)
{
    public static HapticDspSettings Create(
        HapticPreset preset,
        float? gainOverride,
        float? gateOverride,
        float? highPassOverride,
        float? lowPassOverride,
        float? transientOverride,
        float? tailOverride)
    {
        var settings = preset switch
        {
            HapticPreset.Raw => new HapticDspSettings(
                "Raw",
                0.45f, 0.020f, 35f, 0f,
                0f, 1f,
                1f, 30f, 20f, 180f,
                1f, 50f, 1f),
            HapticPreset.Natural => new HapticDspSettings(
                "Natural",
                0.52f, 0.018f, 40f, 420f,
                0.55f, 0.78f,
                0.8f, 28f, 18f, 170f,
                0.7f, 42f, 1.15f),
            HapticPreset.Ps5 => new HapticDspSettings(
                "PS5-like",
                0.62f, 0.024f, 48f, 360f,
                1.35f, 0.42f,
                0.35f, 16f, 14f, 145f,
                0.4f, 24f, 1.25f),
            HapticPreset.Impact => new HapticDspSettings(
                "Impact",
                0.72f, 0.032f, 55f, 310f,
                1.85f, 0.25f,
                0.2f, 11f, 12f, 120f,
                0.25f, 16f, 1.4f),
            _ => throw new ArgumentOutOfRangeException(nameof(preset))
        };

        return settings with
        {
            Gain = gainOverride ?? settings.Gain,
            Gate = gateOverride ?? settings.Gate,
            HighPassHz = highPassOverride ?? settings.HighPassHz,
            LowPassHz = lowPassOverride ?? settings.LowPassHz,
            TransientBoost = transientOverride ?? settings.TransientBoost,
            TailLevel = tailOverride ?? settings.TailLevel
        };
    }
}
