namespace DualSenseEnhancedTransport;

internal readonly record struct GyroMotionSample(
    float X,
    float Y,
    float Z,
    float AccelX,
    float AccelY,
    float AccelZ,
    byte L2,
    byte RightStickX,
    byte RightStickY,
    ulong Timestamp)
{
    // Magnitude in g (duaLib reports acceleration normalized to g, not
    // m/s^2 -- confirmed live: a flat, resting controller reads ~0.97).
    // A controller at rest should read close to 1g regardless of
    // orientation; deviation from that means it is actually being
    // moved/accelerated, which is a more direct "is it really still" signal
    // than checking the gyro against itself.
    public float AccelMagnitude =>
        MathF.Sqrt(AccelX * AccelX + AccelY * AccelY + AccelZ * AccelZ);
}
