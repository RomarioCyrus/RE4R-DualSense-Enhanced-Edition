#define UNICODE
#define _UNICODE
#include <windows.h>

#define TH32CS_SNAPPROCESS 0x00000002

typedef struct tagPROCESSENTRY32W
{
    DWORD dwSize;
    DWORD cntUsage;
    DWORD th32ProcessID;
    ULONG_PTR th32DefaultHeapID;
    DWORD th32ModuleID;
    DWORD cntThreads;
    DWORD th32ParentProcessID;
    LONG pcPriClassBase;
    DWORD dwFlags;
    WCHAR szExeFile[MAX_PATH];
} PROCESSENTRY32W;

typedef HANDLE (WINAPI *CreateToolhelp32SnapshotFn)(DWORD, DWORD);
typedef BOOL (WINAPI *Process32FirstWFn)(HANDLE, PROCESSENTRY32W*);
typedef BOOL (WINAPI *Process32NextWFn)(HANDLE, PROCESSENTRY32W*);
typedef HANDLE (WINAPI *CreateJobObjectWFn)(LPSECURITY_ATTRIBUTES, LPCWSTR);
typedef BOOL (WINAPI *SetInformationJobObjectFn)(
    HANDLE,
    JOBOBJECTINFOCLASS,
    LPVOID,
    DWORD);
typedef BOOL (WINAPI *AssignProcessToJobObjectFn)(HANDLE, HANDLE);
typedef HANDLE (WINAPI *CreateMutexWFn)(LPSECURITY_ATTRIBUTES, BOOL, LPCWSTR);

typedef struct
{
    int major;
    int minor;
    int patch;
    const char* game_name;
} REFrameworkPluginVersion;

static HANDLE g_job = NULL;
static CreateToolhelp32SnapshotFn pCreateToolhelp32Snapshot = NULL;
static Process32FirstWFn pProcess32FirstW = NULL;
static Process32NextWFn pProcess32NextW = NULL;
static CreateJobObjectWFn pCreateJobObjectW = NULL;
static SetInformationJobObjectFn pSetInformationJobObject = NULL;
static AssignProcessToJobObjectFn pAssignProcessToJobObject = NULL;
static CreateMutexWFn pCreateMutexW = NULL;

static void write_launcher_log(const wchar_t* game_dir, const wchar_t* text)
{
    wchar_t path[MAX_PATH];
    HANDLE file;
    DWORD bytes;
    wsprintfW(path, L"%s\\reframework\\data\\DualSenseEnhanced\\launcher.log", game_dir);
    file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;
    WriteFile(file, text, (DWORD)(lstrlenW(text) * sizeof(wchar_t)), &bytes, NULL);
    CloseHandle(file);
}

static void initialize_kernel_api(void)
{
    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (kernel32 == NULL)
        return;

    pCreateToolhelp32Snapshot = (CreateToolhelp32SnapshotFn)
        GetProcAddress(kernel32, "CreateToolhelp32Snapshot");
    pProcess32FirstW = (Process32FirstWFn)
        GetProcAddress(kernel32, "Process32FirstW");
    pProcess32NextW = (Process32NextWFn)
        GetProcAddress(kernel32, "Process32NextW");
    pCreateJobObjectW = (CreateJobObjectWFn)
        GetProcAddress(kernel32, "CreateJobObjectW");
    pSetInformationJobObject = (SetInformationJobObjectFn)
        GetProcAddress(kernel32, "SetInformationJobObject");
    pAssignProcessToJobObject = (AssignProcessToJobObjectFn)
        GetProcAddress(kernel32, "AssignProcessToJobObject");
    pCreateMutexW = (CreateMutexWFn)
        GetProcAddress(kernel32, "CreateMutexW");
}

static BOOL is_process_running(const wchar_t* executable_name)
{
    PROCESSENTRY32W entry;
    HANDLE snapshot;
    BOOL found = FALSE;

    if (pCreateToolhelp32Snapshot == NULL ||
        pProcess32FirstW == NULL ||
        pProcess32NextW == NULL)
    {
        return FALSE;
    }

    snapshot = pCreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
        return FALSE;

    ZeroMemory(&entry, sizeof(entry));
    entry.dwSize = sizeof(entry);

    if (pProcess32FirstW(snapshot, &entry))
    {
        do
        {
            if (lstrcmpiW(entry.szExeFile, executable_name) == 0)
            {
                found = TRUE;
                break;
            }
        }
        while (pProcess32NextW(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return found;
}

static void initialize_job(void)
{
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION information;

    if (g_job != NULL)
        return;

    if (pCreateJobObjectW == NULL || pSetInformationJobObject == NULL)
        return;

    g_job = pCreateJobObjectW(NULL, NULL);
    if (g_job == NULL)
        return;

    ZeroMemory(&information, sizeof(information));
    information.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    pSetInformationJobObject(
        g_job,
        JobObjectExtendedLimitInformation,
        &information,
        sizeof(information));
}

static BOOL launch_audio_bridge(
    const wchar_t* game_dir,
    const wchar_t* reframework_path)
{
    wchar_t executable_path[MAX_PATH];
    wchar_t command_line[MAX_PATH * 3];
    STARTUPINFOW startup_info;
    PROCESS_INFORMATION process_info;

    wsprintfW(
        executable_path,
        L"%s\\reframework\\data\\DualSenseEnhanced\\DualsenseAudioBridge.exe",
        game_dir);
    if (GetFileAttributesW(executable_path) == INVALID_FILE_ATTRIBUTES)
        return FALSE;

    wsprintfW(
        command_line,
        L"\"%s\" --reframework \"%s\" --game-process \"re4\"",
        executable_path,
        reframework_path);

    ZeroMemory(&startup_info, sizeof(startup_info));
    startup_info.cb = sizeof(startup_info);
    ZeroMemory(&process_info, sizeof(process_info));

    if (!CreateProcessW(
            executable_path,
            command_line,
            NULL,
            NULL,
            FALSE,
            CREATE_NO_WINDOW | DETACHED_PROCESS,
            NULL,
            game_dir,
            &startup_info,
            &process_info))
    {
        return FALSE;
    }

    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return TRUE;
}

static BOOL launch_dsx_udp_client(const wchar_t* game_dir)
{
    wchar_t executable_path[MAX_PATH];
    wchar_t command_line[MAX_PATH * 2];
    STARTUPINFOW startup_info;
    PROCESS_INFORMATION process_info;
    HANDLE launch_mutex = NULL;
    DWORD wait_result;
    BOOL result = FALSE;

    if (pCreateMutexW != NULL)
    {
        launch_mutex = pCreateMutexW(
            NULL,
            FALSE,
            L"Global\\DualsenseDsxUdpClientLauncher_RE4R");
        if (launch_mutex != NULL)
        {
            wait_result = WaitForSingleObject(launch_mutex, 5000);
            if (wait_result != WAIT_OBJECT_0 &&
                wait_result != WAIT_ABANDONED)
            {
                CloseHandle(launch_mutex);
                return FALSE;
            }
        }
    }

    if (is_process_running(L"DSX_UDPClient.exe"))
    {
        result = TRUE;
        goto cleanup;
    }

    wsprintfW(executable_path, L"%s\\DSX_UDPClient.exe", game_dir);
    if (GetFileAttributesW(executable_path) == INVALID_FILE_ATTRIBUTES)
        goto cleanup;

    wsprintfW(command_line, L"\"%s\"", executable_path);

    ZeroMemory(&startup_info, sizeof(startup_info));
    startup_info.cb = sizeof(startup_info);
    ZeroMemory(&process_info, sizeof(process_info));

    if (!CreateProcessW(
            executable_path,
            command_line,
            NULL,
            NULL,
            FALSE,
            CREATE_NO_WINDOW | CREATE_SUSPENDED,
            NULL,
            game_dir,
            &startup_info,
            &process_info))
    {
        goto cleanup;
    }

    initialize_job();
    if (g_job != NULL && pAssignProcessToJobObject != NULL)
        pAssignProcessToJobObject(g_job, process_info.hProcess);

    ResumeThread(process_info.hThread);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    result = TRUE;

cleanup:
    if (launch_mutex != NULL)
    {
        ReleaseMutex(launch_mutex);
        CloseHandle(launch_mutex);
    }
    return result;
}

static BOOL transport_mode_is_dsx(const wchar_t* game_dir)
{
    wchar_t path[MAX_PATH];
    HANDLE file;
    char buffer[16] = {0};
    DWORD read = 0;

    wsprintfW(
        path,
        L"%s\\reframework\\data\\DualSenseEnhanced\\transport_mode.txt",
        game_dir);
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return FALSE; /* Native is the safe default. */

    ReadFile(file, buffer, sizeof(buffer) - 1, &read, NULL);
    CloseHandle(file);
    return read >= 3 && buffer[0] == 'd' && buffer[1] == 's' && buffer[2] == 'x';
}

static BOOL launch_trigger_watcher(
    const wchar_t* game_dir,
    const wchar_t* reframework_path)
{
    wchar_t executable_path[MAX_PATH];
    wchar_t command_path[MAX_PATH];
    wchar_t command_line[MAX_PATH * 4];
    STARTUPINFOW startup_info;
    PROCESS_INFORMATION process_info;

    wsprintfW(executable_path,
        L"%s\\reframework\\data\\DualSenseEnhanced\\DualSenseEnhancedTransport.exe",
        game_dir);
    if (GetFileAttributesW(executable_path) == INVALID_FILE_ATTRIBUTES)
        return FALSE;
    wsprintfW(command_path, L"%s\\data\\trigger_command.json", reframework_path);
    wsprintfW(command_line,
        L"\"%s\" --watch \"%s\" --game-process re4 --acknowledge-output-conflict",
        executable_path, command_path);

    ZeroMemory(&startup_info, sizeof(startup_info));
    startup_info.cb = sizeof(startup_info);
    ZeroMemory(&process_info, sizeof(process_info));
    if (!CreateProcessW(executable_path, command_line, NULL, NULL, FALSE,
            CREATE_NO_WINDOW | DETACHED_PROCESS, NULL, game_dir,
            &startup_info, &process_info))
    {
        wchar_t log[128];
        wsprintfW(log, L"native watcher CreateProcess failed: %lu", GetLastError());
        write_launcher_log(game_dir, log);
        return FALSE;
    }

    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return TRUE;
}

static DWORD WINAPI launch_bridges(LPVOID unused)
{
    wchar_t game_exe[MAX_PATH];
    wchar_t game_dir[MAX_PATH];
    wchar_t reframework_path[MAX_PATH];
    wchar_t* separator;
    DWORD result = 0;

    (void)unused;

    if (GetModuleFileNameW(NULL, game_exe, MAX_PATH) == 0)
        return 1;

    initialize_kernel_api();

    lstrcpynW(game_dir, game_exe, MAX_PATH);
    separator = wcsrchr(game_dir, L'\\');
    if (separator == NULL)
        return 1;
    *separator = L'\0';

    wsprintfW(reframework_path, L"%s\\reframework", game_dir);

    if (!launch_audio_bridge(game_dir, reframework_path))
        result |= 2;

    if (transport_mode_is_dsx(game_dir)) {
        if (!launch_dsx_udp_client(game_dir)) result |= 4;
    }

    if (result == 0)
        write_launcher_log(game_dir, transport_mode_is_dsx(game_dir)
            ? L"launcher: audio + DSX UDP started"
            : L"launcher: audio started; native trigger watcher deferred");

    return result;
}

__declspec(dllexport) void CALLBACK LaunchBridge(
    HWND hwnd,
    HINSTANCE instance,
    LPWSTR command_line,
    int show_command)
{
    HANDLE thread;
    (void)hwnd;
    (void)instance;
    (void)command_line;
    (void)show_command;

    thread = CreateThread(NULL, 0, launch_bridges, NULL, 0, NULL);
    if (thread != NULL)
        CloseHandle(thread);
}

__declspec(dllexport) void reframework_plugin_required_version(
    REFrameworkPluginVersion* version)
{
    if (version == NULL)
        return;

    version->major = 1;
    version->minor = 0;
    version->patch = 0;
    version->game_name = "RE4";
}

__declspec(dllexport) BOOL reframework_plugin_initialize(const void* parameter)
{
    (void)parameter;
    return TRUE;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    HANDLE thread;
    (void)reserved;

    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(instance);
        thread = CreateThread(NULL, 0, launch_bridges, NULL, 0, NULL);
        if (thread != NULL)
            CloseHandle(thread);
    }
    else if (reason == DLL_PROCESS_DETACH && g_job != NULL)
    {
        CloseHandle(g_job);
        g_job = NULL;
    }

    return TRUE;
}
