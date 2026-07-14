using System.Text.Json;

namespace DualSenseEnhancedTransport;

internal sealed record TriggerCommandFile(
    long Sequence,
    TriggerCommand? L2,
    TriggerCommand? R2,
    PlayerIndicatorsCommand? Indicators = null,
    LightBarCommand? Led = null,
    MicLightCommand? Mic = null,
    HapticsCommand? Haptics = null);

internal sealed record HapticsCommand(int Mode)
{
    public int ToMode()
    {
        if (Mode is < 1 or > 2)
            throw new ArgumentOutOfRangeException(
                nameof(Mode), Mode, "Haptics mode must be 1 (haptics) or 2 (rumble).");
        return Mode;
    }
}

internal sealed record MicLightCommand(int Mode)
{
    public byte ToMode()
    {
        if (Mode is < 0 or > 2)
            throw new ArgumentOutOfRangeException(
                nameof(Mode), Mode, "Mic light mode must be 0..2.");
        return (byte)Mode;
    }
}

internal sealed record LightBarCommand(int R, int G, int B)
{
    public (byte R, byte G, byte B) ToRgb()
    {
        return (Byte(R, nameof(R)), Byte(G, nameof(G)), Byte(B, nameof(B)));
    }

    private static byte Byte(int value, string name)
    {
        if (value is < 0 or > 255)
            throw new ArgumentOutOfRangeException(name, value, "Expected 0..255.");
        return (byte)value;
    }
}

internal sealed record PlayerIndicatorsCommand(int Mask)
{
    public byte ToMask()
    {
        if (Mask is < 0 or > 0x1F)
            throw new ArgumentOutOfRangeException(
                nameof(Mask),
                Mask,
                "Player-indicator mask must be 0..31.");
        return (byte)Mask;
    }
}

internal sealed record TriggerCommand(
    string Mode,
    int Position = 0,
    int Strength = 0,
    int EndPosition = 0,
    int EndStrength = 0,
    int Frequency = 0)
{
    public TriggerEffect ToEffect()
    {
        var mode = Mode.Trim().ToLowerInvariant() switch
        {
            "off" => TriggerMode.Off,
            "feedback" or "resistance" => TriggerMode.Feedback,
            "weapon" => TriggerMode.Weapon,
            "vibration" => TriggerMode.Vibration,
            "slope" or "slope-feedback" => TriggerMode.SlopeFeedback,
            _ => throw new ArgumentException($"Unsupported trigger mode: {Mode}")
        };

        return new TriggerEffect(
            mode,
            Byte(Position, nameof(Position)),
            Byte(Strength, nameof(Strength)),
            Byte(EndPosition, nameof(EndPosition)),
            Byte(EndStrength, nameof(EndStrength)),
            Byte(Frequency, nameof(Frequency)));
    }

    private static byte Byte(int value, string name)
    {
        if (value is < 0 or > 255)
            throw new ArgumentOutOfRangeException(name, value, "Expected 0..255.");
        return (byte)value;
    }
}

internal static class CommandFile
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static TriggerCommandFile ReadStable(string path)
    {
        Exception? lastError = null;
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                var first = File.ReadAllBytes(path);
                Thread.Sleep(10);
                var second = File.ReadAllBytes(path);
                if (!first.AsSpan().SequenceEqual(second))
                    continue;

                return JsonSerializer.Deserialize<TriggerCommandFile>(
                           second,
                           JsonOptions)
                       ?? throw new InvalidDataException(
                           "Trigger command JSON was empty.");
            }
            catch (Exception ex) when (
                ex is IOException or JsonException or UnauthorizedAccessException)
            {
                lastError = ex;
                Thread.Sleep(25);
            }
        }

        throw new InvalidDataException(
            $"Could not read a stable trigger command from {path}.",
            lastError);
    }
}
