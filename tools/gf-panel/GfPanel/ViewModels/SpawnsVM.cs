using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows.Media;
using System.Windows.Threading;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

public sealed class SpawnMapItem : ObservableObject
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    private bool _has, _pick, _cur;
    public bool HasAtlas { get => _has; set { if (Set(ref _has, value)) OnPropertyChanged(nameof(Display)); } }
    public bool HasPick { get => _pick; set { if (Set(ref _pick, value)) OnPropertyChanged(nameof(Display)); } }
    public bool IsCurrent { get => _cur; set { if (Set(ref _cur, value)) OnPropertyChanged(nameof(Display)); } }
    public string Display => (IsCurrent ? "▶ " : "") + Name + "   " + Id + (HasAtlas ? "" : "   · not scanned") + (HasPick ? "   · PICK" : "");
    public override string ToString() => Display;
}

public sealed class LayerItem
{
    public string Key { get; init; } = "";
    public string Label { get; init; } = "";
    public override string ToString() => Label;
}

public sealed class InfoRow
{
    public string Label { get; init; } = "";
    public string Value { get; init; } = "";
    public string Tip { get; init; } = "";
    public string Layer { get; init; } = "";
}

/// <summary>
/// The SPAWNS tab (the spawn atlas, docs/notes/spawn-atlas.md): per map, every spawn point for every mode -
/// starts and mid-match respawn pools, S&D groups, BO2-named starts, the engine's live lists - plotted top-down,
/// the dense areas found, and every start layout ranked; one click makes a layout this map's PICK (gf_sp_map
/// "&lt;map&gt;:&lt;kind&gt;" + gf_sp_a/b), which the mod uses over AUTO on that map only.
/// </summary>
public sealed class SpawnsVM : ObservableObject
{
    private readonly MainViewModel _m;
    public SpawnAtlasStore Store { get; } = new();
    public MapArtCache ArtCache { get; } = new();
    public ObservableCollection<MapArtDef> ArtChoices { get; } = new();
    private static readonly MapArtDef NoArt = new("none", "No picture (grid)");
    private readonly DispatcherTimer _alignSave;
    public ObservableCollection<SpawnMapItem> MapItems { get; } = new();
    public ObservableCollection<ModeRow> ModeRows { get; } = new();
    public ObservableCollection<SpawnLayout> Layouts { get; } = new();
    public ObservableCollection<LayerItem> Layers { get; } = new();
    public ObservableCollection<InfoRow> Extras { get; } = new();

    private string _curMap = "", _staged = "", _phase = "";
    /// <summary>The map gf_sp_map was last written for by this panel (so a deleted pick can be cleared in game).</summary>
    private string _dvarMap = "";
    private bool _scanIsAuto;

    public SpawnsVM(MainViewModel m)
    {
        _m = m;
        var have = Store.Maps();
        foreach (var d in Catalog.Maps.Where(d => d.Gametype == null).GroupBy(d => d.Id).Select(g => g.First()))
            MapItems.Add(new SpawnMapItem { Id = d.Id, Name = d.Name, HasAtlas = have.Contains(d.Id), HasPick = Store.Picks.ContainsKey(d.Id) });
        foreach (var id in have.Where(id => MapItems.All(i => i.Id != id)))
            MapItems.Add(new SpawnMapItem { Id = id, Name = id, HasAtlas = true, HasPick = Store.Picks.ContainsKey(id) });
        _m.Link.AtlasReceived += OnAtlas;
        _m.Link.SpawnEventsReceived += OnSpawnEvents;
        _m.Link.AtlasFailed += why => { ScanState = ""; _tourScanTcs?.TrySetResult(false); if (!_scanIsAuto) _m.Toasts.Show("Spawn atlas: " + why, LogLevel.Warn); };
        _alignSave = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
        _alignSave.Tick += (_, _) => { _alignSave.Stop(); SaveAlignNow(); };
        _radius = _m.Prefs.SpawnAreaRadiusSet;
        _band = _m.Prefs.SpawnAreaBand;
        _minPerSide = _m.Prefs.SpawnMinPerSide;
        Selected = MapItems.FirstOrDefault(i => i.HasAtlas) ?? MapItems.FirstOrDefault();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // selection
    // ─────────────────────────────────────────────────────────────────────────
    private SpawnMapItem? _sel;
    public SpawnMapItem? Selected { get => _sel; set { if (Set(ref _sel, value)) { Load(); OnPropertyChanged(nameof(ViewedMapText)); OnPropertyChanged(nameof(ViewingOtherMap)); } } }
    /// <summary>MATCH → SPAWN LAYOUT names the map its list is for: the atlas follows the running map unless another
    /// map was picked on the SPAWN ATLAS page.</summary>
    public string ViewedMapText => _sel == null ? "no map yet" : (_sel.IsCurrent ? "running now: " : "viewing: ") + _sel.Name + "  " + _sel.Id;
    public bool ViewingOtherMap => _sel != null && !_sel.IsCurrent && MapItems.Any(i => i.IsCurrent);
    public RelayCommand ShowRunningMap => new(() => { if (MapItems.FirstOrDefault(i => i.IsCurrent) is { } cur) Selected = cur; });

    private SpawnAtlas? _atlas;
    public SpawnAtlas? Atlas { get => _atlas; private set { Set(ref _atlas, value); OnPropertyChanged(nameof(HasAtlas)); OnPropertyChanged(nameof(NoAtlas)); } }
    public bool HasAtlas => Atlas != null;
    public bool NoAtlas => Atlas == null;

    private LayerItem? _layer;
    public LayerItem? Layer { get => _layer; set { if (Set(ref _layer, value)) OnPropertyChanged(nameof(LayerKey)); } }
    public string LayerKey => Layer?.Key ?? "all";

    private SpawnLayout? _layout;
    public SpawnLayout? SelectedLayout { get => _layout; set { if (Set(ref _layout, value)) OnPropertyChanged(nameof(LayoutWhy)); } }
    public string LayoutWhy => SelectedLayout == null ? "" : SelectedLayout.Why + "\n" + SelectedLayout.Metrics;

    private List<SpawnArea> _areas = new();
    public List<SpawnArea> Areas { get => _areas; private set => Set(ref _areas, value); }

    private bool _showAreas = true;
    public bool ShowAreas { get => _showAreas; set => Set(ref _showAreas, value); }
    private int _rotation;
    public int Rotation { get => _rotation; set => Set(ref _rotation, ((value % 4) + 4) % 4); }
    public RelayCommand Rotate => new(() => Rotation++);

    // dense-area knobs: raw text-friendly ints, clamped where they are used (a clamping setter fights typing)
    private int _radius, _band, _minPerSide;
    public int AreaRadius { get => _radius; set { if (Set(ref _radius, value)) { _m.Prefs.SpawnAreaRadiusSet = value; _m.Prefs.Save(); Recompute(); } } }
    public int AreaBand { get => _band; set { if (Set(ref _band, value)) { _m.Prefs.SpawnAreaBand = value; _m.Prefs.Save(); Recompute(); } } }
    public int MinPerSide { get => _minPerSide; set { if (Set(ref _minPerSide, value)) { _m.Prefs.SpawnMinPerSide = value; _m.Prefs.Save(); Recompute(); } } }

    public bool AutoScan { get => _m.Prefs.SpawnAutoScanOn; set { _m.Prefs.SpawnAutoScanOn = value; _m.Prefs.Save(); OnPropertyChanged(); } }

    private string _status = "", _auto = "", _live = "", _pickText = "", _scanState = "";
    public string StatusText { get => _status; private set => Set(ref _status, value); }
    public string AutoText { get => _auto; private set => Set(ref _auto, value); }
    public string LiveText { get => _live; private set => Set(ref _live, value); }
    public string PickText { get => _pickText; private set => Set(ref _pickText, value); }
    public string ScanState { get => _scanState; private set => Set(ref _scanState, value); }
    public string FolderText => Store.WriteDir;

    private int TeamSize
    {
        get
        {
            var st = _m.Link.State;
            if (_m.Link.StateFreshNow && st != null && st.TeamSize > 0) return st.TeamSize;
            return Atlas is { TeamSize: > 0 } a ? a.TeamSize : 4;
        }
    }
    private int Need => MinPerSide > 0 ? Math.Clamp(MinPerSide, 1, 32) : TeamSize;
    /// <summary>The mod's spawn system (picks, AUTO, the family, the guard) runs only in GUNFIGHT matches:
    /// mod_apply returns at its Gunfight gate before it installs the spawn hook (MEASURED 2026-09-22: a Miami pick
    /// + restart in an FFA match gave a stock spawn in the middle of the map).</summary>
    private bool RunningGunfight => (_m.Link.State?.Gametype ?? "").StartsWith("gunfight", StringComparison.OrdinalIgnoreCase);
    private string RunningGametype => _m.Link.State?.Gametype ?? "";

    /// <summary>The spawn settings block (guard, family, side pick, gap, trip distance, anti-stack, Strike, diag):
    /// moved here from ADVANCED 2026-09-22 (klaze: "merge the controls from advanced > spawns into our new tool") -
    /// the same rows, dvars, pins and apply path as every other settings block.</summary>
    public IEnumerable<SectionVM> SettingsSections => _m.Sections.Where(s => s.Tab == "spawns");

    /// <summary>The guard / family the AUTO tag was last computed with: a change from the settings block re-tags.</summary>
    private int _taggedGuard = -1, _taggedFamily = -1;

    private int LiveGuard => _m.Link.Baseline.TryGetValue("gf_spawn_guard", out var g) ? g : Atlas?.Guard ?? 2;
    private int LiveFamily => _m.Link.Baseline.TryGetValue("gf_spawn_family", out var f) ? f : Atlas?.Family ?? 8;

    /// <summary>The dense-area radius in use: the knob when set (> 0), else scaled to the map.</summary>
    private double EffectiveRadius(SpawnAtlas a) => AreaRadius > 0 ? Math.Clamp(AreaRadius, 150, 3000) : SpawnAnalysis.AutoRadius(a);

    private void Load()
    {
        Atlas = Selected == null ? null : Store.Load(Selected.Id);
        Recompute();
        RefreshArt();
        RefreshLive();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // live spawns (klaze 2026-09-22: "how can i visualize where everyone is spawning? do i add bots and the
    // visualizer will show what spots they use?"): the match's actual spawns from GFSPAWNED, per map
    // ─────────────────────────────────────────────────────────────────────────
    private readonly Dictionary<string, Dictionary<string, SpawnEvent>> _events = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTime> _eventsAt = new(StringComparer.OrdinalIgnoreCase);
    private bool _showLive = true;
    public bool ShowLive { get => _showLive; set { if (Set(ref _showLive, value)) RefreshLive(); } }
    public List<string> LiveScopes { get; } = new() { "this round", "this match", "every round seen" };
    private string _liveScope = "this round";
    public string LiveScope { get => _liveScope; set { if (Set(ref _liveScope, value)) RefreshLive(); } }
    private bool _showNumbers;
    public bool ShowNumbers { get => _showNumbers; set => Set(ref _showNumbers, value); }
    private List<SpawnEvent> _liveEvents = new();
    public List<SpawnEvent> LiveEvents { get => _liveEvents; private set => Set(ref _liveEvents, value); }
    private string _liveText = "";
    public string LiveSpawnText { get => _liveText; private set => Set(ref _liveText, value); }
    public RelayCommand ClearLive => new(() => { if (Selected != null) { _events.Remove(Selected.Id); _eventsAt.Remove(Selected.Id); } RefreshLive(); });

    private void OnSpawnEvents(string map, long match, List<SpawnEvent> evs)
    {
        if (!_events.TryGetValue(map, out var d)) _events[map] = d = new Dictionary<string, SpawnEvent>();
        foreach (var e in evs) d[e.Key] = e;
        _eventsAt[map] = DateTime.Now;
        if (string.Equals(Selected?.Id, map, StringComparison.OrdinalIgnoreCase)) RefreshLive();
    }

    private void RefreshLive()
    {
        var map = Selected?.Id;
        if (map == null || !ShowLive || !_events.TryGetValue(map, out var d) || d.Count == 0)
        {
            LiveEvents = new List<SpawnEvent>();
            LiveSpawnText = !ShowLive || map == null ? "" :
                            string.Equals(_curMap, map, StringComparison.OrdinalIgnoreCase) ? "live: waiting for the first spawn on this map (the atlas build, spawn diag on)" :
                            "live spawns show while this map is the one running";
            return;
        }
        var all = d.Values.ToList();
        var lastMatch = all.Max(e => e.Match);
        var inMatch = all.Where(e => e.Match == lastMatch).ToList();
        var round = inMatch.Max(e => e.Round);
        var cur = inMatch.Where(e => e.Round == round).ToList();
        var shown = LiveScope switch
        {
            "this match" => inMatch,
            "every round seen" => all,
            _ => cur,
        };
        LiveEvents = shown.OrderBy(e => e.Match).ThenBy(e => e.Round).ThenBy(e => e.Order).ToList();
        LiveSpawnText = $"live: round {round + 1} - {cur.Count} spawns ({cur.Count(e => e.How == 'e')} by the engine, {cur.Count(e => e.How == 'a')} on the mod's anchors, {cur.Count(e => e.How == 's')} stock)"
                        + (LiveScope != "this round" ? $" - showing {shown.Count}" : "")
                        + (_eventsAt.TryGetValue(map, out var at) ? $" - updated {at:HH:mm:ss}" : "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the map picture (klaze 2026-09-22: "are you able to digitize them on the maps?" + the gamesatlas
    // examples): the in-game tactical map from the wiki, laid on the game's minimap frame, north up
    // ─────────────────────────────────────────────────────────────────────────
    private MapArtDef? _art;
    public MapArtDef? SelectedArt { get => _art; set { if (Set(ref _art, value)) { RememberArtChoice(); LoadArt(); } } }
    private ImageSource? _artImage;
    public ImageSource? ArtImage { get => _artImage; private set => Set(ref _artImage, value); }
    private string _artStatus = "";
    public string ArtStatus { get => _artStatus; private set => Set(ref _artStatus, value); }
    private double _artOpacity = 0.9;
    public double ArtOpacity { get => _artOpacity; set => Set(ref _artOpacity, value); }
    private bool _alignMode;
    public bool AlignMode { get => _alignMode; set => Set(ref _alignMode, value); }
    private bool _northUp = true;
    public bool NorthUp { get => _northUp; set => Set(ref _northUp, value); }
    private ArtAlign? _artAlign;
    /// <summary>The picture's alignment on this map (the plot writes it back while aligning); saved 0.7 s after the last change.</summary>
    public ArtAlign? ArtAlign { get => _artAlign; set { if (Set(ref _artAlign, value)) { _alignSave.Stop(); _alignSave.Start(); } } }
    public RelayCommand ResetAlign => new(() => ArtAlign = new ArtAlign());
    public string ExportDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Gunfight spawn maps");

    private static string ArtKey(MapArtDef a) => a.Custom != null ? "custom:" + a.Custom : a.File;

    /// <summary>What the atlas shows under <paramref name="map"/>, for another plot (the RACING page's map): the atlas
    /// (its minimap frame + north), the chosen picture (else the map's first) and its saved alignment. No picture when
    /// the choice is "none" or the download fails.</summary>
    public async Task<(SpawnAtlas? Atlas, ImageSource? Art, ArtAlign? Align)> BackdropFor(string map)
    {
        SpawnAtlas? atlas = null;
        try { atlas = Store.Load(map); } catch { }
        Store.Art.Chosen.TryGetValue(map, out var chosen);
        if (chosen == NoArt.File) return (atlas, null, null);
        MapArtDef? art;
        if (chosen != null && chosen.StartsWith("custom:", StringComparison.Ordinal) && File.Exists(chosen[7..])) art = new MapArtDef("custom", "custom", chosen[7..]);
        else
        {
            var defs = MapArt.For(map).ToList();
            art = defs.FirstOrDefault(d => chosen != null && ArtKey(d) == chosen) ?? defs.FirstOrDefault();
        }
        if (art == null) return (atlas, null, null);
        try
        {
            var img = await ArtCache.GetAsync(art);
            var align = Store.Art.Align.TryGetValue(map + "|" + ArtKey(art), out var al) ? al.Copy() : new ArtAlign();
            return (atlas, img, align);
        }
        catch { return (atlas, null, null); }
    }

    private void RefreshArt()
    {
        var map = Selected?.Id;
        ArtChoices.Clear();
        if (map == null) { _art = null; OnPropertyChanged(nameof(SelectedArt)); ArtImage = null; ArtStatus = ""; return; }
        foreach (var d in MapArt.For(map)) ArtChoices.Add(d);
        Store.Art.Chosen.TryGetValue(map, out var chosen);
        if (chosen != null && chosen.StartsWith("custom:", StringComparison.Ordinal) && File.Exists(chosen[7..]))
            ArtChoices.Add(new MapArtDef("custom", "Your picture: " + Path.GetFileName(chosen[7..]), chosen[7..]));
        ArtChoices.Add(NoArt);
        _art = ArtChoices.FirstOrDefault(c => chosen != null && ArtKey(c) == chosen) ?? ArtChoices.FirstOrDefault();
        OnPropertyChanged(nameof(SelectedArt));
        LoadArt();
    }

    private void RememberArtChoice()
    {
        var map = Selected?.Id;
        if (map == null || _art == null) return;
        Store.Art.Chosen[map] = ArtKey(_art);
        try { Store.SaveArt(); } catch { }
    }

    private int _artReq;
    private async void LoadArt()
    {
        var req = ++_artReq;
        var art = _art;
        var map = Selected?.Id;
        _artAlign = map != null && art != null && Store.Art.Align.TryGetValue(map + "|" + ArtKey(art), out var al) ? al.Copy() : new ArtAlign();
        OnPropertyChanged(nameof(ArtAlign));
        if (art == null || ReferenceEquals(art, NoArt) || art.File == "none") { ArtImage = null; ArtStatus = ""; return; }
        ArtStatus = ArtCache.IsCached(art) ? "" : "downloading the map picture...";
        try
        {
            var img = await ArtCache.GetAsync(art);
            if (req != _artReq) return;
            ArtImage = img;
            ArtStatus = Atlas == null ? "" :
                        Atlas.Frame() == null ? "no minimap frame in this scan (rescan with the current build) - the picture sits around the points: Align it" :
                        _artAlign?.IsIdentity ?? true ? "placed on the game's minimap frame - if the points miss the streets, Align it once" : "minimap frame + your alignment";
        }
        catch (Exception e)
        {
            if (req != _artReq) return;
            ArtImage = null;
            ArtStatus = "picture failed: " + e.Message;
        }
    }

    private void SaveAlignNow()
    {
        var map = Selected?.Id;
        if (map == null || _art == null || _artAlign == null || ReferenceEquals(_art, NoArt)) return;
        Store.Art.Align[map + "|" + ArtKey(_art)] = _artAlign.Copy();
        try { Store.SaveArt(); } catch { }
    }

    /// <summary>Use a picture file of your own for this map (a site's layout image, a screenshot): copied into
    /// the picture folder so it stays, then aligned like the wiki art.</summary>
    public RelayCommand LoadCustomArt => new(() =>
    {
        var map = Selected?.Id;
        if (map == null) return;
        var dlg = new Microsoft.Win32.OpenFileDialog { Filter = "Pictures (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp", Title = "A map picture for " + Catalog.MapName(map) };
        if (dlg.ShowDialog() != true) return;
        try
        {
            Directory.CreateDirectory(ArtCache.Dir);
            var dest = Path.Combine(ArtCache.Dir, "custom_" + map + "_" + Path.GetFileName(dlg.FileName));
            File.Copy(dlg.FileName, dest, true);
            Store.Art.Chosen[map] = "custom:" + dest;
            Store.SaveArt();
            RefreshArt();
        }
        catch (Exception e) { _m.Toasts.Show("Could not use that picture: " + e.Message, LogLevel.Err); }
    });

    public void ImageSaved(string path) => _m.Toasts.Show("Saved " + path, LogLevel.Ok);
    public void ImageFailed(string why) => _m.Toasts.Show("Could not save the picture: " + why, LogLevel.Err);

    /// <summary>Every scanned map as a picture: its map art (the chosen one, else the gunfight layout's), every
    /// spawn point, its pick (else what AUTO runs) highlighted - into Pictures, "Gunfight spawn maps".</summary>
    public async Task SaveAllImages(Action<string, SpawnAtlas, ImageSource?, ArtAlign?, SpawnLayout?> render, bool openFolder = true)
    {
        var maps = Store.Maps().OrderBy(m => m).ToList();
        if (maps.Count == 0) { _m.Toasts.Show("No scanned maps yet", LogLevel.Warn); return; }
        var done = 0;
        foreach (var map in maps)
        {
            var a = Store.Load(map);
            if (a == null) continue;
            Store.Art.Chosen.TryGetValue(map, out var chosen);
            var choices = MapArt.For(map).ToList();
            MapArtDef? art = chosen == "none" ? null :
                chosen != null && chosen.StartsWith("custom:", StringComparison.Ordinal) && File.Exists(chosen[7..]) ? new MapArtDef("custom", "custom", chosen[7..]) :
                choices.FirstOrDefault(c => c.File == chosen) ?? choices.FirstOrDefault();
            ImageSource? img = null;
            ArtAlign? al = null;
            if (art != null)
            {
                try { img = await ArtCache.GetAsync(art); } catch { img = null; }
                al = Store.Art.Align.TryGetValue(map + "|" + ArtKey(art), out var x) ? x : null;
            }
            var areas = SpawnAnalysis.Areas(a, EffectiveRadius(a), Math.Clamp(AreaBand, 32, 2000), 3);
            var layouts = SpawnAnalysis.Layouts(a, areas, Need);
            TagLayouts(a, layouts);
            var lay = layouts.FirstOrDefault(l => l.Tag.Contains("PICK")) ?? layouts.FirstOrDefault(l => l.Tag.Contains("AUTO"));
            try { render(Path.Combine(ExportDir, map + ".png"), a, img, al, lay); done++; }
            catch (Exception e) { _m.Toasts.Show($"{map}: {e.Message}", LogLevel.Err); }
        }
        _m.Toasts.Show($"Saved {done} map pictures to {ExportDir}", LogLevel.Ok);
        if (openFolder) try { Process.Start(new ProcessStartInfo("explorer.exe", ExportDir) { UseShellExecute = true }); } catch { }
    }

    private void Recompute()
    {
        var keepLayer = Layer?.Key;
        ModeRows.Clear(); Layouts.Clear(); Layers.Clear(); Extras.Clear();
        var a = Atlas;
        if (a == null)
        {
            Areas = new List<SpawnArea>();
            SelectedLayout = null; Layer = null;
            StatusText = Selected == null ? "" : $"{Selected.Name} has not been scanned yet. Load it in a match with the atlas build and press SCAN THE MAP RUNNING NOW, turn on auto-scan, or run the SCAN TOUR (side panel) to do every map.";
            AutoText = ""; UpdateTexts();
            return;
        }

        foreach (var r in SpawnAnalysis.Modes(a)) ModeRows.Add(r);

        Layers.Add(new LayerItem { Key = "all", Label = $"Everything ({a.Markers.Count + a.Named.Count + a.GroupPoints.Count} points)" });
        foreach (var r in ModeRows) Layers.Add(new LayerItem { Key = r.Key, Label = $"{r.Label}  ({r.Markers})" });
        if (a.Named.Count > 0) Layers.Add(new LayerItem { Key = "named", Label = $"BO2-named structs ({a.Named.Count})" });
        if (a.GroupPoints.Count > 0) Layers.Add(new LayerItem { Key = "groups", Label = $"S&D spawn groups ({a.Groups.Count})" });
        if (a.Markers.Any(p => p.Hq)) Layers.Add(new LayerItem { Key = "hq", Label = $"HQ spawns ({a.Markers.Count(p => p.Hq)})" });
        foreach (var n in a.Lists.Select(l => l.Name).Distinct())
            Layers.Add(new LayerItem { Key = "list:" + n, Label = $"engine list: {n}" });
        Layer = Layers.FirstOrDefault(x => x.Key == keepLayer) ?? Layers.FirstOrDefault(x => x.Key == "tdm") ?? Layers[0];

        var radius = EffectiveRadius(a);
        var band = Math.Clamp(AreaBand, 32, 2000);
        Areas = SpawnAnalysis.Areas(a, radius, band, 3);

        var layouts = SpawnAnalysis.Layouts(a, Areas, Need);
        TagLayouts(a, layouts);
        foreach (var l in layouts) Layouts.Add(l);

        foreach (var g in a.Named.GroupBy(p => p.Name ?? "?"))
        {
            var info = SpawnNames.Info(g.Key);
            Extras.Add(new InfoRow { Label = g.Key, Value = $"{g.Count()}  ({info.Mode} {(info.Start ? "start" : "respawn")}, {(info.Side == 1 ? "allies" : info.Side == 2 ? "axis" : "either")})", Layer = "named" });
        }
        foreach (var g in a.Groups)
            Extras.Add(new InfoRow { Label = $"S&D group {g.Id} ({(g.Side == 1 ? "side A" : g.Side == 2 ? "side B" : "no side")})" + (g.Gametype.Length > 0 ? $" · under {g.Gametype}" : ""), Value = $"{a.GroupPoints.Count(q => q.Index == g.Id)} points · {g.Target} · {g.Objective}", Layer = "groups" });
        foreach (var g in a.Objectives.GroupBy(o => o.Gametype))
        {
            var named = g.Where(o => o.Kind != "ent").ToList();
            var ents = g.Count(o => o.Kind == "ent");
            var parts = named.GroupBy(o => o.KindText).Select(k => $"{k.Count()} {k.Key}{(k.Count() > 1 ? "s" : "")}" +
                        (k.Any(o => o.Short.Length > 0 && o.Short != "bomb" && o.Short != "flag") ? " (" + string.Join(" ", k.Select(o => o.Short).Where(x => x.Length > 0).Distinct()) + ")" : ""));
            Extras.Add(new InfoRow { Label = $"objectives under {(g.Key.Length > 0 ? g.Key : "?")}", Layer = "",
                Value = string.Join(" · ", parts) + (ents > 0 ? $"{(named.Count > 0 ? " · " : "")}{ents} other {g.Key} entities" : "") + (named.Count + ents == 0 ? "none" : ""),
                Tip = "What that mode kept on this map when it loaded (the ★ on the plot; hover one for its position, radius and targetname). Every other mode's objectives are deleted at load, so each mode needs its own scan - the scan tour does that." });
        }
        foreach (var n in a.Lists.Select(l => l.Name).Distinct())
        {
            var s1 = a.Lists.FirstOrDefault(l => l.Name == n && l.Side == 1);
            var s2 = a.Lists.FirstOrDefault(l => l.Name == n && l.Side == 2);
            Extras.Add(new InfoRow { Label = "engine: " + n, Value = $"{s1?.Size ?? 0} allies · {s2?.Size ?? 0} axis", Layer = "list:" + n,
                Tip = $"The engine's live '{n}' list under {a.Gametype} (read per team with function_82061144). start_spawn = where stock opens; auto_normal = the mid-match respawn pool." });
        }

        SelectedLayout = Layouts.FirstOrDefault(l => l.Tag.Contains("PICK")) ?? Layouts.FirstOrDefault(l => l.Tag.Contains("AUTO")) ?? Layouts.FirstOrDefault();
        UpdateTexts();
    }

    /// <summary>AUTO = what runs on this map with no pick (live guard / family); PICK = this map's saved pick
    /// (an area pick that matches no listed layout gets its own row).</summary>
    private void TagLayouts(SpawnAtlas a, List<SpawnLayout> layouts)
    {
        var guard = LiveGuard;
        _taggedGuard = guard; _taggedFamily = LiveFamily;
        if (guard != 0)
        {
            var (ea, eb, _) = SpawnAnalysis.EngineStarts(a);
            SpawnLayout? auto = null;
            if (guard == 2 && ea > 0 && eb > 0) auto = layouts.FirstOrDefault(l => l.Kind == "stock");
            else
            {
                var fam = LiveFamily == 8 ? SpawnAnalysis.AutoFamily(a, TeamSize) : LiveFamily;
                auto = layouts.FirstOrDefault(l => l.Kind == "family" && l.Family == fam && l.A.Count >= 2 && l.B.Count >= 2);
            }
            if (auto != null) auto.Tag = "AUTO";
        }

        if (!Store.Picks.TryGetValue(a.Map, out var pk)) return;
        SpawnLayout? hit = pk.Kind switch
        {
            10 => layouts.FirstOrDefault(l => l.Kind == "stock"),
            9 => layouts.FirstOrDefault(l => l.Kind == "area" && l.ToPick() is var p && p.A != null && p.B != null && pk.A != null && pk.B != null && p.A.SequenceEqual(pk.A) && p.B.SequenceEqual(pk.B)),
            _ => layouts.FirstOrDefault(l => l.Kind == "family" && l.Family == pk.Kind),
        };
        if (hit == null && pk.Kind == 9 && pk.A != null && pk.B != null)
        {
            var pool = a.PickPool();
            List<AtlasPoint> In(int[] s) => pool.Where(p => Math.Abs(p.Z - s[2]) <= s[4] && p.Dist2(s[0], s[1]) <= (double)s[3] * s[3]).ToList();
            var A = In(pk.A); var B = In(pk.B);
            hit = new SpawnLayout
            {
                Source = "Saved pick: " + pk.Label, Why = "the areas saved for this map (the dense-area settings have changed since)",
                Kind = "area", A = A, B = B, AreaA = SpawnArea.Of(0, A.Count > 0 ? A : new List<AtlasPoint> { new() { X = pk.A[0], Y = pk.A[1], Z = pk.A[2] } }),
                AreaB = SpawnArea.Of(0, B.Count > 0 ? B : new List<AtlasPoint> { new() { X = pk.B[0], Y = pk.B[1], Z = pk.B[2] } }),
                GameAPoints = A, GameBPoints = B,
            };
            layouts.Insert(0, hit);
        }
        if (hit != null) hit.Tag = hit.Tag.Length > 0 ? "PICK · " + hit.Tag : "PICK";
    }

    private void UpdateTexts()
    {
        var a = Atlas;
        if (a != null && (LiveGuard != _taggedGuard || LiveFamily != _taggedFamily)) { Recompute(); return; }
        if (a != null)
        {
            StatusText = $"{Catalog.MapName(a.Map)} · scanned under {a.ScannedModes} (last {a.Captured:yyyy-MM-dd HH:mm}) · {a.Markers.Count} markers · {a.Named.Count} named · {a.Objectives.Count} objectives · " +
                         $"{a.Groups.Count} S&D groups ({a.GroupPoints.Count} pts) · {a.Lists.Count} engine lists · {Areas.Count} dense areas (r {EffectiveRadius(a):0}{(AreaRadius > 0 ? "" : ", auto")})";
            AutoText = SpawnAnalysis.Predict(a, LiveGuard, LiveFamily, TeamSize);
        }
        var st = _m.Link.State;
        if (a != null && st != null && _m.Link.StateFreshNow && st.Map == a.Map && !RunningGunfight)
            AutoText = $"This match is {st.Gametype}, not Gunfight: the mod's spawn system is OFF here - {st.Gametype}'s own spawns place everyone (picks, AUTO and the guard run only in Gunfight matches). In a Gunfight match on this map: " + AutoText;
        LiveText = st == null || !_m.Link.StateFreshNow ? "no match running" :
                   a != null && st.Map == a.Map && !RunningGunfight ? $"{st.Gametype} match - the mod's spawns are off outside Gunfight · {(st.SpawnNote.Length > 0 ? st.SpawnNote : "-")}" :
                   a != null && st.Map != a.Map ? $"running now: {Catalog.MapName(st.Map)} (not this map) · {(st.SpawnNote.Length > 0 ? st.SpawnNote : "—")}" :
                   st.SpawnNote.Length > 0 ? st.SpawnNote : "the injected build does not report its spawn source (older than the atlas build)";
        PickText = a != null && Store.Picks.TryGetValue(a.Map, out var pk)
            ? $"PICK for this map: {pk.Label}  ({pk.KindText}, saved {pk.At:g})"
            : "No pick for this map - AUTO decides.";
    }

    private void RefreshItems()
    {
        var have = Store.Maps();
        foreach (var it in MapItems) { it.HasAtlas = have.Contains(it.Id); it.HasPick = Store.Picks.ContainsKey(it.Id); }
    }

    private SpawnMapItem EnsureItem(string map)
    {
        var it = MapItems.FirstOrDefault(i => i.Id == map);
        if (it != null) return it;
        it = new SpawnMapItem { Id = map, Name = Catalog.MapName(map) };
        MapItems.Add(it);
        return it;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the game
    // ─────────────────────────────────────────────────────────────────────────
    public void OnState(GfState? s)
    {
        if (s == null)
        {
            foreach (var it in MapItems) it.IsCurrent = false;
            _curMap = "";
            UpdateTexts();
            return;
        }
        if (s.Map.Length > 0 && s.Map != _curMap)
        {
            var prev = _curMap;
            _curMap = s.Map;
            var cur = EnsureItem(s.Map);
            foreach (var it in MapItems) it.IsCurrent = it.Id == s.Map;
            if (Selected == null || Selected.Id == prev || !Selected.HasAtlas) Selected = cur;
            OnPropertyChanged(nameof(ViewedMapText)); OnPropertyChanged(nameof(ViewingOtherMap));
            OnMapLoaded(s.Map);
        }
        // the match is over and a map is staged for the next one: its pick goes in now (the current map no
        // longer needs the slot), so the next level's first round already spawns on it
        if (s.Phase != _phase)
        {
            _phase = s.Phase;
            if (_phase == "ended" && s.StagedMap.Length > 0) PrePush(s.StagedMap);
        }
        _staged = s.StagedMap;
        UpdateTexts();
    }

    private void OnMapLoaded(string map)
    {
        if (Store.Picks.TryGetValue(map, out var pk)) Push(map, pk, true, "map loaded");
        else if (_dvarMap == map) { _m.Link.Send($"Spawns {Catalog.MapName(map)}: stale pick cleared", Commands.Action("spawnpick", "clear"), 4); _dvarMap = ""; }
        if (AutoScan && Store.Load(map) == null) AutoScanLater(map);
    }

    private async void AutoScanLater(string map)
    {
        await Task.Delay(8000);
        if (TourRunning || _curMap != map || !_m.Link.StateFreshNow || Store.Load(map) != null || _m.Link.AtlasPending) return;
        ScanMap(map, true);
    }

    /// <summary>Before a Switch NOW from the panel: write the target map's pick so its first round already uses it.</summary>
    public void PrePush(string map)
    {
        if (Store.Picks.TryGetValue(map, out var pk)) Push(map, pk, false, "before the switch");
        else if (_dvarMap == map) { _ = _m.Link.SendRaw(new[] { "set gf_sp_map \"\"" }, 4); _dvarMap = ""; }
    }

    private void Push(string map, SpawnPick pk, bool verb, string why)
    {
        _dvarMap = map;
        var lines = pk.Lines(map);
        if (verb) _m.Link.Send($"Spawns {Catalog.MapName(map)}: {pk.Label} ({why})", lines.Concat(Commands.Action("spawnpick", "apply")), 4);
        else _ = _m.Link.SendRaw(lines, 4);
    }

    private void ScanMap(string map, bool auto)
    {
        _scanIsAuto = auto;
        _m.Link.Send((auto ? "Spawn atlas (auto): scan " : "Spawn atlas: scan ") + Catalog.MapName(map), Commands.Action("spawnscan"), 4);
        _m.Link.RequestAtlas(map);
        ScanState = $"scanning {Catalog.MapName(map)}…";
    }

    private void OnAtlas(SpawnAtlas a)
    {
        ScanState = "";
        _tourScanTcs?.TrySetResult(true);
        try { Store.Save(a); }
        catch (Exception e) { _m.Toasts.Show("Spawn atlas: could not save - " + e.Message, LogLevel.Err); }
        EnsureItem(a.Map);
        RefreshItems();
        if (Selected?.Id == a.Map) Load();
        else if (Selected == null || Selected.Id == _curMap) Selected = MapItems.FirstOrDefault(i => i.Id == a.Map);
        _m.Toasts.Show($"Spawn atlas: {Catalog.MapName(a.Map)} filed - {a.Markers.Count} markers, {a.Named.Count} named, {a.Groups.Count} groups", LogLevel.Ok);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // commands
    // ─────────────────────────────────────────────────────────────────────────
    public RelayCommand Scan => new(() =>
    {
        var st = _m.Link.State;
        if (st == null || !_m.Link.StateFreshNow || st.Map.Length == 0) { _m.Toasts.Show("No match running - load a map (with the atlas build injected) first", LogLevel.Warn); return; }
        if (_m.Link.AtlasPending) { _m.Toasts.Show("A scan is already on its way", LogLevel.Info); return; }
        ScanMap(st.Map, false);
    });

    public RelayCommand UsePick => new(() => Use(false));
    public RelayCommand UsePickRestart => new(() => Use(true));

    private void Use(bool restart)
    {
        var a = Atlas; var l = SelectedLayout;
        if (a == null || l == null) { _m.Toasts.Show("Pick a start layout in the list first", LogLevel.Warn); return; }
        if (Math.Min(l.GameA, l.GameB) == 0) { _m.Toasts.Show("That layout arms no point on one side in game - pick another", LogLevel.Warn); return; }
        var pk = l.ToPick();
        pk.Label = l.Source.StartsWith("Saved pick: ") ? l.Source["Saved pick: ".Length..] : l.Source;
        pk.At = DateTime.Now;
        Store.Picks[a.Map] = pk;
        try { Store.SavePicks(); } catch (Exception e) { _m.Toasts.Show("Could not save the pick: " + e.Message, LogLevel.Err); }
        if (LiveGuard == 0) _m.Toasts.Show("Saved - but the spawn guard is OFF: picks only run with the guard on (AUTO)", LogLevel.Warn);
        if (_curMap == a.Map && _m.Link.StateFreshNow && !RunningGunfight)
        {
            // stored + sent anyway (it arms the next Gunfight match on this map), but no restart: it cannot take effect here
            Push(a.Map, pk, true, "picked");
            _m.Toasts.Show($"Saved for {Catalog.MapName(a.Map)} - but this match is {RunningGametype}: the mod's spawns (picks, AUTO) only run in GUNFIGHT matches, so {RunningGametype}'s own spawns stay. It applies when you play Gunfight on this map.", LogLevel.Warn);
        }
        else if (_curMap == a.Map && _m.Link.StateFreshNow)
        {
            Push(a.Map, pk, true, "picked");
            if (restart)
            {
                if (_m.Confirm($"Restart the ROUND now so everyone spawns on '{pk.Label}'?\n\nmap_restart(true): scores and round count kept.")) _m.Link.Send("Restart round", Commands.Action("restartround"));
            }
            else _m.Toasts.Show($"Pick sent: {pk.Label} - the next spawns use it (next round, or Restart round)", LogLevel.Ok);
        }
        else _m.Toasts.Show($"Saved for {Catalog.MapName(a.Map)} - sent when that map loads (from the next round) or before a Switch NOW to it", LogLevel.Ok);
        RefreshItems();
        Recompute();
    }

    public RelayCommand ClearPick => new(() =>
    {
        var a = Atlas;
        if (a == null || !Store.Picks.ContainsKey(a.Map)) { _m.Toasts.Show("This map has no pick", LogLevel.Info); return; }
        Store.Picks.Remove(a.Map);
        try { Store.SavePicks(); } catch { }
        if (_curMap == a.Map && _m.Link.StateFreshNow) _m.Link.Send($"Spawns {Catalog.MapName(a.Map)}: pick cleared - back to AUTO", Commands.Action("spawnpick", "clear"), 4);
        else if (_dvarMap == a.Map) _ = _m.Link.SendRaw(new[] { "set gf_sp_map \"\"" }, 4);
        if (_dvarMap == a.Map) _dvarMap = "";
        RefreshItems();
        Recompute();
    });

    private bool _showObjectives = true;
    public bool ShowObjectives { get => _showObjectives; set => Set(ref _showObjectives, value); }

    // ─────────────────────────────────────────────────────────────────────────
    // the scan tour (klaze 2026-09-22 "yes" to: switch through every map on its own and scan each): per map
    // Switch NOW (the session switch, one-shot) -> wait for GFSTATE to show it loaded under the mode -> settle
    // 8 s -> spawnscan -> wait for the atlas -> next. ~1 min a map. Run it once per mode (Gunfight, S&D ...):
    // the scans merge per map.
    // ─────────────────────────────────────────────────────────────────────────
    public IReadOnlyList<Named> TourGametypes => Catalog.Gametypes;
    private Named? _tourGt = Catalog.Gametypes.FirstOrDefault(g => g.Value == "gunfight");
    public Named? TourGametype { get => _tourGt; set => Set(ref _tourGt, value); }
    public List<string> TourScopes { get; } = new() { "maps not yet scanned in this mode", "every MP map", "6v6 maps", "Gunfight maps" };
    private string _tourScope = "maps not yet scanned in this mode";
    public string TourScope { get => _tourScope; set => Set(ref _tourScope, value); }
    private bool _tourRunning;
    public bool TourRunning { get => _tourRunning; private set { if (Set(ref _tourRunning, value)) OnPropertyChanged(nameof(TourIdle)); } }
    public bool TourIdle => !TourRunning;
    private string _tourStatus = "";
    public string TourStatus { get => _tourStatus; private set => Set(ref _tourStatus, value); }
    public ObservableCollection<string> TourLog { get; } = new();
    private CancellationTokenSource? _tourCts;
    private TaskCompletionSource<bool>? _tourScanTcs;

    public RelayCommand StartTour => new(async () => await RunTour());
    public RelayCommand StopTour => new(() => { _tourCts?.Cancel(); TourStatus = "stopping after this step..."; });

    private bool ScannedIn(string map, string gt)
    {
        var a = Store.Load(map);
        if (a == null) return false;
        return a.Scans.Count > 0 ? a.Scans.Any(x => SpawnAtlas.SameMode(x.Gametype, gt)) : SpawnAtlas.SameMode(a.Gametype, gt);
    }

    private bool _tourReturn = true;
    /// <summary>When the tour is done, Switch NOW back to the map + mode that was running when it started.</summary>
    public bool TourReturn { get => _tourReturn; set => Set(ref _tourReturn, value); }

    private List<string> TourMaps(string gt)
    {
        IEnumerable<MapDef> defs = Catalog.Maps.Where(d => d.Gametype == null && (d.Group == "6v6" || d.Group == "Gunfight"));
        defs = TourScope switch
        {
            "6v6 maps" => defs.Where(d => d.Group == "6v6"),
            "Gunfight maps" => defs.Where(d => d.Group == "Gunfight"),
            _ => defs,
        };
        var maps = defs.Select(d => d.Id).Distinct().ToList();
        if (TourScope == "maps not yet scanned in this mode") maps = maps.Where(m => !ScannedIn(m, gt)).ToList();
        // the map already running first (no switch), then by name
        return maps.OrderBy(m => m == _curMap ? 0 : 1).ThenBy(Catalog.MapName).ToList();
    }

    private static async Task<bool> WaitFor(Func<bool> cond, TimeSpan timeout, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed < timeout)
        {
            ct.ThrowIfCancellationRequested();
            if (cond()) return true;
            await Task.Delay(500, ct);
        }
        return cond();
    }

    /// <summary>The running level is <paramref name="map"/> under <paramref name="gt"/> (Gunfight 3v3 = Gunfight) and the mod reports from it.</summary>
    private bool RunningNow(string map, string gt, bool loadedOnly)
    {
        var s = _m.Link.State;
        return s != null && _m.Link.StateFreshNow && s.Map == map && SpawnAtlas.SameMode(s.Gametype, gt)
               && (!loadedOnly || s.Phase == "prematch" || s.Phase == "playing");
    }

    private async Task<bool> TourSwitch(string map, string gt, string why, CancellationToken ct)
    {
        PrePush(map);
        _m.Link.Send($"Scan tour: {why} {Catalog.MapName(map)} / {gt}", Commands.Switch(map, gt, false));
        return await WaitFor(() => RunningNow(map, gt, true), TimeSpan.FromSeconds(150), ct);
    }

    private async Task RunTour()
    {
        if (TourRunning) return;
        var gt = TourGametype?.Value ?? "gunfight";
        var st0 = _m.Link.State;
        if (st0 == null || !_m.Link.StateFreshNow) { _m.Toasts.Show("Start a match first (any map, the atlas build injected) - the tour switches maps from inside a match", LogLevel.Warn); return; }
        var maps = TourMaps(gt);
        if (maps.Count == 0) { _m.Toasts.Show($"Nothing to scan: every map in that set is already scanned under {gt}", LogLevel.Info); return; }
        var (homeMap, homeGt) = (st0.Map, st0.Gametype);
        if (!_m.Confirm($"Scan tour: {maps.Count} map(s) under {gt}?\n\nThe panel switches the session to each map in turn (Switch NOW - everyone in the lobby follows), waits for it to load, scans it and moves on: about a minute a map. A map that does not load under {gt} within 150 s is skipped; two in a row stop the tour." +
                        (TourReturn ? $"\n\nAt the end it switches back to {Catalog.MapName(homeMap)} / {homeGt}." : "") + "\n\nStop any time.")) return;

        _tourCts = new CancellationTokenSource();
        var ct = _tourCts.Token;
        TourRunning = true;
        TourLog.Clear();
        int ok = 0, skipped = 0, missedLoads = 0;
        var why = "";
        try
        {
            for (var i = 0; i < maps.Count; i++)
            {
                ct.ThrowIfCancellationRequested();
                var map = maps[i];
                var name = Catalog.MapName(map);
                if (!RunningNow(map, gt, false))
                {
                    TourStatus = $"{i + 1}/{maps.Count} {name}: switching...";
                    if (!await TourSwitch(map, gt, "switch to", ct))
                    {
                        skipped++;
                        TourLog.Insert(0, $"x {name}: did not load under {gt} in 150 s - skipped");
                        // the mod answers from every level it runs on: two silent levels in a row = it is not
                        // answering any more (payload gone, game stuck in a load) - waiting 150 s a map is pointless
                        if (++missedLoads >= 2) { why = " - two maps in a row never reported: is the game stuck, or the payload no longer injected?"; break; }
                        continue;
                    }
                }
                missedLoads = 0;
                TourStatus = $"{i + 1}/{maps.Count} {name}: settling...";
                await Task.Delay(8000, ct);
                TourStatus = $"{i + 1}/{maps.Count} {name}: scanning...";
                var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                _tourScanTcs = tcs;
                ScanMap(map, true);
                var first = await Task.WhenAny(tcs.Task, Task.Delay(40000, ct));
                _tourScanTcs = null;
                if (first == tcs.Task && tcs.Task.Result) { ok++; TourLog.Insert(0, $"ok {name} ({gt})"); }
                else { skipped++; TourLog.Insert(0, $"x {name}: the scan did not come back"); }
            }
            if (TourReturn && !RunningNow(homeMap, homeGt, false) && why.Length == 0)
            {
                TourStatus = $"back to {Catalog.MapName(homeMap)} / {homeGt}...";
                if (!await TourSwitch(homeMap, homeGt, "back to", ct)) TourLog.Insert(0, $"x the switch back to {Catalog.MapName(homeMap)} / {homeGt} did not report in 150 s");
            }
        }
        catch (OperationCanceledException) { }
        finally
        {
            _tourScanTcs = null;
            TourRunning = false;
            TourStatus = $"tour {(ct.IsCancellationRequested ? "stopped" : why.Length > 0 ? "halted" : "done")}: {ok} scanned, {skipped} skipped (under {gt}){why}";
            if (why.Length > 0) _m.Toasts.Show("Scan tour halted" + why, LogLevel.Warn);
            RefreshItems();
        }
    }

    // clicking a mode row / a named-group-list row shows that layer on the plot
    private ModeRow? _modeRow;
    public ModeRow? SelectedModeRow { get => _modeRow; set { if (Set(ref _modeRow, value) && value != null) Layer = Layers.FirstOrDefault(x => x.Key == value.Key) ?? Layer; } }
    private InfoRow? _extra;
    public InfoRow? SelectedExtra { get => _extra; set { if (Set(ref _extra, value) && value != null && value.Layer.Length > 0) Layer = Layers.FirstOrDefault(x => x.Key == value.Layer) ?? Layer; } }

    public RelayCommand OpenFolder => new(() =>
    {
        try { System.IO.Directory.CreateDirectory(Store.WriteDir); Process.Start(new ProcessStartInfo("explorer.exe", Store.WriteDir) { UseShellExecute = true }); } catch { }
    });

}
