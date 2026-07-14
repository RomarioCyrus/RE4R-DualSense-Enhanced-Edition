using System.Text;

namespace DualsenseAudioBridge;

public static class BridgeLog
{
    public static IDisposable Initialize()
    {
        try
        {
            var logPath = Path.Combine(AppContext.BaseDirectory, "DualsenseAudioBridge.log");
            var stream = new FileStream(
                logPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.ReadWrite);
            var writer = TextWriter.Synchronized(
                new StreamWriter(stream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true))
                {
                    AutoFlush = true
                });
            Console.SetOut(writer);
            Console.SetError(writer);
            return writer;
        }
        catch
        {
            Console.SetOut(TextWriter.Null);
            Console.SetError(TextWriter.Null);
            return NullDisposable.Instance;
        }
    }

    private sealed class NullDisposable : IDisposable
    {
        public static readonly NullDisposable Instance = new();
        public void Dispose() { }
    }
}
