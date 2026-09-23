using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using GfPanel.Native;
using GfPanel.Services;

namespace GfPanel.ViewModels;

public sealed record OverlayChoice(string Key, string Label);

/// <summary>The overlay: THIS window laid over the game on a hotkey, and put back where it was afterwards.
/// Nothing is drawn inside the game - no DLL, no hook, no transparent click-through layer. It is the
/// ordinary opaque panel, borderless and topmost only while it is up, and it hands the game its focus back
/// when it goes. It stays up only while it has the focus: another app taking it, or Windows refusing it in
/// the first place, puts it back. Needs the game in Fullscreen Borderless: exclusive Fullscreen minimises
/// when anything else takes focus (VerifyShown says so). docs/notes/gf-panel.md §6.</summary>
public sealed class OverlayVM : ObservableObject
{
    private const int HotkeyId = 0x4746;   // "GF"

    // Not offered: F4 / F6 / F7 (cwpatch's lobbylaunchgame / fast_restart / full_restart) and F12 (reserved
    // for debuggers, RegisterHotKey's own docs). Whether BOCW binds any of these by default is unchecked;
    // pick one the host does not play with.
    private static readonly OverlayChoice[] Keys =
    {
        new("Insert", "Insert"), new("Home", "Home"), new("End", "End"), new("PageUp", "Page Up"), new("PageDown", "Page Down"),
        new("Pause", "Pause / Break"), new("Scroll", "Scroll Lock"), new("F8", "F8"), new("F9", "F9"), new("F10", "F10"), new("F11", "F11"),
        new("Ctrl+Insert", "Ctrl + Insert"),
    };

    private static readonly OverlayChoice[] Layouts =
    {
        new("right", "Right side - game visible on the left"), new("left", "Left side - game visible on the right"),
        new("centre", "Centre"), new("full", "Full screen"),
    };

    private readonly Prefs _prefs;
    private readonly ToastsVM _toasts;
    private readonly Func<int> _gamePid;
    private Window? _w;
    private HwndSourceHook? _hook;           // held here: HwndSource keeps its hooks only weakly
    private IntPtr _hwnd, _game;
    private bool _armed, _active, _remaximize;
    private string _status = "starting…", _statusKind = "off";

    // where the panel was before the overlay took it: Win32 placement (state + normal rect in one) + chrome
    private User32.WINDOWPLACEMENT _placement;
    private WindowStyle _style;
    private ResizeMode _resize;
    private double _minW, _minH;

    public OverlayVM(Prefs prefs, ToastsVM toasts, Func<int> gamePid)
    {
        _prefs = prefs;
        _toasts = toasts;
        _gamePid = gamePid;
    }

    public IReadOnlyList<OverlayChoice> HotkeyChoices => Keys;
    public IReadOnlyList<OverlayChoice> LayoutChoices => Layouts;

    public bool Enabled
    {
        get => _prefs.OverlayEnabled;
        set { if (_prefs.OverlayEnabled == value) return; _prefs.OverlayEnabled = value; _prefs.Save(); OnPropertyChanged(); Arm(); }
    }

    public string Hotkey
    {
        get => _prefs.OverlayHotkey;
        set
        {
            if (string.IsNullOrEmpty(value) || _prefs.OverlayHotkey == value) return;
            _prefs.OverlayHotkey = value; _prefs.Save();
            OnPropertyChanged(); OnPropertyChanged(nameof(KeyLabel)); OnPropertyChanged(nameof(BackLabel));
            Arm();
        }
    }

    public string Layout
    {
        get => _prefs.OverlayLayout;
        set { if (string.IsNullOrEmpty(value) || _prefs.OverlayLayout == value) return; _prefs.OverlayLayout = value; _prefs.Save(); OnPropertyChanged(); if (Active) Place(); }
    }

    public bool Active { get => _active; private set => Set(ref _active, value); }
    public string StatusText { get => _status; private set => Set(ref _status, value); }
    public string StatusKind { get => _statusKind; private set => Set(ref _statusKind, value); }
    public string KeyLabel => Keys.FirstOrDefault(k => k.Key == Hotkey)?.Label ?? Hotkey;
    public string BackLabel => "⤶ Back to game  (" + KeyLabel + " / Esc)";

    public RelayCommand ToggleCmd => new(Toggle);
    public RelayCommand HideCmd => new(() => Exit(focusGame: true));

    // ─────────────────────────────────────────────────────────────────────────
    // hotkey
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>Called once the window has an HWND (SourceInitialized): the hotkey is registered against it.</summary>
    public void Attach(Window w)
    {
        _w = w;
        _hwnd = new WindowInteropHelper(w).Handle;
        _hook = WndProc;
        HwndSource.FromHwnd(_hwnd)?.AddHook(_hook);
        // Another app took the focus (the user clicked the game, Alt+Tabbed, …): put the panel back rather
        // than leave a topmost window sitting over a game that has the input. Our own dialogs do not raise
        // this - they are in the same app.
        Application.Current.Deactivated += OnAppDeactivated;
        w.Activated += (_, _) =>
        {
            if (_remaximize && !Active) { _remaximize = false; w.WindowState = WindowState.Maximized; }
        };
        Arm();
    }

    public void Detach()
    {
        Exit(focusGame: false);
        if (_remaximize && _w != null) { _remaximize = false; _w.WindowState = WindowState.Maximized; }   // closing: the saved state must be the real one
        Application.Current.Deactivated -= OnAppDeactivated;
        if (_armed) { User32.UnregisterHotKey(_hwnd, HotkeyId); _armed = false; }
    }

    private void OnAppDeactivated(object? sender, EventArgs e)
    {
        if (Active) Exit(focusGame: false);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == User32.WM_HOTKEY && wParam.ToInt32() == HotkeyId)
        {
            handled = true;
            // Out of the window procedure before the window is restyled. Windows lets "the process that
            // received the last input event" take the foreground (SetForegroundWindow remarks), and the
            // hotkey is expected to count as that. Not documented in so many words: VerifyShown checks.
            _w?.Dispatcher.BeginInvoke(DispatcherPriority.Input, Toggle);
        }
        return IntPtr.Zero;
    }

    private void Arm()
    {
        if (_hwnd == IntPtr.Zero) return;
        if (_armed) { User32.UnregisterHotKey(_hwnd, HotkeyId); _armed = false; }
        if (!Enabled) { StatusText = "off - the panel stays an ordinary window"; StatusKind = "off"; return; }
        if (!TryParseHotkey(Hotkey, out var mods, out var vk))
        {
            StatusText = $"can't read the key \"{Hotkey}\" - pick one from the list"; StatusKind = "err"; return;
        }
        if (User32.RegisterHotKey(_hwnd, HotkeyId, mods | User32.MOD_NOREPEAT, vk))
        {
            _armed = true;
            StatusText = $"armed - press {KeyLabel} in the game"; StatusKind = "on";
            return;
        }
        var err = Marshal.GetLastWin32Error();
        StatusText = err == User32.ERROR_HOTKEY_ALREADY_REGISTERED
            ? $"{KeyLabel} is already taken by another app - pick another key"
            : $"could not register {KeyLabel} (Windows error {err})";
        StatusKind = "err";
        _toasts.Show("Overlay hotkey: " + StatusText, LogLevel.Err);
    }

    /// <summary>"Insert", "F9", "Ctrl+Insert", "Ctrl+Alt+Home" → RegisterHotKey's modifiers + virtual key.</summary>
    internal static bool TryParseHotkey(string text, out uint mods, out uint vk)
    {
        mods = 0; vk = 0;
        var parts = (text ?? "").Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0) return false;
        for (var i = 0; i < parts.Length - 1; i++)
        {
            switch (parts[i].ToLowerInvariant())
            {
                case "ctrl": case "control": mods |= User32.MOD_CONTROL; break;
                case "alt": mods |= User32.MOD_ALT; break;
                case "shift": mods |= User32.MOD_SHIFT; break;
                default: return false;
            }
        }
        var name = parts[^1];
        if (!char.IsLetter(name[0]) || !Enum.TryParse<Key>(name, true, out var key) || key == Key.None) return false;
        vk = (uint)KeyInterop.VirtualKeyFromKey(key);
        return vk != 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // show / hide
    // ─────────────────────────────────────────────────────────────────────────

    public void Toggle()
    {
        if (Active) Exit(focusGame: true); else Enter();
    }

    private void Enter()
    {
        if (_w == null || _hwnd == IntPtr.Zero || Active) return;
        _game = FindGameWindow(_gamePid());

        _placement = new User32.WINDOWPLACEMENT { length = (uint)Marshal.SizeOf<User32.WINDOWPLACEMENT>() };
        User32.GetWindowPlacement(_hwnd, ref _placement);
        if (_remaximize) { _placement.showCmd = User32.SW_SHOWMAXIMIZED; _remaximize = false; }   // still owed from the last click-away
        _style = _w.WindowStyle; _resize = _w.ResizeMode; _minW = _w.MinWidth; _minH = _w.MinHeight;
        Active = true;

        if (_w.WindowState != WindowState.Normal) _w.WindowState = WindowState.Normal;
        _w.WindowStyle = WindowStyle.None;
        _w.ResizeMode = ResizeMode.NoResize;
        _w.MinWidth = 0; _w.MinHeight = 0;       // a side layout on a small screen is narrower than the normal minimum
        _w.Topmost = true;                       // the game may itself be topmost in borderless; only while we are up
        Place();
        _w.Show();
        _w.Activate();
        User32.SetForegroundWindow(_hwnd);

        if (_game == IntPtr.Zero) _toasts.Show("Game window not found - previewing over this monitor", LogLevel.Info);
        VerifyShown();
    }

    /// <summary>Put the panel back exactly where it was; optionally give the game its focus back.</summary>
    public void Exit(bool focusGame)
    {
        if (_w == null || !Active) return;
        Active = false;                          // first: the focus change below raises Deactivated
        _w.Topmost = false;
        _w.WindowStyle = _style;
        _w.ResizeMode = _resize;
        _w.MinWidth = _minW; _w.MinHeight = _minH;

        // Restore without activating: the game is about to get the focus, or the user already gave it to
        // something else. Maximising always activates, so a maximised panel is re-maximised here only when
        // this process still holds the foreground and hands it straight on; after the user clicked away it
        // comes back normal-sized and re-maximises the next time it is activated.
        var p = _placement;
        var maximised = p.showCmd == User32.SW_SHOWMAXIMIZED;
        p.showCmd = p.showCmd == User32.SW_SHOWMINIMIZED ? User32.SW_SHOWMINNOACTIVE
                  : maximised && focusGame ? User32.SW_SHOWMAXIMIZED
                  : User32.SW_SHOWNOACTIVATE;
        _remaximize = maximised && !focusGame;
        // Twice: going back onto a monitor with another DPI makes WPF rescale to Windows' suggested rect;
        // the second call lands on the same monitor and is exact.
        User32.SetWindowPlacement(_hwnd, ref p);
        User32.SetWindowPlacement(_hwnd, ref p);

        if (focusGame && _game != IntPtr.Zero && User32.IsWindow(_game))
        {
            if (User32.IsIconic(_game)) User32.ShowWindow(_game, User32.SW_RESTORE);
            User32.SetForegroundWindow(_game);
        }
    }

    private void Place()
    {
        var r = Carve(TargetArea(), Layout);
        // Physical pixels (the panel is per-monitor DPI aware, so GetWindowRect on the game is physical
        // too). Twice for the same reason as Exit: the first move may cross onto a monitor with another DPI.
        for (var i = 0; i < 2; i++)
            User32.SetWindowPos(_hwnd, IntPtr.Zero, r.Left, r.Top, r.Width, r.Height, User32.SWP_NOZORDER | User32.SWP_NOACTIVATE);
    }

    /// <summary>The game's on-screen area (clipped to its monitor), its monitor if it is minimised, or - game
    /// not running - the work area of the monitor the panel is on, so the layout can be previewed.</summary>
    private User32.RECT TargetArea()
    {
        if (_game != IntPtr.Zero && User32.IsWindow(_game))
        {
            var mon = MonitorArea(_game, work: false);
            if (!User32.IsIconic(_game) && User32.GetWindowRect(_game, out var g))
            {
                var i = new User32.RECT
                {
                    Left = Math.Max(g.Left, mon.Left), Top = Math.Max(g.Top, mon.Top),
                    Right = Math.Min(g.Right, mon.Right), Bottom = Math.Min(g.Bottom, mon.Bottom),
                };
                if (i.Width >= 320 && i.Height >= 240) return i;
            }
            return mon;
        }
        return MonitorArea(_hwnd, work: true);
    }

    private static User32.RECT MonitorArea(IntPtr hwnd, bool work)
    {
        // MonitorFromWindow uses the pre-minimise rect for a minimised window, so this is the game's monitor either way
        var mi = new User32.MONITORINFO { cbSize = (uint)Marshal.SizeOf<User32.MONITORINFO>() };
        var mon = User32.MonitorFromWindow(hwnd, User32.MONITOR_DEFAULTTONEAREST);
        if (mon != IntPtr.Zero && User32.GetMonitorInfo(mon, ref mi)) return work ? mi.rcWork : mi.rcMonitor;
        return new User32.RECT { Left = 0, Top = 0, Right = 1920, Bottom = 1080 };
    }

    private static User32.RECT Carve(User32.RECT a, string layout)
    {
        var m = Math.Max(8, a.Height * 3 / 100);   // an inset, so it reads as a layer over the game
        int x, y, w, h;
        switch (layout)
        {
            case "full": x = a.Left + m; y = a.Top + m; w = a.Width - 2 * m; h = a.Height - 2 * m; break;
            case "left": w = a.Width * 55 / 100; h = a.Height - 2 * m; x = a.Left + m; y = a.Top + m; break;
            case "centre": w = a.Width * 80 / 100; h = a.Height * 86 / 100; x = a.Left + (a.Width - w) / 2; y = a.Top + (a.Height - h) / 2; break;
            default: w = a.Width * 55 / 100; h = a.Height - 2 * m; x = a.Right - m - w; y = a.Top + m; break;   // right
        }
        return new User32.RECT { Left = x, Top = y, Right = x + w, Bottom = y + h };
    }

    /// <summary>The largest visible, unowned top-level window of the game process. Window enumeration only -
    /// no handle to the process.</summary>
    private static IntPtr FindGameWindow(int pid)
    {
        if (pid <= 0) pid = GameProcess.FindPid();
        if (pid <= 0) return IntPtr.Zero;
        var best = IntPtr.Zero;
        long bestArea = 0;
        User32.EnumWindows((h, _) =>
        {
            User32.GetWindowThreadProcessId(h, out var owner);
            if (owner != (uint)pid || !User32.IsWindowVisible(h) || User32.GetWindow(h, User32.GW_OWNER) != IntPtr.Zero) return true;
            long area = 1;
            if (!User32.IsIconic(h) && User32.GetWindowRect(h, out var r)) area = Math.Max(1L, (long)r.Width * r.Height);
            if (area > bestArea) { bestArea = area; best = h; }
            return true;
        }, IntPtr.Zero);
        return best;
    }

    /// <summary>A moment after showing, two things the overlay cannot see from Enter():
    /// (1) Windows refused the focus - then it flashes the taskbar button instead, and the overlay would be a
    ///     topmost window over a game that still has the input. Stand down and say so rather than stay up.
    /// (2) the game minimised - exclusive Fullscreen gives up the display when it loses focus, and the
    ///     overlay then sits on the desktop. Say what to change instead of leaving it to be guessed.</summary>
    private void VerifyShown()
    {
        var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(800) };
        t.Tick += (_, _) =>
        {
            t.Stop();
            if (!Active) return;
            if (!OwnsForeground())
            {
                Exit(focusGame: false);
                _toasts.Show("Windows did not give the panel the focus, so the overlay stood down. Alt+Tab to the panel instead (and note it: gf-panel.md §6).", LogLevel.Warn);
                return;
            }
            if (_game != IntPtr.Zero && User32.IsWindow(_game) && User32.IsIconic(_game))
                _toasts.Show("BOCW minimised when the panel took focus - it is in exclusive Fullscreen. Set Display Mode to Fullscreen Borderless.", LogLevel.Warn);
        };
        t.Start();
    }

    private static bool OwnsForeground()
    {
        var fg = User32.GetForegroundWindow();
        if (fg == IntPtr.Zero) return false;
        User32.GetWindowThreadProcessId(fg, out var pid);
        return pid == (uint)Environment.ProcessId;
    }
}
