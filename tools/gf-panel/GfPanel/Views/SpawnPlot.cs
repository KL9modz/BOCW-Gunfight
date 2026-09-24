using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.Views;

/// <summary>
/// One map's spawn atlas, top-down, NORTH UP like the in-game map (the scan's getnorthyaw; turned further in
/// 90° steps by Rotation), over the map's picture (Art) laid on the game's minimap frame (minimap_corner) and
/// nudged by ArtAlign. Wheel zooms around the cursor, drag pans, double-click fits; in AlignMode drag moves the
/// picture, Ctrl+wheel scales it, Shift+wheel turns it. Hovering a point says what it is. Colours: allies side
/// blue, axis side red, either grey; filled = a START (the mode opens there), hollow = a RESPAWN (mid-match
/// pool); squares = BO2-named structs, diamonds = S&D group points; yellow rings = dense areas; the selected
/// layout's sides get cyan / red halos.
/// </summary>
public sealed class SpawnPlot : FrameworkElement
{
    public static readonly DependencyProperty AtlasProperty = Reg<SpawnAtlas?>(nameof(Atlas), null, true);
    public static readonly DependencyProperty LayerProperty = Reg<string>(nameof(Layer), "all");
    public static readonly DependencyProperty LayoutProperty = Reg<SpawnLayout?>(nameof(Layout), null);
    public static readonly DependencyProperty AreasProperty = Reg<IList<SpawnArea>?>(nameof(Areas), null);
    public static readonly DependencyProperty ShowAreasProperty = Reg<bool>(nameof(ShowAreas), true);
    public static readonly DependencyProperty RotationProperty = Reg<int>(nameof(Rotation), 0, true);
    public static readonly DependencyProperty NorthUpProperty = Reg<bool>(nameof(NorthUp), true, true);
    public static readonly DependencyProperty ArtProperty = Reg<ImageSource?>(nameof(Art), null);
    public static readonly DependencyProperty ArtOpacityProperty = Reg<double>(nameof(ArtOpacity), 0.9);
    public static readonly DependencyProperty AlignModeProperty = Reg<bool>(nameof(AlignMode), false);
    /// <summary>A title block drawn top-left (the exported pictures: map, what is highlighted, the legend).</summary>
    public static readonly DependencyProperty CaptionProperty = Reg<string?>(nameof(Caption), null);
    /// <summary>The match's actual spawns (GFSPAWNED): the latest round numbered in spawn order, earlier ones faded.</summary>
    public static readonly DependencyProperty LiveEventsProperty = Reg<IList<SpawnEvent>?>(nameof(LiveEvents), null);
    /// <summary>Draw every marker's number next to it.</summary>
    public static readonly DependencyProperty ShowNumbersProperty = Reg<bool>(nameof(ShowNumbers), false);
    /// <summary>Draw the objectives every scanned mode kept (bomb sites, DOM flags, Hardpoint / Control zones, CTF flags).</summary>
    public static readonly DependencyProperty ShowObjectivesProperty = Reg<bool>(nameof(ShowObjectives), true);
    public static readonly DependencyProperty ArtAlignProperty = DependencyProperty.Register(nameof(ArtAlign), typeof(ArtAlign), typeof(SpawnPlot),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.BindsTwoWayByDefault));

    public SpawnAtlas? Atlas { get => (SpawnAtlas?)GetValue(AtlasProperty); set => SetValue(AtlasProperty, value); }
    public string Layer { get => (string)GetValue(LayerProperty); set => SetValue(LayerProperty, value); }
    public SpawnLayout? Layout { get => (SpawnLayout?)GetValue(LayoutProperty); set => SetValue(LayoutProperty, value); }
    public IList<SpawnArea>? Areas { get => (IList<SpawnArea>?)GetValue(AreasProperty); set => SetValue(AreasProperty, value); }
    public bool ShowAreas { get => (bool)GetValue(ShowAreasProperty); set => SetValue(ShowAreasProperty, value); }
    public int Rotation { get => (int)GetValue(RotationProperty); set => SetValue(RotationProperty, value); }
    public bool NorthUp { get => (bool)GetValue(NorthUpProperty); set => SetValue(NorthUpProperty, value); }
    public ImageSource? Art { get => (ImageSource?)GetValue(ArtProperty); set => SetValue(ArtProperty, value); }
    public double ArtOpacity { get => (double)GetValue(ArtOpacityProperty); set => SetValue(ArtOpacityProperty, value); }
    public bool AlignMode { get => (bool)GetValue(AlignModeProperty); set => SetValue(AlignModeProperty, value); }
    public string? Caption { get => (string?)GetValue(CaptionProperty); set => SetValue(CaptionProperty, value); }
    public IList<SpawnEvent>? LiveEvents { get => (IList<SpawnEvent>?)GetValue(LiveEventsProperty); set => SetValue(LiveEventsProperty, value); }
    public bool ShowNumbers { get => (bool)GetValue(ShowNumbersProperty); set => SetValue(ShowNumbersProperty, value); }
    public bool ShowObjectives { get => (bool)GetValue(ShowObjectivesProperty); set => SetValue(ShowObjectivesProperty, value); }
    public ArtAlign? ArtAlign { get => (ArtAlign?)GetValue(ArtAlignProperty); set => SetValue(ArtAlignProperty, value); }

    private static DependencyProperty Reg<T>(string name, T def, bool reset = false) =>
        DependencyProperty.Register(name, typeof(T), typeof(SpawnPlot), new FrameworkPropertyMetadata(def, FrameworkPropertyMetadataOptions.AffectsRender,
            reset ? (d, _) => ((SpawnPlot)d).ResetView() : null));

    // ── paint ──
    private static SolidColorBrush B(uint argb) { var b = new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb)); b.Freeze(); return b; }
    private static Pen P(Brush b, double w, bool dash = false) { var p = new Pen(b, w); if (dash) p.DashStyle = new DashStyle(new double[] { 4, 3 }, 0); p.Freeze(); return p; }
    private static readonly Brush Bg = B(0xFF0B0D14), GridBr = B(0x14FFFFFF), GridLbl = B(0x60A0A8C8), Dim = B(0x40FFFFFF),
        SideA = B(0xFF7AB4FF), SideB = B(0xFFFF8A7A), SideE = B(0xFFB4B4C8), Both = B(0xFFF0F0FF),
        HaloA = B(0xFF00B4FF), HaloB = B(0xFFFF3B4E), AreaBr = B(0x90FFD60A), HostBr = B(0xFF2EC653),
        Text = B(0xFFDCE4FF), TextDim = B(0xFF7880A0), TipBg = B(0xF0141720), TipBd = B(0xFF252840), Shadow = B(0xA0000000),
        AlignBr = B(0xFFFFD60A);
    private static readonly Pen GridPen = P(GridBr, 1), AreaPen = P(AreaBr, 1, true), HaloPenA = P(HaloA, 2.2), HaloPenB = P(HaloB, 2.2),
        LinkPen = P(B(0x90FFFFFF), 1.2, true), TipPen = P(TipBd, 1), HostPen = P(HostBr, 1.6), CenterPen = P(B(0x90DCE4FF), 1.2),
        AreaPickA = P(HaloA, 1.6, true), AreaPickB = P(HaloB, 1.6, true), ShadowPen = P(Shadow, 3), AlignPen = P(AlignBr, 1.4, true);
    private static readonly Typeface Face = new("Segoe UI");
    private static readonly Brush LiveA = B(0xFF3D9BFF), LiveB = B(0xFFFF4D5E), LiveE = B(0xFFD0D0DC), White = B(0xFFFFFFFF), UsedBr = B(0xE6FFFFFF);
    private static readonly Pen UsedPen = P(UsedBr, 1.6), LiveRim = P(B(0xE0000000), 1.6);
    private static readonly Brush ObjBr = B(0xFFFFB020), ObjFill = B(0x30FFB020), ObjEnt = B(0xFFC8A0FF);
    private static readonly Pen ObjPen = P(ObjBr, 1.8), ObjRing = P(ObjBr, 1.2, true), ObjEntPen = P(ObjEnt, 1.4);

    // ── view state ──
    private double _zoom = 1;
    private Vector _pan;
    private Point? _dragFrom;
    private Vector _panAtDrag;
    private ArtAlign? _alignAtDrag;
    private Point? _mouse;
    // the base fit + the turn (recomputed each render)
    private double _scale = 1, _minx, _maxy, _ox, _oy, _theta, _cos = 1, _sin;

    public SpawnPlot() { ClipToBounds = true; Cursor = Cursors.Cross; }

    public void ResetView() { _zoom = 1; _pan = new Vector(); InvalidateVisual(); }

    /// <summary>The turn applied to the world: north up (90° - the map's north yaw) when known, plus the quarter turns.</summary>
    private double ThetaDeg()
    {
        var ny = Atlas?.NorthYaw;
        return (NorthUp && ny.HasValue ? 90 - ny.Value : 0) + 90 * Rotation;
    }

    private (double X, double Y) Rot(double x, double y) => (x * _cos - y * _sin, x * _sin + y * _cos);

    private Point ToScreen(double x, double y)
    {
        var (rx, ry) = Rot(x, y);
        var bx = _ox + (rx - _minx) * _scale;
        var by = _oy + (_maxy - ry) * _scale;
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        return new Point(cx + (bx - cx) * _zoom + _pan.X, cy + (by - cy) * _zoom + _pan.Y);
    }

    /// <summary>Screen -> the turned world frame (for the grid).</summary>
    private (double X, double Y) ToRot(Point s)
    {
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        var bx = cx + (s.X - cx - _pan.X) / _zoom;
        var by = cy + (s.Y - cy - _pan.Y) / _zoom;
        return (_minx + (bx - _ox) / _scale, _maxy - (by - _oy) / _scale);
    }

    /// <summary>A screen-space drag -> the world-space delta.</summary>
    private (double X, double Y) ScreenDeltaToWorld(Vector d)
    {
        var k = 1 / Math.Max(1e-9, _scale * _zoom);
        double rx = d.X * k, ry = -d.Y * k;                      // turned frame (y up)
        return (rx * _cos + ry * _sin, -rx * _sin + ry * _cos);  // undo the turn
    }

    private void Fit(SpawnAtlas a)
    {
        _theta = ThetaDeg() * Math.PI / 180;
        _cos = Math.Cos(_theta); _sin = Math.Sin(_theta);
        double minx = double.MaxValue, maxx = double.MinValue, miny = double.MaxValue, maxy = double.MinValue;
        void Add(double x, double y)
        {
            var (rx, ry) = Rot(x, y);
            minx = Math.Min(minx, rx); maxx = Math.Max(maxx, rx); miny = Math.Min(miny, ry); maxy = Math.Max(maxy, ry);
        }
        foreach (var p in a.AllPoints) Add(p.X, p.Y);
        foreach (var g in a.Groups) Add(g.X, g.Y);
        foreach (var o in a.Objectives) Add(o.X, o.Y);
        if (a.Host is { Length: >= 2 } h) Add(h[0], h[1]);
        if (minx == double.MaxValue && a.Frame() is { } f) { Add(f.NWx, f.NWy); Add(f.SEx, f.SEy); Add(f.NEx, f.NEy); Add(f.SWx, f.SWy); }
        if (minx == double.MaxValue) { minx = -1000; maxx = 1000; miny = -1000; maxy = 1000; }
        // a margin so the points do not sit on the edge (the picture fills around them)
        var mx = (maxx - minx) * 0.06 + 150; var my = (maxy - miny) * 0.06 + 150;
        minx -= mx; maxx += mx; miny -= my; maxy += my;
        var w = Math.Max(1, maxx - minx);
        var hh = Math.Max(1, maxy - miny);
        const double pad = 12;
        var W = Math.Max(10, ActualWidth - 2 * pad);
        var H = Math.Max(10, ActualHeight - 2 * pad);
        _scale = Math.Min(W / w, H / hh);
        _minx = minx; _maxy = maxy;
        _ox = pad + (W - w * _scale) / 2;
        _oy = pad + (H - hh * _scale) / 2;
    }

    // ── the picture ──
    /// <summary>The picture's north-west, north-east and south-west corners in the world: the game's minimap
    /// frame (else a box around the points at the picture's aspect), moved / scaled / turned by ArtAlign.</summary>
    private (Point NW, Point NE, Point SW)? ArtCorners(SpawnAtlas a, double imgW, double imgH)
    {
        MinimapFrame f;
        if (a.Frame() is { } fr) f = fr;
        else
        {
            var pts = a.AllPoints.ToList();
            if (pts.Count == 0) return null;
            double x0 = pts.Min(p => p.X), x1 = pts.Max(p => p.X), y0 = pts.Min(p => p.Y), y1 = pts.Max(p => p.Y);
            double cx0 = (x0 + x1) / 2, cy0 = (y0 + y1) / 2, w = Math.Max(500, (x1 - x0) * 1.7), h = Math.Max(500, (y1 - y0) * 1.7);
            var aspect = imgW / Math.Max(1, imgH);
            if (w / h < aspect) w = h * aspect; else h = w / aspect;
            f = new MinimapFrame(cx0 - w / 2, cy0 + h / 2, cx0 + w / 2, cy0 + h / 2, cx0 - w / 2, cy0 - h / 2, cx0 + w / 2, cy0 - h / 2, 90);
        }
        var al = ArtAlign ?? new ArtAlign();
        var ny = f.NorthYaw * Math.PI / 180;
        double nx = Math.Cos(ny), nyv = Math.Sin(ny);      // north
        double ex = nyv, ey = -nx;                          // east = -west
        double cx = (f.NWx + f.SEx) / 2, cy = (f.NWy + f.SEy) / 2;
        var r = al.Rot * Math.PI / 180;
        double c = Math.Cos(r) * al.Scale, s = Math.Sin(r) * al.Scale;
        Point T(double x, double y)
        {
            double vx = x - cx, vy = y - cy;
            return new Point(cx + vx * c - vy * s + ex * al.Dx + nx * al.Dy, cy + vx * s + vy * c + ey * al.Dx + nyv * al.Dy);
        }
        return (T(f.NWx, f.NWy), T(f.NEx, f.NEy), T(f.SWx, f.SWy));
    }

    private void DrawArt(DrawingContext dc, SpawnAtlas a)
    {
        if (Art is not { } img) return;
        double w = img.Width, h = img.Height;
        if (w <= 0 || h <= 0 || ArtCorners(a, w, h) is not { } k) return;
        var s0 = ToScreen(k.NW.X, k.NW.Y);
        var s1 = ToScreen(k.NE.X, k.NE.Y);
        var s2 = ToScreen(k.SW.X, k.SW.Y);
        var m = new Matrix((s1.X - s0.X) / w, (s1.Y - s0.Y) / w, (s2.X - s0.X) / h, (s2.Y - s0.Y) / h, s0.X, s0.Y);
        dc.PushTransform(new MatrixTransform(m));
        dc.PushOpacity(Math.Clamp(ArtOpacity, 0.05, 1));
        dc.DrawImage(img, new Rect(0, 0, w, h));
        dc.Pop();
        dc.Pop();
        if (AlignMode)
        {
            var s3 = new Point(s1.X + s2.X - s0.X, s1.Y + s2.Y - s0.Y);
            var g = new StreamGeometry();
            using (var c = g.Open()) { c.BeginFigure(s0, false, true); c.LineTo(s1, true, false); c.LineTo(s3, true, false); c.LineTo(s2, true, false); }
            g.Freeze();
            dc.DrawGeometry(null, AlignPen, g);
        }
    }

    // ── input ──
    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        var mods = Keyboard.Modifiers;
        if (AlignMode && Art != null && (mods & (ModifierKeys.Control | ModifierKeys.Shift)) != 0)
        {
            var al = (ArtAlign ?? new ArtAlign()).Copy();
            var fine = (mods & ModifierKeys.Alt) != 0;
            if ((mods & ModifierKeys.Control) != 0) al.Scale *= e.Delta > 0 ? (fine ? 1.002 : 1.02) : 1 / (fine ? 1.002 : 1.02);
            else al.Rot += (e.Delta > 0 ? 1 : -1) * (fine ? 0.1 : 0.5);
            SetCurrentValue(ArtAlignProperty, al);
            e.Handled = true;
            return;
        }
        var s = e.GetPosition(this);
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        var bx = cx + (s.X - cx - _pan.X) / _zoom;
        var by = cy + (s.Y - cy - _pan.Y) / _zoom;
        var z = Math.Clamp(_zoom * (e.Delta > 0 ? 1.2 : 1 / 1.2), 0.5, 60);
        _pan = new Vector(s.X - cx - (bx - cx) * z, s.Y - cy - (by - cy) * z);
        _zoom = z;
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2) { ResetView(); return; }
        _dragFrom = e.GetPosition(this);
        _panAtDrag = _pan;
        _alignAtDrag = AlignMode && Art != null ? (ArtAlign ?? new ArtAlign()).Copy() : null;
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        _dragFrom = null;
        _alignAtDrag = null;
        ReleaseMouseCapture();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var p = e.GetPosition(this);
        if (_dragFrom is { } f)
        {
            if (_alignAtDrag is { } at && Atlas != null)
            {
                // move the picture: the drag in world units, split along the map's east / north
                var (wx, wy) = ScreenDeltaToWorld(p - f);
                var ny = (Atlas.Frame()?.NorthYaw ?? 90) * Math.PI / 180;
                double nx = Math.Cos(ny), nyv = Math.Sin(ny), ex = nyv, ey = -nx;
                var al = at.Copy();
                al.Dx += wx * ex + wy * ey;
                al.Dy += wx * nx + wy * nyv;
                SetCurrentValue(ArtAlignProperty, al);
            }
            else _pan = _panAtDrag + (p - f);
        }
        _mouse = p;
        InvalidateVisual();
    }

    protected override void OnMouseLeave(MouseEventArgs e) { _mouse = null; InvalidateVisual(); }

    // ── render ──
    protected override void OnRender(DrawingContext dc)
    {
        var rect = new Rect(0, 0, ActualWidth, ActualHeight);
        dc.DrawRectangle(Bg, null, rect);
        var a = Atlas;
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        if (a == null)
        {
            Label(dc, "no atlas for this map yet", new Point(16, 16), 13, TextDim, dpi);
            return;
        }
        Fit(a);
        DrawArt(dc, a);
        if (Art == null) DrawGrid(dc, dpi);

        // every point, dim: the map's shape
        foreach (var p in a.AllPoints) dc.DrawEllipse(Dim, null, ToScreen(p.X, p.Y), 1.8, 1.8);

        var layer = Layer ?? "all";
        var tick = _scale * _zoom > 0.06;   // yaw ticks once the points spread out a bit
        if (layer == "all")
        {
            foreach (var p in a.Markers) Marker(dc, p, SideBrush(p.Side), p.Start, tick || p.Start);
            foreach (var p in a.Named) Square(dc, p, SideBrush(p.Side), SpawnNames.Info(p.Name).Start);
            foreach (var p in a.GroupPoints) Diamond(dc, p, SideBrush(p.Side));
        }
        else if (layer == "named")
        {
            foreach (var p in a.Named) Square(dc, p, SideBrush(p.Side), SpawnNames.Info(p.Name).Start);
        }
        else if (layer == "groups")
        {
            foreach (var p in a.GroupPoints) Diamond(dc, p, SideBrush(p.Side));
            foreach (var g in a.Groups)
            {
                var s = ToScreen(g.X, g.Y);
                var br = SideBrush(g.Side);
                dc.DrawGeometry(null, P(br, 1.4), DiamondGeo(s, 8));
                Label(dc, "G" + g.Id, new Point(s.X + 9, s.Y - 8), 10, br, dpi);
            }
        }
        else if (layer == "hq")
        {
            foreach (var p in a.Markers.Where(p => p.Hq)) Marker(dc, p, SideBrush(p.Side), true, true);
        }
        else if (layer.StartsWith("list:", StringComparison.Ordinal))
        {
            var name = layer[5..];
            var l1 = a.Lists.FirstOrDefault(l => l.Name == name && l.Side == 1);
            var l2 = a.Lists.FirstOrDefault(l => l.Name == name && l.Side == 2);
            var s1 = l1?.Members.ToHashSet() ?? new HashSet<int>();
            var s2 = l2?.Members.ToHashSet() ?? new HashSet<int>();
            foreach (var p in a.Markers)
            {
                var in1 = s1.Contains(p.Index); var in2 = s2.Contains(p.Index);
                if (!in1 && !in2) continue;
                Marker(dc, p, in1 && in2 ? Both : in1 ? SideA : SideB, p.Start, tick);
            }
            foreach (var (l, br) in new[] { (l1, SideA), (l2, SideB) })
                if (l != null) foreach (var v in l.Extra) dc.DrawEllipse(br, null, ToScreen(v[0], v[1]), 3.5, 3.5);
        }
        else
        {
            var m = SpawnModes.ByKey(layer);
            if (m != null) foreach (var p in a.Markers.Where(m.In)) Marker(dc, p, SideBrush(p.Side), p.Start, tick || p.Start);
        }

        // every marker's number (the index the in-game feed's "near mp_spawn_point#N" and the hover use)
        if (ShowNumbers)
            foreach (var p in a.Markers)
            {
                var s = ToScreen(p.X, p.Y);
                Label(dc, p.Index.ToString(CultureInfo.InvariantCulture), new Point(s.X + 5, s.Y - 13), 9, TextDim, dpi);
            }

        // objectives: every scanned mode's (a map scanned under several modes carries each one's)
        if (ShowObjectives)
            foreach (var o in a.Objectives)
            {
                var s = ToScreen(o.X, o.Y);
                if (o.Kind == "ent")
                {
                    dc.DrawRectangle(null, ObjEntPen, new Rect(s.X - 3.5, s.Y - 3.5, 7, 7));
                    continue;
                }
                if (o.Radius > 0)
                {
                    var r = Math.Max(5, o.Radius * _scale * _zoom);
                    dc.DrawEllipse(ObjFill, ObjRing, s, r, r);
                }
                dc.DrawGeometry(Shadow, ShadowPen, StarGeo(s, 9));
                dc.DrawGeometry(ObjBr, null, StarGeo(s, 8));
                var lbl = o.Short;
                if (lbl.Length > 0) Label(dc, lbl, new Point(s.X + 9, s.Y - 17), 11, ObjBr, dpi, true);
            }

        // dense areas
        if (ShowAreas && Areas != null)
            foreach (var ar in Areas)
            {
                var c = ToScreen(ar.X, ar.Y);
                var r = Math.Max(4, ar.Spec[3] * _scale * _zoom);
                dc.DrawEllipse(null, AreaPen, c, r, r);
                Label(dc, $"{ar.Id}·{ar.Points.Count}", new Point(c.X - 8, c.Y - r - 14), 10, AreaBr, dpi);
            }

        // the selected layout: halos on what the game arms, the pick areas, the link between the sides
        if (Layout is { } lay)
        {
            foreach (var p in lay.GameAPoints.Count > 0 ? lay.GameAPoints : lay.A) { var s = ToScreen(p.X, p.Y); dc.DrawEllipse(null, HaloPenA, s, 7.5, 7.5); }
            foreach (var p in lay.GameBPoints.Count > 0 ? lay.GameBPoints : lay.B) { var s = ToScreen(p.X, p.Y); dc.DrawEllipse(null, HaloPenB, s, 7.5, 7.5); }
            if (lay.Kind == "area")
            {
                foreach (var (ar, pen) in new[] { (lay.AreaA ?? (lay.A.Count > 0 ? SpawnArea.Of(0, lay.A) : null), AreaPickA), (lay.AreaB ?? (lay.B.Count > 0 ? SpawnArea.Of(0, lay.B) : null), AreaPickB) })
                {
                    if (ar == null) continue;
                    var c = ToScreen(ar.X, ar.Y);
                    var r = Math.Max(4, ar.Spec[3] * _scale * _zoom);
                    dc.DrawEllipse(null, pen, c, r, r);
                }
            }
            if (lay.A.Count > 0 && lay.B.Count > 0)
            {
                var ca = ToScreen(lay.AX, lay.AY);
                var cb = ToScreen(lay.BX, lay.BY);
                dc.DrawLine(LinkPen, ca, cb);
                Label(dc, $"{lay.Separation:0}u", new Point((ca.X + cb.X) / 2 + 6, (ca.Y + cb.Y) / 2 - 8), 11, Text, dpi);
                Label(dc, "A", new Point(ca.X - 4, ca.Y - 22), 12, HaloA, dpi, true);
                Label(dc, "B", new Point(cb.X - 4, cb.Y - 22), 12, HaloB, dpi, true);
            }
        }

        // live spawns: rings + use counts on the spots that were used, earlier rounds faded, the latest round
        // numbered in spawn order (1 = the first player to spawn), team coloured, facing ticks
        var live = LiveEvents;
        var latestRound = -1;
        long latestMatch = -1;
        if (live is { Count: > 0 })
        {
            latestMatch = live.Max(e => e.Match);
            latestRound = live.Where(e => e.Match == latestMatch).Max(e => e.Round);
            var pool = a.AllPoints.ToList();
            var uses = new Dictionary<AtlasPoint, int>();
            foreach (var e in live)
            {
                var sp = NearestSpot(pool, e);
                if (sp != null) uses[sp] = uses.GetValueOrDefault(sp) + 1;
            }
            foreach (var (sp, n) in uses)
            {
                var s = ToScreen(sp.X, sp.Y);
                dc.DrawEllipse(null, UsedPen, s, 11, 11);
                if (n > 1) Label(dc, "x" + n, new Point(s.X + 11, s.Y + 2), 10, White, dpi, true);
            }
            foreach (var e in live)
            {
                if (e.Match == latestMatch && e.Round == latestRound) continue;
                var s = ToScreen(e.X, e.Y);
                dc.PushOpacity(0.45);
                dc.DrawEllipse(LiveBrush(e.Team), LiveRim, s, 4.5, 4.5);
                dc.Pop();
            }
            foreach (var e in live)
            {
                if (e.Match != latestMatch || e.Round != latestRound) continue;
                var s = ToScreen(e.X, e.Y);
                var ang = e.Yaw * Math.PI / 180 + _theta;
                var tip = new Point(s.X + Math.Cos(ang) * 18, s.Y - Math.Sin(ang) * 18);
                dc.DrawLine(ShadowPen, s, tip);
                dc.DrawLine(P(LiveBrush(e.Team), 2), s, tip);
                dc.DrawEllipse(LiveBrush(e.Team), LiveRim, s, 8.5, 8.5);
                var num = Fmt(e.Order.ToString(CultureInfo.InvariantCulture), 10, White, dpi, true);
                dc.DrawText(num, new Point(s.X - num.Width / 2, s.Y - num.Height / 2));
            }
        }

        // map centre + the host at scan time
        if (a.MapCenter is { Length: >= 2 } mc)
        {
            var s = ToScreen(mc[0], mc[1]);
            dc.DrawLine(CenterPen, new Point(s.X - 6, s.Y), new Point(s.X + 6, s.Y));
            dc.DrawLine(CenterPen, new Point(s.X, s.Y - 6), new Point(s.X, s.Y + 6));
        }
        if (a.Host is { Length: >= 4 } h)
        {
            var s = ToScreen(h[0], h[1]);
            var ang = h[3] * Math.PI / 180 + _theta;
            var f = new Vector(Math.Cos(ang), -Math.Sin(ang));
            var n = new Vector(-f.Y, f.X);
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(s + f * 10, true, true);
                c.LineTo(s - f * 6 + n * 6, true, false);
                c.LineTo(s - f * 6 - n * 6, true, false);
            }
            g.Freeze();
            dc.DrawGeometry(null, HostPen, g);
            Label(dc, "you (at scan)", new Point(s.X + 10, s.Y + 4), 10, HostBr, dpi);
        }

        // hover: an objective, else a spawn (the latest round first), else a spot
        var hoverDone = false;
        if (ShowObjectives && _mouse is { } om && _dragFrom == null && a.Objectives.Count > 0)
        {
            AtlasObjective? bo = null;
            var bdo = 121.0;
            foreach (var o in a.Objectives)
            {
                var d = (ToScreen(o.X, o.Y) - om).LengthSquared;
                if (d < bdo) { bdo = d; bo = o; }
            }
            if (bo != null)
            {
                var ft = Fmt(bo.Describe(), 11, Text, dpi, false);
                var box = new Rect(om.X + 14, om.Y + 12, ft.Width + 14, ft.Height + 10);
                if (box.Right > ActualWidth - 4) box.X = om.X - box.Width - 14;
                if (box.Bottom > ActualHeight - 4) box.Y = om.Y - box.Height - 12;
                dc.DrawRoundedRectangle(TipBg, TipPen, box, 5, 5);
                dc.DrawText(ft, new Point(box.X + 7, box.Y + 5));
                hoverDone = true;
            }
        }
        if (!hoverDone && _mouse is { } hm && _dragFrom == null && live is { Count: > 0 })
        {
            SpawnEvent? be = null;
            var bde = 144.0;
            foreach (var e in live)
            {
                var d = (ToScreen(e.X, e.Y) - hm).LengthSquared;
                if (d >= bde) continue;
                var cur = e.Match == latestMatch && e.Round == latestRound;
                var beCur = be != null && be.Match == latestMatch && be.Round == latestRound;
                if (cur || !beCur) { bde = d; be = e; }
            }
            if (be != null)
            {
                var sp = NearestSpot(a.AllPoints.ToList(), be);
                var ft = Fmt(be.Describe(sp), 11, Text, dpi, false);
                var box = new Rect(hm.X + 14, hm.Y + 12, ft.Width + 14, ft.Height + 10);
                if (box.Right > ActualWidth - 4) box.X = hm.X - box.Width - 14;
                if (box.Bottom > ActualHeight - 4) box.Y = hm.Y - box.Height - 12;
                dc.DrawRoundedRectangle(TipBg, TipPen, box, 5, 5);
                dc.DrawText(ft, new Point(box.X + 7, box.Y + 5));
                hoverDone = true;
            }
        }
        if (!hoverDone && _mouse is { } mouse && _dragFrom == null)
        {
            AtlasPoint? best = null;
            var bd = 100.0;
            foreach (var p in a.AllPoints)
            {
                var s = ToScreen(p.X, p.Y);
                var d = (s - mouse).LengthSquared;
                if (d < bd) { bd = d; best = p; }
            }
            if (best != null)
            {
                var s = ToScreen(best.X, best.Y);
                dc.DrawEllipse(null, P(Text, 1.4), s, 9, 9);
                var ft = Fmt(best.Describe(), 11, Text, dpi, false);
                var box = new Rect(mouse.X + 14, mouse.Y + 12, ft.Width + 14, ft.Height + 10);
                if (box.Right > ActualWidth - 4) box.X = mouse.X - box.Width - 14;
                if (box.Bottom > ActualHeight - 4) box.Y = mouse.Y - box.Height - 12;
                dc.DrawRoundedRectangle(TipBg, TipPen, box, 5, 5);
                dc.DrawText(ft, new Point(box.X + 7, box.Y + 5));
            }
        }

        // compass: which way the in-game map's north is on this plot
        {
            var ny = a.NorthYaw;
            var up = new Point(ActualWidth - 26, 30);
            var ang = (ny ?? 90) * Math.PI / 180 + _theta;
            var v = new Vector(Math.Cos(ang), -Math.Sin(ang));
            dc.DrawLine(P(Text, 1.6), up - v * 12, up + v * 12);
            dc.DrawEllipse(Text, null, up + v * 12, 2.5, 2.5);
            Label(dc, ny.HasValue ? "N" : "+Y", new Point(up.X + v.X * 22 - 5, up.Y + v.Y * 22 - 8), 11, Text, dpi, true);
        }
        if (Caption is { Length: > 0 } cap)
        {
            var ft = Fmt(cap, 15, Text, dpi, false);
            var box = new Rect(10, 10, ft.Width + 20, ft.Height + 14);
            dc.DrawRoundedRectangle(TipBg, TipPen, box, 6, 6);
            dc.DrawText(ft, new Point(20, 17));
        }
        if (AlignMode) Label(dc, "ALIGN PICTURE: drag = move · Ctrl+wheel = scale · Shift+wheel = turn · add Alt = fine", new Point(12, ActualHeight - 24), 11, AlignBr, dpi, true);
    }

    private void DrawGrid(DrawingContext dc, double dpi)
    {
        var unitsPer100 = 100 / Math.Max(1e-6, _scale * _zoom);
        var step = new[] { 100.0, 250, 500, 1000, 2000, 5000, 10000 }.FirstOrDefault(s => s >= unitsPer100, 10000);
        var (x0, y1) = ToRot(new Point(0, 0));
        var (x1, y0) = ToRot(new Point(ActualWidth, ActualHeight));
        if (x1 < x0) (x0, x1) = (x1, x0);
        if (y1 < y0) (y0, y1) = (y1, y0);
        double cx = ActualWidth / 2, cy = ActualHeight / 2;
        for (var gx = Math.Ceiling(x0 / step) * step; gx <= x1 && gx - x0 < step * 400; gx += step)
        {
            var sx = cx + (_ox + (gx - _minx) * _scale - cx) * _zoom + _pan.X;
            dc.DrawLine(GridPen, new Point(sx, 0), new Point(sx, ActualHeight));
        }
        for (var gy = Math.Ceiling(y0 / step) * step; gy <= y1 && gy - y0 < step * 400; gy += step)
        {
            var sy = cy + (_oy + (_maxy - gy) * _scale - cy) * _zoom + _pan.Y;
            dc.DrawLine(GridPen, new Point(0, sy), new Point(ActualWidth, sy));
        }
        var px = step * _scale * _zoom;
        var y = ActualHeight - 14;
        dc.DrawLine(P(GridLbl, 2), new Point(12, y), new Point(12 + px, y));
        Label(dc, $"{step:0} units (grid)", new Point(16 + px, y - 8), 10, GridLbl, dpi);
    }

    private SolidColorBrush SideBrush(int side) => (SolidColorBrush)(side == 1 ? SideA : side == 2 ? SideB : SideE);
    private static Brush LiveBrush(int team) => team == 1 ? LiveA : team == 2 ? LiveB : LiveE;

    /// <summary>The scanned spot a spawn landed on: the nearest within 48u across and 72u up/down, else null.</summary>
    private static AtlasPoint? NearestSpot(List<AtlasPoint> pool, SpawnEvent e)
    {
        AtlasPoint? best = null;
        var bd = 48.0 * 48.0;
        foreach (var p in pool)
        {
            if (Math.Abs(p.Z - e.Z) > 72) continue;
            var d = p.Dist2(e.X, e.Y);
            if (d <= bd) { bd = d; best = p; }
        }
        return best;
    }

    // every glyph gets a dark rim so it reads on the light parts of the map art too
    private void Marker(DrawingContext dc, AtlasPoint p, Brush br, bool start, bool tick)
    {
        var s = ToScreen(p.X, p.Y);
        if (tick) YawTick(dc, s, p.Yaw, br, start ? 11 : 8);
        if (start) dc.DrawEllipse(br, ShadowPen, s, 4.8, 4.8);
        else { dc.DrawEllipse(null, ShadowPen, s, 3.4, 3.4); dc.DrawEllipse(null, P(br, 1.5), s, 3.4, 3.4); }
    }

    private void Square(DrawingContext dc, AtlasPoint p, Brush br, bool start)
    {
        var s = ToScreen(p.X, p.Y);
        YawTick(dc, s, p.Yaw, br, 10);
        var r = new Rect(s.X - 4.5, s.Y - 4.5, 9, 9);
        dc.DrawRectangle(null, ShadowPen, r);
        dc.DrawRectangle(start ? br : null, start ? null : P(br, 1.4), r);
    }

    private void Diamond(DrawingContext dc, AtlasPoint p, Brush br)
    {
        var s = ToScreen(p.X, p.Y);
        YawTick(dc, s, p.Yaw, br, 10);
        dc.DrawGeometry(null, ShadowPen, DiamondGeo(s, 5));
        dc.DrawGeometry(br, null, DiamondGeo(s, 5));
    }

    /// <summary>A five-point star (an objective).</summary>
    private static Geometry StarGeo(Point s, double r)
    {
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            for (var i = 0; i < 10; i++)
            {
                var rr = i % 2 == 0 ? r : r * 0.45;
                var ang = -Math.PI / 2 + i * Math.PI / 5;
                var pt = new Point(s.X + Math.Cos(ang) * rr, s.Y + Math.Sin(ang) * rr);
                if (i == 0) c.BeginFigure(pt, true, true); else c.LineTo(pt, true, false);
            }
        }
        g.Freeze();
        return g;
    }

    private static Geometry DiamondGeo(Point s, double r)
    {
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            c.BeginFigure(new Point(s.X, s.Y - r), true, true);
            c.LineTo(new Point(s.X + r, s.Y), true, false);
            c.LineTo(new Point(s.X, s.Y + r), true, false);
            c.LineTo(new Point(s.X - r, s.Y), true, false);
        }
        g.Freeze();
        return g;
    }

    private void YawTick(DrawingContext dc, Point s, int yaw, Brush br, double len)
    {
        var ang = yaw * Math.PI / 180 + _theta;
        var e = new Point(s.X + Math.Cos(ang) * len, s.Y - Math.Sin(ang) * len);
        dc.DrawLine(ShadowPen, s, e);
        dc.DrawLine(P(br, 1.3), s, e);
    }

    private FormattedText Fmt(string text, double size, Brush br, double dpi, bool bold) =>
        new(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, bold ? new Typeface(Face.FontFamily, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal) : Face, size, br, dpi);

    private void Label(DrawingContext dc, string text, Point at, double size, Brush br, double dpi, bool bold = false)
    {
        dc.DrawText(Fmt(text, size, Shadow, dpi, bold), new Point(at.X + 1, at.Y + 1));
        dc.DrawText(Fmt(text, size, br, dpi, bold), at);
    }

    // ── export ──
    /// <summary>This plot as a PNG at <paramref name="scale"/>x its on-screen size (no hover box).</summary>
    public void SavePng(string path, double scale = 2)
    {
        var w = Math.Max(1, (int)(ActualWidth * scale));
        var h = Math.Max(1, (int)(ActualHeight * scale));
        var hover = _mouse;
        _mouse = null;
        var rtb = new RenderTargetBitmap(w, h, 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen()) OnRender(dc);
        rtb.Render(dv);
        _mouse = hover;
        Encode(rtb, path);
    }

    /// <summary>An off-screen plot of one map (the "save every map" export).</summary>
    public static void SaveOffscreen(string path, int width, int height, SpawnAtlas atlas, ImageSource? art, ArtAlign? align, string layer, SpawnLayout? layout, bool northUp)
    {
        var caption = $"{Catalog.MapName(atlas.Map)}  ({atlas.Map}) - every spawn point, scanned {atlas.Captured:yyyy-MM-dd}"
                      + (layout != null ? $"\nhighlighted: {layout.Source}{(layout.Tag.Length > 0 ? "  [" + layout.Tag + "]" : "")} - {layout.Metrics}" : "")
                      + "\nfilled = start  ·  hollow = mid-match respawn  ·  blue = allies side  ·  red = axis side  ·  grey = either  ·  ■ BO2-named  ·  ◆ S&D group  ·  ★ objective";
        var p = new SpawnPlot { Atlas = atlas, Art = art, ArtAlign = align, Layer = layer, Layout = layout, ShowAreas = false, NorthUp = northUp, ArtOpacity = 0.95, Caption = caption };
        p.Measure(new Size(width, height));
        p.Arrange(new Rect(0, 0, width, height));
        p.UpdateLayout();
        var rtb = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(p);
        Encode(rtb, path);
    }

    private static void Encode(BitmapSource bmp, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using var fs = File.Create(path);
        enc.Save(fs);
    }
}
