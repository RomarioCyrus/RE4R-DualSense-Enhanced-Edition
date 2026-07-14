namespace DualsenseAudioBridge;

public sealed class BridgeRuntimeOptions
{
    public string ReframeworkDirectory { get; private init; } = "";
    public string? GameProcessName { get; private init; }
    public bool ListDevices { get; private init; }

    public static BridgeRuntimeOptions Parse(string[] args)
    {
        string? reframeworkArg = null;
        string? gameProcessName = null;
        var listDevices = false;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--reframework" when i + 1 < args.Length:
                    reframeworkArg = args[++i];
                    break;
                case "--game-process" when i + 1 < args.Length:
                    gameProcessName = Path.GetFileNameWithoutExtension(args[++i]);
                    break;
                case "--list-devices":
                    listDevices = true;
                    break;
            }
        }

        var reframeworkDir = ResolveReframeworkDirectory(reframeworkArg);
        return new BridgeRuntimeOptions
        {
            ReframeworkDirectory = reframeworkDir,
            // Default to "re4" instead of leaving this null. A bridge with
            // no game process to watch waits on Task.Delay(Infinite) and
            // never self-exits; if it's ever started without --game-process
            // (a manual test run, a stale shortcut), it becomes a zombie
            // that blocks every later launch via the single-instance mutex
            // with no trace in the log. Pass --game-process "" to opt out.
            GameProcessName = gameProcessName is null
                ? "re4"
                : (string.IsNullOrWhiteSpace(gameProcessName) ? null : gameProcessName),
            ListDevices = listDevices
        };
    }

    private static string ResolveReframeworkDirectory(string? configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            var explicitPath = Path.GetFullPath(configuredPath, Environment.CurrentDirectory);
            if (Directory.Exists(explicitPath))
                return explicitPath;

            throw new DirectoryNotFoundException(
                $"REFramework directory not found: {explicitPath}");
        }

        var fromExecutable = FindAncestorNamed(AppContext.BaseDirectory, "reframework");
        if (fromExecutable != null)
            return fromExecutable;

        var fromWorkingDirectory = Path.Combine(Environment.CurrentDirectory, "reframework");
        if (Directory.Exists(fromWorkingDirectory))
            return Path.GetFullPath(fromWorkingDirectory);

        throw new DirectoryNotFoundException(
            "REFramework directory was not found. Pass --reframework <path>.");
    }

    private static string? FindAncestorNamed(string startPath, string directoryName)
    {
        var current = new DirectoryInfo(Path.GetFullPath(startPath));
        while (current != null)
        {
            if (current.Name.Equals(directoryName, StringComparison.OrdinalIgnoreCase))
                return current.FullName;
            current = current.Parent;
        }

        return null;
    }
}
