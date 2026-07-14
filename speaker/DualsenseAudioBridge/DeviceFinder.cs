using NAudio.CoreAudioApi;
using System.Text.Json.Serialization;

namespace DualsenseAudioBridge;

public sealed class AudioEndpointInfo
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("index")]
    public int Index { get; init; }

    [JsonPropertyName("is_dualsense")]
    public bool IsDualSense { get; init; }

    [JsonPropertyName("is_default_auto")]
    public bool IsDefaultAuto { get; init; }
}

/// <summary>
/// Finds the DualSense speaker device via Windows WASAPI enumeration.
/// DSX must be running (USB) for the device to appear.
/// </summary>
public static class DeviceFinder
{
    private static readonly string[] Keywords = 
    {
        "wireless controller",
        "dualsense",
        "dualshock"
    };

    public static bool IsDualSenseName(string friendlyName)
    {
        var name = friendlyName.ToLowerInvariant();
        return Keywords.Any(name.Contains);
    }

    public static List<AudioEndpointInfo> ListActiveRenderEndpoints()
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active).ToList();
        var autoId = ChooseAutoDualSense(devices)?.ID;

        return devices.Select((device, index) => new AudioEndpointInfo
        {
            Id = device.ID,
            Name = device.FriendlyName,
            Index = index,
            IsDualSense = IsDualSenseName(device.FriendlyName),
            IsDefaultAuto = string.Equals(device.ID, autoId, StringComparison.OrdinalIgnoreCase)
        }).ToList();
    }

    /// <summary>
    /// Auto-detect DualSense speaker by name keyword.
    /// Returns null if not found.
    /// </summary>
    public static MMDevice? FindDualSense()
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active);
        return ChooseAutoDualSense(devices);
    }

    /// <summary>
    /// Find device by exact name fragment (user-specified in config).
    /// </summary>
    public static MMDevice? FindByName(string nameFragment)
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active);
        var lower = nameFragment.ToLowerInvariant();
        return devices.FirstOrDefault(d => d.FriendlyName.ToLowerInvariant().Contains(lower));
    }

    /// <summary>
    /// Find device by stable Windows endpoint id.
    /// </summary>
    public static MMDevice? FindById(string endpointId)
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active);
        return devices.FirstOrDefault(d =>
            string.Equals(d.ID, endpointId, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Find device by index.
    /// </summary>
    public static MMDevice? FindByIndex(int index)
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active).ToList();
        return index >= 0 && index < devices.Count ? devices[index] : null;
    }

    /// <summary>
    /// List all active output devices to console.
    /// </summary>
    public static void ListDevices()
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active).ToList();
        Console.WriteLine("\nAvailable audio output devices:");
        for (int i = 0; i < devices.Count; i++)
            Console.WriteLine($"  [{i,2}] {devices[i].FriendlyName}");
        Console.WriteLine();
    }

    private static MMDevice? ChooseAutoDualSense(IEnumerable<MMDevice> devices)
    {
        var list = devices.ToList();

        return list.FirstOrDefault(d =>
                   d.FriendlyName.Contains("DualSense Edge Wireless Controller", StringComparison.OrdinalIgnoreCase))
               ?? list.FirstOrDefault(d =>
                   d.FriendlyName.Contains("DualSense Wireless Controller", StringComparison.OrdinalIgnoreCase))
               ?? list.FirstOrDefault(d => IsDualSenseName(d.FriendlyName));
    }
}
