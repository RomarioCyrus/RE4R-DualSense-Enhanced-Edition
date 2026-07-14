using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

internal static unsafe class LauncherExports
{
    private static readonly IntPtr GameName = Marshal.StringToHGlobalAnsi("RE4");
    private static readonly object StartLock = new();
    private static bool started;

    [StructLayout(LayoutKind.Sequential)]
    public struct REFrameworkPluginVersion
    {
        public int major;
        public int minor;
        public int patch;
        public IntPtr game_name;
    }

    [UnmanagedCallersOnly(EntryPoint = "reframework_plugin_required_version")]
    public static void RequiredVersion(REFrameworkPluginVersion* version)
    {
        if (version == null) return;
        version->major = 1;
        version->minor = 0;
        version->patch = 0;
        version->game_name = GameName;
    }

    [UnmanagedCallersOnly(EntryPoint = "reframework_plugin_initialize")]
    public static int Initialize(IntPtr parameter)
    {
        _ = parameter;
        StartOnce();
        return 1;
    }

    [UnmanagedCallersOnly(
        EntryPoint = "LaunchBridge",
        CallConvs = new[] { typeof(CallConvStdcall) })]
    public static void LaunchBridge(
        IntPtr hwnd,
        IntPtr instance,
        IntPtr commandLine,
        int showCommand)
    {
        _ = hwnd;
        _ = instance;
        _ = commandLine;
        _ = showCommand;
        StartOnce();
    }

    private static void StartOnce()
    {
        lock (StartLock)
        {
            if (started) return;
            started = true;
        }

        var thread = new Thread(LaunchBridges)
        {
            IsBackground = true,
            Name = "DualSenseEnhancedLauncher"
        };
        thread.Start();
    }

    private static void LaunchBridges()
    {
        try
        {
            var gameExe = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(gameExe)) return;

            var gameDir = Path.GetDirectoryName(gameExe);
            if (string.IsNullOrWhiteSpace(gameDir)) return;

            var reframeworkPath = Path.Combine(gameDir, "reframework");
            var audioStarted = LaunchAudioBridge(gameDir, reframeworkPath);
            var dsxStarted = false;
            if (TransportModeIsDsx(gameDir))
            {
                dsxStarted = LaunchDsxUdpClient(gameDir);
            }

            if (audioStarted)
            {
                WriteLauncherLog(
                    gameDir,
                    dsxStarted
                        ? "launcher: audio + DSX UDP started"
                        : "launcher: audio started; DSX UDP not requested");
            }
        }
        catch (Exception ex)
        {
            TryWriteFallbackLog(ex.ToString());
        }
    }

    private static bool LaunchAudioBridge(string gameDir, string reframeworkPath)
    {
        var executable = Path.Combine(
            gameDir,
            "reframework",
            "data",
            "DualSenseEnhanced",
            "DualsenseAudioBridge.exe");
        if (!File.Exists(executable)) return false;

        try
        {
            var startInfo = new ProcessStartInfo(executable)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = gameDir,
            };
            startInfo.ArgumentList.Add("--reframework");
            startInfo.ArgumentList.Add(reframeworkPath);
            startInfo.ArgumentList.Add("--game-process");
            startInfo.ArgumentList.Add("re4");
            Process.Start(startInfo)?.Dispose();
            return true;
        }
        catch (Exception ex)
        {
            WriteLauncherLog(gameDir, "audio bridge CreateProcess failed: " + ex.Message);
            return false;
        }
    }

    private static bool LaunchDsxUdpClient(string gameDir)
    {
        using var mutex = new Mutex(false, @"Global\DualsenseDsxUdpClientLauncher_RE4R");
        var ownsMutex = false;
        try
        {
            ownsMutex = mutex.WaitOne(TimeSpan.FromSeconds(5));
            if (!ownsMutex) return false;

            if (Process.GetProcessesByName("DSX_UDPClient").Length > 0)
                return true;

            var executable = Path.Combine(gameDir, "DSX_UDPClient.exe");
            if (!File.Exists(executable)) return false;

            var startInfo = new ProcessStartInfo(executable)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = gameDir,
            };
            Process.Start(startInfo)?.Dispose();
            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            if (ownsMutex) mutex.ReleaseMutex();
        }
    }

    private static bool TransportModeIsDsx(string gameDir)
    {
        var path = Path.Combine(
            gameDir,
            "reframework",
            "data",
            "DualSenseEnhanced",
            "transport_mode.txt");
        try
        {
            return File.Exists(path)
                && File.ReadAllText(path).Trim().StartsWith(
                    "dsx",
                    StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static void WriteLauncherLog(string gameDir, string text)
    {
        try
        {
            var path = Path.Combine(
                gameDir,
                "reframework",
                "data",
                "DualSenseEnhanced",
                "launcher.log");
            File.WriteAllText(path, text);
        }
        catch
        {
        }
    }

    private static void TryWriteFallbackLog(string text)
    {
        try
        {
            File.WriteAllText("DualsenseAudioBridgeLauncher.initfail.log", text);
        }
        catch
        {
        }
    }
}
