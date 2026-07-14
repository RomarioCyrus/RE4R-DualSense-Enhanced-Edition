using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace DualSenseHapticsProbe;

internal static class DualSenseHidModeSwitcher
{
    private const ushort SonyVendorId = 0x054C;
    private const ushort DualSenseProductId = 0x0CE6;
    private const ushort DualSenseEdgeProductId = 0x0DF2;

    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;

    public static string SelectAudioHapticsMode()
    {
        HidD_GetHidGuid(out var hidGuid);
        var deviceInfoSet = SetupDiGetClassDevs(
            ref hidGuid,
            null,
            IntPtr.Zero,
            DigcfPresent | DigcfDeviceInterface);
        if (deviceInfoSet == IntPtr.Zero || deviceInfoSet == new IntPtr(-1))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "Could not enumerate HID devices.");

        try
        {
            for (uint index = 0; ; index++)
            {
                var interfaceData = new SpDeviceInterfaceData
                {
                    Size = Marshal.SizeOf<SpDeviceInterfaceData>()
                };
                if (!SetupDiEnumDeviceInterfaces(
                        deviceInfoSet,
                        IntPtr.Zero,
                        ref hidGuid,
                        index,
                        ref interfaceData))
                {
                    var error = Marshal.GetLastWin32Error();
                    if (error == 259)
                        break;
                    throw new Win32Exception(error);
                }

                SetupDiGetDeviceInterfaceDetail(
                    deviceInfoSet,
                    ref interfaceData,
                    IntPtr.Zero,
                    0,
                    out var requiredSize,
                    IntPtr.Zero);
                if (requiredSize == 0)
                    continue;

                var detailBuffer = Marshal.AllocHGlobal((int)requiredSize);
                try
                {
                    Marshal.WriteInt32(
                        detailBuffer,
                        IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(
                            deviceInfoSet,
                            ref interfaceData,
                            detailBuffer,
                            requiredSize,
                            out _,
                            IntPtr.Zero))
                        continue;

                    var devicePath = Marshal.PtrToStringUni(
                        IntPtr.Add(detailBuffer, 4));
                    if (string.IsNullOrWhiteSpace(devicePath))
                        continue;

                    using var handle = CreateFile(
                        devicePath,
                        GenericWrite,
                        FileShareRead | FileShareWrite,
                        IntPtr.Zero,
                        OpenExisting,
                        0,
                        IntPtr.Zero);
                    if (handle.IsInvalid)
                        continue;

                    var attributes = new HiddAttributes
                    {
                        Size = Marshal.SizeOf<HiddAttributes>()
                    };
                    if (!HidD_GetAttributes(handle, ref attributes))
                        continue;
                    if (attributes.VendorId != SonyVendorId ||
                        (attributes.ProductId != DualSenseProductId &&
                         attributes.ProductId != DualSenseEdgeProductId))
                        continue;

                    if (!HidD_GetPreparsedData(handle, out var preparsedData))
                        continue;
                    ushort outputReportLength;
                    try
                    {
                        var capsStatus = HidP_GetCaps(
                            preparsedData,
                            out var caps);
                        if (capsStatus < 0 || caps.OutputReportByteLength < 3)
                            continue;
                        outputReportLength = caps.OutputReportByteLength;
                    }
                    finally
                    {
                        HidD_FreePreparsedData(preparsedData);
                    }

                    // USB report 0x02, 63 bytes. Valid flag 0 bit 1 means
                    // "apply haptics selection"; leaving compatible-vibration
                    // bits clear selects native/audio haptics instead of the
                    // classic rumble emulation selected by games such as RE4R.
                    // Windows WriteFile requires the complete HID descriptor
                    // OutputReportByteLength, including the report ID byte.
                    var report = new byte[outputReportLength];
                    report[0] = 0x02;
                    report[1] = 0x02;

                    if (!WriteFile(
                            handle,
                            report,
                            report.Length,
                            out var written,
                            IntPtr.Zero))
                        throw new Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "Failed to write the DualSense output report.");
                    if (written != report.Length)
                        throw new IOException(
                            $"Short HID write: {written}/{report.Length} bytes.");

                    var model = attributes.ProductId == DualSenseEdgeProductId
                        ? "DualSense Edge"
                        : "DualSense";
                    return $"{model} USB HID audio-haptics selection sent " +
                           $"({outputReportLength}-byte output report)";
                }
                finally
                {
                    Marshal.FreeHGlobal(detailBuffer);
                }
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(deviceInfoSet);
        }

        throw new InvalidOperationException(
            "No writable USB DualSense or DualSense Edge HID interface was found.");
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SpDeviceInterfaceData
    {
        public int Size;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HiddAttributes
    {
        public int Size;
        public ushort VendorId;
        public ushort ProductId;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HidpCaps
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
        public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_GetAttributes(
        SafeFileHandle deviceObject,
        ref HiddAttributes attributes);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_GetPreparsedData(
        SafeFileHandle deviceObject,
        out IntPtr preparsedData);

    [DllImport("hid.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_FreePreparsedData(
        IntPtr preparsedData);

    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(
        IntPtr preparsedData,
        out HidpCaps capabilities);

    [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(
        ref Guid classGuid,
        string? enumerator,
        IntPtr hwndParent,
        uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr deviceInfoSet,
        IntPtr deviceInfoData,
        ref Guid interfaceClassGuid,
        uint memberIndex,
        ref SpDeviceInterfaceData deviceInterfaceData);

    [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr deviceInfoSet,
        ref SpDeviceInterfaceData deviceInterfaceData,
        IntPtr deviceInterfaceDetailData,
        uint deviceInterfaceDetailDataSize,
        out uint requiredSize,
        IntPtr deviceInfoData);

    [DllImport("setupapi.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiDestroyDeviceInfoList(
        IntPtr deviceInfoSet);

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteFile(
        SafeFileHandle file,
        byte[] buffer,
        int numberOfBytesToWrite,
        out int numberOfBytesWritten,
        IntPtr overlapped);
}
