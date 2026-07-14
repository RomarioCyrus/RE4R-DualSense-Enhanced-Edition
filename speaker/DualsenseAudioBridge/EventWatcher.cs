using System.Text.Json;

namespace DualsenseAudioBridge;

/// <summary>
/// Watches audio_events.json written by Lua (audio_feedback.lua).
/// Uses FileSystemWatcher for instant detection (no polling lag).
///
/// The file is an append-only NDJSON log (one JSON object per line); the
/// watcher tracks a byte offset and only reads newly-appended lines on each
/// change notification, rather than re-reading and overwriting a single
/// JSON value. This avoids a race present in the old single-overwritten-file
/// design: two emits close together could be coalesced by the OS into one
/// FileSystemWatcher notification, and since each write fully replaced the
/// file's content, the earlier event was silently lost. Appending instead
/// of overwriting means a coalesced notification still results in every
/// line since the last read position being processed -- no event is ever
/// skipped, regardless of how many writes land between watcher callbacks.
///
/// File format (one per line):
/// {"event":"heal_herb","ts":12345.678901,"device_id":"","device":"","volume":0.85}
/// </summary>
public class EventWatcher : IDisposable
{
    private const string HapticEventPrefix = "haptic_";

    private readonly string _eventsFile;
    private readonly SoundPlayer _player;
    private readonly SoundMap _soundMap;
    private readonly HapticPlayer? _hapticPlayer;
    private readonly FileSystemWatcher _watcher;

    private long _readOffset;
    private readonly object _lock = new();

    public EventWatcher(
        string eventsFile,
        SoundPlayer player,
        SoundMap soundMap,
        HapticPlayer? hapticPlayer = null)
    {
        _eventsFile = eventsFile;
        _player     = player;
        _soundMap   = soundMap;
        _hapticPlayer = hapticPlayer;

        // Ensure directory exists
        var dir = Path.GetDirectoryName(eventsFile)!;
        Directory.CreateDirectory(dir);

        _watcher = new FileSystemWatcher(dir, Path.GetFileName(eventsFile))
        {
            NotifyFilter        = NotifyFilters.LastWrite | NotifyFilters.Size,
            EnableRaisingEvents = false
        };
        _watcher.Changed += OnFileChanged;
        _watcher.Created += OnFileChanged;
    }

    public void Start()
    {
        // Skip any pre-existing content (e.g. leftover from before the
        // bridge started) -- only react to lines appended from now on.
        try
        {
            _readOffset = new FileInfo(_eventsFile).Exists
                ? new FileInfo(_eventsFile).Length
                : 0;
        }
        catch
        {
            _readOffset = 0;
        }

        _watcher.EnableRaisingEvents = true;
        Console.WriteLine($"[Watcher] Watching: {_eventsFile}");
    }

    public void Stop()
    {
        _watcher.EnableRaisingEvents = false;
    }

    private void OnFileChanged(object sender, FileSystemEventArgs e)
    {
        lock (_lock)
        {
            try
            {
                var lines = TryReadNewLines(_eventsFile, ref _readOffset);
                foreach (var line in lines)
                {
                    ProcessLine(line);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Watcher] Error: {ex.Message}");
            }
        }
    }

    private void ProcessLine(string line)
    {
        if (string.IsNullOrWhiteSpace(line)) return;

        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;

            if (!root.TryGetProperty("event", out var evProp)) return;

            var eventName = evProp.GetString() ?? "";
            string? deviceId = null;
            string? device = null;
            float? volume = null;

            if (root.TryGetProperty("device_id", out var deviceIdProp) &&
                deviceIdProp.ValueKind == JsonValueKind.String)
            {
                deviceId = deviceIdProp.GetString();
            }

            if (root.TryGetProperty("device", out var deviceProp) &&
                deviceProp.ValueKind == JsonValueKind.String)
            {
                device = deviceProp.GetString();
            }

            if (root.TryGetProperty("volume", out var volumeProp) &&
                volumeProp.ValueKind == JsonValueKind.Number &&
                volumeProp.TryGetSingle(out var parsedVolume))
            {
                volume = parsedVolume;
            }

            float? hapticIntensity = null;
            if (root.TryGetProperty("haptic_intensity", out var intensityProp) &&
                intensityProp.ValueKind == JsonValueKind.Number &&
                intensityProp.TryGetSingle(out var parsedIntensity))
            {
                hapticIntensity = parsedIntensity;
            }

            Dispatch(eventName, deviceId, device, volume, hapticIntensity);
        }
        catch (JsonException)
        {
            // Partial/corrupt line (shouldn't happen with line-based
            // reads, but skip defensively).
        }
    }

    private void Dispatch(string eventName, string? deviceId, string? device, float? volume, float? hapticIntensity = null)
    {
        // low_hp_end = signal to stop the looping heartbeat, no sound.
        // Only that channel -- must not interrupt unrelated sounds that
        // happen to still be playing.
        if (eventName == "low_hp_end")
        {
            _player.StopChannel("low_hp");
            return;
        }

        // "haptic_" events target the actuators (channels 3/4), never the
        // speaker. When haptics are disabled in the bridge config the event
        // is dropped silently on purpose: Lua's haptics toggle may be
        // deployed ahead of the user's bridge config opt-in.
        if (eventName.StartsWith(HapticEventPrefix, StringComparison.OrdinalIgnoreCase))
        {
            if (_hapticPlayer == null) return;

            var hapticPath = _soundMap.Resolve(eventName);
            if (hapticPath == null)
            {
                Console.WriteLine($"[Watcher] No haptic sound for event: {eventName}");
                return;
            }

            Console.WriteLine($"[Watcher] {eventName} → actuators ({Path.GetFileName(hapticPath)})");
            _hapticPlayer.PlayAlternating(hapticPath, volume, hapticIntensity);
            return;
        }

        var path = _soundMap.Resolve(eventName);
        if (path == null)
        {
            Console.WriteLine($"[Watcher] No sound for event: {eventName}");
            return;
        }

        Console.WriteLine($"[Watcher] {eventName} → {Path.GetFileName(path)}");
        _player.Play(eventName, path, deviceId, device, volume);
    }

    /// <summary>
    /// Read all complete lines appended since the last read offset, with
    /// retry (Lua may still have the file handle briefly). Advances
    /// <paramref name="offset"/> only past complete lines (ending in '\n'),
    /// so a line still being written is picked up on the next notification
    /// instead of being read half-written. Resets to the start if the file
    /// was truncated (e.g. a fresh Lua script reload) since the last read.
    /// </summary>
    private static List<string> TryReadNewLines(string path, ref long offset, int retries = 3)
    {
        var result = new List<string>();

        for (int i = 0; i < retries; i++)
        {
            try
            {
                using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

                if (fs.Length < offset)
                {
                    // File was truncated (new session) -- start over.
                    offset = 0;
                }

                fs.Seek(offset, SeekOrigin.Begin);
                using var sr = new StreamReader(fs);
                var text = sr.ReadToEnd();

                var lastNewline = text.LastIndexOf('\n');
                if (lastNewline < 0) return result;

                var complete = text.Substring(0, lastNewline);
                offset += System.Text.Encoding.UTF8.GetByteCount(text.Substring(0, lastNewline + 1));

                foreach (var line in complete.Split('\n'))
                {
                    if (!string.IsNullOrWhiteSpace(line)) result.Add(line);
                }
                return result;
            }
            catch (IOException)
            {
                Thread.Sleep(15);
            }
        }
        return result;
    }

    public void Dispose()
    {
        _watcher.Dispose();
    }
}
