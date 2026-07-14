# Experimental DSX UDP Client

This is an independent test implementation of the public DSX UDP transport.
It does not contain code from `DualSense4Rockstar`.

The client:

- sends the existing `payload.json` bytes to DSX on `127.0.0.1`;
- reads the Steam DSX port from
  `%LOCALAPPDATA%\DSX\DSX_UDP_PortNumber.txt`;
- falls back to the legacy
  `C:\Temp\DualSenseEnhanced\DualSenseEnhanced_PortNumber.txt`, then port `6969`;
- uses `ReadDirectoryChangesW` instead of polling;
- waits for two identical reads before sending;
- does not resend unchanged content;
- repeats the initial controller state at 0, 0.5, 1.5, and 3.5 seconds to
  survive a startup race with DSX;
- runs as a separate native process with no .NET runtime.

Default payload path when placed in the RE4R directory:

```text
reframework\data\DualSenseEnhanced\payload.json
```

An alternate file can be supplied for testing:

```powershell
.\DSX_UDPClient_Test.exe --payload "C:\path\payload.json"
```

For a local listener test, the DSX port can be overridden:

```powershell
.\DSX_UDPClient_Test.exe --payload "C:\path\payload.json" --port 16969
```

Do not run it alongside another DSX UDP client during an in-game test.
