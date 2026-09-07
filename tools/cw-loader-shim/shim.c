/*
 * discord_game_sdk.dll - loader shim for Black Ops Cold War
 *
 * The game LoadLibrary()s "discord_game_sdk.dll" from its own folder late in
 * startup and resolves exactly one symbol, DiscordCreate.  That makes it the
 * only usable hijack slot in the process: the other dynamically loaded DLLs
 * (bink2w64, dxgi, ole32, oo2core_8_win64, steam_api64) are all load-bearing
 * and load far too early to pattern-scan the decrypted exe against.
 *
 * This shim takes that slot and chain-loads two payloads:
 *
 *   cwpatch.dll         the original hijack DLL, renamed.  Its DiscordCreate
 *                       starts its own two threads: one sets the dvar
 *                       loot_fakeall (hash 0x60cdc482a7d159f8), the other
 *                       binds F4/F5/F6/F7 to lobbylaunchgame, killserver,
 *                       fast_restart, full_restart.
 *
 *   CW_Soft_Unlock.dll  loaded on F8.  It does all of its work synchronously
 *                       in DllMain, once, with no retry, so it has to be
 *                       loaded when the loot/inventory system is already up -
 *                       the same moment you would otherwise attach Process
 *                       Hacker.  A timer would be guesswork; the hotkey
 *                       reproduces the known-good timing.
 *
 * DiscordCreate returns 1 (DiscordResult_ServiceUnavailable), exactly as
 * cwpatch.dll does, so the game cleanly skips its Discord integration.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define UNLOCK_HOTKEY   VK_F8
#define CWPATCH_DLL     "cwpatch.dll"
#define SOFTUNLOCK_DLL  "CW_Soft_Unlock.dll"

typedef int (*DiscordCreate_t)(int version, void *params, void **result);

static HMODULE       g_self;
static volatile LONG g_unlock_loaded;

/* "<folder holding this dll>\<name>", so nothing depends on the CWD. */
static BOOL sibling_path(const char *name, char *out, DWORD cch)
{
    DWORD n = GetModuleFileNameA(g_self, out, cch);

    if (n == 0 || n >= cch)
        return FALSE;

    while (n > 0 && out[n - 1] != '\\' && out[n - 1] != '/')
        n--;
    out[n] = '\0';

    if ((DWORD)lstrlenA(out) + (DWORD)lstrlenA(name) + 1 > cch)
        return FALSE;

    lstrcatA(out, name);
    return TRUE;
}

static HMODULE load_sibling(const char *name)
{
    char path[1024];

    if (!sibling_path(name, path, sizeof(path)))
        return NULL;

    return LoadLibraryA(path);
}

static DWORD WINAPI unlock_thread(LPVOID unused)
{
    (void)unused;

    for (;;) {
        if (GetAsyncKeyState(UNLOCK_HOTKEY) & 0x8000) {
            if (InterlockedCompareExchange(&g_unlock_loaded, 1, 0) == 0) {
                /* CW_Soft_Unlock puts up its own message box when it runs. */
                if (!load_sibling(SOFTUNLOCK_DLL)) {
                    MessageBoxA(NULL,
                                "Could not load " SOFTUNLOCK_DLL ".\n"
                                "It has to sit next to BlackOpsColdWar.exe.",
                                "Loader shim", MB_OK | MB_ICONERROR);
                    InterlockedExchange(&g_unlock_loaded, 0); /* allow retry */
                }
            }
        }
        Sleep(50);
    }
}

__declspec(dllexport)
int DiscordCreate(int version, void *params, void **result)
{
    HMODULE cwpatch = load_sibling(CWPATCH_DLL);
    HANDLE  thread;

    if (cwpatch) {
        DiscordCreate_t chain =
            (DiscordCreate_t)(void *)GetProcAddress(cwpatch, "DiscordCreate");

        if (chain)
            chain(version, params, result); /* loot_fakeall + F4-F7 */
    }

    thread = CreateThread(NULL, 0, unlock_thread, NULL, 0, NULL);
    if (thread)
        CloseHandle(thread);

    return 1; /* DiscordResult_ServiceUnavailable, same as cwpatch.dll */
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;

    if (reason == DLL_PROCESS_ATTACH) {
        g_self = (HMODULE)inst;
        DisableThreadLibraryCalls(inst);
    }

    return TRUE;
}
