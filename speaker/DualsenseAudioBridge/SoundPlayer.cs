using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace DualsenseAudioBridge;

/// <summary>
/// Plays audio files through a specific WASAPI device (DualSense speaker).
/// Non-blocking: each play runs on a background thread.
///
/// Unrelated sounds play concurrently (WASAPI shared mode mixes multiple
/// streams to the same endpoint fine) -- e.g. closing the inventory while
/// a heal sound is still finishing should not cut the heal off. Each event
/// name has its own playback "channel": starting a new sound for an event
/// name that's already playing stops the previous instance of that *same*
/// event first (so e.g. the low-HP heartbeat, re-emitted every beat,
/// replaces itself instead of stacking overlapping copies), but playing a
/// different event name never touches another event's channel.
/// </summary>
public class SoundPlayer : IDisposable
{
    private sealed class Channel
    {
        public WasapiOut? Output;
        public CancellationTokenSource Cts;

        public Channel(CancellationTokenSource cts)
        {
            Cts = cts;
        }
    }

    private readonly string _defaultDevice;
    private readonly float _defaultVolume;
    private readonly object _lock = new();
    private readonly Dictionary<string, MMDevice> _deviceCache =
        new(StringComparer.OrdinalIgnoreCase);

    private readonly Dictionary<string, Channel> _channels =
        new(StringComparer.OrdinalIgnoreCase);

    public SoundPlayer(string defaultDevice = "", float defaultVolume = 0.85f)
    {
        _defaultDevice = defaultDevice;
        _defaultVolume = Math.Clamp(defaultVolume, 0f, 1f);

        // Resolve supported controller endpoints once at startup so even the
        // first in-game event does not pay the Windows device-enumeration cost.
        GetCachedDevice(null, "");
        GetCachedDevice(null, "DualSense Wireless Controller");
        GetCachedDevice(null, "DualSense Edge Wireless Controller");
    }

    /// <summary>
    /// Play a sound file asynchronously on the given event's channel.
    /// If a sound is already playing for this same <paramref name="channel"/>
    /// (i.e. the same event name re-fired), it is stopped first. Sounds on
    /// different channels are never interrupted by each other.
    /// </summary>
    public void Play(
        string channel,
        string filePath,
        string? requestedDeviceId = null,
        string? requestedDevice = null,
        float? requestedVolume = null)
    {
        if (!File.Exists(filePath))
        {
            Console.WriteLine($"[Player] File not found: {filePath}");
            return;
        }

        lock (_lock)
        {
            StopChannelLocked(channel);

            var entry = new Channel(new CancellationTokenSource());
            _channels[channel] = entry;

            var thread = new Thread(() =>
                PlayInternal(channel, entry, filePath, requestedDeviceId, requestedDevice, requestedVolume))
            {
                IsBackground = true,
                Name = "AudioPlayback"
            };
            thread.Start();
        }
    }

    private void PlayInternal(
        string channel,
        Channel entry,
        string filePath,
        string? requestedDeviceId,
        string? requestedDevice,
        float? requestedVolume)
    {
        var ct = entry.Cts.Token;
        WasapiOut? output = null;
        AudioFileReader? reader = null;
        MMDevice? device = null;

        try
        {
            if (ct.IsCancellationRequested) return;

            var deviceName = requestedDevice ?? _defaultDevice;
            device = GetCachedDevice(requestedDeviceId, deviceName);

            if (device == null)
            {
                Console.WriteLine($"[Player] Device not found: id={requestedDeviceId ?? ""} name={deviceName}");
                return;
            }

            // Values above 1.0 are an intentional boost above unity gain (UI
            // slider goes to 200%) for the DualSense's quiet internal
            // speaker; NAudio's VolumeSampleProvider just multiplies samples
            // and does not clamp to 1.0 itself, so this amplifies rather
            // than being a no-op.
            var volume = Math.Clamp(requestedVolume ?? _defaultVolume, 0f, 2f);
            reader = new AudioFileReader(filePath) { Volume = volume };
            output = new WasapiOut(device, AudioClientShareMode.Shared, true, 50);
            output.Init(reader);

            lock (_lock)
            {
                if (ct.IsCancellationRequested) { output.Dispose(); reader.Dispose(); return; }
                entry.Output = output;
            }

            Console.WriteLine($"[Player] Device: {device.FriendlyName} | Volume: {volume:P0}");
            output.Play();

            // Wait for playback to finish or cancellation
            while (output.PlaybackState == PlaybackState.Playing && !ct.IsCancellationRequested)
                Thread.Sleep(20);

            output.Stop();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            Console.WriteLine($"[Player] Playback error: {ex.Message}");
        }
        finally
        {
            lock (_lock)
            {
                if (_channels.TryGetValue(channel, out var current) && current == entry)
                    _channels.Remove(channel);
            }
            output?.Dispose();
            reader?.Dispose();
        }
    }

    private MMDevice? GetCachedDevice(string? deviceId, string? deviceName)
    {
        var cacheKey = !string.IsNullOrWhiteSpace(deviceId)
            ? "id:" + deviceId.Trim()
            : string.IsNullOrWhiteSpace(deviceName)
                ? "<auto>"
                : "name:" + deviceName.Trim();

        lock (_lock)
        {
            if (_deviceCache.TryGetValue(cacheKey, out var cached))
                return cached;

            var found = !string.IsNullOrWhiteSpace(deviceId)
                ? DeviceFinder.FindById(deviceId.Trim())
                : cacheKey == "<auto>"
                    ? DeviceFinder.FindDualSense()
                    : DeviceFinder.FindByName(deviceName?.Trim() ?? "");

            if (found != null)
            {
                _deviceCache[cacheKey] = found;
                Console.WriteLine($"[Player] Cached device: {found.FriendlyName}");
            }

            return found;
        }
    }

    /// <summary>Stops playback on a single named channel, if active.</summary>
    public void StopChannel(string channel)
    {
        lock (_lock) { StopChannelLocked(channel); }
    }

    /// <summary>Must be called while holding <see cref="_lock"/>.</summary>
    private void StopChannelLocked(string channel)
    {
        if (!_channels.TryGetValue(channel, out var entry)) return;
        entry.Cts.Cancel();
        try { entry.Output?.Stop(); } catch { }
        _channels.Remove(channel);
    }

    /// <summary>Stops every currently playing channel.</summary>
    public void Stop()
    {
        lock (_lock)
        {
            foreach (var channel in _channels.Keys.ToList())
                StopChannelLocked(channel);
        }
    }

    public void Dispose()
    {
        Stop();
        lock (_lock)
        {
            foreach (var device in _deviceCache.Values.Distinct())
                device.Dispose();
            _deviceCache.Clear();
        }
    }
}
