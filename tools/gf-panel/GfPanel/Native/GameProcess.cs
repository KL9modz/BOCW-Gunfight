using System.IO;
using System.Runtime.InteropServices;

namespace GfPanel.Native;

/// <summary>Finding the game: pid, exe path, install folder, module range. Toolhelp only - no
/// subprocess, no handle to the game beyond a QUERY_LIMITED one for the image path.</summary>
public static class GameProcess
{
    public const string ExeName = "BlackOpsColdWar.exe";

    public static int FindPid(string name = ExeName)
    {
        var snap = Win32.CreateToolhelp32Snapshot(Win32.TH32CS_SNAPPROCESS, 0);
        if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return 0;
        try
        {
            var e = new Win32.PROCESSENTRY32W { dwSize = (uint)Marshal.SizeOf<Win32.PROCESSENTRY32W>() };
            if (!Win32.Process32FirstW(snap, ref e)) return 0;
            do
            {
                if (string.Equals(e.szExeFile, name, StringComparison.OrdinalIgnoreCase)) return (int)e.th32ProcessID;
            } while (Win32.Process32NextW(snap, ref e));
            return 0;
        }
        finally { Win32.CloseHandle(snap); }
    }

    public static string? ExePath(int pid)
    {
        if (pid <= 0) return null;
        var h = Win32.OpenProcess(Win32.PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
        if (h == IntPtr.Zero) return null;
        try
        {
            var buf = new char[1024];
            uint size = (uint)buf.Length;
            return Win32.QueryFullProcessImageNameW(h, 0, buf, ref size) ? new string(buf, 0, (int)size) : null;
        }
        finally { Win32.CloseHandle(h); }
    }

    /// <summary>The install folder: from the running process, else the usual Battle.net / Steam spots.</summary>
    public static string? FindGameDir(int pid)
    {
        var exe = ExePath(pid);
        if (exe != null) return Path.GetDirectoryName(exe);
        foreach (var p in new[]
                 {
                     @"D:\Battle.net\Call of Duty Black Ops Cold War",
                     @"C:\Program Files\Call of Duty Black Ops Cold War",
                     @"C:\Program Files (x86)\Battle.net\Call of Duty Black Ops Cold War",
                     @"C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops Cold War",
                 })
            if (File.Exists(Path.Combine(p, ExeName))) return p;
        return null;
    }

    /// <summary>(base, size) of a module in the game, or null. The exe's own range ranks the
    /// script string pool region first in the sweep (it is a private RW region INSIDE the image range).</summary>
    public static (long Base, long Size)? ModuleRange(int pid, string name = ExeName)
    {
        var snap = Win32.CreateToolhelp32Snapshot(Win32.TH32CS_SNAPMODULE | Win32.TH32CS_SNAPMODULE32, (uint)pid);
        if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return null;
        try
        {
            var e = new Win32.MODULEENTRY32W { dwSize = (uint)Marshal.SizeOf<Win32.MODULEENTRY32W>() };
            if (!Win32.Module32FirstW(snap, ref e)) return null;
            do
            {
                if (string.Equals(e.szModule, name, StringComparison.OrdinalIgnoreCase))
                    return (e.modBaseAddr.ToInt64(), e.modBaseSize);
            } while (Win32.Module32NextW(snap, ref e));
            return null;
        }
        finally { Win32.CloseHandle(snap); }
    }

    /// <summary>cwpatch present = the discord slot module is the small 0x9000-byte image (stock SDK is 0x3b8000).</summary>
    public static (bool Loaded, uint Size) DiscordModule(int pid)
    {
        var r = ModuleRange(pid, "discord_game_sdk.dll");
        return r == null ? (false, 0u) : (true, (uint)r.Value.Size);
    }
}
