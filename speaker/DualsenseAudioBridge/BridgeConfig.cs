using System.Text.Json;
using System.Text.Json.Serialization;

namespace DualsenseAudioBridge;

public class BridgeConfig
{
    private const string DefaultSoundsDir = @"data\DualSenseEnhanced\sounds";
    private const string DefaultEventsFile = @"data\audio_events.json";

    /// <summary>Device name fragment to match. Empty = auto-detect DualSense.</summary>
    [JsonPropertyName("device")]
    public string Device { get; set; } = "";

    /// <summary>Playback volume from 0.0 to 1.0.</summary>
    [JsonPropertyName("volume")]
    public float Volume { get; set; } = 0.85f;

    /// <summary>
    /// Routes "haptic_"-prefixed events to channels 3/4 of the DualSense
    /// 4-channel endpoint (actuators). Requires the duaLib transport's
    /// opt-in audio-haptics mode (Lua "Hold audio-haptics mode" checkbox,
    /// off by default) to actually produce physical output -- this being
    /// true just constructs the HapticPlayer at bridge startup so that
    /// checkbox is the single effective toggle for the user, instead of
    /// also needing a manual JSON edit.
    /// </summary>
    [JsonPropertyName("haptics_enabled")]
    public bool HapticsEnabled { get; set; } = true;

    /// <summary>Haptic playback gain from 0.0 to 1.0.</summary>
    [JsonPropertyName("haptics_volume")]
    public float HapticsVolume { get; set; } = 0.6f;

    /// <summary>Sound directory, absolute or relative to the reframework directory.</summary>
    [JsonPropertyName("sounds_dir")]
    public string SoundsDir { get; set; } = DefaultSoundsDir;

    /// <summary>Events file, absolute or relative to the reframework directory.</summary>
    [JsonPropertyName("events_file")]
    public string EventsFile { get; set; } = DefaultEventsFile;

    private static readonly string ConfigPath =
        Path.Combine(AppContext.BaseDirectory, "DualsenseAudioBridge.json");

    public static BridgeConfig Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                var json = File.ReadAllText(ConfigPath);
                var config = JsonSerializer.Deserialize<BridgeConfig>(json) ?? new BridgeConfig();
                if (config.UpgradeLegacyPaths())
                    config.Save();
                return config;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Config] Failed to read config: {ex.Message}. Using defaults.");
        }

        var newConfig = new BridgeConfig();
        newConfig.Save();
        return newConfig;
    }

    public string ResolveSoundsDir(string reframeworkDir) =>
        ResolvePath(reframeworkDir, SoundsDir);

    public string ResolveEventsFile(string reframeworkDir) =>
        ResolvePath(reframeworkDir, EventsFile);

    public void Save()
    {
        try
        {
            var options = new JsonSerializerOptions { WriteIndented = true };
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(this, options));
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Config] Failed to save config: {ex.Message}");
        }
    }

    private bool UpgradeLegacyPaths()
    {
        var upgradedSoundsDir = MakePortable(SoundsDir, DefaultSoundsDir);
        var upgradedEventsFile = MakePortable(EventsFile, DefaultEventsFile);
        var changed =
            !string.Equals(SoundsDir, upgradedSoundsDir, StringComparison.Ordinal) ||
            !string.Equals(EventsFile, upgradedEventsFile, StringComparison.Ordinal);

        SoundsDir = upgradedSoundsDir;
        EventsFile = upgradedEventsFile;
        return changed;
    }

    private static string MakePortable(string configuredPath, string portablePath)
    {
        var normalized = configuredPath.Replace('/', '\\').Trim();
        var normalizedPortable = portablePath.Replace('/', '\\');
        var legacyRelative = @"reframework\" + normalizedPortable;

        if (normalized.Equals(legacyRelative, StringComparison.OrdinalIgnoreCase) ||
            normalized.EndsWith(@"\" + legacyRelative, StringComparison.OrdinalIgnoreCase) ||
            normalized.EndsWith(@"\" + normalizedPortable, StringComparison.OrdinalIgnoreCase))
        {
            return portablePath;
        }

        return configuredPath;
    }

    private static string ResolvePath(string reframeworkDir, string configuredPath)
    {
        var path = Path.IsPathRooted(configuredPath)
            ? configuredPath
            : Path.Combine(reframeworkDir, configuredPath);

        return Path.GetFullPath(path);
    }
}
