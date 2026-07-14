#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define PAYLOAD_CAPACITY (64 * 1024)
#define CHANGE_BUFFER_SIZE 4096
#define DEFAULT_DSX_PORT 6969
#define AF_INET 2
#define SOCK_DGRAM 2
#define IPPROTO_UDP 17
#define INVALID_SOCKET ((SOCKET)(~0))
#define SOCKET_ERROR (-1)

typedef uintptr_t SOCKET;

typedef struct
{
    unsigned short sin_family;
    unsigned short sin_port;
    uint32_t sin_addr;
    char sin_zero[8];
} SOCKADDR_IN;

typedef struct
{
    WORD version;
    WORD high_version;
    char description[257];
    char system_status[129];
    unsigned short max_sockets;
    unsigned short max_udp_datagram;
    char* vendor_info;
} WSADATA_LOCAL;

typedef int (WINAPI *WSAStartupFn)(WORD, WSADATA_LOCAL*);
typedef int (WINAPI *WSACleanupFn)(void);
typedef SOCKET (WINAPI *SocketFn)(int, int, int);
typedef int (WINAPI *SendToFn)(
    SOCKET,
    const char*,
    int,
    int,
    const void*,
    int);
typedef int (WINAPI *CloseSocketFn)(SOCKET);
typedef wchar_t** (WINAPI *CommandLineToArgvWFn)(const wchar_t*, int*);

static wchar_t g_payload_path[MAX_PATH];
static wchar_t g_payload_directory[MAX_PATH];
static wchar_t g_payload_name[MAX_PATH];
static wchar_t g_log_path[MAX_PATH];
static char g_last_payload[PAYLOAD_CAPACITY];
static DWORD g_last_payload_size;
static SOCKET g_socket = INVALID_SOCKET;
static SOCKADDR_IN g_endpoint;
static WSAStartupFn pWSAStartup;
static WSACleanupFn pWSACleanup;
static SocketFn pSocket;
static SendToFn pSendTo;
static CloseSocketFn pCloseSocket;
static CommandLineToArgvWFn pCommandLineToArgvW;
static int g_port_override;
static CRITICAL_SECTION g_send_lock;

static unsigned short host_to_network_short(unsigned short value)
{
    return (unsigned short)((value << 8) | (value >> 8));
}

static BOOL initialize_winsock_api(void)
{
    HMODULE module = LoadLibraryW(L"ws2_32.dll");
    if (module == NULL)
        return FALSE;

    pWSAStartup = (WSAStartupFn)GetProcAddress(module, "WSAStartup");
    pWSACleanup = (WSACleanupFn)GetProcAddress(module, "WSACleanup");
    pSocket = (SocketFn)GetProcAddress(module, "socket");
    pSendTo = (SendToFn)GetProcAddress(module, "sendto");
    pCloseSocket = (CloseSocketFn)GetProcAddress(module, "closesocket");

    return pWSAStartup != NULL &&
        pWSACleanup != NULL &&
        pSocket != NULL &&
        pSendTo != NULL &&
        pCloseSocket != NULL;
}

static void write_log(const wchar_t* message)
{
    HANDLE file;
    SYSTEMTIME time;
    wchar_t line[1024];
    DWORD bytes_written;
    int length;

    file = CreateFileW(
        g_log_path,
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE)
        return;

    GetLocalTime(&time);
    length = wsprintfW(
        line,
        L"%04u-%02u-%02u %02u:%02u:%02u.%03u %s\r\n",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds,
        message);
    WriteFile(file, line, (DWORD)(length * sizeof(wchar_t)), &bytes_written, NULL);
    CloseHandle(file);
}

static BOOL read_text_file(
    const wchar_t* path,
    char* buffer,
    DWORD capacity,
    DWORD* size)
{
    HANDLE file;
    DWORD file_size;
    DWORD bytes_read;

    file = CreateFileW(
        path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE)
        return FALSE;

    file_size = GetFileSize(file, NULL);
    if (file_size == INVALID_FILE_SIZE ||
        file_size == 0 ||
        file_size >= capacity)
    {
        CloseHandle(file);
        return FALSE;
    }

    bytes_read = 0;
    if (!ReadFile(file, buffer, file_size, &bytes_read, NULL) ||
        bytes_read != file_size)
    {
        CloseHandle(file);
        return FALSE;
    }

    CloseHandle(file);
    buffer[bytes_read] = '\0';
    *size = bytes_read;
    return TRUE;
}

static BOOL is_plausible_dsx_packet(const char* payload, DWORD size)
{
    DWORD first = 0;
    DWORD last = size;

    while (first < size &&
           (payload[first] == ' ' ||
            payload[first] == '\t' ||
            payload[first] == '\r' ||
            payload[first] == '\n'))
    {
        ++first;
    }

    while (last > first &&
           (payload[last - 1] == ' ' ||
            payload[last - 1] == '\t' ||
            payload[last - 1] == '\r' ||
            payload[last - 1] == '\n'))
    {
        --last;
    }

    if (last - first < 20 ||
        payload[first] != '{' ||
        payload[last - 1] != '}')
    {
        return FALSE;
    }

    return strstr(payload + first, "\"instructions\"") != NULL;
}

static BOOL read_stable_payload(char* payload, DWORD* size)
{
    DWORD attempt;
    DWORD first_size;
    DWORD second_size;
    char first[PAYLOAD_CAPACITY];
    char second[PAYLOAD_CAPACITY];

    for (attempt = 0; attempt < 6; ++attempt)
    {
        if (!read_text_file(
                g_payload_path,
                first,
                PAYLOAD_CAPACITY,
                &first_size))
        {
            Sleep(2);
            continue;
        }

        Sleep(2);
        if (!read_text_file(
                g_payload_path,
                second,
                PAYLOAD_CAPACITY,
                &second_size))
        {
            Sleep(2);
            continue;
        }

        if (first_size == second_size &&
            memcmp(first, second, first_size) == 0 &&
            is_plausible_dsx_packet(second, second_size))
        {
            memcpy(payload, second, second_size);
            payload[second_size] = '\0';
            *size = second_size;
            return TRUE;
        }

        Sleep(2);
    }

    return FALSE;
}

static int read_port_file(const wchar_t* path)
{
    char buffer[32];
    DWORD size;
    int port;

    if (!read_text_file(path, buffer, sizeof(buffer), &size))
        return 0;

    buffer[size] = '\0';
    port = atoi(buffer);
    if (port < 1 || port > 65535)
        return 0;
    return port;
}

static int find_dsx_port(void)
{
    wchar_t path[MAX_PATH];
    wchar_t local_app_data[MAX_PATH];
    DWORD length;
    int port;

    length = GetEnvironmentVariableW(
        L"LOCALAPPDATA",
        local_app_data,
        MAX_PATH);
    if (length > 0 && length < MAX_PATH)
    {
        wsprintfW(
            path,
            L"%s\\DSX\\DSX_UDP_PortNumber.txt",
            local_app_data);
        port = read_port_file(path);
        if (port != 0)
            return port;
    }

    port = read_port_file(
        L"C:\\Temp\\DualSenseEnhanced\\DualSenseEnhanced_PortNumber.txt");
    return port != 0 ? port : DEFAULT_DSX_PORT;
}

static BOOL send_current_payload(BOOL force)
{
    char payload[PAYLOAD_CAPACITY];
    DWORD payload_size;
    int sent;

    EnterCriticalSection(&g_send_lock);

    if (!read_stable_payload(payload, &payload_size))
    {
        LeaveCriticalSection(&g_send_lock);
        return FALSE;
    }

    if (!force &&
        payload_size == g_last_payload_size &&
        memcmp(payload, g_last_payload, payload_size) == 0)
    {
        LeaveCriticalSection(&g_send_lock);
        return TRUE;
    }

    sent = pSendTo(
        g_socket,
        payload,
        (int)payload_size,
        0,
        &g_endpoint,
        sizeof(g_endpoint));
    if (sent != (int)payload_size)
    {
        LeaveCriticalSection(&g_send_lock);
        return FALSE;
    }

    memcpy(g_last_payload, payload, payload_size);
    g_last_payload_size = payload_size;
    LeaveCriticalSection(&g_send_lock);
    return TRUE;
}

static DWORD WINAPI repeat_startup_state(LPVOID unused)
{
    static const DWORD delays[] = { 500, 1000, 2000 };
    DWORD index;

    (void)unused;

    for (index = 0; index < sizeof(delays) / sizeof(delays[0]); ++index)
    {
        Sleep(delays[index]);
        send_current_payload(TRUE);
    }

    return 0;
}

static BOOL notification_mentions_payload(
    const BYTE* buffer,
    DWORD bytes_returned)
{
    DWORD offset = 0;

    while (offset < bytes_returned)
    {
        const FILE_NOTIFY_INFORMATION* information =
            (const FILE_NOTIFY_INFORMATION*)(buffer + offset);
        int name_length = (int)(information->FileNameLength / sizeof(wchar_t));

        if (name_length == lstrlenW(g_payload_name) &&
            _wcsnicmp(
                information->FileName,
                g_payload_name,
                name_length) == 0)
        {
            return TRUE;
        }

        if (information->NextEntryOffset == 0)
            break;
        offset += information->NextEntryOffset;
    }

    return FALSE;
}

static int watch_payload(void)
{
    HANDLE directory;
    BYTE change_buffer[CHANGE_BUFFER_SIZE];
    DWORD bytes_returned;

    directory = CreateFileW(
        g_payload_directory,
        FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS,
        NULL);
    if (directory == INVALID_HANDLE_VALUE)
    {
        write_log(L"Failed to open payload directory.");
        return 5;
    }

    send_current_payload(TRUE);

    for (;;)
    {
        if (!ReadDirectoryChangesW(
                directory,
                change_buffer,
                sizeof(change_buffer),
                FALSE,
                FILE_NOTIFY_CHANGE_FILE_NAME |
                    FILE_NOTIFY_CHANGE_LAST_WRITE |
                    FILE_NOTIFY_CHANGE_SIZE,
                &bytes_returned,
                NULL,
                NULL))
        {
            write_log(L"ReadDirectoryChangesW failed.");
            CloseHandle(directory);
            return 6;
        }

        if (!notification_mentions_payload(change_buffer, bytes_returned))
            continue;

        Sleep(3);
        send_current_payload(FALSE);
    }
}

static void split_payload_path(void)
{
    wchar_t* separator;

    lstrcpynW(g_payload_directory, g_payload_path, MAX_PATH);
    separator = wcsrchr(g_payload_directory, L'\\');
    if (separator == NULL)
    {
        lstrcpyW(g_payload_directory, L".");
        lstrcpynW(g_payload_name, g_payload_path, MAX_PATH);
        return;
    }

    lstrcpynW(g_payload_name, separator + 1, MAX_PATH);
    *separator = L'\0';
}

static void set_default_paths(void)
{
    wchar_t executable_path[MAX_PATH];
    wchar_t* separator;

    GetModuleFileNameW(NULL, executable_path, MAX_PATH);
    lstrcpynW(g_log_path, executable_path, MAX_PATH);
    separator = wcsrchr(g_log_path, L'\\');
    if (separator != NULL)
    {
        *(separator + 1) = L'\0';
        lstrcatW(g_log_path, L"DSX_UDPClient_Test.log");
    }
    else
    {
        lstrcpyW(g_log_path, L"DSX_UDPClient_Test.log");
    }

    lstrcpynW(g_payload_path, executable_path, MAX_PATH);
    separator = wcsrchr(g_payload_path, L'\\');
    if (separator != NULL)
    {
        *(separator + 1) = L'\0';
        lstrcatW(
            g_payload_path,
            L"reframework\\data\\DualSenseEnhanced\\payload.json");
    }
    else
    {
        lstrcpyW(
            g_payload_path,
            L"reframework\\data\\DualSenseEnhanced\\payload.json");
    }
}

static void parse_arguments(void)
{
    HMODULE shell32;
    int argument_count;
    int index;
    wchar_t** arguments;

    shell32 = LoadLibraryW(L"shell32.dll");
    if (shell32 == NULL)
        return;

    pCommandLineToArgvW = (CommandLineToArgvWFn)
        GetProcAddress(shell32, "CommandLineToArgvW");
    if (pCommandLineToArgvW == NULL)
        return;

    arguments = pCommandLineToArgvW(GetCommandLineW(), &argument_count);

    if (arguments == NULL)
        return;

    for (index = 1; index + 1 < argument_count; ++index)
    {
        if (lstrcmpiW(arguments[index], L"--payload") == 0)
        {
            lstrcpynW(
                g_payload_path,
                arguments[index + 1],
                MAX_PATH);
            ++index;
        }
        else if (lstrcmpiW(arguments[index], L"--log") == 0)
        {
            lstrcpynW(
                g_log_path,
                arguments[index + 1],
                MAX_PATH);
            ++index;
        }
        else if (lstrcmpiW(arguments[index], L"--port") == 0)
        {
            int candidate = _wtoi(arguments[index + 1]);
            if (candidate > 0 && candidate <= 65535)
                g_port_override = candidate;
            ++index;
        }
    }

    LocalFree(arguments);
}

int WINAPI wWinMain(
    HINSTANCE instance,
    HINSTANCE previous_instance,
    LPWSTR command_line,
    int show_command)
{
    HANDLE mutex;
    HANDLE startup_repeat_thread;
    WSADATA_LOCAL winsock_data;
    int port;
    int result;
    wchar_t message[256];

    (void)instance;
    (void)previous_instance;
    (void)command_line;
    (void)show_command;

    mutex = CreateMutexW(
        NULL,
        TRUE,
        L"Local\\DSX_UDPClient_Test_RE4R");
    if (mutex == NULL || GetLastError() == ERROR_ALREADY_EXISTS)
    {
        if (mutex != NULL)
            CloseHandle(mutex);
        return 0;
    }

    set_default_paths();
    parse_arguments();
    split_payload_path();
    InitializeCriticalSection(&g_send_lock);

    if (!initialize_winsock_api() ||
        pWSAStartup(MAKEWORD(2, 2), &winsock_data) != 0)
    {
        write_log(L"WSAStartup failed.");
        CloseHandle(mutex);
        return 2;
    }

    g_socket = pSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (g_socket == INVALID_SOCKET)
    {
        write_log(L"Failed to create UDP socket.");
        pWSACleanup();
        CloseHandle(mutex);
        return 3;
    }

    port = g_port_override != 0 ? g_port_override : find_dsx_port();
    ZeroMemory(&g_endpoint, sizeof(g_endpoint));
    g_endpoint.sin_family = AF_INET;
    g_endpoint.sin_port = host_to_network_short((unsigned short)port);
    g_endpoint.sin_addr = 0x0100007f;

    wsprintfW(
        message,
        L"Started. Port=%d Payload=%s",
        port,
        g_payload_path);
    write_log(message);

    startup_repeat_thread = CreateThread(
        NULL,
        0,
        repeat_startup_state,
        NULL,
        0,
        NULL);
    if (startup_repeat_thread != NULL)
        CloseHandle(startup_repeat_thread);

    result = watch_payload();

    pCloseSocket(g_socket);
    pWSACleanup();
    DeleteCriticalSection(&g_send_lock);
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return result;
}
