using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DualSenseEnhancedTransport;

internal sealed class GyroMouseMapper
{
    private const uint InputMouse = 0;
    private const uint MouseEventMove = 0x0001;

    private readonly string _gameProcessName;
    private readonly int _aimThreshold;
    private readonly double _deadzone;
    private readonly double _yawSensitivity;
    private readonly double _pitchSensitivity;
    private readonly bool _invertYaw;
    private readonly bool _invertPitch;
    private readonly long _calibrationTicks;
    private readonly Action<string> _log;
    private long _calibrationStartedAt = Stopwatch.GetTimestamp();
    private long _lastSampleAt;
    private int _calibrationSamples;
    private double _sumX;
    private double _sumZ;
    private double _minX = double.MaxValue;
    private double _maxX = double.MinValue;
    private double _minZ = double.MaxValue;
    private double _maxZ = double.MinValue;
    private int _calibrationAttempt;
    private double _biasX;
    private double _biasZ;
    private bool _calibrated;

    // A gyroscope reads rotation rate, not tilt, so a genuinely still
    // controller should average near zero on every axis regardless of its
    // orientation. A bias average or in-window spread above this means the
    // controller was actually moved (picked up, set down, settled into an
    // aim stance) during the calibration window -- accepting that as the
    // "zero" point causes a constant one-directional aim drift for the rest
    // of the session, which previously had no recovery except recalibrating
    // by releasing and re-holding L2.
    private const double MaxPlausibleBias = 0.05;
    private const int MaxCalibrationAttempts = 5;

    // duaLib's s_ScePadData also exposes a linear-acceleration vector.
    // Measured live (--gyro-log, controller flat on a table): magnitude
    // ~0.97, not ~9.81, so duaLib reports this in g (1g = at rest), not
    // m/s^2. A controller genuinely at rest reads close to 1g regardless of
    // which way it is held, so its magnitude is a direct "is this actually
    // still" signal -- unlike checking the gyro against its own bias
    // estimate, which is self-referential and proves nothing if that
    // estimate is itself the thing that's wrong.
    private const double RestAccelMagnitude = 1.0;
    private const double RestAccelTolerance = 0.15;
    private double _minAccelMagnitude = double.MaxValue;
    private double _maxAccelMagnitude = double.MinValue;

    private static bool IsAtRest(GyroMotionSample sample) =>
        Math.Abs(sample.AccelMagnitude - RestAccelMagnitude) < RestAccelTolerance;

    // Slow background nudge toward the current reading whenever the
    // controller looks at rest outside active aiming; see the call site
    // below. Deliberately tiny so it cannot be felt as input lag/snapping.
    private const double BackgroundRecalibrationAlpha = 0.01;
    private double _remainderX;
    private double _remainderY;

    // Low-pass filter on the bias-corrected angular velocity, applied before
    // the deadzone/sensitivity scaling below. IMU sensor noise rides on top
    // of deliberate panning and grows with signal amplitude, so it stays
    // under the deadzone at rest but shows up as visible jitter only while
    // actively turning -- exactly what a raw mouse/stick input path does not
    // have. A mouse's own sensor noise floor is much lower, and a stick's
    // position-based input is naturally damped by the small physical
    // deflection of a real tremor, so neither needs this filter.
    private const double SmoothingAlpha = 0.35;
    private double _filteredYawRaw;
    private double _filteredPitchRaw;
    private bool _filterPrimed;

    public GyroMouseMapper(
        string gameProcessName,
        int aimThreshold,
        double deadzone,
        double yawSensitivity,
        double pitchSensitivity,
        int calibrationMs,
        bool invertYaw,
        bool invertPitch,
        Action<string> log)
    {
        _gameProcessName = Path.GetFileNameWithoutExtension(gameProcessName);
        _aimThreshold = aimThreshold;
        _deadzone = deadzone;
        _yawSensitivity = yawSensitivity;
        _pitchSensitivity = pitchSensitivity;
        _calibrationTicks = calibrationMs * Stopwatch.Frequency / 1000;
        _invertYaw = invertYaw;
        _invertPitch = invertPitch;
        _log = log;
    }

    public void Feed(GyroMotionSample sample)
    {
        var now = Stopwatch.GetTimestamp();
        if (!_calibrated)
        {
            _sumX += sample.X;
            _sumZ += sample.Z;
            _calibrationSamples++;
            if (sample.X < _minX) _minX = sample.X;
            if (sample.X > _maxX) _maxX = sample.X;
            if (sample.Z < _minZ) _minZ = sample.Z;
            if (sample.Z > _maxZ) _maxZ = sample.Z;
            var accelMagnitude = sample.AccelMagnitude;
            if (accelMagnitude < _minAccelMagnitude) _minAccelMagnitude = accelMagnitude;
            if (accelMagnitude > _maxAccelMagnitude) _maxAccelMagnitude = accelMagnitude;
            if (now - _calibrationStartedAt < _calibrationTicks)
                return;

            var meanX = _sumX / _calibrationSamples;
            var meanZ = _sumZ / _calibrationSamples;
            var spreadX = _maxX - _minX;
            var spreadZ = _maxZ - _minZ;
            var accelOffRest =
                Math.Abs(_minAccelMagnitude - RestAccelMagnitude) > RestAccelTolerance ||
                Math.Abs(_maxAccelMagnitude - RestAccelMagnitude) > RestAccelTolerance;
            var implausible =
                Math.Abs(meanX) > MaxPlausibleBias || Math.Abs(meanZ) > MaxPlausibleBias ||
                spreadX > MaxPlausibleBias || spreadZ > MaxPlausibleBias ||
                accelOffRest;

            if (implausible && _calibrationAttempt < MaxCalibrationAttempts)
            {
                _calibrationAttempt++;
                _log($"Calibration rejected (mean X={meanX:F4}, Z={meanZ:F4}, " +
                     $"spread X={spreadX:F4}, Z={spreadZ:F4} rad/s, " +
                     $"accel |a|={_minAccelMagnitude:F2}..{_maxAccelMagnitude:F2} m/s^2) -- " +
                     $"controller moved during calibration. Retrying " +
                     $"({_calibrationAttempt}/{MaxCalibrationAttempts}); keep it still.");
                _sumX = 0;
                _sumZ = 0;
                _calibrationSamples = 0;
                _minX = double.MaxValue;
                _maxX = double.MinValue;
                _minZ = double.MaxValue;
                _maxZ = double.MinValue;
                _minAccelMagnitude = double.MaxValue;
                _maxAccelMagnitude = double.MinValue;
                _calibrationStartedAt = now;
                return;
            }

            _biasX = meanX;
            _biasZ = meanZ;
            _calibrated = true;
            _lastSampleAt = now;
            _log($"Gyro calibrated from {_calibrationSamples} samples: " +
                 $"X={_biasX:F4}, Z={_biasZ:F4} rad/s" +
                 (implausible ? " (accepted after max retries; aim may drift)." : "."));
            return;
        }

        var elapsed = (now - _lastSampleAt) / (double)Stopwatch.Frequency;
        _lastSampleAt = now;
        if (!IsGameForeground() || sample.L2 < _aimThreshold ||
            IsRightStickActive(sample))
        {
            ResetResidual();

            // Background drift correction: gyro bias is not a fixed
            // constant, it creeps with temperature and time in use. A
            // one-time startup calibration that was good at session start
            // can still go stale over a long play session ("starts pulling
            // to one side"). Whenever the controller is not being actively
            // aimed with, use the accelerometer to confirm it is actually
            // at rest (not just "close to the current bias guess", which
            // proves nothing if that guess is itself wrong), then nudge the
            // bias estimate slowly toward the current reading. The slow
            // rate keeps real deliberate motion from ever being mistaken
            // for drift.
            if (IsAtRest(sample))
            {
                _biasX += BackgroundRecalibrationAlpha * (sample.X - _biasX);
                _biasZ += BackgroundRecalibrationAlpha * (sample.Z - _biasZ);
            }
            return;
        }

        // Clamp pauses/debugger stops so they never produce a large camera jump.
        elapsed = Math.Clamp(elapsed, 0.0, 0.05);

        var rawYaw = sample.Z - _biasZ;
        var rawPitch = sample.X - _biasX;
        if (!_filterPrimed)
        {
            _filteredYawRaw = rawYaw;
            _filteredPitchRaw = rawPitch;
            _filterPrimed = true;
        }
        else
        {
            _filteredYawRaw += SmoothingAlpha * (rawYaw - _filteredYawRaw);
            _filteredPitchRaw += SmoothingAlpha * (rawPitch - _filteredPitchRaw);
        }

        var yaw = ApplyDeadzone(_filteredYawRaw);
        var pitch = ApplyDeadzone(_filteredPitchRaw);
        if (_invertYaw)
            yaw = -yaw;
        if (!_invertPitch)
            pitch = -pitch;

        _remainderX += yaw * _yawSensitivity * elapsed;
        _remainderY += pitch * _pitchSensitivity * elapsed;
        var dx = (int)Math.Truncate(_remainderX);
        var dy = (int)Math.Truncate(_remainderY);
        _remainderX -= dx;
        _remainderY -= dy;
        if (dx != 0 || dy != 0)
            SendRelativeMouseMove(dx, dy, _log);
    }

    private double ApplyDeadzone(double value) =>
        Math.Abs(value) < _deadzone ? 0.0 : value;

    private void ResetResidual()
    {
        _remainderX = 0;
        _remainderY = 0;
        _filterPrimed = false;
    }

    // Avoid mixing mouse deltas with a deliberate controller-camera input.
    private static bool IsRightStickActive(GyroMotionSample sample) =>
        Math.Abs(sample.RightStickX - 128) >= 24 ||
        Math.Abs(sample.RightStickY - 128) >= 24;

    private bool IsGameForeground()
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero)
            return false;
        GetWindowThreadProcessId(window, out var processId);
        try
        {
            using var process = Process.GetProcessById((int)processId);
            return process.ProcessName.Equals(
                _gameProcessName,
                StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private static int _sendCount;
    private static int _sendFailures;

    // SendInput can be silently dropped by Windows UIPI when the foreground
    // window runs at a higher integrity level (e.g. RE4R/Steam elevated)
    // than this process; it does not throw, it just does nothing. Log the
    // outcome so a "calibrated but camera never moves" report can be told
    // apart from a sensitivity/deadzone problem.
    private static void SendRelativeMouseMove(int dx, int dy, Action<string> log)
    {
        var input = new Input
        {
            Type = InputMouse,
            Union = new InputUnion
            {
                Mouse = new MouseInput { Dx = dx, Dy = dy, Flags = MouseEventMove }
            }
        };
        var sent = SendInput(1, new[] { input }, Marshal.SizeOf<Input>());
        _sendCount++;
        if (sent == 0)
        {
            _sendFailures++;
            var error = Marshal.GetLastWin32Error();
            if (_sendFailures <= 5 || _sendFailures % 200 == 0)
            {
                log($"SendInput failed (dx={dx}, dy={dy}): Win32 error {error}. " +
                    $"Failures {_sendFailures}/{_sendCount}. This usually means UIPI " +
                    "blocked the injection because the foreground window runs at a " +
                    "higher integrity level than this process (try running the " +
                    "transport/launcher as Administrator).");
            }
        }
        else if (_sendCount <= 5)
        {
            log($"SendInput ok (dx={dx}, dy={dy}).");
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion Union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }
}
