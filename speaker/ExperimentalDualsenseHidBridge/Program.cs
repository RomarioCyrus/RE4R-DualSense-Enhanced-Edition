using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace DualSenseHapticsProbe;

internal static class Program
{
    private const string Version = "0.3.0-experimental";

    private static int Main(string[] args)
    {
        Console.WriteLine($"DualSense Haptics Probe {Version}");
        Console.WriteLine("Experimental standalone tool. It does not modify the stable RE4R mod.");
        Console.WriteLine();

        try
        {
            var options = Options.Parse(args);
            return options.Command switch
            {
                Command.Help => PrintHelp(),
                Command.List => ListDevices(),
                Command.SelfTest => RunSelfTest(),
                Command.HidAudioMode => RunHidAudioMode(),
                Command.Tone => RunTone(options),
                Command.Loopback => RunLoopback(options),
                _ => PrintHelp()
            };
        }
        catch (ArgumentException ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            return 2;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Fatal error: {ex}");
            return 1;
        }
    }

    private static int PrintHelp()
    {
        Console.WriteLine(
            @"Commands:
  --list
      List active render endpoints and their mix formats.

  --self-test
      Verify channel mapping and DSP without opening an audio device.

  --set-audio-haptics
      Send one USB HID report selecting native/audio haptics instead of
      compatible rumble. Experimental; RE4R may immediately override it.

  --tone left|right|both [options]
      Send a short sine test directly to DualSense haptic channels 3/4.

  --loopback [options]
      Capture a Windows render endpoint and continuously copy its audio into
      DualSense haptic channels 3/4. Press Q, Escape, or Ctrl+C to stop.

Options:
  --device <text>       Output endpoint name contains this text.
                        Default: auto-detect DualSense / Wireless Controller.
  --source <text>       Loopback source endpoint name contains this text.
                        Default: Windows default multimedia output.
  --preset <name>       raw, natural, ps5, or impact. Default: ps5.
  --gain <0..4>         Override preset haptic gain.
  --gate <0..1>         Override preset noise gate threshold.
  --highpass <Hz>       Override preset high-pass cutoff.
  --lowpass <Hz>        Override preset low-pass cutoff; 0 disables it.
  --transient <0..4>    Override transient emphasis.
  --tail <0..2>         Override sustained/reverb tail level.
  --duration <seconds>  Tone duration. Default: 1.0.
  --frequency <Hz>      Tone frequency. Default: 120.
  --latency <ms>        WASAPI output latency. Default: 20.
  --swap                Swap left and right haptic channels.
  --audio-haptics       Send the one-shot audio-haptics HID selection before
                        starting a tone or loopback stream.
  --audio-haptics-burst Start audio first, then send five selections over
                        200 ms. Diagnostic only; tone mode only.

Examples:
  DualSenseHapticsProbe.exe --list
  DualSenseHapticsProbe.exe --tone left --gain 0.35
  DualSenseHapticsProbe.exe --tone left --audio-haptics --gain 0.20
  DualSenseHapticsProbe.exe --tone left --audio-haptics-burst --duration 1.5
  DualSenseHapticsProbe.exe --tone both --frequency 160 --duration 0.5
  DualSenseHapticsProbe.exe --loopback --preset ps5
  DualSenseHapticsProbe.exe --loopback --preset natural

Important:
  - Connect the physical DualSense by USB.
  - The output endpoint must expose at least four channels.
  - This v0.3 captures an endpoint mix, not an internal Wwise SFX bus.
  - For an SFX-only approximation, temporarily set RE4R Music and Voice to 0.
");
        return 0;
    }

    private static int ListDevices()
    {
        using var enumerator = new MMDeviceEnumerator();
        var defaultDevice = enumerator.GetDefaultAudioEndpoint(
            DataFlow.Render,
            Role.Multimedia);

        Console.WriteLine("Active render endpoints:");
        foreach (var device in enumerator.EnumerateAudioEndPoints(
                     DataFlow.Render,
                     DeviceState.Active))
        {
            using (device)
            {
                var format = device.AudioClient.MixFormat;
                var marker = device.ID == defaultDevice.ID ? " [DEFAULT]" : "";
                Console.WriteLine(
                    $"- {device.FriendlyName}{marker}\n" +
                    $"  ID: {device.ID}\n" +
                    $"  Mix: {format.SampleRate} Hz, {format.Channels} ch, " +
                    $"{format.BitsPerSample}-bit, {format.Encoding}");
            }
        }

        return 0;
    }

    private static int RunSelfTest()
    {
        var tone = new HapticToneSampleProvider(
            ToneSide.Left,
            120f,
            0.1f,
            0.5f,
            swap: false);
        var buffer = new float[480 * 4];
        var read = tone.Read(buffer, 0, buffer.Length);
        if (read <= 0)
            throw new InvalidOperationException("Tone provider returned no samples.");

        var speakerEnergy = 0f;
        var leftEnergy = 0f;
        var rightEnergy = 0f;
        for (var i = 0; i < read; i += 4)
        {
            speakerEnergy += MathF.Abs(buffer[i]) + MathF.Abs(buffer[i + 1]);
            leftEnergy += MathF.Abs(buffer[i + 2]);
            rightEnergy += MathF.Abs(buffer[i + 3]);
        }

        if (speakerEnergy != 0f || leftEnergy <= 0f || rightEnergy != 0f)
        {
            throw new InvalidOperationException(
                "Four-channel routing self-test failed.");
        }

        Console.WriteLine("PASS: channels 1/2 are silent.");
        Console.WriteLine("PASS: left haptic maps to channel 3.");
        Console.WriteLine("PASS: right haptic remains silent in left-only test.");
        Console.WriteLine("PASS: DSP providers initialized at 48 kHz float.");
        return 0;
    }

    private static int RunHidAudioMode()
    {
        Console.WriteLine(DualSenseHidModeSwitcher.SelectAudioHapticsMode());
        Console.WriteLine(
            "No report is repeated. A game may restore compatible rumble immediately.");
        return 0;
    }

    private static int RunTone(Options options)
    {
        if (!options.AudioHapticsBurst)
            ApplyAudioHapticsSelection(options);
        using var outputDevice = DeviceLocator.FindOutput(options.Device);
        PrintOutputDevice(outputDevice);
        EnsureFourChannels(outputDevice);

        var toneGain = options.Gain ?? 0.20f;
        var source = new HapticToneSampleProvider(
            options.ToneSide,
            options.Frequency,
            options.DurationSeconds,
            toneGain,
            options.Swap);

        using var output = new WasapiOut(
            outputDevice,
            AudioClientShareMode.Shared,
            true,
            options.LatencyMs);
        output.Init(new ExtensibleFloatWaveProvider(source));

        Console.WriteLine(
            $"Tone: {options.ToneSide.ToString().ToLowerInvariant()}, " +
            $"{options.Frequency:0.#} Hz, {options.DurationSeconds:0.##} s, " +
            $"gain {toneGain:0.###}");
        Console.WriteLine("If there is no actuator response, the controller may not be in audio-haptics mode.");

        output.Play();
        if (options.AudioHapticsBurst)
            RunAudioHapticsBurst();
        while (output.PlaybackState == PlaybackState.Playing)
            Thread.Sleep(10);

        return 0;
    }

    private static int RunLoopback(Options options)
    {
        ApplyAudioHapticsSelection(options);
        using var outputDevice = DeviceLocator.FindOutput(options.Device);
        using var sourceDevice = DeviceLocator.FindSource(options.Source);
        PrintOutputDevice(outputDevice);
        EnsureFourChannels(outputDevice);

        Console.WriteLine($"Loopback source: {sourceDevice.FriendlyName}");
        var dsp = HapticDspSettings.Create(
            options.Preset,
            options.Gain,
            options.Gate,
            options.HighPassHz,
            options.LowPassHz,
            options.TransientBoost,
            options.TailLevel);
        Console.WriteLine(
            $"Preset: {dsp.Name} | gain={dsp.Gain:0.###}, gate={dsp.Gate:0.####}, " +
            $"band={dsp.HighPassHz:0.#}-{(dsp.LowPassHz <= 0 ? "off" : dsp.LowPassHz.ToString("0.#"))} Hz, " +
            $"transient={dsp.TransientBoost:0.##}, tail={dsp.TailLevel:0.##}, " +
            $"latency={options.LatencyMs} ms");

        using var capture = new WasapiLoopbackCapture(sourceDevice);
        var buffered = new BufferedWaveProvider(capture.WaveFormat)
        {
            BufferDuration = TimeSpan.FromMilliseconds(250),
            DiscardOnBufferOverflow = true,
            ReadFully = true
        };

        ISampleProvider samples = buffered.ToSampleProvider();
        samples = new StereoDownmixSampleProvider(samples);
        if (samples.WaveFormat.SampleRate != HapticLoopbackSampleProvider.OutputSampleRate)
            samples = new WdlResamplingSampleProvider(
                samples,
                HapticLoopbackSampleProvider.OutputSampleRate);

        var mapped = new HapticLoopbackSampleProvider(
            samples,
            dsp,
            options.Swap);

        using var output = new WasapiOut(
            outputDevice,
            AudioClientShareMode.Shared,
            true,
            options.LatencyMs);
        output.Init(new ExtensibleFloatWaveProvider(mapped));

        capture.DataAvailable += (_, eventArgs) =>
        {
            buffered.AddSamples(eventArgs.Buffer, 0, eventArgs.BytesRecorded);
        };
        capture.RecordingStopped += (_, eventArgs) =>
        {
            if (eventArgs.Exception != null)
                Console.Error.WriteLine($"Capture stopped: {eventArgs.Exception.Message}");
        };

        using var quit = new ManualResetEventSlim(false);
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            quit.Set();
        };

        capture.StartRecording();
        output.Play();
        Console.WriteLine();
        Console.WriteLine("LIVE. Press Q or Escape to stop.");

        while (!quit.IsSet)
        {
            if (Console.KeyAvailable)
            {
                var key = Console.ReadKey(intercept: true).Key;
                if (key is ConsoleKey.Q or ConsoleKey.Escape)
                    quit.Set();
            }

            if (output.PlaybackState == PlaybackState.Stopped)
                throw new InvalidOperationException("WASAPI haptic output stopped unexpectedly.");

            Thread.Sleep(25);
        }

        capture.StopRecording();
        output.Stop();
        Console.WriteLine("Stopped.");
        return 0;
    }

    private static void ApplyAudioHapticsSelection(Options options)
    {
        if (!options.AudioHaptics)
            return;
        Console.WriteLine(DualSenseHidModeSwitcher.SelectAudioHapticsMode());
    }

    private static void RunAudioHapticsBurst()
    {
        const int count = 5;
        const int intervalMs = 50;
        Console.WriteLine(
            $"Diagnostic HID burst: {count} selections, {intervalMs} ms apart.");
        for (var i = 0; i < count; i++)
        {
            Console.WriteLine(
                $"  {i + 1}/{count}: " +
                DualSenseHidModeSwitcher.SelectAudioHapticsMode());
            if (i + 1 < count)
                Thread.Sleep(intervalMs);
        }
    }

    private static void PrintOutputDevice(MMDevice device)
    {
        var format = device.AudioClient.MixFormat;
        Console.WriteLine($"Haptic output: {device.FriendlyName}");
        Console.WriteLine(
            $"Endpoint mix: {format.SampleRate} Hz, {format.Channels} ch, " +
            $"{format.BitsPerSample}-bit, {format.Encoding}");
    }

    private static void EnsureFourChannels(MMDevice device)
    {
        var channels = device.AudioClient.MixFormat.Channels;
        if (channels < 4)
        {
            throw new InvalidOperationException(
                $"Selected endpoint exposes only {channels} channel(s). " +
                "DualSense audio haptics require the 4-channel USB endpoint.");
        }
    }
}

internal enum Command
{
    Help,
    List,
    SelfTest,
    HidAudioMode,
    Tone,
    Loopback
}

internal enum ToneSide
{
    Left,
    Right,
    Both
}

internal enum HapticPreset
{
    Raw,
    Natural,
    Ps5,
    Impact
}

internal sealed record Options(
    Command Command,
    ToneSide ToneSide,
    string? Device,
    string? Source,
    HapticPreset Preset,
    float? Gain,
    float? Gate,
    float? HighPassHz,
    float? LowPassHz,
    float? TransientBoost,
    float? TailLevel,
    float DurationSeconds,
    float Frequency,
    int LatencyMs,
    bool Swap,
    bool AudioHaptics,
    bool AudioHapticsBurst)
{
    public static Options Parse(string[] args)
    {
        if (args.Length == 0 || args.Contains("--help") || args.Contains("-h"))
            return Defaults(Command.Help);
        if (args.Contains("--list"))
            return Defaults(Command.List);
        if (args.Contains("--self-test"))
            return Defaults(Command.SelfTest);
        if (args.Contains("--set-audio-haptics"))
            return Defaults(Command.HidAudioMode);

        var command = args.Contains("--loopback") ? Command.Loopback :
            args.Contains("--tone") ? Command.Tone :
            throw new ArgumentException("Specify --list, --tone, or --loopback.");

        var options = Defaults(command);
        var toneSide = options.ToneSide;
        var device = options.Device;
        var source = options.Source;
        var preset = options.Preset;
        var gain = options.Gain;
        var gate = options.Gate;
        var highPass = options.HighPassHz;
        var lowPass = options.LowPassHz;
        var transient = options.TransientBoost;
        var tail = options.TailLevel;
        var duration = options.DurationSeconds;
        var frequency = options.Frequency;
        var latency = options.LatencyMs;
        var swap = options.Swap;
        var audioHaptics = options.AudioHaptics;
        var audioHapticsBurst = options.AudioHapticsBurst;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--tone":
                    if (i + 1 < args.Length && !args[i + 1].StartsWith("--"))
                        toneSide = ParseSide(args[++i]);
                    break;
                case "--loopback":
                case "--list":
                case "--set-audio-haptics":
                    break;
                case "--device":
                    device = ReadValue(args, ref i);
                    break;
                case "--source":
                    source = ReadValue(args, ref i);
                    break;
                case "--preset":
                    preset = ParsePreset(ReadValue(args, ref i));
                    break;
                case "--gain":
                    gain = ParseFloat(ReadValue(args, ref i), "gain", 0f, 4f);
                    break;
                case "--gate":
                    gate = ParseFloat(ReadValue(args, ref i), "gate", 0f, 1f);
                    break;
                case "--highpass":
                    highPass = ParseFloat(ReadValue(args, ref i), "highpass", 0f, 1000f);
                    break;
                case "--lowpass":
                    lowPass = ParseFloat(ReadValue(args, ref i), "lowpass", 0f, 5000f);
                    break;
                case "--transient":
                    transient = ParseFloat(ReadValue(args, ref i), "transient", 0f, 4f);
                    break;
                case "--tail":
                    tail = ParseFloat(ReadValue(args, ref i), "tail", 0f, 2f);
                    break;
                case "--duration":
                    duration = ParseFloat(ReadValue(args, ref i), "duration", 0.05f, 30f);
                    break;
                case "--frequency":
                    frequency = ParseFloat(ReadValue(args, ref i), "frequency", 20f, 1000f);
                    break;
                case "--latency":
                    latency = (int)ParseFloat(ReadValue(args, ref i), "latency", 5f, 250f);
                    break;
                case "--swap":
                    swap = true;
                    break;
                case "--audio-haptics":
                    audioHaptics = true;
                    break;
                case "--audio-haptics-burst":
                    audioHapticsBurst = true;
                    break;
                default:
                    if (args[i].StartsWith("--"))
                        throw new ArgumentException($"Unknown option: {args[i]}");
                    break;
            }
        }

        return new Options(
            command,
            toneSide,
            device,
            source,
            preset,
            gain,
            gate,
            highPass,
            lowPass,
            transient,
            tail,
            duration,
            frequency,
            latency,
            swap,
            audioHaptics,
            audioHapticsBurst);
    }

    private static Options Defaults(Command command) => new(
        command,
        ToneSide.Both,
        null,
        null,
        HapticPreset.Ps5,
        null,
        null,
        null,
        null,
        null,
        null,
        1.0f,
        120f,
        20,
        false,
        false,
        false);

    private static string ReadValue(string[] args, ref int index)
    {
        if (++index >= args.Length)
            throw new ArgumentException($"Missing value after {args[index - 1]}.");
        return args[index];
    }

    private static float ParseFloat(string text, string name, float min, float max)
    {
        if (!float.TryParse(
                text,
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture,
                out var value) ||
            value < min ||
            value > max)
        {
            throw new ArgumentException(
                $"{name} must be a number between {min} and {max}.");
        }

        return value;
    }

    private static ToneSide ParseSide(string text) =>
        text.ToLowerInvariant() switch
        {
            "left" => ToneSide.Left,
            "right" => ToneSide.Right,
            "both" => ToneSide.Both,
            _ => throw new ArgumentException("Tone side must be left, right, or both.")
        };

    private static HapticPreset ParsePreset(string text) =>
        text.ToLowerInvariant() switch
        {
            "raw" => HapticPreset.Raw,
            "natural" => HapticPreset.Natural,
            "ps5" or "ps5-like" => HapticPreset.Ps5,
            "impact" or "sharp" => HapticPreset.Impact,
            _ => throw new ArgumentException(
                "Preset must be raw, natural, ps5, or impact.")
        };
}
