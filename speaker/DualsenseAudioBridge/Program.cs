using System.Diagnostics;
using DualsenseAudioBridge;

// Stand test for the experimental haptics path. Runs before the
// single-instance mutex and log redirection on purpose: it neither watches
// events nor spawns the transport, and its output belongs on the console.
// Physical actuator response additionally requires audio-haptics mode to be
// held (DualSenseEnhancedTransport.exe --test-haptics-mode).
if (RunHapticTestIfRequested(args))
    return;
if (RunSpeakerTestIfRequested(args))
    return;
if (RunSpeaker16BitTestIfRequested(args))
    return;

bool createdNew;
using var mutex = new Mutex(true, "DualsenseAudioBridge_RE4R", out createdNew);
if (!createdNew)
    return;

using var log = BridgeLog.Initialize();
Console.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] DualSense Audio Bridge starting");

BridgeRuntimeOptions options;
try
{
    options = BridgeRuntimeOptions.Parse(args);
}
catch (Exception ex)
{
    Console.WriteLine($"[Bridge] Startup error: {ex.Message}");
    return;
}

if (options.ListDevices)
{
    DeviceFinder.ListDevices();
    return;
}

var config = BridgeConfig.Load();
var soundsDir = config.ResolveSoundsDir(options.ReframeworkDirectory);
var eventsFile = config.ResolveEventsFile(options.ReframeworkDirectory);
var devicesFile = Path.Combine(
    options.ReframeworkDirectory,
    "data",
    "DualSenseEnhanced",
    "audio_devices.json");

Console.WriteLine($"[Config] REFramework:  {options.ReframeworkDirectory}");
Console.WriteLine($"[Config] Sounds dir:   {soundsDir}");
Console.WriteLine($"[Config] Events file:  {eventsFile}");
Console.WriteLine($"[Config] Devices file: {devicesFile}");
Console.WriteLine($"[Config] Volume:       {config.Volume:P0}");

// Runs the native speaker-route init as soon as the bridge starts (as soon
// as the controller connects), independent of the game-campaign-ready gate
// that --watch's trigger/gyro session waits for. The route is a one-shot
// duaLib write that has been hardware-confirmed to persist for the whole
// power cycle (survives process exit, even a Windows restart), so a short,
// self-contained probe run here is enough for the controller speaker to
// work immediately in menus/loading screens too, not just once a save is
// active. Runs before StartTriggerTransportWhenReady below, so this
// process's brief duaLib session is guaranteed to have exited (freeing the
// transport's single-instance mutex) long before --watch is ever launched.
RunEarlySpeakerInit(options.ReframeworkDirectory);

try
{
    Directory.CreateDirectory(soundsDir);
}
catch (Exception ex)
{
    Console.WriteLine($"[Bridge] Cannot create sounds directory: {ex.Message}");
    return;
}

var soundMap = new SoundMap(soundsDir);
using var player = new SoundPlayer(config.Device, config.Volume);
using var hapticPlayer = config.HapticsEnabled
    ? new HapticPlayer(config.Device, config.HapticsVolume)
    : null;
if (config.HapticsEnabled)
    Console.WriteLine($"[Config] Haptics:      enabled (volume {config.HapticsVolume:P0})");
using var watcher = new EventWatcher(eventsFile, player, soundMap, hapticPlayer);
using var deviceSnapshotWriter = new AudioDeviceSnapshotWriter(devicesFile);

var foundSounds = soundMap.KnownEvents
    .Where(eventName => soundMap.Resolve(eventName) != null)
    .ToList();
Console.WriteLine($"[Bridge] Sounds available: {foundSounds.Count}/{soundMap.KnownEvents.Count()}");
foreach (var eventName in foundSounds)
    Console.WriteLine($"[Bridge] Sound ready: {eventName}");

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cts.Cancel();
};

watcher.Start();
deviceSnapshotWriter.Start(cts.Token);
Console.WriteLine("[Bridge] Listening for events.");

using var triggerLaunchCts = CancellationTokenSource.CreateLinkedTokenSource(cts.Token);
var triggerLaunchTask = StartTriggerTransportWhenReady(
    options.ReframeworkDirectory,
    triggerLaunchCts.Token);

try
{
    if (options.GameProcessName != null)
        await WaitForGameExit(options.GameProcessName, cts.Token);
    else
        await Task.Delay(Timeout.Infinite, cts.Token);
}
catch (TaskCanceledException)
{
}

triggerLaunchCts.Cancel();
try
{
    var triggerTransport = await triggerLaunchTask;
    triggerTransport?.Dispose();
}
catch (TaskCanceledException)
{
}

watcher.Stop();
Console.WriteLine("[Bridge] Stopped.");

static async Task<Process?> StartTriggerTransportWhenReady(
    string reframeworkDirectory,
    CancellationToken cancellationToken)
{
    var dataDirectory = Path.Combine(reframeworkDirectory, "data");
    var transportDirectory = Path.Combine(dataDirectory, "DualSenseEnhanced");
    var readyFile = Path.Combine(transportDirectory, "trigger_transport.ready");
    var executable = Path.Combine(
        transportDirectory,
        "DualSenseEnhancedTransport.exe");
    var commandFile = Path.Combine(dataDirectory, "trigger_command.json");
    var gyroConfigFile = Path.Combine(transportDirectory, "native_gyro.json");

    try
    {
        // A marker must belong to this exact RE4R session.  Lua recreates it
        // only after CampaignManager.onStartInGame.
        File.Delete(readyFile);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[Trigger] Cannot clear stale ready marker: {ex.Message}");
    }

    Console.WriteLine("[Trigger] Waiting for in-game ready marker.");
    while (!cancellationToken.IsCancellationRequested)
    {
        try
        {
            if (File.Exists(readyFile) &&
                string.Equals(
                    File.ReadAllText(readyFile).Trim(),
                    "ready",
                    StringComparison.OrdinalIgnoreCase))
            {
                if (!File.Exists(executable))
                {
                    Console.WriteLine("[Trigger] Transport executable is unavailable; native triggers remain off.");
                    return null;
                }

                // The transport is single-instance (named mutex). A leftover
                // process from a previous session that hasn't noticed RE4R
                // already exited yet would otherwise make this session's
                // launch fail with "Another transport instance is already
                // running", silently disabling triggers and gyro for the
                // whole session with no retry.
                KillLeftoverTransport();

                var startInfo = new ProcessStartInfo(executable)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = transportDirectory,
                };
                startInfo.ArgumentList.Add("--watch");
                startInfo.ArgumentList.Add(commandFile);
                startInfo.ArgumentList.Add("--game-process");
                startInfo.ArgumentList.Add("re4");
                startInfo.ArgumentList.Add("--acknowledge-output-conflict");
                startInfo.ArgumentList.Add("--init-speaker");
                var gyro = ReadGyroConfig(gyroConfigFile);
                if (gyro.Enabled)
                {
                    startInfo.ArgumentList.Add("--gyro-mouse");
                    startInfo.ArgumentList.Add("--gyro-yaw-sensitivity");
                    startInfo.ArgumentList.Add(gyro.YawSensitivity.ToString(
                        System.Globalization.CultureInfo.InvariantCulture));
                    startInfo.ArgumentList.Add("--gyro-pitch-sensitivity");
                    startInfo.ArgumentList.Add(gyro.PitchSensitivity.ToString(
                        System.Globalization.CultureInfo.InvariantCulture));
                    startInfo.ArgumentList.Add("--gyro-deadzone");
                    startInfo.ArgumentList.Add(gyro.Deadzone.ToString(
                        System.Globalization.CultureInfo.InvariantCulture));
                    startInfo.ArgumentList.Add("--gyro-aim-threshold");
                    startInfo.ArgumentList.Add(gyro.AimThreshold.ToString(
                        System.Globalization.CultureInfo.InvariantCulture));
                    startInfo.ArgumentList.Add("--gyro-calibration-ms");
                    startInfo.ArgumentList.Add(gyro.CalibrationMs.ToString(
                        System.Globalization.CultureInfo.InvariantCulture));
                    if (gyro.InvertPitch)
                        startInfo.ArgumentList.Add("--gyro-invert-pitch");
                    Console.WriteLine("[Trigger] Native gyro-to-mouse enabled for this session.");
                }
                var process = Process.Start(startInfo);
                Console.WriteLine(process is null
                    ? "[Trigger] Failed to start transport."
                    : "[Trigger] Transport started after in-game ready marker.");
                return process;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Trigger] Ready-marker check failed: {ex.Message}");
        }

        await Task.Delay(250, cancellationToken);
    }

    return null;
}

static void KillLeftoverTransport()
{
    foreach (var process in Process.GetProcessesByName("DualSenseEnhancedTransport"))
    {
        try
        {
            Console.WriteLine($"[Trigger] Stopping leftover transport process (PID {process.Id}).");
            process.Kill();
            process.WaitForExit(2000);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Trigger] Could not stop leftover transport process: {ex.Message}");
        }
        finally
        {
            process.Dispose();
        }
    }
}

static GyroLaunchConfig ReadGyroConfig(string path)
{
    try
    {
        if (!File.Exists(path))
            return GyroLaunchConfig.Disabled;

        return System.Text.Json.JsonSerializer.Deserialize<GyroLaunchConfig>(
                   File.ReadAllText(path),
                   new System.Text.Json.JsonSerializerOptions
                   {
                       PropertyNameCaseInsensitive = true
                   })
               ?? GyroLaunchConfig.Disabled;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[Trigger] Native gyro config ignored: {ex.Message}");
        return GyroLaunchConfig.Disabled;
    }
}

static async Task WaitForGameExit(string processName, CancellationToken cancellationToken)
{
    var seenGame = false;
    var startupDeadline = DateTime.UtcNow.AddSeconds(15);
    Console.WriteLine($"[Bridge] Watching process: {processName}.exe");

    while (!cancellationToken.IsCancellationRequested)
    {
        var running = IsProcessRunning(processName);
        if (running)
        {
            seenGame = true;
        }
        else if (seenGame)
        {
            Console.WriteLine("[Bridge] Game exited.");
            return;
        }
        else if (DateTime.UtcNow >= startupDeadline)
        {
            Console.WriteLine("[Bridge] Game process was not found within 15 seconds.");
            return;
        }

        await Task.Delay(1000, cancellationToken);
    }
}

static bool IsProcessRunning(string processName)
{
    var processes = Process.GetProcessesByName(processName);
    try
    {
        return processes.Length > 0;
    }
    finally
    {
        foreach (var process in processes)
            process.Dispose();
    }
}

static bool RunHapticTestIfRequested(string[] args)
{
    var index = Array.FindIndex(
        args,
        a => a.Equals("--test-haptic", StringComparison.OrdinalIgnoreCase));
    if (index < 0)
        return false;

    var side = HapticPlayer.Side.Both;
    if (index + 1 < args.Length && !args[index + 1].StartsWith("--"))
    {
        side = args[index + 1].ToLowerInvariant() switch
        {
            "left" => HapticPlayer.Side.Left,
            "right" => HapticPlayer.Side.Right,
            "both" => HapticPlayer.Side.Both,
            _ => throw new ArgumentException(
                "--test-haptic accepts left, right, or both.")
        };
    }

    const float durationSeconds = 4f;
    var config = BridgeConfig.Load();
    using var haptic = new HapticPlayer(config.Device, config.HapticsVolume);
    Console.WriteLine(
        $"[Haptic] Test tone ({side}, 80 Hz, {durationSeconds:0}s) on channels 3/4. " +
        "Physical response requires audio-haptics mode to be held, e.g. " +
        "DualSenseEnhancedTransport.exe --test-haptics-mode --acknowledge-output-conflict.");
    if (haptic.PlayTestTone(side, durationSeconds: durationSeconds))
    {
        Thread.Sleep(TimeSpan.FromSeconds(durationSeconds + 0.5));
        Console.WriteLine("[Haptic] Test tone finished.");
    }
    return true;
}

static void RunEarlySpeakerInit(string reframeworkDirectory)
{
    var transportDirectory = Path.Combine(reframeworkDirectory, "data", "DualSenseEnhanced");
    var executable = Path.Combine(transportDirectory, "DualSenseEnhancedTransport.exe");
    if (!File.Exists(executable))
    {
        Console.WriteLine("[Speaker] Init skipped: transport executable is unavailable.");
        return;
    }

    try
    {
        var startInfo = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = transportDirectory,
        };
        startInfo.ArgumentList.Add("--test-speaker-init");
        startInfo.ArgumentList.Add("--acknowledge-output-conflict");
        startInfo.ArgumentList.Add("--duration");
        startInfo.ArgumentList.Add("3000");
        startInfo.ArgumentList.Add("--speaker-volume");
        startInfo.ArgumentList.Add("72");

        using var process = Process.Start(startInfo);
        if (process is null)
        {
            Console.WriteLine("[Speaker] Init skipped: failed to start the probe process.");
            return;
        }

        // Bounded well above the probe's own 3000ms hold so a genuinely
        // stuck probe can't block bridge startup indefinitely, while still
        // giving it time to finish normally.
        if (!process.WaitForExit(10000))
        {
            Console.WriteLine("[Speaker] Init probe did not exit in time; leaving it running.");
            return;
        }

        Console.WriteLine(
            $"[Speaker] Native speaker route initialized (probe exit code {process.ExitCode}).");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[Speaker] Init failed: {ex.Message}");
    }
}

static bool RunSpeakerTestIfRequested(string[] args)
{
    var index = Array.FindIndex(
        args,
        a => a.Equals("--test-speaker", StringComparison.OrdinalIgnoreCase));
    if (index < 0)
        return false;

    var frequency = 440f;
    if (index + 1 < args.Length && !args[index + 1].StartsWith("--"))
    {
        if (!float.TryParse(
                args[index + 1],
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture,
                out frequency) || frequency < 20f || frequency > 20000f)
        {
            throw new ArgumentException(
                "--test-speaker accepts an optional frequency of 20..20000 Hz.");
        }
    }

    var durationSeconds = 4f;
    var durationIndex = Array.FindIndex(
        args, a => a.Equals("--duration-seconds", StringComparison.OrdinalIgnoreCase));
    if (durationIndex >= 0 && durationIndex + 1 < args.Length)
    {
        if (!float.TryParse(
                args[durationIndex + 1],
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture,
                out durationSeconds) || durationSeconds < 1f || durationSeconds > 300f)
        {
            throw new ArgumentException("--duration-seconds must be 1..300.");
        }
    }
    var config = BridgeConfig.Load();
    using var haptic = new HapticPlayer(config.Device, config.HapticsVolume);
    Console.WriteLine(
        $"[Speaker] Test tone ({frequency:0} Hz, {durationSeconds:0}s) on channel 2 " +
        "(the controller speaker feed; channels 3/4 stay silent so the actuators " +
        "must not vibrate). Audible sound requires the speaker route to be " +
        "initialized first, e.g. DualSenseEnhancedTransport.exe " +
        "--test-speaker-init --acknowledge-output-conflict --duration 60000.");
    if (haptic.PlaySpeakerTestTone(frequency, durationSeconds))
    {
        Thread.Sleep(TimeSpan.FromSeconds(durationSeconds + 0.5));
        Console.WriteLine("[Speaker] Test tone finished.");
    }
    return true;
}

// Standalone diagnostic, deliberately independent of HapticPlayer's proven
// 32-bit float actuator path: a USB capture of DualSenseY-v2's working
// speaker stream measured 384 bytes per 1ms isochronous packet on 4
// channels at 48kHz, which is only consistent with 16-bit PCM (384 /
// (4 * 2) = 48 frames = exactly 1ms @ 48kHz; 32-bit would need 768 bytes).
// Testing whether the DualSense firmware's speaker DAC specifically
// requires 16-bit samples on the wire, unlike the actuator channels which
// are already confirmed to tolerate 32-bit float.
static bool RunSpeaker16BitTestIfRequested(string[] args)
{
    var index = Array.FindIndex(
        args,
        a => a.Equals("--test-speaker-16bit", StringComparison.OrdinalIgnoreCase));
    if (index < 0)
        return false;

    const int sampleRate = 48000;
    const int channels = 4;
    const float frequency = 440f;
    const float durationSeconds = 5f;

    var config = BridgeConfig.Load();
    var device = string.IsNullOrWhiteSpace(config.Device)
        ? DeviceFinder.FindDualSense()
        : DeviceFinder.FindByName(config.Device);
    if (device is null)
    {
        Console.WriteLine("[Speaker16] DualSense endpoint not found.");
        return true;
    }

    Console.WriteLine(
        $"[Speaker16] Test tone ({frequency:0} Hz, {durationSeconds:0}s) on channel 2, " +
        "16-bit PCM 4-channel 48kHz (matches the byte layout measured in a working " +
        "DualSenseY-v2 USB capture, unlike the 32-bit float format the actuator " +
        "path uses). Audible sound requires the speaker route to be initialized " +
        "first, e.g. DualSenseEnhancedTransport.exe --test-speaker-init " +
        "--acknowledge-output-conflict --duration 60000.");

    var totalFrames = (int)(sampleRate * durationSeconds);
    var samples = new short[totalFrames * channels];
    const double fadeFraction = 0.04;
    for (var frame = 0; frame < totalFrames; frame++)
    {
        var progress = (double)frame / totalFrames;
        var envelope =
            progress < fadeFraction ? progress / fadeFraction :
            progress > 1.0 - fadeFraction ? (1.0 - progress) / fadeFraction :
            1.0;
        var sample = (short)(
            Math.Sin(2.0 * Math.PI * frequency * frame / sampleRate) *
            0.5 * envelope * short.MaxValue);
        samples[frame * channels + 1] = sample; // channel index 1 = speaker feed
    }

    var bytes = new byte[samples.Length * sizeof(short)];
    Buffer.BlockCopy(samples, 0, bytes, 0, bytes.Length);

    using var stream = new NAudio.Wave.RawSourceWaveStream(
        new MemoryStream(bytes),
        new NAudio.Wave.WaveFormatExtensible(sampleRate, 16, channels));
    // Shared mode lets Windows' audio engine pick/cache the actual wire
    // format and USB alternate setting; a bare WASAPI open after a fresh
    // device connect may not reliably force the exact 4-channel/16-bit
    // configuration this test requests. Exclusive mode hands the app direct
    // control over the format instead (Windows' device properties already
    // confirmed "Allow applications to use exclusive mode" is enabled).
    var exclusive = args.Contains("--exclusive", StringComparer.OrdinalIgnoreCase);
    using var output = new NAudio.Wave.WasapiOut(
        device,
        exclusive
            ? NAudio.CoreAudioApi.AudioClientShareMode.Exclusive
            : NAudio.CoreAudioApi.AudioClientShareMode.Shared,
        true, 50);
    Console.WriteLine($"[Speaker16] Mode: {(exclusive ? "Exclusive" : "Shared")}");
    output.Init(stream);
    output.Play();
    Thread.Sleep(TimeSpan.FromSeconds(durationSeconds + 0.5));
    Console.WriteLine("[Speaker16] Test tone finished.");
    return true;
}

sealed class GyroLaunchConfig
{
    public static GyroLaunchConfig Disabled { get; } = new();
    public bool Enabled { get; init; }
    public double YawSensitivity { get; init; } = 600;
    public double PitchSensitivity { get; init; } = 600;
    public double Deadzone { get; init; } = 0.03;
    public int AimThreshold { get; init; } = 32;
    public int CalibrationMs { get; init; } = 1500;
    public bool InvertPitch { get; init; }
}
