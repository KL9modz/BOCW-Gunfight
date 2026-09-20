/* gf_luihook.c - inject a custom Lua chunk into Cold War's LUI VM by hooking the engine's Lua loader.
 *
 * WHY: GSC/CSC cannot modify a LUI menu (measured - docs/notes/pause-menu.md); only Lua running in the
 * LUI VM can. The proven way in (ate47's BO4 shield-plugin) is a DLL that hooks the Lua loader and runs
 * a custom chunk in the live VM. This is the Cold War (T9, LuaJIT 2.1) port. Full RE: docs/notes/lui-dll-re.md.
 *
 * WHAT IT DOES:
 *   1. Sig-scans the running BlackOpsColdWar.exe for lua_loadx (the LuaJIT bytecode/source loader).
 *   2. Inline-hooks lua_loadx. The hook runs on the VM/main thread (LuaJIT is NOT thread-safe, so we must
 *      NOT touch the VM from a worker thread - the loader hook is our main-thread execution point) and:
 *        - captures the lua_State* (rcx / arg1) of whatever VM is loading chunks,
 *        - counts chunk-loads (a timing proxy: StartMenu_Main is not defined until the UI chunks load),
 *        - once enough chunks have loaded, calls the REAL lua_loadx on our embedded gf_loadtest.luac
 *          bytecode and then lua_pcall to run it.
 *   3. gf_loadtest wraps LUI.createMenu["#StartMenu_Main"] and adds a bright "GUNFIGHT MENU LOADED" label.
 *      If that label shows when ESC opens, a custom chunk loaded and ran in the LUI VM == the integrated
 *      pause-menu-tab route is open. The chunk is defensive (no-ops until the UI is up) and idempotent
 *      (guards on LUI.gf_loadtest_done), so firing it repeatedly across a timing window is safe.
 *
 * DIVISION OF LABOUR (project guard, docs/notes/lui-dll-re.md): the agent wrote this SOURCE + the custom
 * chunk + the RE; klaze BUILDS (zig), INJECTS, and iterates the two empirical pieces flagged below
 * (GF_PCALL_RVA and GF_TRIGGER_N). The agent does not build or inject DLLs.
 *
 * ---------------------------------------------------------------------------------------------------
 * TWO THINGS TO PIN LIVE (everything else is resolved by sig and confirmed against the read-only dump):
 *
 *   (A) GF_PCALL_RVA - lua_pcall. Could NOT be pinned from the read-only exe dump (LuaJIT has many
 *       similar internal funcs; the public lua_pcall did not surface by shape/caller-count alone). It is
 *       trivial to pin live with a debugger (see docs/notes/lui-dll-re.md "Pinning lua_pcall"). Until it
 *       is set, the DLL still proves state-capture + load (watch the DebugView log) but cannot run the
 *       chunk. Set GF_PCALL_RVA to the resolved RVA, OR fill GF_PCALL_SIG with a prologue sig.
 *
 *   (B) GF_TRIGGER_N - the load-count at which the UI is up enough that StartMenu_Main exists. The chunk
 *       is idempotent + defensive, so this is forgiving: start at the default, watch the log line
 *       "load#=N", and if the label never appears, lower/raise it. The DLL retries every load in
 *       [GF_TRIGGER_N, GF_TRIGGER_N+GF_MAX_ATTEMPTS], so an approximate value works.
 * ---------------------------------------------------------------------------------------------------
 *
 * Debug output: OutputDebugStringA, one line per event (view with Sysinternals DebugView). The REAL
 * result is visual (the ESC-menu label), matching the project's one-line debug-feed convention.
 *
 * Build / inject: see src/gf_luihook/README.md. klaze runs both.
 */

#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "gf_bytecode.h"   /* static const unsigned char GF_BYTECODE[]; regenerate after editing the .lua */

/* ============================ CONFIG - the two live-tuned knobs are marked ============================ */

#define GF_TRIGGER_N     40     /* (B) begin trying after this many chunk-loads. Tune live. */
#define GF_MAX_ATTEMPTS  400    /* keep retrying for this many loads past the trigger (chunk is idempotent) */
#define GF_CHUNKNAME     "=gf"  /* chunk name for error messages (T9 flag-0x18 bytecode carries no name) */

/* (A) lua_pcall - PIN ONE OF THESE LIVE (see header). RVA is relative to the BlackOpsColdWar.exe base. */
#define GF_PCALL_RVA     0      /* e.g. 0x0d1XXXXX once verified; 0 => try GF_PCALL_SIG instead */
#define GF_PCALL_SIG     ""     /* optional: a unique prologue sig for lua_pcall, "48 89 .. .." form */

/* lua_loadx - resolved by sig. This is cw.json's proven relative call-site sig (data/games/cw.json,
 * scans/lua/lua_loadx: Relative, offset 1). It matches a CALL to lua_loadx; we resolve the E8 target. */
#define GF_LOADX_SIG "E8 ?? ?? ?? ?? 41 B8 ?? ?? ?? ?? 8B D0 48 8B CB 48 8B 7C 24 ?? 48 8B 74 24"

/* ==================================================================================================== */

/* Log to BOTH OutputDebugString and a file, opening+flushing+closing per line so the last line
 * survives a crash (crash-proof post-mortem, no external monitor needed). */
#define GF_LOGFILE "C:\\bocw\\payloads\\gf_luihook.log"
static void logsink(const char *s) {
    OutputDebugStringA(s);
    FILE *f = fopen(GF_LOGFILE, "a");
    if (f) { fputs(s, f); fclose(f); }
}
static void logln(const char *s) { logsink(s); }
static void logf1(const char *fmt, ...) {
    char buf[256]; va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf) - 1, fmt, ap); va_end(ap);
    buf[sizeof(buf) - 1] = 0; logsink(buf);
}

/* -------- module range -------- */
static unsigned char *g_base = NULL;
static size_t g_size = 0;

static int module_range(void) {
    HMODULE h = GetModuleHandleA("BlackOpsColdWar.exe");
    if (!h) h = GetModuleHandleA(NULL);
    if (!h) return 0;
    g_base = (unsigned char *)h;
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)h;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(g_base + dos->e_lfanew);
    g_size = nt->OptionalHeader.SizeOfImage;
    return 1;
}

/* -------- IDA-style signature scan ("E8 ?? 90 ...", ?? = wildcard) -------- */
static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
/* parse "xx ?? xx" -> bytes[] / mask[] (mask 1 = must match). returns count, or -1 on error. */
static int sig_parse(const char *sig, unsigned char *bytes, unsigned char *mask, int cap) {
    int n = 0;
    for (const char *p = sig; *p && n < cap; ) {
        while (*p == ' ') p++;
        if (!*p) break;
        if (p[0] == '?') { bytes[n] = 0; mask[n] = 0; n++; p++; if (*p == '?') p++; continue; }
        int hi = hexval(p[0]), lo = hexval(p[1]);
        if (hi < 0 || lo < 0) return -1;
        bytes[n] = (unsigned char)((hi << 4) | lo); mask[n] = 1; n++; p += 2;
    }
    return n;
}
static unsigned char *sig_scan(const char *sig) {
    unsigned char b[64], m[64];
    int n = sig_parse(sig, b, m, 64);
    if (n <= 0) return NULL;
    /* Walk the actual committed memory map with VirtualQuery and scan ONLY pages that are genuinely
     * readable+executable (PAGE_EXECUTE_READ/READWRITE/WRITECOPY = 0x20/0x40/0x80). Cold War is
     * Arxan-protected: its executable sections contain EXECUTE-ONLY (0x10) and uncommitted pages that
     * fault on read. This never touches those, so it cannot access-violate. The call-site we resolve
     * lives in ordinary readable .text, so it is still found. */
    unsigned char *module_end = g_base + g_size;
    MEMORY_BASIC_INFORMATION mbi;
    unsigned char *p = g_base;
    while (p < module_end) {
        if (!VirtualQuery(p, &mbi, sizeof(mbi))) break;
        unsigned char *region = (unsigned char *)mbi.BaseAddress;
        unsigned char *rend = region + mbi.RegionSize;
        int rx = (mbi.State == MEM_COMMIT) && (mbi.Protect & 0xE0) && !(mbi.Protect & PAGE_GUARD);
        if (rx) {
            unsigned char *s = region < g_base ? g_base : region;
            unsigned char *e = rend > module_end ? module_end : rend;
            if ((size_t)(e - s) >= (size_t)n)
                for (unsigned char *q = s; q <= e - n; q++) {
                    int i = 0;
                    for (; i < n; i++) if (m[i] && q[i] != b[i]) break;
                    if (i == n) return q;
                }
        }
        if (rend <= p) break;   /* no forward progress -> stop */
        p = rend;
    }
    return NULL;
}
/* resolve a relative (E8/E9) call/jmp target: rel32 at match+off. */
static unsigned char *rel_target(unsigned char *match, int off) {
    if (!match) return NULL;
    int32_t rel = *(int32_t *)(match + off);
    return match + off + 4 + rel;
}

/* -------- the functions we call -------- */
typedef int (*loadx_t)(void *L, void *reader, void *ud, const char *chunkname, const char *mode);
typedef int (*pcall_t)(void *L, int nargs, int nresults, int errfunc);

static loadx_t o_loadx = NULL;   /* trampoline -> REAL lua_loadx (set by install_hook) */
static pcall_t p_pcall = NULL;   /* lua_pcall (klaze-pinned) */

static void  *g_L = NULL;
static volatile LONG g_count = 0;
static volatile LONG g_done  = 0;
static DWORD  g_guard_tid = 0;   /* re-entrancy guard: our own nested load must pass straight through */
static unsigned char *g_loadx = NULL;      /* patched lua_loadx entry (for self-unhook) */
static unsigned char  g_orig[16];          /* its original 16 bytes */

/* restore lua_loadx's original bytes (remove our JMP patch) */
static void unhook_self(void) {
    if (!g_loadx) return;
    DWORD oldp;
    if (VirtualProtect(g_loadx, 16, PAGE_EXECUTE_READWRITE, &oldp)) {
        memcpy(g_loadx, g_orig, 16);
        VirtualProtect(g_loadx, 16, oldp, &oldp);
        FlushInstructionCache(GetCurrentProcess(), g_loadx, 16);
    }
}

/* -------- lua_Reader that hands our whole buffer once, then EOF -------- */
typedef struct { const unsigned char *p; size_t n; int done; } gf_rd;
static const char *gf_reader(void *L, void *ud, size_t *sz) {
    (void)L; gf_rd *r = (gf_rd *)ud;
    if (r->done) { *sz = 0; return NULL; }
    r->done = 1; *sz = r->n; return (const char *)r->p;
}

/* -------- run our chunk in state L (called on the VM thread, from the hook) --------
 * Only ever loads when p_pcall is set: lua_loadx PUSHES the compiled chunk onto L's stack, and only
 * lua_pcall pops+runs it. Without pcall we would leak a stack slot every fire (up to GF_MAX_ATTEMPTS)
 * and eventually overflow the VM stack. So with pcall unset this is a no-op - the hook still proves
 * sig/capture/timing without touching the VM stack at all. */
static void gf_run(void *L) {
    if (!p_pcall) return;
    gf_rd rd = { GF_BYTECODE, sizeof(GF_BYTECODE), 0 };
    g_guard_tid = GetCurrentThreadId();               /* our own load must not re-trigger the hook logic */
    int lr = o_loadx(L, gf_reader, &rd, GF_CHUNKNAME, "b");   /* mode "b" = precompiled bytecode */
    g_guard_tid = 0;
    if (lr != 0) { logf1("[gf_luihook] loadx FAILED rc=%d (bytecode/state bad)\n", lr); return; }
    int pr = p_pcall(L, 0, 0, 0);                      /* run the chunk: 0 args, 0 results, no errfunc; pops it */
    logf1("[gf_luihook] pcall rc=%d (0=ran ok) - open ESC, look for GUNFIGHT MENU LOADED\n", pr);
}

/* -------- our hook: replaces lua_loadx -------- */
static int hk_loadx(void *L, void *reader, void *ud, const char *chunkname, const char *mode) {
    if (g_guard_tid == GetCurrentThreadId())          /* our own nested load - pass through untouched */
        return o_loadx(L, reader, ud, chunkname, mode);

    LONG pre = g_count;                                /* DIAG: trace the first real call to localise a crash */
    if (pre == 0) logf1("[gf_luihook] hk#0 enter L=%p rd=%p ud=%p nm=%p md=%p\n", L, reader, ud, chunkname, (void *)mode);
    int ret = o_loadx(L, reader, ud, chunkname, mode); /* let the game's chunk load first (via the trampoline) */
    if (pre == 0) {                                    /* one clean call validates the trampoline; unhook immediately to preserve the game */
        logf1("[gf_luihook] hk#0 ret=%d (trampoline OK) - self-unhooking\n", ret);
        unhook_self();
        logln("[gf_luihook] self-unhooked - if the game now survives, the inline PATCH was the crash (Arxan integrity) => switch to VEH; if it crashed before this line, the trampoline is the bug\n");
    }
    g_L = L;
    LONG c = InterlockedIncrement(&g_count);

    if (!g_done && c >= GF_TRIGGER_N && c < (GF_TRIGGER_N + GF_MAX_ATTEMPTS)) {
        if (c == GF_TRIGGER_N)
            logf1("[gf_luihook] trigger at load#=%ld L=%p pcall=%s\n", c, L,
                  p_pcall ? "set - injecting our chunk" : "NOT set - hook+capture proven; set GF_PCALL_RVA to inject");
        gf_run(L);                                     /* no-op unless pcall set; idempotent + defensive otherwise */
        /* g_done stays 0 so we keep retrying until the UI is up; the chunk itself guards against double-wrap.
         * If you add a Lua->C success signal later, set InterlockedExchange(&g_done,1) here. */
    }
    return ret;
}

/* -------- self-contained inline hook of lua_loadx --------
 * The DLL is built as a single self-contained .c (project style: no MinHook/other lib). We only ever hook
 * ONE function whose prologue we know from the dump (VERIFIED against the raw bytes - note the redundant
 * REX 0x40 prefix on push rbx that a disassembler folds into the mnemonic):
 *
 *   d186960  40 53                 push rbx                    (2 bytes)
 *   d186962  48 81 EC F0 00 00 00  sub  rsp, 0xF0              (7 bytes)
 *   d186969  48 8B 05 D8 97 B5 01  mov  rax, [rip+0x1b597d8]   (7 bytes) <-- one RIP-relative insn to fix
 *
 * = 16 bytes, 3 whole instructions, a clean boundary >= the 14 bytes a JMP[rip] patch needs.
 *
 * The `mov rax,[rip+disp32]` is RIP-relative, so it CANNOT be copied verbatim to a trampoline at a
 * different address. Relocating its disp32 fails when the trampoline is >2GB from loadx (VirtualAlloc
 * puts it far from the game's high 0x7ff6.. base) - the int32 disp overflows and the mov reads a wild
 * address => crash on the next lua_loadx call. So instead we emit that ONE instruction as
 * position-independent in the trampoline: `movabs rax, <absolute cookie addr>; mov rax,[rax]`. The other
 * two prologue insns (push rbx; sub rsp,imm32) are position-independent and copy verbatim. If the
 * prologue does NOT match (game updated), we bail LOUDLY rather than corrupt the process.
 *
 * Trampoline layout (36 bytes):
 *   +0  40 53                    push rbx                       (verbatim, 2)
 *   +2  48 81 EC F0 00 00 00     sub  rsp, 0xF0                 (verbatim, 7)
 *   +9  48 B8 <abs64>            movabs rax, cookie_addr        (PIC replacement for the rip-rel mov, 10)
 *   +19 48 8B 00                 mov  rax, [rax]                (3)
 *   +22 FF 25 00 00 00 00 <q>    jmp  [rip] -> loadx+16         (14)
 */
static unsigned char *install_hook(unsigned char *loadx, void *hook) {
    /* 1) verify the known prologue (raw bytes, incl. the 0x40 REX prefix) */
    if (!(loadx[0] == 0x40 && loadx[1] == 0x53 &&                        /* push rbx */
          loadx[2] == 0x48 && loadx[3] == 0x81 && loadx[4] == 0xEC &&    /* sub rsp, 0xF0 */
          loadx[9] == 0x48 && loadx[10] == 0x8B && loadx[11] == 0x05)) { /* mov rax,[rip+disp32] */
        logf1("[gf_luihook] lua_loadx prologue mismatch (%02x %02x .. %02x %02x %02x) - NOT hooking\n",
              loadx[0], loadx[1], loadx[9], loadx[10], loadx[11]);
        return NULL;
    }
    const int STOLEN = 16;

    /* absolute address the stolen `mov rax,[rip+disp]` (at loadx+9, next insn at loadx+16) targets */
    int32_t disp = *(int32_t *)(loadx + 12);
    uint64_t cookie_addr = (uint64_t)(loadx + 16) + (int64_t)disp;

    /* 2) build the trampoline. RWX. */
    unsigned char *tr = (unsigned char *)VirtualAlloc(NULL, 128, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tr) { logln("[gf_luihook] VirtualAlloc(trampoline) failed\n"); return NULL; }
    int o = 0;
    memcpy(tr + o, loadx, 9); o += 9;                                    /* push rbx ; sub rsp,0xF0 (verbatim) */
    tr[o++] = 0x48; tr[o++] = 0xB8; *(uint64_t *)(tr + o) = cookie_addr; o += 8;  /* movabs rax, cookie_addr */
    tr[o++] = 0x48; tr[o++] = 0x8B; tr[o++] = 0x00;                      /* mov rax, [rax] */
    tr[o++] = 0xFF; tr[o++] = 0x25; *(int32_t *)(tr + o) = 0; o += 4;    /* jmp [rip+0] */
    *(uint64_t *)(tr + o) = (uint64_t)(loadx + STOLEN); o += 8;          /*   -> loadx+16 */

    /* 3) patch loadx: JMP [rip+0] ; qword hook  (14 bytes) then NOP the leftover 2 */
    memcpy(g_orig, loadx, STOLEN); g_loadx = loadx;     /* save originals for unhook_self() */
    DWORD oldp;
    if (!VirtualProtect(loadx, STOLEN, PAGE_EXECUTE_READWRITE, &oldp)) {
        logln("[gf_luihook] VirtualProtect(loadx) failed\n"); return NULL;
    }
    loadx[0] = 0xFF; loadx[1] = 0x25;
    *(int32_t *)(loadx + 2) = 0;
    *(uint64_t *)(loadx + 6) = (uint64_t)hook;
    loadx[14] = 0x90; loadx[15] = 0x90;                 /* NOP the leftover 2 bytes */
    VirtualProtect(loadx, STOLEN, oldp, &oldp);
    FlushInstructionCache(GetCurrentProcess(), loadx, STOLEN);
    logf1("[gf_luihook] trampoline @ %p, cookie src %p\n", (void *)tr, (void *)cookie_addr);
    return tr;
}

/* -------- worker: resolve + install once the module is up -------- */
static DWORD WINAPI init_thread(LPVOID unused) {
    (void)unused;
    for (int i = 0; i < 200 && !module_range(); i++) Sleep(50);
    if (!g_base) { logln("[gf_luihook] module not found\n"); return 1; }
    logf1("[gf_luihook] base=%p size=%#zx\n", (void *)g_base, g_size);

    unsigned char *loadx = rel_target(sig_scan(GF_LOADX_SIG), 1);
    if (!loadx) { logln("[gf_luihook] lua_loadx sig NOT found (build changed?)\n"); return 1; }
    logf1("[gf_luihook] lua_loadx = %p (rva %#zx)\n", (void *)loadx, (size_t)(loadx - g_base));

    /* lua_pcall (klaze-pinned): RVA first, then optional sig */
    if (GF_PCALL_RVA) p_pcall = (pcall_t)(g_base + GF_PCALL_RVA);
    else if (GF_PCALL_SIG[0]) { unsigned char *pc = sig_scan(GF_PCALL_SIG); if (pc) p_pcall = (pcall_t)pc; }
    if (p_pcall) logf1("[gf_luihook] lua_pcall = %p (rva %#zx)\n", (void *)p_pcall, (size_t)((unsigned char *)p_pcall - g_base));
    else         logln("[gf_luihook] lua_pcall NOT set - will capture+load only (see README 'Pinning lua_pcall')\n");

    o_loadx = (loadx_t)install_hook(loadx, (void *)hk_loadx);
    if (!o_loadx) { logln("[gf_luihook] hook install failed\n"); return 1; }
    logln("[gf_luihook] hook installed - waiting for the LUI VM to load chunks\n");
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(h);
        CreateThread(NULL, 0, init_thread, NULL, 0, NULL);
    }
    return TRUE;
}
