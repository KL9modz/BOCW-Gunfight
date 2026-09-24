using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.Views;

/// <summary>
/// The RACING page's map (2026-09-24): the game's race track top-down over the map picture the SPAWN ATLAS placed
/// (its minimap frame + saved alignment, north up; a plain grid for a map never scanned), with every player live.
/// The editor: click a gate to select it; with EditMode on, drag its centre to move it, drag a post to turn and
/// widen it, Ctrl+click empty ground to insert a gate after the selected one (or at the end); keys Delete,
/// [ ] turn (Shift = 15°), + - widen, arrows nudge (Shift = far), Esc deselects. Wheel zooms around the cursor,
/// drag pans, double-click fits. Every edit leaves as a TrackEdit through EditCommand; the plot never changes the
/// track itself (it draws a drag's preview until the game's own copy comes back).
/// </summary>
public sealed class TrackPlot : FrameworkElement
{
    public static readonly DependencyProperty GatesProperty = Reg<IList<RaceGate>?>(nameof(Gates), null);
    /// <summary>A saved track shown faint over the live one (the library's preview).</summary>
    public static readonly DependencyProperty GhostProperty = Reg<IList<RaceGate>?>(nameof(Ghost), null);
    public static readonly DependencyProperty PlayersProperty = Reg<IList<RaceDot>?>(nameof(Players), null);
    public static readonly DependencyProperty FrameProperty = Reg<MinimapFrame?>(nameof(Frame), null);
    public static readonly DependencyProperty NorthYawProperty = Reg<double?>(nameof(NorthYaw), null);
    public static readonly DependencyProperty ArtProperty = Reg<ImageSource?>(nameof(Art), null);
    public static readonly DependencyProperty ArtAlignProperty = Reg<ArtAlign?>(nameof(ArtAlign), null);
    public static readonly DependencyProperty ArtOpacityProperty = Reg<double>(nameof(ArtOpacity), 0.85);
    public static readonly DependencyProperty SelectedGateProperty = DependencyProperty.Register(nameof(SelectedGate), typeof(int), typeof(TrackPlot),
        new FrameworkPropertyMetadata(-1, FrameworkPropertyMetadataOptions.BindsTwoWayByDefault | FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty EditModeProperty = Reg<bool>(nameof(EditMode), false);
    public static readonly DependencyProperty FollowHostProperty = Reg<bool>(nameof(FollowHost), false);
    public static readonly DependencyProperty ShowCorridorProperty = Reg<bool>(nameof(ShowCorridor), true);
    /// <summary>gf_race_corridor: the boundary's whole width around the gate-to-gate line (0 = off).</summary>
    public static readonly DependencyProperty CorridorWidthProperty = Reg<double>(nameof(CorridorWidth), 1600);
    public static readonly DependencyProperty ShowNamesProperty = Reg<bool>(nameof(ShowNames), true);
    public static readonly DependencyProperty ShowGridProperty = Reg<bool>(nameof(ShowGrid), true);
    /// <summary>gf_race_grid_gap: the start grid's column spacing.</summary>
    public static readonly DependencyProperty GridGapProperty = Reg<int>(nameof(GridGap), 220);
    /// <summary>gf_race_sprint: an A-to-B course has no leg back to the start.</summary>
    public static readonly DependencyProperty SprintProperty = Reg<bool>(nameof(Sprint), false);
    public static readonly DependencyProperty EditCommandProperty = DependencyProperty.Register(nameof(EditCommand), typeof(ICommand), typeof(TrackPlot));

    public IList<RaceGate>? Gates { get => (IList<RaceGate>?)GetValue(GatesProperty); set => SetValue(GatesProperty, value); }
    public IList<RaceGate>? Ghost { get => (IList<RaceGate>?)GetValue(GhostProperty); set => SetValue(GhostProperty, value); }
    public IList<RaceDot>? Players { get => (IList<RaceDot>?)GetValue(PlayersProperty); set => SetValue(PlayersProperty, value); }
    public MinimapFrame? Frame { get => (MinimapFrame?)GetValue(FrameProperty); set => SetValue(FrameProperty, value); }
    public double? NorthYaw { get => (double?)GetValue(NorthYawProperty); set => SetValue(NorthYawProperty, value); }
    public ImageSource? Art { get => (ImageSource?)GetValue(ArtProperty); set => SetValue(ArtProperty, value); }
    public ArtAlign? ArtAlign { get => (ArtAlign?)GetValue(ArtAlignProperty); set => SetValue(ArtAlignProperty, value); }
    public double ArtOpacity { get => (double)GetValue(ArtOpacityProperty); set => SetValue(ArtOpacityProperty, value); }
    public int SelectedGate { get => (int)GetValue(SelectedGateProperty); set => SetValue(SelectedGateProperty, value); }
    public bool EditMode { get => (bool)GetValue(EditModeProperty); set => SetValue(EditModeProperty, value); }
    public bool FollowHost { get => (bool)GetValue(FollowHostProperty); set => SetValue(FollowHostProperty, value); }
    public bool ShowCorridor { get => (bool)GetValue(ShowCorridorProperty); set => SetValue(ShowCorridorProperty, value); }
    public double CorridorWidth { get => (double)GetValue(CorridorWidthProperty); set => SetValue(CorridorWidthProperty, value); }
    public bool ShowNames { get => (bool)GetValue(ShowNamesProperty); set => SetValue(ShowNamesProperty, value); }
    public bool ShowGrid { get => (bool)GetValue(ShowGridProperty); set => SetValue(ShowGridProperty, value); }
    public int GridGap { get => (int)GetValue(GridGapProperty); set => SetValue(GridGapProperty, value); }
    public bool Sprint { get => (bool)GetValue(SprintProperty); set => SetValue(SprintProperty, value); }
    public ICommand? EditCommand { get => (ICommand?)GetValue(EditCommandProperty); set => SetValue(EditCommandProperty, value); }

    private static DependencyProperty Reg<T>(string name, T def) =>
        DependencyProperty.Register(name, typeof(T), typeof(TrackPlot), new FrameworkPropertyMetadata(def, FrameworkPropertyMetadataOptions.AffectsRender, OnChanged));

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var p = (TrackPlot)d;
        if (e.Property == PlayersProperty && p.FollowHost) p.CentreOnHost();
        else if (e.Property == FrameProperty || e.Property == NorthYawProperty) p._view = null;   // another map: fit again
    }

    // ── look ──
    private static SolidColorBrush B(uint argb) { var b = new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb)); b.Freeze(); return b; }
    private static Pen P(Brush b, double w, bool dash = false, bool round = false)
    {
        var p = new Pen(b, w);
        if (dash) p.DashStyle = new DashStyle(new double[] { 3, 3 }, 0);
        if (round) { p.StartLineCap = p.EndLineCap = PenLineCap.Round; p.LineJoin = PenLineJoin.Round; }
        p.Freeze();
        return p;
    }
    private static readonly Brush Bg = B(0xFF0B0D14), GridBr = B(0x14FFFFFF), GridLbl = B(0x60A0A8C8), TextBr = B(0xFFE6E8F0), TextDim = B(0xFF8A90A8),
        CorridorBr = B(0x2E3DDC84), GateBr = B(0xFFFFB020), StartBr = B(0xFFFFFFFF), SelBr = B(0xFF33D6FF), GhostBr = B(0x90C8A0FF),
        HostBr = B(0xFFFFD24A), RacerBr = B(0xFF3DDC84), PlayerBr = B(0xFFB8C0D8), DeadBr = B(0xFF5A6078), FinBr = B(0xFFFFFFFF), SlotBr = B(0x70FFFFFF),
        HandleFill = B(0xFF0B0D14), LabelBg = B(0xC00B0D14);
    private static readonly Pen GridPen = P(GridBr, 1), LinePen = P(B(0x66FFFFFF), 1.4, true), GatePen = P(GateBr, 4, false, true), SelPen = P(SelBr, 5, false, true),
        StartPen = P(StartBr, 5, false, true), StartDash = P(B(0xFF000000), 5, true), GhostPen = P(GhostBr, 2.5, true, true), HandlePen = P(SelBr, 2),
        ArrowPen = P(B(0xB0FFFFFF), 1.6, false, true), DotRim = P(B(0xE0000000), 1.4);
    private static readonly Typeface Face = new("Segoe UI");

    // ── view: a world box fitted once (on the first content, a new map, Fit), then zoom / pan on top ──
    private (double MinX, double MaxX, double MinY, double MaxY)? _view;
    private double _zoom = 1, _scale = 1, _ox, _oy, _cos = 1, _sin;
    private Vector _pan;
    private Point? _mouse;

    // ── a drag: pan, or (EditMode) a gate being moved / turned ──
    private enum Drag { None, Pan, Move, PostA, PostB }
    private Drag _drag;
    private Point _dragFrom;
    private Vector _panAtDrag;
    private int _dragGate = -1;
    private RaceGate? _preview;

    public TrackPlot() { ClipToBounds = true; Focusable = true; Cursor = Cursors.Cross; }

    /// <summary>Fit the track (else the players, else the map frame) into the plot.</summary>
    public void FitToContent() { _view = null; _zoom = 1; _pan = new Vector(); InvalidateVisual(); }

    private double Theta => (NorthYaw.HasValue ? 90 - NorthYaw.Value : 0) * Math.PI / 180;
    private (double X, double Y) Rot(double x, double y) => (x * _cos - y * _sin, x * _sin + y * _cos);

    private void ComputeView()
    {
        var t = Theta;
        _cos = Math.Cos(t); _sin = Math.Sin(t);
        if (_view == null)
        {
            var pts = new List<(double X, double Y)>();
            if (Gates is { Count: > 0 } gs)
                foreach (var g in gs) { pts.Add(g.PostA); pts.Add(g.PostB); pts.Add((g.X, g.Y)); }
            else if (Players is { Count: > 0 } ps)
                foreach (var p in ps) pts.Add((p.X, p.Y));
            else if (Frame is { } f)
            {
                pts.Add((f.NWx, f.NWy)); pts.Add((f.NEx, f.NEy)); pts.Add((f.SWx, f.SWy)); pts.Add((f.SEx, f.SEy));
            }
            if (pts.Count == 0) { _view = (-2000, 2000, -2000, 2000); }
            else
            {
                double x0 = double.MaxValue, x1 = double.MinValue, y0 = double.MaxValue, y1 = double.MinValue;
                foreach (var (x, y) in pts)
                {
                    var (rx, ry) = Rot(x, y);
                    x0 = Math.Min(x0, rx); x1 = Math.Max(x1, rx); y0 = Math.Min(y0, ry); y1 = Math.Max(y1, ry);
                }
                var mx = (x1 - x0) * 0.1 + 400; var my = (y1 - y0) * 0.1 + 400;
                _view = (x0 - mx, x1 + mx, y0 - my, y1 + my);
            }
        }
        var v = _view.Value;
        const double pad = 10;
        double w = Math.Max(1, v.MaxX - v.MinX), h = Math.Max(1, v.MaxY - v.MinY);
        double W = Math.Max(10, ActualWidth - 2 * pad), H = Math.Max(10, ActualHeight - 2 * pad);
        _scale = Math.Min(W / w, H / h);
        _ox = pad + (W - w * _scale) / 2;
        _oy = pad + (H - h * _scale) / 2;
    }

    private Point ToScreen(double x, double y)
    {
        var v = _view!.Value;
        var (rx, ry) = Rot(x, y);
        var bx = _ox + (rx - v.MinX) * _scale;
        var by = _oy + (v.MaxY - ry) * _scale;
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        return new Point(cx + (bx - cx) * _zoom + _pan.X, cy + (by - cy) * _zoom + _pan.Y);
    }
    private Point ToScreen((double X, double Y) p) => ToScreen(p.X, p.Y);

    private (double X, double Y) ToWorld(Point s)
    {
        var v = _view!.Value;
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        var bx = cx + (s.X - cx - _pan.X) / _zoom;
        var by = cy + (s.Y - cy - _pan.Y) / _zoom;
        double rx = v.MinX + (bx - _ox) / _scale, ry = v.MaxY - (by - _oy) / _scale;
        return (rx * _cos + ry * _sin, -rx * _sin + ry * _cos);        // undo the turn
    }

    /// <summary>World units per screen pixel's inverse: pixels per unit.</summary>
    private double Px => _scale * _zoom;

    private void CentreOnHost()
    {
        if (_view == null || Players == null || ActualWidth <= 0) return;
        var host = Players.FirstOrDefault(p => p.IsHost);
        if (host == null) return;
        var s = ToScreen(host.X, host.Y);
        _pan += new Vector(ActualWidth / 2 - s.X, ActualHeight / 2 - s.Y);
        InvalidateVisual();
    }

    // ── render ──
    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRectangle(Bg, null, new Rect(0, 0, ActualWidth, ActualHeight));
        if (ActualWidth < 20 || ActualHeight < 20) return;
        ComputeView();
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        DrawArt(dc);
        if (Art == null) DrawGrid(dc, dpi);

        var gates = Gates?.ToList() ?? new List<RaceGate>();
        if (_preview != null && _dragGate >= 0 && _dragGate < gates.Count) gates[_dragGate] = _preview;
        var circuit = !Sprint;

        // the boundary corridor and the racing line (gate centre to gate centre; a circuit closes back to the start)
        if (gates.Count >= 2)
        {
            var line = new StreamGeometry();
            using (var c = line.Open())
            {
                c.BeginFigure(ToScreen(gates[0].X, gates[0].Y), false, false);
                for (var i = 1; i < gates.Count; i++) c.LineTo(ToScreen(gates[i].X, gates[i].Y), true, true);
                if (circuit && gates.Count > 2) c.LineTo(ToScreen(gates[0].X, gates[0].Y), true, true);
            }
            line.Freeze();
            if (ShowCorridor && CorridorWidth > 0)
                dc.DrawGeometry(null, P(CorridorBr, Math.Max(2, CorridorWidth * Px), false, true), line);
            dc.DrawGeometry(null, LinePen, line);
            // a chevron halfway along each leg: which way the course runs
            var legs = gates.Count - 1 + (circuit && gates.Count > 2 ? 1 : 0);
            for (var i = 0; i < legs; i++)
            {
                var a = gates[i]; var b = gates[(i + 1) % gates.Count];
                Chevron(dc, ToScreen((a.X + b.X) / 2.0, (a.Y + b.Y) / 2.0), ToScreen(a.X, a.Y), ToScreen(b.X, b.Y), 7, ArrowPen);
            }
        }

        // the start grid behind gate 0 (race_grid_place: 12 slots shown)
        if (ShowGrid && gates.Count > 0)
            foreach (var slot in gates[0].GridSlots(12, GridGap))
                dc.DrawEllipse(SlotBr, null, ToScreen(slot), 2.6, 2.6);

        // a saved track's preview, faint
        if (Ghost is { Count: > 0 } ghost)
            foreach (var g in ghost)
                dc.DrawLine(GhostPen, ToScreen(g.PostA), ToScreen(g.PostB));

        // the gates: start / finish white with black dashes, the rest amber, the selected one cyan
        var sel = SelectedGate;
        for (var i = 0; i < gates.Count; i++)
        {
            var g = gates[i];
            Point a = ToScreen(g.PostA), b = ToScreen(g.PostB), c = ToScreen(g.X, g.Y);
            if (i == sel) dc.DrawLine(SelPen, a, b);
            else if (i == 0) { dc.DrawLine(StartPen, a, b); dc.DrawLine(StartDash, a, b); }
            else dc.DrawLine(GatePen, a, b);
            var fwd = g.Fwd;
            Chevron(dc, c, c, ToScreen(g.X + fwd.X * 100, g.Y + fwd.Y * 100), i == sel ? 9 : 7, i == sel ? HandlePen : ArrowPen);
            var label = i == 0 ? (Sprint ? "START" : "START/FINISH") : (Sprint && i == gates.Count - 1 ? i + " FINISH" : i.ToString(CultureInfo.InvariantCulture));
            Label(dc, label, new Point(b.X + 5, b.Y - 8), 10.5, i == sel ? SelBr : i == 0 ? StartBr : GateBr, dpi, true);
            if (i == sel && EditMode)
            {
                dc.DrawEllipse(HandleFill, HandlePen, a, 6, 6);
                dc.DrawEllipse(HandleFill, HandlePen, b, 6, 6);
                dc.DrawRectangle(HandleFill, HandlePen, new Rect(c.X - 5, c.Y - 5, 10, 10));
            }
        }

        // the players
        if (Players is { } players)
        {
            foreach (var p in players.OrderBy(p => p.IsHost))
            {
                var s = ToScreen(p.X, p.Y);
                var br = p.Dead ? DeadBr : p.IsHost ? HostBr : p.Finished ? FinBr : p.Racing ? RacerBr : PlayerBr;
                var yaw = p.Yaw * Math.PI / 180;
                var ahead = ToScreen(p.X + Math.Cos(yaw) * 100, p.Y + Math.Sin(yaw) * 100);
                var d = ahead - s;
                if (d.Length < 0.01) d = new Vector(0, -1);
                d.Normalize();
                var n = new Vector(-d.Y, d.X);
                var size = p.IsHost ? 11 : 9;
                var tri = new StreamGeometry();
                using (var c = tri.Open())
                {
                    c.BeginFigure(s + d * size, true, true);
                    c.LineTo(s - d * size * 0.6 + n * size * 0.65, true, false);
                    c.LineTo(s - d * size * 0.25, true, false);
                    c.LineTo(s - d * size * 0.6 - n * size * 0.65, true, false);
                }
                tri.Freeze();
                dc.DrawGeometry(br, DotRim, tri);
                if (ShowNames || p.IsHost)
                {
                    var text = p.Info.Length > 0 ? p.Name + "  " + p.Info : p.Name;
                    var ft = Fmt(text, 10.5, br, dpi, p.IsHost);
                    var at = new Point(s.X + 10, s.Y - 7);
                    dc.DrawRectangle(LabelBg, null, new Rect(at.X - 2, at.Y - 1, ft.Width + 4, ft.Height + 2));
                    dc.DrawText(ft, at);
                }
            }
        }

        // where the mouse is, in the game's units (for reading a spot off the map)
        if (_mouse is { } m && _view != null)
        {
            var (wx, wy) = ToWorld(m);
            Label(dc, string.Create(CultureInfo.InvariantCulture, $"x {wx:0}  y {wy:0}"), new Point(8, ActualHeight - 20), 10.5, TextDim, dpi);
        }
        if (gates.Count == 0 && (Players == null || Players.Count == 0))
            Label(dc, "No track and nobody live yet. Drive the course in game and press Gate here (menu or this page) - gates appear here as you place them.",
                  new Point(14, 14), 12, TextDim, dpi);
    }

    private void DrawArt(DrawingContext dc)
    {
        if (Art is not { } img) return;
        double w = img.Width, h = img.Height;
        if (w <= 0 || h <= 0) return;
        var pts = (Gates ?? (IList<RaceGate>)Array.Empty<RaceGate>()).Select(g => ((double)g.X, (double)g.Y));
        if (SpawnPlot.ArtCornersFor(Frame, pts, ArtAlign, w, h) is not { } k) return;
        var s0 = ToScreen(k.NW.X, k.NW.Y);
        var s1 = ToScreen(k.NE.X, k.NE.Y);
        var s2 = ToScreen(k.SW.X, k.SW.Y);
        var mtx = new Matrix((s1.X - s0.X) / w, (s1.Y - s0.Y) / w, (s2.X - s0.X) / h, (s2.Y - s0.Y) / h, s0.X, s0.Y);
        dc.PushTransform(new MatrixTransform(mtx));
        dc.PushOpacity(Math.Clamp(ArtOpacity, 0.05, 1));
        dc.DrawImage(img, new Rect(0, 0, w, h));
        dc.Pop();
        dc.Pop();
    }

    /// <summary>A world grid (500 / 1000 / 2000 u by zoom) with its coordinates, when there is no picture.</summary>
    private void DrawGrid(DrawingContext dc, double dpi)
    {
        var (ax, ay) = ToWorld(new Point(0, 0));
        var (bx, by) = ToWorld(new Point(ActualWidth, ActualHeight));
        var (cx, cy) = ToWorld(new Point(ActualWidth, 0));
        var (ex, ey) = ToWorld(new Point(0, ActualHeight));
        double x0 = new[] { ax, bx, cx, ex }.Min(), x1 = new[] { ax, bx, cx, ex }.Max(), y0 = new[] { ay, by, cy, ey }.Min(), y1 = new[] { ay, by, cy, ey }.Max();
        var span = Math.Max(x1 - x0, y1 - y0);
        var step = span > 30000 ? 4000 : span > 12000 ? 2000 : span > 5000 ? 1000 : 500;
        var lines = 0;
        for (var x = Math.Floor(x0 / step) * step; x <= x1 && lines < 200; x += step, lines++)
        {
            dc.DrawLine(GridPen, ToScreen(x, y0), ToScreen(x, y1));
            Label(dc, x.ToString("0", CultureInfo.InvariantCulture), ToScreen(x, y1) + new Vector(3, 3), 9, GridLbl, dpi);
        }
        for (var y = Math.Floor(y0 / step) * step; y <= y1 && lines < 400; y += step, lines++)
        {
            dc.DrawLine(GridPen, ToScreen(x0, y), ToScreen(x1, y));
            Label(dc, y.ToString("0", CultureInfo.InvariantCulture), ToScreen(x0, y) + new Vector(3, 3), 9, GridLbl, dpi);
        }
    }

    /// <summary>A chevron at <paramref name="at"/> pointing along from -> to.</summary>
    private static void Chevron(DrawingContext dc, Point at, Point from, Point to, double size, Pen pen)
    {
        var d = to - from;
        if (d.Length < 0.01) return;
        d.Normalize();
        var n = new Vector(-d.Y, d.X);
        var tip = at + d * size * 0.6;
        dc.DrawLine(pen, tip, tip - d * size + n * size * 0.7);
        dc.DrawLine(pen, tip, tip - d * size - n * size * 0.7);
    }

    private FormattedText Fmt(string text, double size, Brush br, double dpi, bool bold) =>
        new(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, bold ? new Typeface(Face.FontFamily, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal) : Face, size, br, dpi);

    private void Label(DrawingContext dc, string text, Point at, double size, Brush br, double dpi, bool bold = false) =>
        dc.DrawText(Fmt(text, size, br, dpi, bold), at);

    // ── hit tests (screen space) ──
    private int GateAt(Point s)
    {
        var gates = Gates;
        if (gates == null || _view == null) return -1;
        int best = -1; double bestD = 10;
        for (var i = 0; i < gates.Count; i++)
        {
            var g = gates[i];
            var d = Math.Min(SegDist(s, ToScreen(g.PostA), ToScreen(g.PostB)), (s - ToScreen(g.X, g.Y)).Length);
            if (d <= bestD) { bestD = d; best = i; }
        }
        return best;
    }

    private static double SegDist(Point p, Point a, Point b)
    {
        var ab = b - a;
        var len2 = ab.LengthSquared;
        if (len2 < 1e-6) return (p - a).Length;
        var t = Math.Clamp(((p - a) * ab) / len2, 0, 1);
        return (p - (a + ab * t)).Length;
    }

    private Drag HandleAt(Point s)
    {
        var gates = Gates;
        var i = SelectedGate;
        if (!EditMode || gates == null || i < 0 || i >= gates.Count || _view == null) return Drag.None;
        var g = gates[i];
        if ((s - ToScreen(g.PostA)).Length <= 9) return Drag.PostA;
        if ((s - ToScreen(g.PostB)).Length <= 9) return Drag.PostB;
        if ((s - ToScreen(g.X, g.Y)).Length <= 10) return Drag.Move;
        return Drag.None;
    }

    private void Raise(TrackEdit e)
    {
        var cmd = EditCommand;
        if (cmd != null && cmd.CanExecute(e)) cmd.Execute(e);
    }

    private void Select(int i)
    {
        SetCurrentValue(SelectedGateProperty, i);
        Raise(new TrackEdit(TrackEditKind.Select, i));
    }

    // ── input ──
    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        if (_view == null) return;
        var s = e.GetPosition(this);
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        var bx = cx + (s.X - cx - _pan.X) / _zoom;
        var by = cy + (s.Y - cy - _pan.Y) / _zoom;
        var z = Math.Clamp(_zoom * (e.Delta > 0 ? 1.2 : 1 / 1.2), 0.3, 80);
        _pan = new Vector(s.X - cx - (bx - cx) * z, s.Y - cy - (by - cy) * z);
        _zoom = z;
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        Focus();
        if (_view == null) return;
        var s = e.GetPosition(this);
        if (e.ClickCount == 2) { FitToContent(); e.Handled = true; return; }
        _dragFrom = s;
        _panAtDrag = _pan;
        _preview = null;
        var handle = HandleAt(s);
        if (handle != Drag.None) { _drag = handle; _dragGate = SelectedGate; }
        else if (GateAt(s) is var hit and >= 0)
        {
            Select(hit);
            _drag = EditMode ? Drag.Move : Drag.Pan;
            _dragGate = hit;
        }
        else if (EditMode && (Keyboard.Modifiers & ModifierKeys.Control) != 0)
        {
            var (wx, wy) = ToWorld(s);
            Raise(new TrackEdit(TrackEditKind.Insert, SelectedGate, null, wx, wy));
            _drag = Drag.None;
            e.Handled = true;
            return;
        }
        else _drag = Drag.Pan;
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var s = e.GetPosition(this);
        _mouse = s;
        if (_drag == Drag.Pan) _pan = _panAtDrag + (s - _dragFrom);
        else if (_drag != Drag.None && Gates is { } gates && _dragGate >= 0 && _dragGate < gates.Count && (s - _dragFrom).Length > 3)
        {
            var g = gates[_dragGate];
            var (wx, wy) = ToWorld(s);
            _preview = _drag switch
            {
                Drag.Move => g.MovedTo(wx, wy),
                Drag.PostA => g.WithPost(false, wx, wy),
                _ => g.WithPost(true, wx, wy),
            };
        }
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        if (_preview != null && _dragGate >= 0) Raise(new TrackEdit(TrackEditKind.Set, _dragGate, _preview));
        _preview = null;
        _drag = Drag.None;
        _dragGate = -1;
        ReleaseMouseCapture();
        InvalidateVisual();
    }

    protected override void OnMouseRightButtonDown(MouseButtonEventArgs e)
    {
        Focus();
        if (_view != null && GateAt(e.GetPosition(this)) is var hit and >= 0) Select(hit);   // the context menu acts on it
    }

    protected override void OnMouseLeave(MouseEventArgs e) { _mouse = null; InvalidateVisual(); }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        var gates = Gates;
        var i = SelectedGate;
        if (e.Key == Key.Escape) { Select(-1); e.Handled = true; return; }
        if (!EditMode || gates == null || i < 0 || i >= gates.Count || _view == null) return;
        var g = gates[i];
        var shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
        RaceGate? to = null;
        switch (e.Key)
        {
            case Key.Delete: case Key.Back: Raise(new TrackEdit(TrackEditKind.Delete, i)); e.Handled = true; return;
            case Key.OemOpenBrackets: to = g.Turned(shift ? 15 : 5); break;          // [ = turn left (counter-clockwise)
            case Key.OemCloseBrackets: to = g.Turned(shift ? -15 : -5); break;
            case Key.OemPlus: case Key.Add: to = g.Widened(shift ? 400 : 100); break;
            case Key.OemMinus: case Key.Subtract: to = g.Widened(shift ? -400 : -100); break;
            case Key.Left: case Key.Right: case Key.Up: case Key.Down:
            {
                // nudge along the SCREEN's axes, 32 u (Shift 128 u)
                var d = e.Key switch { Key.Left => new Vector(-1, 0), Key.Right => new Vector(1, 0), Key.Up => new Vector(0, -1), _ => new Vector(0, 1) };
                var (x0, y0) = ToWorld(new Point(ActualWidth / 2, ActualHeight / 2));
                var (x1, y1) = ToWorld(new Point(ActualWidth / 2, ActualHeight / 2) + d * 50);
                var len = Math.Sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
                if (len < 1e-9) return;
                var step = shift ? 128 : 32;
                to = g.MovedTo(g.X + (x1 - x0) / len * step, g.Y + (y1 - y0) / len * step);
                break;
            }
        }
        if (to != null) { Raise(new TrackEdit(TrackEditKind.Set, i, to)); e.Handled = true; }
    }
}
