using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Encodings.Web;

namespace DualsenseAudioBridge;

public sealed class AudioDeviceSnapshotWriter : IDisposable
{
    private sealed class Snapshot
    {
        [JsonPropertyName("generated_at")]
        public string GeneratedAt { get; init; } = "";

        [JsonPropertyName("devices")]
        public List<AudioEndpointInfo> Devices { get; init; } = new();
    }

    private readonly string _path;
    private readonly TimeSpan _interval;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private CancellationTokenSource? _cts;
    private Task? _task;

    public AudioDeviceSnapshotWriter(string path, TimeSpan? interval = null)
    {
        _path = path;
        _interval = interval ?? TimeSpan.FromSeconds(3);
    }

    public void Start(CancellationToken parentToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        WriteOnce();

        _cts = CancellationTokenSource.CreateLinkedTokenSource(parentToken);
        _task = Task.Run(() => RunAsync(_cts.Token), _cts.Token);
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(_interval, cancellationToken);
                WriteOnce();
            }
            catch (TaskCanceledException)
            {
                return;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Devices] Refresh failed: {ex.Message}");
            }
        }
    }

    private void WriteOnce()
    {
        var snapshot = new Snapshot
        {
            GeneratedAt = DateTimeOffset.Now.ToString("O"),
            Devices = DeviceFinder.ListActiveRenderEndpoints()
        };

        var tempPath = _path + ".tmp";
        File.WriteAllText(tempPath, JsonSerializer.Serialize(snapshot, _jsonOptions));
        File.Copy(tempPath, _path, overwrite: true);
        File.Delete(tempPath);
    }

    public void Dispose()
    {
        if (_cts == null) return;
        _cts.Cancel();
        try { _task?.Wait(TimeSpan.FromSeconds(1)); } catch { }
        _cts.Dispose();
    }
}
