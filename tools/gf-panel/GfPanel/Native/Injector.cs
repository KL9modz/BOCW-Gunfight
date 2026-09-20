using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace GfPanel.Native;

/// <summary>The launch steps the Inject tab drives (gf_native.py, ported): LoadLibrary a prebuilt DLL
/// into the game, put cwpatch in the discord slot (hash-checked), and run `acts injectcw` for the
/// menu payload. The HUMAN clicks these; nothing here is hidden or spoofed.</summary>
public static class Injector
{
    // cwpatch identity - docs/notes/unlock-dlls.md (the full hash)
    public const string CwpatchSha256 = "f72249204ff2cc03620a66e2bda8eb8308023e3a16754f5bfada611e646e84d1";
    public const int CwpatchSize = 13824;
    public const uint CwpatchImageSize = 0x9000;

    public const string MenuHook = @"scripts\mp_common\bb.gsc";
    public const string MenuReplace = @"scripts\core_common\clientids_shared.gsc";

    public static string? Sha256(string path)
    {
        if (!File.Exists(path)) return null;
        using var f = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(f)).ToLowerInvariant();
    }

    /// <summary>LoadLibraryA a DLL into pid via a remote thread. Returns a human-readable status line.</summary>
    public static string InjectDll(int pid, string dllPath)
    {
        dllPath = Path.GetFullPath(dllPath);
        if (!File.Exists(dllPath)) return "DLL not found: " + dllPath;
        var h = Win32.OpenProcess(Win32.PROCESS_ALL_ACCESS, false, (uint)pid);
        if (h == IntPtr.Zero) return $"OpenProcess failed (err {Marshal.GetLastWin32Error()}) - run the panel elevated";
        try
        {
            var buf = Encoding.ASCII.GetBytes(dllPath + "\0");
            var remote = Win32.VirtualAllocEx(h, IntPtr.Zero, (IntPtr)buf.Length, Win32.MEM_COMMIT | Win32.MEM_RESERVE, Win32.PAGE_READWRITE);
            if (remote == IntPtr.Zero) return "VirtualAllocEx failed";
            Win32.WriteProcessMemory(h, remote, buf, (IntPtr)buf.Length, out _);
            var loadlib = Win32.GetProcAddress(Win32.GetModuleHandleA("kernel32.dll"), "LoadLibraryA");
            if (loadlib == IntPtr.Zero) return "could not resolve LoadLibraryA";
            var th = Win32.CreateRemoteThread(h, IntPtr.Zero, IntPtr.Zero, loadlib, remote, 0, IntPtr.Zero);
            if (th == IntPtr.Zero) return $"CreateRemoteThread failed (err {Marshal.GetLastWin32Error()})";
            Win32.WaitForSingleObject(th, 5000);
            Win32.GetExitCodeThread(th, out var code);
            Win32.CloseHandle(th);
            return code == 0
                ? $"LoadLibrary returned 0 for {Path.GetFileName(dllPath)} (already loaded, or DllMain failed)"
                : $"injected {Path.GetFileName(dllPath)} into pid {pid} (module base 0x{code:X})";
        }
        finally { Win32.CloseHandle(h); }
    }

    /// <summary>Put cwpatch in &lt;gameDir&gt;\discord_game_sdk.dll (backing the stock SDK up once). Refuses a
    /// source that fails the recorded hash. The slot is read at game start: a fresh install takes effect next launch.</summary>
    public static string InstallCwpatch(string src, string? gameDir, bool gameRunning)
    {
        if (Sha256(src) != CwpatchSha256) return $"cwpatch source fails its hash check ({src}) - refusing to install";
        if (string.IsNullOrEmpty(gameDir) || !Directory.Exists(gameDir)) return "game folder not found - can't install cwpatch";
        var slot = Path.Combine(gameDir, "discord_game_sdk.dll");
        if (Sha256(slot) == CwpatchSha256) return "cwpatch already in place";
        if (gameRunning) return "game is running with the stock DLL loaded - close it, then install cwpatch";
        var backup = Path.Combine(gameDir, "discord_game_sdk.dll.stock");
        try
        {
            if (File.Exists(slot) && !File.Exists(backup)) File.Copy(slot, backup);
            File.Copy(src, slot, true);
        }
        catch (UnauthorizedAccessException) { return "can't write the game folder - run elevated (and close the game first)"; }
        catch (Exception e) { return "cwpatch copy failed: " + e.Message; }
        return Sha256(slot) == CwpatchSha256 ? "cwpatch installed - it loads on the NEXT game launch" : "cwpatch copy landed but the hash doesn't match - check the game folder";
    }

    /// <summary>acts injectcw &lt;payload&gt; &lt;hook&gt; &lt;replace&gt;, off-thread. Returns (ok, output).</summary>
    public static async Task<(bool Ok, string Output)> ActsInjectAsync(string acts, string payload, CancellationToken ct = default)
    {
        if (!File.Exists(acts)) return (false, "acts.exe not found: " + acts);
        if (!File.Exists(payload)) return (false, "payload not found: " + payload);
        var psi = new ProcessStartInfo(acts)
        {
            WorkingDirectory = Path.GetDirectoryName(acts)!,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        psi.ArgumentList.Add("injectcw");
        psi.ArgumentList.Add(payload);
        psi.ArgumentList.Add(MenuHook);
        psi.ArgumentList.Add(MenuReplace);
        try
        {
            using var p = Process.Start(psi)!;
            var so = p.StandardOutput.ReadToEndAsync(ct);
            var se = p.StandardError.ReadToEndAsync(ct);
            await p.WaitForExitAsync(ct);
            var output = ((await so) + (await se)).Trim();
            return (p.ExitCode == 0 && !output.Contains("find target script", StringComparison.OrdinalIgnoreCase), output);
        }
        catch (Exception e) { return (false, "acts failed to start: " + e.Message); }
    }
}
