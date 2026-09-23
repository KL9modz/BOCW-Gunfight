using System.Runtime.InteropServices;

namespace GfPanel.Native;

/// <summary>The user32 surface the overlay uses (ViewModels/OverlayVM.cs): one registered hotkey, the
/// panel's own window placement, and ordinary window-manager calls on the game's top-level window -
/// where it is, whether it is minimised, and handing it the focus back. The same calls the taskbar and
/// Alt+Tab make. Nothing here opens the game process, reads its memory or puts anything inside it.</summary>
internal static class User32
{
    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_NOREPEAT = 0x4000;
    public const int ERROR_HOTKEY_ALREADY_REGISTERED = 1409;

    public const uint GW_OWNER = 4;
    public const uint MONITOR_DEFAULTTONEAREST = 2;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;

    public const uint SW_SHOWMINIMIZED = 2;
    public const uint SW_SHOWMAXIMIZED = 3;
    public const uint SW_SHOWNOACTIVATE = 4;
    public const uint SW_SHOWMINNOACTIVE = 7;
    public const int SW_RESTORE = 9;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left, Top, Right, Bottom;
        public readonly int Width => Right - Left;
        public readonly int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public uint cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT
    {
        public uint length;
        public uint flags;
        public uint showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW")] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO mi);

    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
}
