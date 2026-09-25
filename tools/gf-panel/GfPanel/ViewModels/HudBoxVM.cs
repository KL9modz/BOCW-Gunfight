using System.Windows.Threading;

namespace GfPanel.ViewModels;

/// <summary>One MENU BACKDROP box (gunfight_menu.gsc hudbox_*, klaze 2026-09-24: "try moving the stage 9 boxes to
/// fill behind the menu center line and hint row"): an event-backed LUIelemBar the menu opens for its owner while
/// the menu is open. gf_hb0 = behind the centre line, gf_hb1 = behind the hint row; "x,y,w,h,alpha,r,g,b" - x / y
/// in 15-px units, w in 8-px units, h in 4-px units (the widget's Lua, core_ui_0685 - the stock px helper's
/// width / 4 is wrong for it), alpha / colour 0..15, alpha 0 = that box off. With Live on, a change is
/// sent 350 ms after the last slider move (one short `set`, well under the 47-byte slot) and the GSC re-applies it
/// on its next 0.1 s tick while the menu is open - tune it while looking at the game. Defaults = the GSC's fallbacks
/// (measured on klaze's screen 2026-09-24: box 0 off, box 1 on the hint row).</summary>
public sealed class HudBoxVM : ObservableObject
{
    private readonly MainViewModel _m;
    private readonly DispatcherTimer _debounce;
    public string Name { get; }
    public string Dvar { get; }

    public HudBoxVM(MainViewModel m, string name, string dvar, int x, int y, int w, int h, int a)
    {
        _m = m; Name = name; Dvar = dvar;
        _x = x; _y = y; _w = w; _h = h; _a = a;
        _debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        _debounce.Tick += (_, _) => { _debounce.Stop(); if (_live) Send(); };
    }

    private int _x, _y, _w, _h, _a, _r, _g, _b;
    public int X { get => _x; set { if (Set(ref _x, Math.Clamp(value, 0, 128))) Changed(); } }
    public int Y { get => _y; set { if (Set(ref _y, Math.Clamp(value, 0, 72))) Changed(); } }
    public int W { get => _w; set { if (Set(ref _w, Math.Clamp(value, 1, 240))) Changed(); } }
    public int H { get => _h; set { if (Set(ref _h, Math.Clamp(value, 1, 270))) Changed(); } }
    public int A { get => _a; set { if (Set(ref _a, Math.Clamp(value, 0, 15))) Changed(); } }

    private bool _live = true;
    /// <summary>Send each change on its own (debounced); off = only the Apply button sends.</summary>
    public bool Live { get => _live; set => Set(ref _live, value); }

    public string Line => $"{_x},{_y},{_w},{_h},{_a},{_r},{_g},{_b}";
    public string Pixels => $"{_x * 15},{_y * 15} px · {_w * 8}×{_h * 4} px";

    private void Changed()
    {
        OnPropertyChanged(nameof(Line));
        OnPropertyChanged(nameof(Pixels));
        _debounce.Stop();
        _debounce.Start();
    }

    private void Send() => _ = _m.Link.SendRaw(new[] { $"set {Dvar} {Line}" }, 6);

    private void Colour(int r, int g, int b)
    {
        _r = r; _g = g; _b = b;
        Changed();
    }

    public RelayCommand Apply => new(() => Send());
    public RelayCommand Off => new(() => { _a = 0; OnPropertyChanged(nameof(A)); Changed(); if (!_live) Send(); });
    public RelayCommand Black => new(() => Colour(0, 0, 0));
    public RelayCommand Navy => new(() => Colour(0, 2, 6));
    public RelayCommand Grey => new(() => Colour(4, 4, 4));
    public RelayCommand Purple => new(() => Colour(6, 2, 10));
}
