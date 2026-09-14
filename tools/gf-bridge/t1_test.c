/* t1_test.c - THE decisive test for the in-context bridge (docs/notes/in-context-bridge.md, T1).
 *
 * Question: does an in-process console `set <dvar> <value>` reach GSC getdvarint()?
 * If yes, the whole bridge is trivial (just run `set gf_cmd_* ...` lines). If no, we need
 * the GSC-store setter the setdvar builtin uses.
 *
 * What it does: press F8 in-game -> runs `set gf_hint_lines 12` (F9 -> `set gf_hint_lines 6`)
 * using cwpatch's EXACT mechanism (overwrite the game's command-string blob, call the engine
 * command executor, restore). Then open the in-game menu (RMB+V) -> Display: the green `*`
 * marker is ABSENT by default (gf_hint_lines is not registered until set - the menu's
 * dvars_register pre-register was disabled 2026-09-13, dvar-pool-crash); if a "*" now
 * appears on "Hint rows 12", getdvarint read our write -> console set reaches GSC. The marker is the
 * right readout because menu_item_line() calls getdvarint(group) on EVERY paint (instant),
 * and gf_hint_lines is consumed only by the never-run HINT layout (region 4) - no side
 * effect in the default layout. (The first draft used `set gf_menu_lines 7`: that dvar is
 * read ONCE per menu_think() start, i.e. only at the next round, and the lower-left feed
 * caps at ~4 lines anyway, so a successful set would have LOOKED like "no change".)
 * Run the test BOTH in the pregame lobby AND in an active match (the match case is the one
 * that matters - a remote-thread `set` wedged mid-match; this runs in-process on our own
 * thread, which is the thing we're testing). Two keys so the two presses are told apart:
 * F9 in the lobby (marker on 6 once the match is up), then F8 in the match (marker on 12).
 *
 * Why this is safe-ish: it is the identical operation cwpatch performs for F4/F6/F7, which
 * return cleanly. If F8 instead hangs the game mid-match, THAT IS THE RESULT (it means even
 * in-process `set` contends the dvar lock and the bridge must run from a main-thread hook,
 * not a worker thread) - note it and relaunch.
 *
 * Build (64-bit DLL), on the dev box with zig cc (already installed, see unlock-dlls.md):
 *     zig cc -target x86_64-windows-gnu -shared -O2 -o gf_t1.dll t1_test.c
 *   or mingw:
 *     x86_64-w64-mingw32-gcc -shared -O2 -o gf_t1.dll t1_test.c
 *
 * Load: inject gf_t1.dll the way you load a DLL (manual-map / LoadLibrary inject), or chain
 * it in tools/cw-loader-shim. cwpatch MUST be loaded (ensure-cwpatch) - this reads cwpatch's
 * already-resolved pointers out of its .data, so it needs no signature scan of its own.
 *
 * GUARD: klaze builds/loads/runs this. The agent wrote the source. Nothing hidden/spoofed -
 * it calls the game's own command executor exactly as cwpatch does.
 */

#include <windows.h>

/* cwpatch (discord_game_sdk.dll, the 13,824-byte build) stores its signature-resolved
 * pointers at these RVAs in its own .data - read statically from the DLL 2026-09-12 and
 * cross-checked live against a fresh signature scan (all 7 agreed). */
#define CW_EXECUTOR_RVA 0x5638  /* engine command executor; takes no args, reads the blob */
#define CW_CMDSLOT_RVA  0x5640  /* resolved address of the "hostmigration_start\n" command string */
#define RESTORE_LEN     48      /* cwpatch saves/restores this many bytes around the slot */

/* Run one console command in-process, cwpatch's way. */
static void run_console_command(const char *cmd)
{
    HMODULE cw = GetModuleHandleA("discord_game_sdk.dll");
    if (!cw) { MessageBeep(MB_ICONHAND); return; }          /* cwpatch not loaded */

    unsigned char *base = (unsigned char *)cw;
    void (*executor)(void) = *(void (**)(void))(base + CW_EXECUTOR_RVA);
    unsigned char *slot    = *(unsigned char **)(base + CW_CMDSLOT_RVA);
    if (!executor || !slot) { MessageBeep(MB_ICONHAND); return; }  /* not resolved yet */

    HANDLE self = GetCurrentProcess();
    SIZE_T n;
    unsigned char saved[RESTORE_LEN];
    if (!ReadProcessMemory(self, slot, saved, RESTORE_LEN, &n)) return;

    char buf[256];
    size_t len = 0;
    while (cmd[len] && len < sizeof(buf) - 2) { buf[len] = cmd[len]; len++; }
    buf[len++] = '\n';                                       /* executor reads up to the newline */

    /* WriteProcessMemory on our own process writes through page protection - cwpatch's trick,
     * so we need no VirtualProtect. */
    WriteProcessMemory(self, slot, buf, len, &n);
    executor();                                             /* no args; reads the blob we just wrote */
    WriteProcessMemory(self, slot, saved, RESTORE_LEN, &n); /* restore */
}

static DWORD WINAPI poll_thread(LPVOID unused)
{
    (void)unused;
    for (;;) {
        if (GetAsyncKeyState(VK_F8) & 1)                    /* low bit = pressed since last poll */
            run_console_command("set gf_hint_lines 12");
        if (GetAsyncKeyState(VK_F9) & 1)
            run_console_command("set gf_hint_lines 6");
        Sleep(30);
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
