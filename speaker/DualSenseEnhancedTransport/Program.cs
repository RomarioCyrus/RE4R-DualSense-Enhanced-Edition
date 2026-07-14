using System.Diagnostics;

namespace DualSenseEnhancedTransport;

internal static class Program
{
    private const string Version = "0.1.0-experimental";
    private const string RiskFlag = "--acknowledge-output-conflict";
    private const string GyroMouseFlag = "--gyro-mouse";
    private static DuaLibBackend? _backend;
    private static StreamWriter? _watchLog;

    private static int Main(string[] args)
    {
        InitializeWatchLog(args);
        Console.WriteLine($"Experimental Adaptive Trigger Transport {Version}");
        Console.WriteLine("Isolated duaLib MVP; not connected to the stable RE4R runtime.");
        Console.WriteLine();

        using var mutex = new Mutex(
            initiallyOwned: true,
            "Local\\RE4R.DualSenseEnhancedTransport",
            out var ownsMutex);
        if (!ownsMutex)
        {
            Console.Error.WriteLine("Another transport instance is already running.");
            return 3;
        }

        try
        {
            if (args.Length == 0 || Has(args, "--help") || Has(args, "-h"))
                return Help();
            if (Has(args, "--self-test"))
                return SelfTest();

            var libraryPath = Value(args, "--dualib")
                ?? Path.Combine(AppContext.BaseDirectory, "duaLib.dll");
            if (Has(args, "--check-library"))
                return CheckLibrary(Path.GetFullPath(libraryPath));

            var watchPath = Value(args, "--watch");
            if (watchPath is not null)
            {
                RequireRiskAcknowledgement(args);
                var gyroMouse = Has(args, GyroMouseFlag);
                var gameProcess = Value(args, "--game-process");
                if (gyroMouse && string.IsNullOrWhiteSpace(gameProcess))
                    throw new ArgumentException(
                        "--gyro-mouse requires --game-process so input is restricted to RE4R's foreground window.");
                var commandPath = Path.GetFullPath(watchPath);
                var readyPath = Value(args, "--ready-file")
                    ?? Path.Combine(
                        Path.GetDirectoryName(commandPath)
                            ?? throw new ArgumentException("Watch path has no parent directory."),
                        "DualSenseEnhanced",
                        "trigger_transport.ready");
                return WaitForInGameReady(
                    commandPath,
                    Path.GetFullPath(readyPath),
                    gameProcess,
                    Path.GetFullPath(libraryPath),
                    Has(args, "--gyro-log"),
                    gyroMouse,
                    IntValue(args, "--gyro-sample-ms", gyroMouse ? 8 : 100, 4, 1000),
                    IntValue(args, "--gyro-calibration-ms", 1500, 500, 10000),
                    IntValue(args, "--gyro-aim-threshold", 32, 1, 255),
                    DoubleValue(args, "--gyro-deadzone", 0.03, 0.0, 1.0),
                    DoubleValue(args, "--gyro-yaw-sensitivity", 600, 1, 5000),
                    DoubleValue(args, "--gyro-pitch-sensitivity", 600, 1, 5000),
                    !Has(args, "--gyro-normal-yaw"),
                    Has(args, "--gyro-invert-pitch"),
                    Has(args, "--init-speaker"),
                    IntValue(args, "--speaker-volume", 72, 0, 120));
            }

            if (Has(args, "--gyro-log"))
            {
                _backend = new DuaLibBackend(
                    Path.GetFullPath(libraryPath),
                    resetTriggersOnDispose: false);
                return LogGyro(IntValue(args, "--duration", 10000, 1000, 600000),
                    IntValue(args, "--gyro-sample-ms", 100, 10, 1000));
            }

            if (Has(args, "--test-speaker-init"))
            {
                RequireRiskAcknowledgement(args);
                // No InstallResetHandlers and no dispose-time Reset: the probe
                // must leave triggers, lightbar, vibration mode, and the newly
                // staged audio route exactly as they are on exit.
                return TestSpeakerInit(args, Path.GetFullPath(libraryPath));
            }

            RequireRiskAcknowledgement(args);
            _backend = new DuaLibBackend(Path.GetFullPath(libraryPath));
            InstallResetHandlers();

            if (Has(args, "--reset"))
            {
                _backend.Reset();
                Console.WriteLine("L2 and R2 reset to Off.");
                return 0;
            }

            if (Has(args, "--test-l2"))
                return Test(TriggerSide.L2, args);
            if (Has(args, "--test-r2"))
                return Test(TriggerSide.R2, args);
            if (Has(args, "--test-indicators"))
                return TestPlayerIndicators(args);
            if (Has(args, "--test-lightbar"))
                return TestLightBar(args);
            if (Has(args, "--test-mic-light"))
                return TestMicLight(args);
            if (Has(args, "--test-haptics-mode"))
                return TestHapticsMode(args);
            if (Has(args, "--test-motor-power-clear"))
                return TestMotorPowerClear(args);

            throw new ArgumentException(
                "Specify --self-test, --gyro-log, --reset, --test-l2, --test-r2, --test-indicators, --test-haptics-mode, --test-motor-power-clear, --test-speaker-init, or --watch.");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: {ex}");
            return 1;
        }
        finally
        {
            _backend?.Dispose();
            _backend = null;
            _watchLog?.Dispose();
            _watchLog = null;
        }
    }

    private static void InitializeWatchLog(string[] args)
    {
        if (!Has(args, "--watch"))
            return;

        try
        {
            _watchLog = new StreamWriter(
                new FileStream(
                    Path.Combine(AppContext.BaseDirectory, "trigger_watcher.log"),
                    FileMode.Create,
                    FileAccess.Write,
                    FileShare.ReadWrite))
            {
                AutoFlush = true
            };
            Console.SetOut(_watchLog);
            Console.SetError(_watchLog);
        }
        catch (Exception ex)
        {
            // The previous silent catch here made a stuck/locked log file
            // indistinguishable from "the transport never ran": Console.Out
            // stayed un-redirected, so all later diagnostics vanished into a
            // window-less detached process with no console. Always record
            // the failure itself somewhere visible instead.
            try
            {
                File.AppendAllText(
                    Path.Combine(AppContext.BaseDirectory, "trigger_watcher.initfail.log"),
                    $"{DateTime.Now:O} InitializeWatchLog failed: {ex}\n");
            }
            catch
            {
                // Best-effort; nothing else we can do if even this fails.
            }
        }
    }

    private static int Help()
    {
        Console.WriteLine(
            $@"Commands:
  --self-test
      Validate the 120-byte duaLib trigger packet without opening hardware.

  --check-library [--dualib <path>]
      Load duaLib.dll and verify required exports without opening a controller.

  --reset {RiskFlag} [--dualib <path>]
      Reset both adaptive triggers.

  --test-l2 {RiskFlag} [--duration <ms>] [--dualib <path>]
      Apply weak L2 feedback at position 4, strength 1, then reset.

  --test-r2 {RiskFlag} [--duration <ms>] [--dualib <path>]
      Apply weak R2 feedback at position 4, strength 1, then reset.

  --test-indicators {RiskFlag} [--mask <0..31>] [--duration <ms>] [--dualib <path>]
      Light the selected lower five white player LEDs, then clear them.

  --test-lightbar {RiskFlag} [--r <0..255>] [--g <0..255>] [--b <0..255>]
      [--duration <ms>] [--dualib <path>]
      Set the lightbar to the given RGB via scePadSetLightBar, then reset it.

  --test-mic-light {RiskFlag} [--mode <0..2>] [--duration <ms>] [--dualib <path>]
      Set the Mic LED via scePadSetMicLight (0=Off,1=On,2=Breathing), then reset it.

  --test-haptics-mode {RiskFlag} [--duration <ms>] [--dualib <path>]
      Select audio-haptics mode via scePadSetVibrationMode and hold it for the
      duration (default 15000 ms) so a 4-channel WASAPI test tone on channels
      3/4 can be verified, then restore compatible-rumble mode.

  --test-motor-power-clear {RiskFlag} [--duration <ms>] [--dualib <path>]
      Research probe (docs/HAPTICS_FOOTSTEPS_TASK.md): selects audio-haptics
      mode like --test-haptics-mode, plus explicitly asserts
      scePadSetMotorPowerReduction(trigger=0, rumble=0) to clear a possibly
      stuck nonzero reduction this fork could never clear before. Run
      during real gameplay (via --watch, not standalone) to test whether
      this is why channels-3/4 haptic content isn't felt in RE4R.

  --test-speaker-init {RiskFlag} [--duration <ms>] [--speaker-volume <0..63>]
      [--dualib <path>]
      One-shot native speaker/audio route probe: scePadIsSupportedAudioFunction,
      scePadSetAudioOutPath(ONLY_SPEAKER), scePadSetVolumeGain (default
      speaker volume 36 = hardware 0x64, the PS5 maximum), then hold (default
      3000 ms) so duaLib flushes the report, and exit without resetting
      triggers, lightbar, vibration mode, or the audio route.

  --gyro-log [--duration <ms>] [--gyro-sample-ms <ms>] [--dualib <path>]
      Read and print angular velocity only. Does not write controller output.

  --watch <json> {RiskFlag} [--gyro-log] [--gyro-sample-ms <ms>]
      [--game-process <name>] [--ready-file <path>] [--dualib <path>]
      [--init-speaker] [--speaker-volume <0..63>]
      Wait for Lua's in-game ready marker, then watch an isolated trigger-command
      JSON file until Ctrl+C or the named game exits. --gyro-log appends IMU
      samples to the watcher log without injecting mouse input. --init-speaker
      runs the native speaker-route init (scePadSetAudioOutPath/VolumeGain)
      once after duaLib opens, so DualsenseAudioBridge's normal WASAPI sound
      effects reach the controller speaker for the rest of the session.

  --watch <json> {RiskFlag} --gyro-mouse --game-process re4.exe
      [--gyro-calibration-ms <ms>] [--gyro-aim-threshold <0..255>]
      [--gyro-deadzone <rad/s>] [--gyro-yaw-sensitivity <counts/rad>]
      [--gyro-pitch-sensitivity <counts/rad>] [--gyro-normal-yaw]
      [--gyro-invert-pitch]
      Opt-in gyro-to-mouse prototype. Runs only while L2 is held and RE4R is
      the foreground window. Right-stick look suppresses gyro. Keep the
      controller still during calibration.

Safety:
  - USB DualSense/DualSense Edge only for this first MVP.
  - Close DSX and disable Steam Input before native RE4R testing.
  - This process may race RE4R's complete HID output reports.
  - Stop on lightbar flicker, lost native haptics, USB instability, or stuck triggers.
  - Writes require the explicit {RiskFlag} flag.
  - --gyro-log is input-only; it never injects mouse input or changes trigger state.
  - --gyro-mouse injects Windows mouse deltas only while aiming; it can switch
    RE4R's visible prompts to keyboard/mouse.
");
        return 0;
    }

    private static int SelfTest()
    {
        var l2 = new TriggerEffect(
            TriggerMode.Feedback,
            Position: 4,
            Strength: 1);
        var r2 = new TriggerEffect(
            TriggerMode.Weapon,
            Position: 2,
            Strength: 3,
            EndPosition: 5);
        var packet = TriggerPacket.Build(l2, r2);

        Require(packet.Length == 120, "packet size");
        Require(packet[0] == 0x03, "trigger mask");
        Require(packet[8] == (byte)TriggerMode.Feedback, "L2 mode");
        Require(packet[16] == 4 && packet[17] == 1, "L2 feedback data");
        Require(packet[64] == (byte)TriggerMode.Weapon, "R2 mode");
        Require(
            packet[72] == 2 && packet[73] == 5 && packet[74] == 3,
            "R2 weapon data");

        var reset = TriggerPacket.Build(TriggerEffect.Off, TriggerEffect.Off);
        Require(reset[0] == 0x03, "reset mask");
        Require(reset.Skip(1).All(value => value == 0), "reset payload");
        Require(DuaLibBackend.MotionStateSize == 120,
            "ScePadData size");

        Console.WriteLine("PASS: packet size and ABI offsets.");
        Console.WriteLine("PASS: L2 feedback encoding.");
        Console.WriteLine("PASS: R2 weapon encoding.");
        Console.WriteLine("PASS: explicit two-trigger reset.");
        Console.WriteLine("PASS: IMU read-state ABI size.");
        return 0;
    }

    private static int CheckLibrary(string path)
    {
        var exports = DuaLibBackend.ProbeLibrary(path);
        Console.WriteLine($"PASS: loaded {path}");
        Console.WriteLine(
            $"PASS: verified {exports.Count} required duaLib exports.");
        return 0;
    }

    private static int Test(TriggerSide side, string[] args)
    {
        var duration = IntValue(args, "--duration", 800, 100, 5000);
        var weak = new TriggerEffect(
            TriggerMode.Feedback,
            Position: 4,
            Strength: 1);

        if (side == TriggerSide.L2)
            _backend!.Apply(weak, TriggerEffect.Off);
        else
            _backend!.Apply(TriggerEffect.Off, weak);

        Console.WriteLine(
            $"Weak {side} feedback active for {duration} ms. " +
            "Do not launch this test with DSX running.");
        Thread.Sleep(duration);
        _backend.Reset();
        Console.WriteLine("Triggers reset.");
        return 0;
    }

    private static int TestPlayerIndicators(string[] args)
    {
        if (!_backend!.SupportsPlayerIndicators)
        {
            Console.WriteLine(
                "scePadSetPlayerIndicators is not exported by this duaLib.dll; nothing to test.");
            return 0;
        }

        var mask = IntValue(args, "--mask", 0x1F, 0, 0x1F);
        var duration = IntValue(args, "--duration", 1500, 100, 5000);
        _backend.SetPlayerIndicators((byte)mask);
        Console.WriteLine(
            $"Player-indicator mask 0x{mask:X2} active for {duration} ms. " +
            "Do not launch this test with DSX running.");
        Thread.Sleep(duration);
        _backend.SetPlayerIndicators(0);
        Console.WriteLine("Player indicators cleared.");
        return 0;
    }

    private static int TestMicLight(string[] args)
    {
        if (!_backend!.SupportsMicLight)
        {
            Console.WriteLine(
                "scePadSetMicLight is not exported by this duaLib.dll; nothing to test.");
            return 0;
        }

        var duration = IntValue(args, "--duration", 1500, 100, 5000);
        var mode = IntValue(args, "--mode", 1, 0, 2);
        _backend.SetMicLight((byte)mode);
        Console.WriteLine(
            $"Mic LED mode {mode} (0=Off,1=On,2=Breathing) active for {duration} ms. " +
            "Do not launch this test with DSX running.");
        Thread.Sleep(duration);
        _backend.SetMicLight(0);
        Console.WriteLine("Mic LED reset to Off.");
        return 0;
    }

    private static int TestHapticsMode(string[] args)
    {
        if (!_backend!.SupportsVibrationMode)
        {
            Console.WriteLine(
                "scePadSetVibrationMode is not exported by this duaLib.dll; nothing to test.");
            return 0;
        }

        var duration = IntValue(args, "--duration", 15000, 1000, 600000);
        _backend.SetVibrationMode(DuaLibBackend.VibrationModeHaptics);
        Console.WriteLine(
            $"Audio-haptics mode selected for {duration} ms. While this holds, " +
            "play a 4-channel test tone on channels 3/4 (e.g. " +
            "DualsenseAudioBridge.exe --test-haptic both) and check the " +
            "actuators physically respond. Do not launch this test with DSX running.");
        Thread.Sleep(duration);
        _backend.SetVibrationMode(DuaLibBackend.VibrationModeRumble);
        Console.WriteLine("Compatible-rumble mode restored.");
        return 0;
    }

    // Research probe for the footstep-haptics investigation
    // (docs/HAPTICS_FOOTSTEPS_TASK.md): audio-haptics content on channels
    // 3/4 plays fine standalone but isn't felt during real RE4R gameplay,
    // previously theorized as an external RE4R HID write race. This tests
    // an alternative, mechanistically concrete hypothesis found 2026-07-11
    // while fixing the native speaker route: this fork's own trigger-only
    // output-suppression guard has always unconditionally forced
    // AllowMotorPowerLevel off, so it could never explicitly clear a
    // Trigger/RumbleMotorPowerReduction stuck at a nonzero value by some
    // other writer (Capcom's native haptics init, DSX, a previous session).
    // Same shape as --test-haptics-mode, plus an explicit "no reduction"
    // assert. Run this instead of --test-haptics-mode during a real
    // gameplay footstep-haptics test to see if it makes a difference.
    private static int TestMotorPowerClear(string[] args)
    {
        if (!_backend!.SupportsVibrationMode)
        {
            Console.WriteLine(
                "scePadSetVibrationMode is not exported by this duaLib.dll; nothing to test.");
            return 0;
        }
        if (!_backend.SupportsMotorPowerReduction)
        {
            Console.WriteLine(
                "scePadSetMotorPowerReduction is not exported by this duaLib.dll; nothing to test.");
            return 0;
        }

        var duration = IntValue(args, "--duration", 15000, 1000, 600000);
        _backend.SetVibrationMode(DuaLibBackend.VibrationModeHaptics);
        var result = _backend.SetMotorPowerReductionRaw(triggerReduction: 0, rumbleReduction: 0);
        Console.WriteLine(
            "scePadSetMotorPowerReduction(trigger=0, rumble=0): " + (result >= 0
                ? "OK"
                : $"error 0x{unchecked((uint)result):X8}"));
        Console.WriteLine(
            $"Audio-haptics mode selected + motor power reduction explicitly cleared for " +
            $"{duration} ms. Play a 4-channel test tone on channels 3/4 (e.g. " +
            "DualsenseAudioBridge.exe --test-haptic both) and check the actuators " +
            "physically respond. For the real research question, do this during actual " +
            "RE4R gameplay instead (footstep-haptics pipeline), not standalone. " +
            "Do not launch this test with DSX running.");
        Thread.Sleep(duration);
        _backend.SetVibrationMode(DuaLibBackend.VibrationModeRumble);
        Console.WriteLine("Compatible-rumble mode restored.");
        return 0;
    }

    private static int TestSpeakerInit(string[] args, string libraryPath)
    {
        var duration = IntValue(args, "--duration", 3000, 250, 600000);
        // duaLib writes speakerVolume + 64 into the report's VolumeSpeaker
        // byte (uint8_t, no wraparound below input 191). The PS5 itself only
        // ever uses hardware 0x3D..0x64 (input -3..36), but DualSenseY-v2's
        // own volume slider goes up to hardware 0x88 (input 72, confirmed
        // via USB capture during real audible playback) and is noticeably
        // louder -- use that as the default instead of capping at the PS5's
        // own conservative range. (The original 100 -> hardware 0xA4 failure
        // that started this investigation was a red herring: the real root
        // cause was duaLib's own trigger-only-transport Allow-flag
        // suppression stripping the write regardless of volume value.)
        var speakerVolume = IntValue(args, "--speaker-volume", 72, 0, 120);
        // DualSenseY-v2's applySettings() conditionally calls
        // scePadSetVibrationMode (rumble or haptics, chosen by whether
        // emulated-controller rumble motor values are nonzero) alongside the
        // audio-path/volume calls. Our probe intentionally never called this
        // per the original task scope; testing whether it is in fact the
        // missing "wake" step for the whole audio DSP (not just the
        // channels-3/4 actuators, which is duaLib's documented effect for
        // this call) after silent speaker-only attempts.
        var wakeVibrationMode = Has(args, "--wake-vibration-mode");

        Console.WriteLine("Speaker-init probe: native duaLib audio routing only.");
        Console.WriteLine("No trigger, lightbar, or vibration-mode writes; no reset on exit.");
        Console.WriteLine($"duaLib path: {libraryPath}");

        _backend = new DuaLibBackend(libraryPath, resetTriggersOnDispose: false);
        Console.WriteLine("duaLib loaded: OK");
        Console.WriteLine("controller opened: OK");
        Console.WriteLine(
            $"controller type: {_backend.ControllerType} (2 = DualSense/DualSense Edge)");
        Console.WriteLine($"bus type: {_backend.BusType} (1 = USB)");

        int? supportResult = null;
        if (_backend.SupportsAudioFunctionQuery)
        {
            supportResult = _backend.QueryAudioFunctionSupport();
            Console.WriteLine(
                "scePadIsSupportedAudioFunction: " + supportResult switch
                {
                    1 => "supported (1)",
                    0 => "not supported (0)",
                    _ => $"error 0x{unchecked((uint)supportResult.Value):X8}"
                });
        }
        else
        {
            Console.WriteLine(
                "scePadIsSupportedAudioFunction: not exported by this duaLib.dll");
        }

        int? pathResult = null;
        if (_backend.SupportsAudioOutPath)
        {
            pathResult = _backend.SetAudioOutPathRaw(
                DuaLibBackend.AudioPathOnlySpeaker);
            Console.WriteLine(
                "scePadSetAudioOutPath(3 = ONLY_SPEAKER): " + (pathResult >= 0
                    ? "OK"
                    : $"error 0x{unchecked((uint)pathResult.Value):X8}"));
        }
        else
        {
            Console.WriteLine(
                "scePadSetAudioOutPath: not exported by this duaLib.dll");
        }

        int? gainResult = null;
        if (_backend.SupportsVolumeGain)
        {
            gainResult = _backend.SetVolumeGainRaw(
                speaker: (byte)speakerVolume, headset: 0, micGain: 64);
            Console.WriteLine(
                $"scePadSetVolumeGain(speaker={speakerVolume} -> hardware byte " +
                $"0x{speakerVolume + 64:X2}, headset=0, micGain=64): " +
                (gainResult >= 0
                    ? "OK"
                    : $"error 0x{unchecked((uint)gainResult.Value):X8}"));
        }
        else
        {
            Console.WriteLine(
                "scePadSetVolumeGain: not exported by this duaLib.dll");
        }

        if (wakeVibrationMode && _backend.SupportsVibrationMode)
        {
            _backend.SetVibrationMode(DuaLibBackend.VibrationModeRumble);
            Console.WriteLine(
                "scePadSetVibrationMode(RUMBLE_MODE): OK (research probe for " +
                "whether this wakes the whole audio DSP, not just channels 3/4)");
        }
        else if (wakeVibrationMode)
        {
            Console.WriteLine(
                "scePadSetVibrationMode: not exported by this duaLib.dll");
        }

        // The set calls above only stage duaLib's in-memory output state; its
        // background read thread performs the actual hid_write. Exiting
        // immediately can race the flush (same failure as the 2025-06-29
        // lightbar bug), so hold here. A longer --duration also lets a test
        // sound be played while this process is still alive, versus after it
        // exits, to learn whether the route survives duaLib close.
        //
        // DualSenseY-v2 (the working open-source reference) does not set
        // these fields once and idle -- it calls scePadSetAudioOutPath and
        // scePadSetVolumeGain again on every single main-loop iteration
        // (tens of times per second) for as long as its process runs.
        // duaLib's Allow-flag diff logic means only the first call actually
        // flips Allow=true in the wire report, so this shouldn't matter for
        // the bytes on the wire -- but it's an observable behavioral
        // difference from our original one-shot-then-idle probe, so
        // --repeat reproduces it exactly in case something about repeated
        // application (or repeated wasDisconnected-adjacent state) matters
        // in practice.
        var repeat = Has(args, "--repeat");
        if (repeat)
        {
            // USB capture evidence (2026-07-11): duaLib's write thread only
            // sets AllowSpeakerVolume=true in the wire report on the tick
            // where VolumeSpeaker actually differs from the last-written
            // value. A working DualSenseY-v2 capture showed that bit set on
            // every single output report during audible playback; our own
            // capture -- sending the exact same speakerVolume every
            // iteration -- never set it after the first tick. Jitter the
            // value by 1 each iteration so every write is a genuine diff,
            // forcing AllowSpeakerVolume=true continuously like DualSenseY.
            Console.WriteLine(
                $"Re-applying scePadSetAudioOutPath/scePadSetVolumeGain every " +
                $"200 ms for {duration} ms, jittering speaker volume by +/-1 " +
                "each tick so duaLib's diff-based Allow flag stays asserted " +
                "(matches AllowSpeakerVolume always-set behavior measured in a " +
                "working DualSenseY-v2 USB capture). Play a speaker test sound now.");
            var deadline = DateTime.UtcNow.AddMilliseconds(duration);
            var jitterHigh = false;
            while (DateTime.UtcNow < deadline)
            {
                if (_backend.SupportsAudioOutPath)
                    _backend.SetAudioOutPathRaw(DuaLibBackend.AudioPathOnlySpeaker);
                if (_backend.SupportsVolumeGain)
                {
                    var jittered = jitterHigh
                        ? Math.Min(63, speakerVolume + 1)
                        : Math.Max(0, speakerVolume - 1);
                    jitterHigh = !jitterHigh;
                    _backend.SetVolumeGainRaw(
                        speaker: (byte)jittered, headset: 0, micGain: 64);
                }
                Thread.Sleep(200);
            }
        }
        else
        {
            Console.WriteLine(
                $"Holding for {duration} ms so duaLib flushes the output report. " +
                "Play a speaker test sound now (and again after exit) to check " +
                "whether the route survives this process closing. " +
                "Do not launch this test with DSX running.");
            Thread.Sleep(duration);
        }

        var status =
            pathResult >= 0 && gainResult >= 0 ? "OK"
            : pathResult >= 0 || gainResult >= 0 ? "PARTIAL"
            : "FAILED";
        Console.WriteLine($"SPEAKER INIT: {status}");
        Console.WriteLine("Exiting without resetting triggers, lightbar, or audio route.");
        return status == "FAILED" ? 1 : 0;
    }

    private static int TestLightBar(string[] args)
    {
        if (!_backend!.SupportsLightBar)
        {
            Console.WriteLine(
                "scePadSetLightBar is not exported by this duaLib.dll; nothing to test.");
            return 0;
        }

        var duration = IntValue(args, "--duration", 1500, 100, 5000);
        var r = (byte)IntValue(args, "--r", 255, 0, 255);
        var g = (byte)IntValue(args, "--g", 0, 0, 255);
        var b = (byte)IntValue(args, "--b", 255, 0, 255);
        _backend.SetLightBar(r, g, b);
        Console.WriteLine(
            $"Lightbar RGB({r},{g},{b}) active for {duration} ms via scePadSetLightBar. " +
            "Do not launch this test with DSX running.");
        Thread.Sleep(duration);
        _backend.ResetLightBar();
        Console.WriteLine("Lightbar reset to firmware default.");
        return 0;
    }

    private static int WaitForInGameReady(
        string commandPath,
        string readyPath,
        string? gameProcessName,
        string libraryPath,
        bool gyroLog,
        bool gyroMouse,
        int gyroSampleMs,
        int gyroCalibrationMs,
        int gyroAimThreshold,
        double gyroDeadzone,
        double gyroYawSensitivity,
        double gyroPitchSensitivity,
        bool gyroInvertYaw,
        bool gyroInvertPitch,
        bool initSpeaker,
        int speakerVolume)
    {
        Console.WriteLine($"Waiting for in-game ready marker: {readyPath}");
        Console.WriteLine("duaLib will remain unloaded until the save is fully active.");

        using var stop = new ManualResetEventSlim(false);
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            stop.Set();
        };

        while (!stop.IsSet)
        {
            if (gameProcessName is not null && !IsProcessRunning(gameProcessName))
            {
                Console.WriteLine("Game exited before in-game ready marker.");
                return 0;
            }

            try
            {
                if (File.Exists(readyPath) &&
                    string.Equals(
                        File.ReadAllText(readyPath).Trim(),
                        "ready",
                        StringComparison.OrdinalIgnoreCase))
                {
                    _backend = new DuaLibBackend(libraryPath);
                    InstallResetHandlers();
                    Console.WriteLine("In-game ready marker received; duaLib opened.");
                    if (initSpeaker)
                        InitializeSpeakerRoute(_backend, speakerVolume);
                    return Watch(
                        commandPath, gameProcessName, gyroLog, gyroMouse, gyroSampleMs,
                        gyroCalibrationMs, gyroAimThreshold, gyroDeadzone,
                        gyroYawSensitivity, gyroPitchSensitivity, gyroInvertYaw,
                        gyroInvertPitch);
                }
            }
            catch (IOException)
            {
                // Lua may be replacing the one-line marker at this moment.
            }

            stop.Wait(100);
        }

        return 0;
    }

    /// <summary>
    /// One-shot native speaker route init for --watch, opt-in via
    /// --init-speaker. Same two calls as --test-speaker-init, minus the
    /// diagnostic verbosity, run once right after duaLib opens so the
    /// standard 2-channel WASAPI speaker path (DualsenseAudioBridge's normal
    /// sound-effect playback) works for the rest of the game session without
    /// a separate manual probe run.
    /// </summary>
    private static void InitializeSpeakerRoute(DuaLibBackend backend, int speakerVolume)
    {
        if (backend.SupportsAudioOutPath)
            backend.SetAudioOutPathRaw(DuaLibBackend.AudioPathOnlySpeaker);
        if (backend.SupportsVolumeGain)
            backend.SetVolumeGainRaw(speaker: (byte)speakerVolume, headset: 0, micGain: 64);
        Console.WriteLine($"Speaker route initialized (volume {speakerVolume} -> hardware 0x{speakerVolume + 64:X2}).");
    }

    private static int Watch(
        string path,
        string? gameProcessName,
        bool gyroLog,
        bool gyroMouse,
        int gyroSampleMs,
        int gyroCalibrationMs,
        int gyroAimThreshold,
        double gyroDeadzone,
        double gyroYawSensitivity,
        double gyroPitchSensitivity,
        bool gyroInvertYaw,
        bool gyroInvertPitch)
    {
        Console.WriteLine($"Watching: {path}");
        Console.WriteLine("Press Ctrl+C to stop and reset both triggers.");
        GyroMouseMapper? gyroMapper = null;
        if (gyroLog || gyroMouse)
        {
            _backend!.EnableMotionSensor();
            if (gyroLog)
                Console.WriteLine($"Gyro logging enabled ({gyroSampleMs} ms samples); no mouse input is injected.");
            if (gyroMouse)
            {
                gyroMapper = new GyroMouseMapper(
                    gameProcessName!, gyroAimThreshold, gyroDeadzone,
                    gyroYawSensitivity, gyroPitchSensitivity, gyroCalibrationMs,
                    gyroInvertYaw, gyroInvertPitch, Console.WriteLine);
                Console.WriteLine(
                    $"Gyro mouse enabled: keep controller still for {gyroCalibrationMs} ms; " +
                    $"input is L2-gated (threshold {gyroAimThreshold}) and foreground-gated.");
            }
        }

        using var stop = new ManualResetEventSlim(false);
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            stop.Set();
        };

        var directory = Path.GetDirectoryName(path)
            ?? throw new ArgumentException("Watch path has no parent directory.");
        Directory.CreateDirectory(directory);

        long lastSequence = long.MinValue;
        DateTime lastWrite = DateTime.MinValue;
        var nextGyroSample = DateTime.UtcNow;
        var nextHapticsReassert = DateTime.MaxValue;
        (byte R, byte G, byte B)? lastLightBar = null;
        byte? lastMicLight = null;
        int? lastHapticsMode = null;
        while (!stop.IsSet)
        {
            if (gameProcessName is not null &&
                !IsProcessRunning(gameProcessName))
            {
                _backend!.Reset();
                Console.WriteLine("Game exited; triggers reset.");
                return 0;
            }

            if ((gyroLog || gyroMouse) && DateTime.UtcNow >= nextGyroSample)
            {
                // A transient USB/BT hiccup (controller standby, power
                // management, brief disconnect) must not take down the whole
                // watcher -- that previously required a full RE4R restart to
                // recover triggers and gyro both. Skip this sample and keep
                // the loop alive; the next iteration retries on its own.
                try
                {
                    var sample = _backend!.ReadMotion();
                    if (gyroLog)
                        WriteGyroSample(sample);
                    gyroMapper?.Feed(sample);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Gyro sample skipped: {ex.Message}");
                }
                nextGyroSample = DateTime.UtcNow.AddMilliseconds(gyroSampleMs);
            }

            // Periodic reassert while audio-haptics mode is held: RE4R's own
            // native haptics/rumble (e.g. a hit reaction) flips the
            // controller back to compatible-rumble mode at the hardware
            // level without going through duaLib, so duaLib's own cached
            // state never notices anything changed. The apply block below
            // only runs when the Lua-side command file's Sequence changes,
            // and IPC.haptics_mode_enabled doesn't change across a native
            // haptics event -- so without this, once RE4R reverts the mode,
            // footstep haptics silently stop until something else forces a
            // Sequence bump (e.g. Reset Scripts recreating the flag).
            // User-reported symptom 2026-07-11: footstep haptics worked while
            // running, stopped the instant native haptics fired, stayed dead
            // until Reset Scripts. Re-issuing the same mode periodically
            // fights back against RE4R's own writes the same way the
            // motor-power-reduction and audio Allow-flag fixes already do.
            if (_backend!.SupportsVibrationMode &&
                lastHapticsMode == DuaLibBackend.VibrationModeHaptics &&
                DateTime.UtcNow >= nextHapticsReassert)
            {
                _backend.SetVibrationMode(DuaLibBackend.VibrationModeHaptics);
                if (_backend.SupportsMotorPowerReduction)
                {
                    _backend.SetMotorPowerReductionRaw(triggerReduction: 0, rumbleReduction: 0);
                }
                nextHapticsReassert = DateTime.UtcNow.AddMilliseconds(500);
            }

            if (File.Exists(path))
            {
                var write = File.GetLastWriteTimeUtc(path);
                if (write != lastWrite)
                {
                    lastWrite = write;
                    // A command file changing fast enough that two reads
                    // 10ms apart never agree (e.g. a continuous LED pulse
                    // writing every couple of frames) must not take down
                    // the whole watcher -- same rationale as the gyro
                    // sample catch above. Skip this iteration; the next
                    // loop tick retries on its own once writes settle.
                    TriggerCommandFile? command = null;
                    try
                    {
                        command = CommandFile.ReadStable(path);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Command read unstable, skipped: {ex.Message}");
                    }

                    if (command is not null && command.Sequence != lastSequence)
                    {
                        try
                        {
                            var l2 = command.L2?.ToEffect();
                            var r2 = command.R2?.ToEffect();
                            var indicators = command.Indicators?.ToMask();
                            _backend!.Apply(l2, r2, indicators);

                            if (_backend.SupportsLightBar)
                            {
                                if (command.Led is { } led)
                                {
                                    var rgb = led.ToRgb();
                                    if (rgb != lastLightBar)
                                    {
                                        _backend.SetLightBar(rgb.R, rgb.G, rgb.B);
                                        lastLightBar = rgb;
                                    }
                                }
                                else if (lastLightBar is not null)
                                {
                                    _backend.ResetLightBar();
                                    lastLightBar = null;
                                }
                            }

                            if (_backend.SupportsMicLight)
                            {
                                if (command.Mic is { } mic)
                                {
                                    var mode = mic.ToMode();
                                    if (mode != lastMicLight)
                                    {
                                        _backend.SetMicLight(mode);
                                        lastMicLight = mode;
                                    }
                                }
                                else if (lastMicLight is not null)
                                {
                                    _backend.SetMicLight(0);
                                    lastMicLight = null;
                                }
                            }

                            if (_backend.SupportsVibrationMode)
                            {
                                if (command.Haptics is { } haptics)
                                {
                                    var hapticsMode = haptics.ToMode();
                                    if (hapticsMode != lastHapticsMode)
                                    {
                                        _backend.SetVibrationMode(hapticsMode);
                                        // Research probe (docs/HAPTICS_FOOTSTEPS_TASK.md):
                                        // explicitly clear motor power reduction whenever
                                        // switching into audio-haptics mode, in case a
                                        // stuck nonzero Trigger/RumbleMotorPowerReduction
                                        // from some other writer is why channels-3/4
                                        // content isn't felt during real gameplay, even
                                        // though vibration-mode selection itself holds.
                                        if (hapticsMode == DuaLibBackend.VibrationModeHaptics &&
                                            _backend.SupportsMotorPowerReduction)
                                        {
                                            var powerResult = _backend.SetMotorPowerReductionRaw(
                                                triggerReduction: 0, rumbleReduction: 0);
                                            Console.WriteLine(
                                                "scePadSetMotorPowerReduction(0,0): " +
                                                (powerResult >= 0
                                                    ? "OK"
                                                    : $"error 0x{unchecked((uint)powerResult):X8}"));
                                        }
                                        lastHapticsMode = hapticsMode;
                                        nextHapticsReassert = hapticsMode == DuaLibBackend.VibrationModeHaptics
                                            ? DateTime.UtcNow.AddMilliseconds(500)
                                            : DateTime.MaxValue;
                                    }
                                }
                                else if (lastHapticsMode is not null)
                                {
                                    _backend.SetVibrationMode(
                                        DuaLibBackend.VibrationModeRumble);
                                    lastHapticsMode = null;
                                    nextHapticsReassert = DateTime.MaxValue;
                                }
                            }

                            lastSequence = command.Sequence;
                            Console.WriteLine(
                                $"Applied sequence {lastSequence}: " +
                                $"L2={l2?.Mode.ToString() ?? "unchanged"}, " +
                                $"R2={r2?.Mode.ToString() ?? "unchanged"}, " +
                                $"Indicators={(indicators.HasValue ? $"0x{indicators.Value:X2}" : "unchanged")}, " +
                                $"Led={(command.Led is { } l ? $"({l.R},{l.G},{l.B})" : "unchanged")}, " +
                                $"Mic={(command.Mic is { } m ? m.Mode.ToString() : "unchanged")}, " +
                                $"Haptics={(command.Haptics is { } h ? (h.Mode == 1 ? "haptics" : "rumble") : "unchanged")}");
                        }
                        catch (Exception ex)
                        {
                            // Same rationale as the gyro sample above: a
                            // transient duaLib/USB error here must not kill
                            // the whole watcher for the rest of the session.
                            Console.WriteLine($"Trigger apply failed (sequence {command.Sequence}): {ex.Message}");
                        }
                    }
                }
            }

            stop.Wait((gyroLog || gyroMouse) ? gyroSampleMs : 50);
        }

        _backend!.Reset();
        Console.WriteLine("Stopped; triggers reset.");
        return 0;
    }

    private static int LogGyro(int durationMs, int sampleMs)
    {
        Console.WriteLine($"Reading IMU angular velocity for {durationMs} ms ({sampleMs} ms samples).");
        Console.WriteLine("Input-only mode: no trigger reset, mouse injection, or controller output writes.");
        _backend!.EnableMotionSensor();

        using var stop = new ManualResetEventSlim(false);
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            stop.Set();
        };

        var deadline = DateTime.UtcNow.AddMilliseconds(durationMs);
        while (!stop.IsSet && DateTime.UtcNow < deadline)
        {
            WriteGyroSample(_backend.ReadMotion());
            stop.Wait(sampleMs);
        }

        Console.WriteLine("Gyro logging complete.");
        return 0;
    }

    private static void WriteGyroSample(GyroMotionSample sample) =>
        Console.WriteLine(
            $"gyro rad/s: x={sample.X:F4} y={sample.Y:F4} z={sample.Z:F4} " +
            $"accel g: x={sample.AccelX:F3} y={sample.AccelY:F3} z={sample.AccelZ:F3} " +
            $"|a|={sample.AccelMagnitude:F3} timestamp={sample.Timestamp}");

    private static bool IsProcessRunning(string processName)
    {
        var name = Path.GetFileNameWithoutExtension(processName);
        var processes = Process.GetProcessesByName(name);
        try { return processes.Length > 0; }
        finally
        {
            foreach (var process in processes)
                process.Dispose();
        }
    }

    private static void InstallResetHandlers()
    {
        AppDomain.CurrentDomain.ProcessExit += (_, _) =>
        {
            try
            {
                _backend?.Reset();
            }
            catch
            {
                // Best effort only during process teardown.
            }
        };
    }

    private static void RequireRiskAcknowledgement(string[] args)
    {
        if (!Has(args, RiskFlag))
            throw new ArgumentException(
                $"Hardware writes require {RiskFlag}.");
    }

    private static void Require(bool condition, string check)
    {
        if (!condition)
            throw new InvalidOperationException($"Self-test failed: {check}.");
    }

    private static bool Has(string[] args, string option) =>
        args.Contains(option, StringComparer.OrdinalIgnoreCase);

    private static string? Value(string[] args, string option)
    {
        for (var index = 0; index < args.Length; index++)
        {
            if (!args[index].Equals(option, StringComparison.OrdinalIgnoreCase))
                continue;
            if (index + 1 >= args.Length)
                throw new ArgumentException($"Missing value after {option}.");
            return args[index + 1];
        }

        return null;
    }

    private static int IntValue(
        string[] args,
        string option,
        int fallback,
        int min,
        int max)
    {
        var text = Value(args, option);
        if (text is null)
            return fallback;
        if (!int.TryParse(text, out var value) || value < min || value > max)
            throw new ArgumentException($"{option} must be {min}..{max}.");
        return value;
    }

    private static double DoubleValue(
        string[] args,
        string option,
        double fallback,
        double min,
        double max)
    {
        var text = Value(args, option);
        if (text is null)
            return fallback;
        if (!double.TryParse(
                text,
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture,
                out var value) || value < min || value > max)
            throw new ArgumentException(
                $"{option} must be {min.ToString(System.Globalization.CultureInfo.InvariantCulture)}.." +
                max.ToString(System.Globalization.CultureInfo.InvariantCulture) + ".");
        return value;
    }
}
