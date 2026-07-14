using System.Runtime.InteropServices;

namespace DualSenseEnhancedTransport;

internal sealed class DuaLibBackend : IDisposable
{
    private const int ScePadErrorDeviceNotConnected =
        unchecked((int)0x80920007);

    private static readonly string[] RequiredExports =
    {
        "scePadInit",
        "scePadTerminate",
        "scePadOpen",
        "scePadClose",
        "scePadSetTriggerEffect",
        "scePadReadState",
        "scePadSetMotionSensorState",
        "scePadGetControllerBusType",
        "scePadGetControllerType"
    };

    private readonly IntPtr _library;
    private readonly ScePadTerminate _terminate;
    private readonly ScePadClose _close;
    private readonly ScePadSetTriggerEffect _setTriggerEffect;
    // Optional: some deployed duaLib.dll builds do not export this (player
    // indicators are DSX-only in the current native MVP per MEMORY.md). It
    // must never block trigger/gyro startup just because it is missing.
    private readonly ScePadSetPlayerIndicators? _setPlayerIndicators;
    // Optional: lightbar output. Missing on older duaLib.dll builds; must
    // never block trigger/gyro startup. When present, this lets the watcher
    // process own the lightbar HID write directly instead of going through
    // RE4R's share.hid.Device, removing the post-update enforcement race
    // that caused flicker in native_feedback.lua.
    private readonly ScePadSetLightBar? _setLightBar;
    private readonly ScePadResetLightBar? _resetLightBar;
    private bool _lightBarOwned;
    private bool _micLightOwned;
    // Optional: Mic LED. Missing on duaLib.dll builds without this custom
    // extension; must never block trigger/gyro startup.
    private readonly ScePadSetMicLight? _setMicLight;
    // Optional: vibration-mode selection (upstream duaLib API). Selecting
    // haptics mode (1) clears UseRumbleNotHaptics/EnableRumbleEmulation in
    // every subsequent output report, which is what keeps the DualSense's
    // 4-channel WASAPI endpoint (channels 3/4 = actuators) audible. Rumble
    // mode (2) is the firmware-default compatible-rumble selection duaLib
    // itself applies at scePadOpen.
    private readonly ScePadSetVibrationMode? _setVibrationMode;
    private bool _hapticsModeOwned;
    // RE4R fork extension (not upstream duaLib/real SDK): explicitly assert
    // motor power reduction. Added to test whether a stuck nonzero
    // Trigger/RumbleMotorPowerReduction -- which this fork could otherwise
    // never clear, since AllowMotorPowerLevel was unconditionally forced
    // off -- is why channels-3/4 audio-haptic content isn't felt during
    // real RE4R gameplay even though vibration-mode selection holds
    // correctly (see docs/HAPTICS_FOOTSTEPS_TASK.md).
    private readonly ScePadSetMotorPowerReduction? _setMotorPowerReduction;
    // Optional: controller speaker/audio routing (upstream duaLib API).
    // These only stage bytes in duaLib's in-memory output state; the
    // background read thread performs the actual hid_write, so callers
    // must hold the process alive briefly after staging (same flush race
    // as the 2025-06-29 lightbar bug). No ownership/reset tracking here:
    // the speaker-init probe must leave the audio route untouched on exit.
    private readonly ScePadIsSupportedAudioFunction? _isSupportedAudioFunction;
    private readonly ScePadSetAudioOutPath? _setAudioOutPath;
    private readonly ScePadSetVolumeGain? _setVolumeGain;

    public const int VibrationModeHaptics = 1;
    public const int VibrationModeRumble = 2;
    // SCE_PAD_AUDIO_PATH_ONLY_SPEAKER from duaLib.h.
    public const int AudioPathOnlySpeaker = 3;
    private readonly ScePadReadState _readState;
    private readonly ScePadSetMotionSensorState _setMotionSensorState;
    private readonly ScePadGetControllerBusType _getBusType;
    private readonly ScePadGetControllerType _getControllerType;
    private readonly bool _resetTriggersOnDispose;
    private int _handle = -1;
    private bool _initialized;

    public int ControllerType { get; }
    public int BusType { get; }

    internal static int MotionStateSize => Marshal.SizeOf<ScePadData>();

    public DuaLibBackend(string libraryPath, bool resetTriggersOnDispose = true)
    {
        _resetTriggersOnDispose = resetTriggersOnDispose;
        _library = NativeLibrary.Load(libraryPath);
        try
        {
            var init = Load<ScePadInit>("scePadInit");
            _terminate = Load<ScePadTerminate>("scePadTerminate");
            var open = Load<ScePadOpen>("scePadOpen");
            _close = Load<ScePadClose>("scePadClose");
            _setTriggerEffect =
                Load<ScePadSetTriggerEffect>("scePadSetTriggerEffect");
            _setPlayerIndicators =
                TryLoad<ScePadSetPlayerIndicators>("scePadSetPlayerIndicators");
            _setLightBar = TryLoad<ScePadSetLightBar>("scePadSetLightBar");
            _resetLightBar = TryLoad<ScePadResetLightBar>("scePadResetLightBar");
            _setMicLight = TryLoad<ScePadSetMicLight>("scePadSetMicLight");
            _setVibrationMode =
                TryLoad<ScePadSetVibrationMode>("scePadSetVibrationMode");
            _setMotorPowerReduction =
                TryLoad<ScePadSetMotorPowerReduction>("scePadSetMotorPowerReduction");
            _isSupportedAudioFunction =
                TryLoad<ScePadIsSupportedAudioFunction>(
                    "scePadIsSupportedAudioFunction");
            _setAudioOutPath =
                TryLoad<ScePadSetAudioOutPath>("scePadSetAudioOutPath");
            _setVolumeGain = TryLoad<ScePadSetVolumeGain>("scePadSetVolumeGain");
            _readState = Load<ScePadReadState>("scePadReadState");
            _setMotionSensorState =
                Load<ScePadSetMotionSensorState>("scePadSetMotionSensorState");
            _getBusType =
                Load<ScePadGetControllerBusType>("scePadGetControllerBusType");
            _getControllerType =
                Load<ScePadGetControllerType>("scePadGetControllerType");

            Check(init(), "scePadInit");
            _initialized = true;

            _handle = open(1, 0, 0);
            Check(_handle, "scePadOpen");

            ControllerType = ReadWithDeviceRetry(
                (int handle, out int value) =>
                    _getControllerType(handle, out value),
                "scePadGetControllerType");
            if (ControllerType != 2)
                throw new InvalidOperationException(
                    $"Opened controller type {ControllerType}, expected DualSense (2).");

            BusType = ReadWithDeviceRetry(
                (int handle, out int value) =>
                    _getBusType(handle, out value),
                "scePadGetControllerBusType");
            if (BusType != 1)
                throw new InvalidOperationException(
                    $"Opened bus type {BusType}; first MVP permits USB only (1).");
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    public static IReadOnlyList<string> ProbeLibrary(string libraryPath)
    {
        var library = NativeLibrary.Load(libraryPath);
        try
        {
            foreach (var export in RequiredExports)
                NativeLibrary.GetExport(library, export);
            return RequiredExports;
        }
        finally
        {
            NativeLibrary.Free(library);
        }
    }

    public void Apply(
        TriggerEffect? l2,
        TriggerEffect? r2,
        byte? playerIndicators = null)
    {
        var packet = TriggerPacket.Build(l2, r2);
        var pinned = GCHandle.Alloc(packet, GCHandleType.Pinned);
        try
        {
            Check(
                _setTriggerEffect(_handle, pinned.AddrOfPinnedObject()),
                "scePadSetTriggerEffect");
        }
        finally
        {
            pinned.Free();
        }

        if (playerIndicators.HasValue)
            SetPlayerIndicators(playerIndicators.Value);
    }

    public bool SupportsPlayerIndicators => _setPlayerIndicators is not null;

    public void SetPlayerIndicators(byte mask)
    {
        if (_setPlayerIndicators is null)
            return;
        Check(
            _setPlayerIndicators(_handle, mask),
            "scePadSetPlayerIndicators");
    }

    public bool SupportsMicLight => _setMicLight is not null;

    public void SetMicLight(byte mode)
    {
        if (_setMicLight is null)
            return;
        Check(_setMicLight(_handle, mode), "scePadSetMicLight");
        _micLightOwned = true;
    }

    public bool SupportsVibrationMode => _setVibrationMode is not null;

    public void SetVibrationMode(int mode)
    {
        if (_setVibrationMode is null)
            return;
        Check(_setVibrationMode(_handle, mode), "scePadSetVibrationMode");
        _hapticsModeOwned = mode == VibrationModeHaptics;
    }

    public bool SupportsMotorPowerReduction => _setMotorPowerReduction is not null;

    /// <summary>
    /// Explicitly asserts motor power reduction (0..7, 12.5% steps each).
    /// Returns the raw duaLib result instead of throwing, matching the
    /// audio-probe methods, since this is a diagnostic/research call.
    /// </summary>
    public int SetMotorPowerReductionRaw(int triggerReduction, int rumbleReduction) =>
        _setMotorPowerReduction is null
            ? throw new InvalidOperationException(
                "scePadSetMotorPowerReduction is not exported by this duaLib.dll.")
            : _setMotorPowerReduction(_handle, triggerReduction, rumbleReduction);

    public bool SupportsAudioFunctionQuery =>
        _isSupportedAudioFunction is not null;
    public bool SupportsAudioOutPath => _setAudioOutPath is not null;
    public bool SupportsVolumeGain => _setVolumeGain is not null;

    // The audio probe methods return duaLib's raw result code instead of
    // throwing: the speaker-init probe must report every step's outcome,
    // including partial failures, in one diagnostic pass.
    public int QueryAudioFunctionSupport() =>
        _isSupportedAudioFunction!(_handle);

    public int SetAudioOutPathRaw(int path) => _setAudioOutPath!(_handle, path);

    public int SetVolumeGainRaw(byte speaker, byte headset, byte micGain)
    {
        var gain = new ScePadVolumeGain
        {
            SpeakerVolume = speaker,
            HeadsetVolume = headset,
            MicGain = micGain
        };
        var pinned = GCHandle.Alloc(gain, GCHandleType.Pinned);
        try
        {
            return _setVolumeGain!(_handle, pinned.AddrOfPinnedObject());
        }
        finally
        {
            pinned.Free();
        }
    }

    public bool SupportsLightBar => _setLightBar is not null;

    public void SetLightBar(byte r, byte g, byte b)
    {
        if (_setLightBar is null)
            return;
        var lightBar = new ScePadLightBar { R = r, G = g, B = b };
        var pinned = GCHandle.Alloc(lightBar, GCHandleType.Pinned);
        try
        {
            Check(
                _setLightBar(_handle, pinned.AddrOfPinnedObject()),
                "scePadSetLightBar");
        }
        finally
        {
            pinned.Free();
        }
        _lightBarOwned = true;
    }

    public void ResetLightBar()
    {
        if (_resetLightBar is null)
            return;
        Check(_resetLightBar(_handle), "scePadResetLightBar");
        _lightBarOwned = false;
    }

    public void Reset()
    {
        Apply(
            TriggerEffect.Off,
            TriggerEffect.Off,
            playerIndicators: 0);
        if (_lightBarOwned)
            ResetLightBar();
        if (_micLightOwned)
        {
            SetMicLight(0);
            _micLightOwned = false;
        }
        if (_hapticsModeOwned)
            SetVibrationMode(VibrationModeRumble);

        // duaLib's background read thread is what actually performs
        // hid_write; these calls only update the in-memory struct it reads.
        // Without a brief settle window here, a caller that resets and then
        // immediately disposes/exits can race the close ahead of the next
        // read-thread iteration, leaving the controller stuck showing the
        // last color/effect that *did* make it out instead of the reset.
        // Hardware-confirmed bug (2025-06-29): the lightbar stayed stuck on
        // the last test color across several --test-lightbar runs that
        // reset with no settle time, while a long Thread.Sleep before the
        // same reset call always flushed correctly.
        Thread.Sleep(50);
    }

    public void EnableMotionSensor() =>
        Check(
            _setMotionSensorState(_handle, true),
            "scePadSetMotionSensorState");

    public GyroMotionSample ReadMotion()
    {
        var state = new ScePadData();
        Check(_readState(_handle, ref state), "scePadReadState");
        return new GyroMotionSample(
            state.AngularVelocityX,
            state.AngularVelocityY,
            state.AngularVelocityZ,
            state.AccelerationX,
            state.AccelerationY,
            state.AccelerationZ,
            state.L2Analog,
            state.RightStickX,
            state.RightStickY,
            state.Timestamp);
    }

    public void Dispose()
    {
        if (_handle >= 0)
        {
            try
            {
                if (_resetTriggersOnDispose)
                    Reset();
            }
            catch
            {
                // Best-effort reset during shutdown.
            }

            try
            {
                _close(_handle);
            }
            catch
            {
                // Continue library teardown.
            }

            _handle = -1;
        }

        if (_initialized)
        {
            try
            {
                _terminate();
            }
            catch
            {
                // Continue library teardown.
            }

            _initialized = false;
        }

        if (_library != IntPtr.Zero)
            NativeLibrary.Free(_library);
    }

    private T Load<T>(string export) where T : Delegate =>
        Marshal.GetDelegateForFunctionPointer<T>(
            NativeLibrary.GetExport(_library, export));

    private T? TryLoad<T>(string export) where T : Delegate =>
        NativeLibrary.TryGetExport(_library, export, out var address)
            ? Marshal.GetDelegateForFunctionPointer<T>(address)
            : null;

    private int ReadWithDeviceRetry(
        ScePadReadInt read,
        string operation)
    {
        const int attempts = 25;
        var lastResult = 0;

        for (var attempt = 1; attempt <= attempts; attempt++)
        {
            lastResult = read(_handle, out var value);
            if (lastResult >= 0)
                return value;

            if (lastResult != ScePadErrorDeviceNotConnected)
                break;

            Thread.Sleep(100);
        }

        Check(lastResult, operation);

        throw new InvalidOperationException(
            $"{operation} failed without returning a value.");
    }

    private static void Check(int result, string operation)
    {
        if (result < 0)
            throw new InvalidOperationException(
                $"{operation} failed: 0x{unchecked((uint)result):X8}");
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadInit();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadTerminate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadOpen(int userId, int unknown1, int unknown2);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadClose(int handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetTriggerEffect(
        int handle,
        IntPtr triggerEffect);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetPlayerIndicators(int handle, int mask);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetLightBar(int handle, IntPtr lightBar);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetMicLight(int handle, int mode);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetVibrationMode(int handle, int mode);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetMotorPowerReduction(
        int handle, int triggerReduction, int rumbleReduction);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadResetLightBar(int handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadIsSupportedAudioFunction(int handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetAudioOutPath(int handle, int path);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetVolumeGain(int handle, IntPtr gainSettings);

    // duaLib.h s_ScePadVolumeGain: duaLib writes speakerVolume + 64 into the
    // output report's speaker byte and micGain as-is.
    [StructLayout(LayoutKind.Sequential)]
    private struct ScePadVolumeGain
    {
        public byte SpeakerVolume;
        public byte HeadsetVolume;
        public byte Padding;
        public byte MicGain;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ScePadLightBar
    {
        public byte R;
        public byte G;
        public byte B;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadReadState(int handle, ref ScePadData state);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadSetMotionSensorState(
        int handle,
        [MarshalAs(UnmanagedType.I1)] bool state);

    private delegate int ScePadReadInt(int handle, out int value);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadGetControllerBusType(
        int handle,
        out int busType);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ScePadGetControllerType(
        int handle,
        out int controllerType);

    // Exact x64 layout of duaLib's s_ScePadData. acceleration (m/s^2) sits
    // right before angularVelocity, per duaLib.h's public struct:
    //   orientation (offset 12, 16 bytes) -> acceleration (offset 28, 12
    //   bytes) -> angularVelocity (offset 40, 12 bytes).
    [StructLayout(LayoutKind.Explicit, Size = 120)]
    private struct ScePadData
    {
        [FieldOffset(6)] public byte RightStickX;
        [FieldOffset(7)] public byte RightStickY;
        [FieldOffset(8)] public byte L2Analog;
        [FieldOffset(28)] public float AccelerationX;
        [FieldOffset(32)] public float AccelerationY;
        [FieldOffset(36)] public float AccelerationZ;
        [FieldOffset(40)] public float AngularVelocityX;
        [FieldOffset(44)] public float AngularVelocityY;
        [FieldOffset(48)] public float AngularVelocityZ;
        [FieldOffset(80)] public ulong Timestamp;
    }
}
