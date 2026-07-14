using NAudio.CoreAudioApi;

namespace DualSenseHapticsProbe;

internal static class DeviceLocator
{
    public static MMDevice FindOutput(string? requested)
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator
            .EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
            .ToList();

        MMDevice? selected;
        if (!string.IsNullOrWhiteSpace(requested))
        {
            selected = devices.FirstOrDefault(device =>
                device.FriendlyName.Contains(
                    requested,
                    StringComparison.OrdinalIgnoreCase));
        }
        else
        {
            selected = devices.FirstOrDefault(IsFourChannelDualSense)
                ?? devices.FirstOrDefault(device =>
                    IsDualSense(device) &&
                    device.AudioClient.MixFormat.Channels >= 4);
        }

        foreach (var device in devices)
        {
            if (!ReferenceEquals(device, selected))
                device.Dispose();
        }

        return selected ?? throw new InvalidOperationException(
            "No active 4-channel DualSense output endpoint was found. " +
            "Connect the controller by USB and run --list.");
    }

    public static MMDevice FindSource(string? requested)
    {
        using var enumerator = new MMDeviceEnumerator();
        if (string.IsNullOrWhiteSpace(requested))
            return enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

        var devices = enumerator
            .EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
            .ToList();
        var selected = devices.FirstOrDefault(device =>
            device.FriendlyName.Contains(
                requested,
                StringComparison.OrdinalIgnoreCase));

        foreach (var device in devices)
        {
            if (!ReferenceEquals(device, selected))
                device.Dispose();
        }

        return selected ?? throw new InvalidOperationException(
            $"Loopback source containing '{requested}' was not found.");
    }

    private static bool IsFourChannelDualSense(MMDevice device) =>
        IsDualSense(device) &&
        device.AudioClient.MixFormat.Channels >= 4;

    private static bool IsDualSense(MMDevice device)
    {
        var name = device.FriendlyName;
        return name.Contains("DualSense", StringComparison.OrdinalIgnoreCase) ||
               name.Contains("Wireless Controller", StringComparison.OrdinalIgnoreCase);
    }
}
