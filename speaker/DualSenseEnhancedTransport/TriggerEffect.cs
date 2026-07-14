using System.Buffers.Binary;

namespace DualSenseEnhancedTransport;

internal enum TriggerSide
{
    L2,
    R2
}

internal enum TriggerMode
{
    Off = 0,
    Feedback = 1,
    Weapon = 2,
    Vibration = 3,
    MultiplePositionFeedback = 4,
    SlopeFeedback = 5,
    MultiplePositionVibration = 6
}

internal sealed record TriggerEffect(
    TriggerMode Mode,
    byte Position = 0,
    byte Strength = 0,
    byte EndPosition = 0,
    byte EndStrength = 0,
    byte Frequency = 0)
{
    public static TriggerEffect Off { get; } = new(TriggerMode.Off);

    public void Validate()
    {
        switch (Mode)
        {
            case TriggerMode.Off:
                return;
            case TriggerMode.Feedback:
                Range(Position, 0, 9, nameof(Position));
                Range(Strength, 1, 8, nameof(Strength));
                return;
            case TriggerMode.Weapon:
                Range(Position, 2, 7, nameof(Position));
                Range(EndPosition, Position + 1, 8, nameof(EndPosition));
                Range(Strength, 1, 8, nameof(Strength));
                return;
            case TriggerMode.Vibration:
                Range(Position, 0, 9, nameof(Position));
                Range(Strength, 1, 8, nameof(Strength));
                Range(Frequency, 1, 255, nameof(Frequency));
                return;
            case TriggerMode.SlopeFeedback:
                Range(Position, 0, 8, nameof(Position));
                Range(EndPosition, Position + 1, 9, nameof(EndPosition));
                Range(Strength, 1, 8, nameof(Strength));
                Range(EndStrength, 1, 8, nameof(EndStrength));
                return;
            default:
                throw new ArgumentException(
                    $"Mode {Mode} is not enabled in the first experimental transport.");
        }
    }

    private static void Range(byte value, int min, int max, string name)
    {
        if (value < min || value > max)
            throw new ArgumentOutOfRangeException(
                name,
                value,
                $"Expected {min}..{max}.");
    }
}

internal static class TriggerPacket
{
    internal const int PacketSize = 120;
    private const int L2CommandOffset = 8;
    private const int R2CommandOffset = 64;
    private const int CommandDataOffset = 8;

    public static byte[] Build(
        TriggerEffect? l2,
        TriggerEffect? r2)
    {
        l2?.Validate();
        r2?.Validate();

        var packet = new byte[PacketSize];
        if (l2 is not null)
        {
            packet[0] |= 0x01;
            WriteCommand(packet, L2CommandOffset, l2);
        }

        if (r2 is not null)
        {
            packet[0] |= 0x02;
            WriteCommand(packet, R2CommandOffset, r2);
        }

        return packet;
    }

    private static void WriteCommand(
        byte[] packet,
        int commandOffset,
        TriggerEffect effect)
    {
        BinaryPrimitives.WriteInt32LittleEndian(
            packet.AsSpan(commandOffset, sizeof(int)),
            (int)effect.Mode);

        var data = commandOffset + CommandDataOffset;
        switch (effect.Mode)
        {
            case TriggerMode.Off:
                break;
            case TriggerMode.Feedback:
                packet[data] = effect.Position;
                packet[data + 1] = effect.Strength;
                break;
            case TriggerMode.Weapon:
                packet[data] = effect.Position;
                packet[data + 1] = effect.EndPosition;
                packet[data + 2] = effect.Strength;
                break;
            case TriggerMode.Vibration:
                packet[data] = effect.Position;
                packet[data + 1] = effect.Strength;
                packet[data + 2] = effect.Frequency;
                break;
            case TriggerMode.SlopeFeedback:
                packet[data] = effect.Position;
                packet[data + 1] = effect.EndPosition;
                packet[data + 2] = effect.Strength;
                packet[data + 3] = effect.EndStrength;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(effect.Mode));
        }
    }
}
