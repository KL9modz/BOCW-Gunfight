/* bridge.c - the in-context control bridge (docs/notes/in-context-bridge.md).
 *
 * External app (gf_control.py via bridge_channel.py) writes console command lines into a
 * named shared-memory block; this DLL, running INSIDE the game, executes them with cwpatch's
 * command mechanism. The app composes `set gf_cmd_map <m>` / `set gf_cmd_gametype <g>` /
 * `set gf_cmd_stage <n>` / `set gf_cmd_go 1`; the existing GSC cmd_poll() consumes gf_cmd_*
 * and performs the action. The DLL is a dumb, generic "run this console command" service -
 * all mod logic stays in GSC and Python.
 *
 * ⚠ SHIP THIS ONLY AFTER T1 PASSES (gf_t1.dll proves console `set` reaches GSC getdvarint).
 *   - If T1 showed in-process `set` is safe mid-match from a worker thread, this is complete.
 *   - If T1 showed it wedges mid-match, the execute step must move to a MAIN-THREAD hook
 *     (see in-context-bridge.md "thread-safety"); the command transport below is unchanged.
 *
 * Build / load / guard: same as t1_test.c. cwpatch must be loaded. klaze builds & runs.
 *
 * Channel layout (256 bytes, little-endian), shared with bridge_channel.py:
 *     +0  u32 magic = 'GFB1' (0x31424647)   - DLL ignores the block until it reads this
 *     +4  u32 seq                           - the app bumps this for each new command
 *     +8  u32 len                           - bytes of cmd in use
 *     +12 char cmd[244]                     - one or more console commands, '\n'-separated
 */

#include <windows.h>

#define CW_EXECUTOR_RVA 0x5638
#define CW_CMDSLOT_RVA  0x5640
#define RESTORE_LEN     48

#define SHM_NAME  "gf_bridge"   /* session-local; app and game are the same user/session */
#define SHM_SIZE  256
#define SHM_MAGIC 0x31424647u

static void run_console_command(const char *cmd, size_t len)
{
    HMODULE cw = GetModuleHandleA("discord_game_sdk.dll");
    if (!cw) return;
    unsigned char *base = (unsigned char *)cw;
    void (*executor)(void) = *(void (**)(void))(base + CW_EXECUTOR_RVA);
    unsigned char *slot    = *(unsigned char **)(base + CW_CMDSLOT_RVA);
    if (!executor || !slot || len == 0) return;

    HANDLE self = GetCurrentProcess();
    SIZE_T n;
    unsigned char saved[RESTORE_LEN];
    if (!ReadProcessMemory(self, slot, saved, RESTORE_LEN, &n)) return;

    char buf[256];
    if (len > sizeof(buf) - 2) len = sizeof(buf) - 2;
    for (size_t i = 0; i < len; i++) buf[i] = cmd[i];
    buf[len] = '\n';
    WriteProcessMemory(self, slot, buf, len + 1, &n);
    executor();
    WriteProcessMemory(self, slot, saved, RESTORE_LEN, &n);
}

/* Execute a block that may hold several '\n'-separated commands, one at a time. */
static void run_block(const char *p, DWORD len)
{
    DWORD i = 0;
    while (i < len) {
        DWORD start = i;
        while (i < len && p[i] != '\n' && p[i] != '\0') i++;
        if (i > start) run_console_command(p + start, i - start);
        while (i < len && (p[i] == '\n' || p[i] == '\0')) i++;
    }
}

static DWORD WINAPI poll_thread(LPVOID unused)
{
    (void)unused;

    HANDLE hMap = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE,
                                     0, SHM_SIZE, SHM_NAME);
    if (!hMap) return 1;
    volatile unsigned char *shm = (volatile unsigned char *)
        MapViewOfFile(hMap, FILE_MAP_ALL_ACCESS, 0, 0, SHM_SIZE);
    if (!shm) return 1;

    /* If we created it fresh, stamp the magic so the app can tell the DLL is listening.
     * (If the app already created it, its magic is set and this is harmless.) */
    if (GetLastError() != ERROR_ALREADY_EXISTS)
        *(volatile DWORD *)(shm + 0) = SHM_MAGIC;

    DWORD last_seq = *(volatile DWORD *)(shm + 4);
    for (;;) {
        if (*(volatile DWORD *)(shm + 0) == SHM_MAGIC) {
            DWORD seq = *(volatile DWORD *)(shm + 4);
            if (seq != last_seq) {
                DWORD len = *(volatile DWORD *)(shm + 8);
                if (len > SHM_SIZE - 12) len = SHM_SIZE - 12;
                char local[SHM_SIZE];
                for (DWORD i = 0; i < len; i++) local[i] = shm[12 + i];
                run_block(local, len);
                last_seq = seq;
            }
        }
        Sleep(50);      /* the GSC poller re-checks gf_cmd_go every 0.25s, so 50ms here is ample */
    }
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(h);
        CreateThread(NULL, 0, poll_thread, NULL, 0, NULL);
    }
    return TRUE;
}
