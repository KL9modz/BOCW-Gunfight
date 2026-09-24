using System.Collections.ObjectModel;
using System.IO;
using System.Windows.Media;
using System.Windows.Threading;
using GfPanel.Game;
using GfPanel.Services;
using Microsoft.Win32;

namespace GfPanel.ViewModels;

/// <summary>One line of the RACING page's standings.</summary>
public sealed record StandingRow(string Place, string Name, string Progress, string Time, bool IsHost, bool Finished, bool OffTrack);

/// <summary>
/// The RACING page (2026-09-24). klaze: "a race track editor and viewer so I can create, save, and load race
/// tracks ... mostly from driving them in game while referencing the live viewer/editor". The game owns the track
/// (gunfight_menu.gsc: 64 gates, packed 4 to a dvar); this page mirrors it live (GFTRACK) with every player on the
/// map (GFRACE), and its edits go to the game - racegset (move / turn / width, coalesced per gate), racegins,
/// racegdel, racegmov, racegrot, racegrev - and come back in the game's next GFTRACK. The race controls and the
/// saved-track library (TracksService, race-tracks.json) live here too.
/// </summary>
public sealed class RaceVM : ObservableObject
{
    private readonly MainViewModel _m;
    private readonly DispatcherTimer _flush, _verify;
    private readonly Dictionary<int, RaceGate> _pending = new();
    private DateTime _editedAt = DateTime.MinValue;
    private RaceTrack? _track;

    public RaceVM(MainViewModel m)
    {
        _m = m;
        _flush = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        _flush.Tick += (_, _) => FlushEdits();
        // after an edit, read the game's track back even when its version did not move (a refused edit)
        _verify = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
        _verify.Tick += (_, _) => { _verify.Stop(); _m.Link.RequestTrack(); };
        _m.Link.TrackReceived += OnTrack;
        _m.Link.RaceLiveReceived += OnLive;
        _m.Tracks.Changed += RefreshLibrary;
        foreach (var d in new[] { "gf_race_width", "gf_race_corridor", "gf_race_grid_gap", "gf_race_sprint", "gf_race_laps" })
            if (_m.Setting(d) is { } row) row.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(SettingRowVM.Value)) OnSettings(); };
        RefreshLibrary();
    }

    private bool _active;
    /// <summary>The RACING page is showing (MainWindow): the game publishes the live line only then.</summary>
    public bool IsActive
    {
        get => _active;
        set
        {
            if (!Set(ref _active, value)) return;
            _m.Link.WantRace = value;
            if (value) { LoadBackdrop(); RefreshLibrary(); }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the race settings the map draws with (RACE SETTINGS rows, the same objects)
    // ─────────────────────────────────────────────────────────────────────────
    private int SettingValue(string dvar, int def) => _m.Setting(dvar)?.Value ?? def;
    public bool Sprint => SettingValue("gf_race_sprint", 0) == 1;
    public int Laps => SettingValue("gf_race_laps", 1);
    public double CorridorWidth => SettingValue("gf_race_corridor", 1600);
    public int GridGap => SettingValue("gf_race_grid_gap", 220);
    private void OnSettings()
    {
        foreach (var n in new[] { nameof(Sprint), nameof(Laps), nameof(CorridorWidth), nameof(GridGap), nameof(SelTitle) }) OnPropertyChanged(n);
        UpdateTrackStatus();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the map: which one, and the picture the atlas placed on it
    // ─────────────────────────────────────────────────────────────────────────
    /// <summary>The map the track is on: the game's track, else the running map.</summary>
    public string Map => _track is { Map.Length: > 0 } t ? t.Map : _m.Link.State?.Map ?? "";
    public MinimapFrame? Frame { get; private set; }
    public double? NorthYaw { get; private set; }
    public ImageSource? ArtImage { get; private set; }
    public ArtAlign? ArtAlign { get; private set; }
    private string _backdropMap = "";
    private string _backdropNote = "";
    public string BackdropNote { get => _backdropNote; private set => Set(ref _backdropNote, value); }
    /// <summary>The view asks the map to fit (a new map, a first track, the Fit button).</summary>
    public event Action? FitRequested;
    public RelayCommand Fit => new(() => FitRequested?.Invoke());

    private async void LoadBackdrop()
    {
        var map = Map;
        if (map.Length == 0 || map == _backdropMap) return;
        _backdropMap = map;
        RefreshLibrary();
        var (atlas, art, align) = await _m.Spawns.BackdropFor(map);
        if (map != _backdropMap) return;
        Frame = atlas?.Frame(); NorthYaw = atlas?.NorthYaw; ArtImage = art; ArtAlign = align;
        foreach (var n in new[] { nameof(Frame), nameof(NorthYaw), nameof(ArtImage), nameof(ArtAlign) }) OnPropertyChanged(n);
        BackdropNote = atlas == null ? $"No spawn scan of {map} yet - the track sits on a plain grid. Scan the map once (MAPS & SPAWNS → SPAWN ATLAS) for its picture, north up."
                     : art == null ? "No map picture (none chosen on the SPAWN ATLAS, or the download failed) - a plain grid."
                     : "";
        FitRequested?.Invoke();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the track: the game's copy + edits on their way to it
    // ─────────────────────────────────────────────────────────────────────────
    private List<RaceGate> _gates = new();
    /// <summary>What the map draws. Always a new list, never changed in place (the plot redraws on a new reference).</summary>
    public List<RaceGate> Gates
    {
        get => _gates;
        private set { _gates = value; OnPropertyChanged(); UpdateTrackStatus(); NotifySel(); }
    }
    private DateTime? _syncedAt;
    private string _trackStatus = "No track read from the game yet.";
    public string TrackStatus { get => _trackStatus; private set => Set(ref _trackStatus, value); }

    private void UpdateTrackStatus() =>
        TrackStatus = _syncedAt == null ? "No track read from the game yet - is the RACING build injected and a match running?"
            : $"{Map}  ·  {_gates.Count}/{RaceTrack.MaxGates} gates  ·  {(Sprint ? "A to B" : $"circuit, {Laps} lap{(Laps == 1 ? "" : "s")}")}  ·  read {_syncedAt:HH:mm:ss}";

    private void OnTrack(RaceTrack t)
    {
        var newMap = _track == null || !string.Equals(_track.Map, t.Map, StringComparison.OrdinalIgnoreCase);
        var wasEmpty = _gates.Count == 0;
        _track = t;
        _syncedAt = DateTime.Now;
        OnPropertyChanged(nameof(Map));
        OnPropertyChanged(nameof(Ghost));
        // an edit still on its way: keep drawing it (the verify re-read after it lands brings the game's truth)
        if (_pending.Count == 0 && DateTime.UtcNow - _editedAt >= TimeSpan.FromSeconds(1.2)) Gates = t.Gates.ToList();
        else UpdateTrackStatus();
        LoadBackdrop();
        if (newMap || (wasEmpty && _gates.Count > 0)) FitRequested?.Invoke();
    }

    // ── selection + the side panel's fields ──
    private int _sel = -1;
    public int SelectedGate
    {
        get => _sel;
        set { var v = value >= 0 && value < _gates.Count ? value : -1; if (Set(ref _sel, v)) NotifySel(); }
    }
    private void NotifySel()
    {
        if (_sel >= _gates.Count) _sel = -1;
        foreach (var n in new[] { nameof(SelectedGate), nameof(HasSelection), nameof(SelTitle), nameof(SelX), nameof(SelY), nameof(SelYaw), nameof(SelW) }) OnPropertyChanged(n);
    }
    public bool HasSelection => _sel >= 0 && _sel < _gates.Count;
    private RaceGate? Sel => HasSelection ? _gates[_sel] : null;
    public string SelTitle => !HasSelection ? "No gate selected - click one on the map"
        : _sel == 0 ? (Sprint ? "Gate 0 - the start line" : "Gate 0 - start / finish")
        : Sprint && _sel == _gates.Count - 1 ? $"Gate {_sel} - the finish" : $"Gate {_sel} of {_gates.Count - 1}";
    public int SelX { get => Sel?.X ?? 0; set { if (Sel is { } g && g.X != value) SetGate(_sel, g with { X = value }); } }
    public int SelY { get => Sel?.Y ?? 0; set { if (Sel is { } g && g.Y != value) SetGate(_sel, g with { Y = value }); } }
    public int SelYaw { get => Sel?.Yaw ?? 0; set { if (Sel is { } g && g.Yaw != Game.RaceGate.NormYaw(value)) SetGate(_sel, g with { Yaw = Game.RaceGate.NormYaw(value) }); } }
    public int SelW { get => Sel?.W ?? 0; set { if (Sel is { } g && g.W != Game.RaceGate.ClampWidth(value)) SetGate(_sel, g with { W = Game.RaceGate.ClampWidth(value) }); } }

    // ── view toggles ──
    private bool _editMode, _follow, _corridor = true, _names = true, _grid = true;
    /// <summary>Mouse and keyboard edits on the map (the buttons always edit).</summary>
    public bool EditMode { get => _editMode; set => Set(ref _editMode, value); }
    public bool FollowHost { get => _follow; set => Set(ref _follow, value); }
    public bool ShowCorridor { get => _corridor; set => Set(ref _corridor, value); }
    public bool ShowNames { get => _names; set => Set(ref _names, value); }
    public bool ShowGrid { get => _grid; set => Set(ref _grid, value); }

    // ─────────────────────────────────────────────────────────────────────────
    // edits: the plot's (TrackEdit) and the side panel's buttons
    // ─────────────────────────────────────────────────────────────────────────
    public RelayCommand Edit => new(p => { if (p is TrackEdit e) Apply(e); });

    private void Apply(TrackEdit e)
    {
        switch (e.Kind)
        {
            case TrackEditKind.Select: SelectedGate = e.Index; break;
            case TrackEditKind.Set when e.Gate != null: SetGate(e.Index, e.Gate); break;
            case TrackEditKind.Insert: InsertAt(e.Index, e.X, e.Y); break;
            case TrackEditKind.Delete: DeleteAt(e.Index); break;
        }
    }

    /// <summary>The game refuses track changes while a race runs, and there is no track without a game: say so.</summary>
    private bool CanEdit()
    {
        if (Live is { State: 1 or 2 }) { _m.Toasts.Show("Stop the race to change the track", LogLevel.Warn); return false; }
        if (!_m.Link.GameRunning && !App.DryRun) { _m.Toasts.Show("No game running - the track lives in the game", LogLevel.Warn); return false; }
        return true;
    }

    /// <summary>Move / turn / widen one gate: drawn at once, sent 0.35 s after the last change to it (a drag or a held
    /// key would otherwise send a command per step - the bridge takes one every ~0.3 s).</summary>
    private void SetGate(int i, RaceGate g)
    {
        if (i < 0 || i >= _gates.Count || !CanEdit()) return;
        var list = _gates.ToList();
        list[i] = g;
        Gates = list;
        _pending[i] = g;
        _editedAt = DateTime.UtcNow;
        _flush.Stop(); _flush.Start();
    }

    private void FlushEdits()
    {
        _flush.Stop();
        if (_pending.Count == 0) return;
        foreach (var (i, g) in _pending.OrderBy(k => k.Key))
            _m.Link.Send($"Gate {i}: {g.X},{g.Y} yaw {g.Yaw} width {g.W}", Commands.Action("racegset", RaceArgs.Edit(i, g)));
        _pending.Clear();
        Sent();
    }

    private void Sent()
    {
        _editedAt = DateTime.UtcNow;
        _verify.Stop(); _verify.Start();
    }

    /// <summary>An index-shifting edit: the coalesced ones go first so the indices it names still hold.</summary>
    private void Structural(string label, List<string> lines, List<RaceGate> local, int select)
    {
        FlushEdits();
        _m.Link.Send(label, lines);
        Gates = local;
        SelectedGate = select;
        Sent();
    }

    private void InsertAt(int after, double x, double y)
    {
        if (!CanEdit()) return;
        if (_gates.Count >= RaceTrack.MaxGates) { _m.Toasts.Show($"{RaceTrack.MaxGates} gates is the limit", LogLevel.Warn); return; }
        var at = after < 0 || after >= _gates.Count ? _gates.Count : after + 1;
        var prev = at > 0 ? _gates[at - 1] : null;
        var next = at < _gates.Count ? _gates[at] : (!Sprint && _gates.Count > 1 ? _gates[0] : null);
        var host = Dots.FirstOrDefault(d => d.IsHost);
        var yaw = prev != null && next != null ? Game.RaceGate.YawTo(prev.X, prev.Y, next.X, next.Y)
                : prev != null ? Game.RaceGate.YawTo(prev.X, prev.Y, x, y)
                : next != null ? Game.RaceGate.YawTo(x, y, next.X, next.Y)
                : host?.Yaw ?? 0;
        var g = new RaceGate((int)Math.Round(x), (int)Math.Round(y), prev?.Z ?? next?.Z ?? 0, yaw, Game.RaceGate.ClampWidth(SettingValue("gf_race_width", 600)));
        var list = _gates.ToList();
        list.Insert(at, g);
        Structural($"Insert gate {at}", Commands.Action("racegins", RaceArgs.Edit(at, g)), list, at);
    }

    private void DeleteAt(int i)
    {
        if (i < 0 || i >= _gates.Count || !CanEdit()) return;
        var list = _gates.ToList();
        list.RemoveAt(i);
        Structural($"Delete gate {i}", Commands.Action("racegdel", i.ToString()), list, Math.Min(i, list.Count - 1));
    }

    private void MoveOrder(int delta)
    {
        if (!HasSelection || !CanEdit()) return;
        var i = _sel;
        var j = i + delta;
        if (j < 0 || j >= _gates.Count) return;
        var list = _gates.ToList();
        var g = list[i];
        list.RemoveAt(i);
        list.Insert(j, g);
        Structural($"Gate {i} → {j}", Commands.Action("racegmov", RaceArgs.Move(i, j)), list, j);
    }

    public RelayCommand DeleteGate => new(() => { if (HasSelection) DeleteAt(_sel); });
    /// <summary>A gate after the selected one, halfway to the next (or 800 u on along the course at the end).</summary>
    public RelayCommand InsertAfter => new(() =>
    {
        if (!HasSelection) { _m.Toasts.Show("Select the gate to insert after", LogLevel.Info); return; }
        var g = _gates[_sel];
        var next = _sel + 1 < _gates.Count ? _gates[_sel + 1] : (!Sprint && _gates.Count > 1 ? _gates[0] : null);
        var f = g.Fwd;
        if (next != null) InsertAt(_sel, (g.X + next.X) / 2.0, (g.Y + next.Y) / 2.0);
        else InsertAt(_sel, g.X + f.X * 800, g.Y + f.Y * 800);
    });
    public RelayCommand GateEarlier => new(() => MoveOrder(-1));
    public RelayCommand GateLater => new(() => MoveOrder(1));
    public RelayCommand FlipGate => new(() => { if (Sel is { } g) SetGate(_sel, g.Turned(180)); });
    public RelayCommand TurnLeft => new(p => { if (Sel is { } g) SetGate(_sel, g.Turned(Step(p, 15))); });
    public RelayCommand TurnRight => new(p => { if (Sel is { } g) SetGate(_sel, g.Turned(-Step(p, 15))); });
    public RelayCommand Wider => new(() => { if (Sel is { } g) SetGate(_sel, g.Widened(100)); });
    public RelayCommand Narrower => new(() => { if (Sel is { } g) SetGate(_sel, g.Widened(-100)); });
    private static int Step(object? p, int def) => p is string s && int.TryParse(s, out var v) ? v : def;
    /// <summary>The selected gate becomes the start: the circuit rotates round (racegrot).</summary>
    public RelayCommand MakeStart => new(() =>
    {
        if (!HasSelection || _sel == 0 || !CanEdit()) return;
        var i = _sel;
        var list = _gates.Skip(i).Concat(_gates.Take(i)).ToList();
        Structural($"Gate {i} is the start", Commands.Action("racegrot", i.ToString()), list, 0);
    });
    /// <summary>The course the other way round: gate 0 stays the start, the rest reversed and turned (racegrev).</summary>
    public RelayCommand ReverseTrack => new(() =>
    {
        if (_gates.Count < 2 || !CanEdit() || !_m.Confirm($"Run the whole course the other way ({_gates.Count} gates)?")) return;
        var list = new List<RaceGate> { _gates[0].Turned(180) };
        for (var k = _gates.Count - 1; k >= 1; k--) list.Add(_gates[k].Turned(180));
        Structural("Reverse the course", Commands.Action("racegrev"), list, 0);
    });

    // ── the in-game track commands (were SANDBOX → RACE) ──
    private void Do(string label, string verb, string? arg = null) => _m.Link.Send(label, Commands.Action(verb, arg));
    public RelayCommand RaceGate => new(() => Do("Gate here", "race", "gate"));
    public RelayCommand RaceUndo => new(() => Do("Undo last gate", "race", "undo"));
    public RelayCommand RaceClear => new(() => { if (_m.Confirm($"Clear the game's track ({_gates.Count} gates)? Save it first to keep it.")) Do("Clear track", "race", "clear"); });
    public RelayCommand RaceLoad => new(() => Do("Load the game's saved track", "race", "load"));
    public RelayCommand RaceMarkers => new(() => Do("Gate markers show/hide", "race", "markers"));
    public RelayCommand RaceResetMe => new(() => Do("Reset me", "race", "resetme"));
    public RelayCommand RaceStart => new(() => Do("START RACE", "race", "start"));
    public RelayCommand RaceStop => new(() => Do("Stop race", "race", "stop"));
    public RelayCommand RaceEndMatch => new(() => { if (_m.Confirm("End the match now with the race standings?")) Do("END MATCH (podium)", "race", "endmatch"); });

    // ─────────────────────────────────────────────────────────────────────────
    // live: every player on the map, the standings
    // ─────────────────────────────────────────────────────────────────────────
    public RaceLive? Live { get; private set; }
    private List<RaceDot> _dots = new();
    public List<RaceDot> Dots { get => _dots; private set { _dots = value; OnPropertyChanged(); } }
    public ObservableCollection<StandingRow> Standings { get; } = new();
    public bool HasStandings => Standings.Count > 0;
    private string _raceStatus = "No live line from the game yet (it is published while this page shows).";
    public string RaceStatus { get => _raceStatus; private set => Set(ref _raceStatus, value); }
    private bool _storeWarned;

    private static string Ordinal(int n) => n switch { 1 => "1st", 2 => "2nd", 3 => "3rd", _ => n + "th" };

    private void OnLive(RaceLive l)
    {
        Live = l;
        var names = new Dictionary<int, string>();
        foreach (var p in _m.Link.Players) names[p.EntNum] = p.Name;
        string Name(RacePlayer p) => names.TryGetValue(p.EntNum, out var n) ? n : "#" + p.EntNum;
        string Progress(RacePlayer p) => l.Sprint ? $"gate {p.Next}/{Math.Max(0, l.GateCount - 1)}" : $"lap {Math.Min(p.Lap + 1, l.Laps)}/{l.Laps} · gate {p.Next}";

        Dots = l.Players.Where(p => !p.Spectator || p.IsHost)
                        .Select(p => new RaceDot(p.X, p.Y, p.Yaw, Name(p),
                                                 !p.Racing ? "" : p.Finished ? $"{Ordinal(p.Place)} {RaceLive.Clock(p.Tenths * 100)}" : Progress(p),
                                                 p.IsHost, p.Racing, p.Finished, p.Dead, p.Riding)).ToList();

        // finishers by place, then the rest by how far round they are (a circuit's gate 0 is the finish line: last)
        var racers = l.Players.Where(p => p.Racing).ToList();
        int Far(RacePlayer p) => p.Lap * 1000 + (!l.Sprint && p.Next == 0 ? l.GateCount : p.Next);
        var order = racers.Where(p => p.Finished).OrderBy(p => p.Place)
                          .Concat(racers.Where(p => !p.Finished).OrderByDescending(Far)).ToList();
        Standings.Clear();
        for (var i = 0; i < order.Count; i++)
        {
            var p = order[i];
            Standings.Add(new StandingRow(p.Finished ? Ordinal(p.Place) : (i + 1).ToString(), Name(p), p.Finished ? "finished" : Progress(p),
                                          p.Finished ? RaceLive.Clock(p.Tenths * 100) : l.State == 2 ? RaceLive.Clock(l.ElapsedMs) : "", p.IsHost, p.Finished, p.OffTrack));
        }
        OnPropertyChanged(nameof(HasStandings));
        RaceStatus = l.State switch
        {
            1 => "3-2-1 countdown…",
            2 => $"RACING  {RaceLive.Clock(l.ElapsedMs)}" + (l.FinishLeft >= 0 ? $"  ·  finish timer {l.FinishLeft} s" : "") + $"  ·  {racers.Count(p => p.Finished)}/{racers.Count} in",
            3 => "Race over - the podium is on the game's end screen",
            _ => $"No race running  ·  {l.Players.Count(p => !p.Spectator)} on the map  ·  START lines everyone up behind gate 0",
        };
        if (l.StoreErr.Length > 0 && !_storeWarned)
        {
            _storeWarned = true;
            _m.Link.Log($"race: the game read a track dvar back SHORT ({l.StoreErr}) - the packed gate store was cut; report it (race_pack() in gunfight_menu.gsc goes to 2)", LogLevel.Err);
        }
        LoadBackdrop();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the library (race-tracks.json)
    // ─────────────────────────────────────────────────────────────────────────
    public ObservableCollection<SavedTrack> SavedTracks { get; } = new();
    private SavedTrack? _selTrack;
    public SavedTrack? SelectedTrack
    {
        get => _selTrack;
        set { if (Set(ref _selTrack, value)) { OnPropertyChanged(nameof(Ghost)); OnPropertyChanged(nameof(HasSelectedTrack)); OnPropertyChanged(nameof(SelectedTrackInfo)); } }
    }
    public bool HasSelectedTrack => _selTrack != null;
    public string SelectedTrackInfo => _selTrack == null ? "" :
        $"{_selTrack.Map}  ·  {_selTrack.Gates.Count} gates  ·  {(_selTrack.Sprint ? "A to B" : $"{_selTrack.Laps} lap{(_selTrack.Laps == 1 ? "" : "s")}")}" +
        (_selTrack.Saved != default ? $"  ·  saved {_selTrack.Saved:yyyy-MM-dd HH:mm}" : "");
    private bool _allMaps, _preview = true;
    public bool AllMaps { get => _allMaps; set { if (Set(ref _allMaps, value)) RefreshLibrary(); } }
    public bool Preview { get => _preview; set { if (Set(ref _preview, value)) OnPropertyChanged(nameof(Ghost)); } }
    /// <summary>The selected saved track, faint on the map - when it is for the map shown.</summary>
    public List<RaceGate>? Ghost => _preview && _selTrack != null && string.Equals(_selTrack.Map, Map, StringComparison.OrdinalIgnoreCase) ? _selTrack.GateList : null;
    private string _trackName = "";
    public string TrackName { get => _trackName; set => Set(ref _trackName, value); }
    private string _libraryNote = "";
    public string LibraryNote { get => _libraryNote; private set => Set(ref _libraryNote, value); }
    private string _loadProgress = "";
    public string LoadProgress { get => _loadProgress; private set => Set(ref _loadProgress, value); }
    private bool _loading;
    public bool Loading { get => _loading; private set => Set(ref _loading, value); }

    private void RefreshLibrary()
    {
        var keep = _selTrack;
        var map = Map;
        SavedTracks.Clear();
        foreach (var t in _m.Tracks.Tracks.Where(t => _allMaps || map.Length == 0 || string.Equals(t.Map, map, StringComparison.OrdinalIgnoreCase))
                                           .OrderBy(t => t.Map).ThenBy(t => t.Name))
            SavedTracks.Add(t);
        SelectedTrack = keep != null && SavedTracks.Contains(keep) ? keep : SavedTracks.FirstOrDefault();
        var others = _m.Tracks.Tracks.Count - SavedTracks.Count;
        LibraryNote = SavedTracks.Count == 0 ? (map.Length > 0 ? $"No saved tracks for {map} yet." : "No saved tracks yet.") + (others > 0 ? $" {others} on other maps (tick all maps)." : "")
                    : others > 0 && !_allMaps ? $"{others} more on other maps (tick all maps)." : "";
    }

    public RelayCommand TrackSave => new(() =>
    {
        if (_track == null || _track.Gates.Count == 0) { _m.Toasts.Show("No track in the game to save - place gates first", LogLevel.Warn); return; }
        if (_pending.Count > 0 || DateTime.UtcNow - _editedAt < TimeSpan.FromSeconds(3))
        {
            _m.Toasts.Show("An edit is still on its way to the game - save again in a moment", LogLevel.Warn);
            _m.Link.RequestTrack();
            return;
        }
        var name = TrackName.Trim();
        if (name.Length == 0) name = (_m.Prompt($"Save the game's {_track.Gates.Count}-gate track on {_track.Map} as:", "track") ?? "").Trim();
        if (name.Length == 0) return;
        if (_m.Tracks.Find(_track.Map, name) != null && !_m.Confirm($"Replace the saved '{name}' on {_track.Map}?")) return;
        var t = _m.Tracks.Put(_track, name, Sprint, Laps);
        RefreshLibrary();
        SelectedTrack = t;
        TrackName = "";
        _m.Toasts.Show($"Saved '{name}' - {t.Gates.Count} gates", LogLevel.Ok);
    });

    public RelayCommand TrackLoad => new(async () =>
    {
        if (_selTrack is not { } t) return;
        var here = _m.Link.State?.Map ?? "";
        if (here.Length > 0 && !string.Equals(here, t.Map, StringComparison.OrdinalIgnoreCase))
        {
            _m.Toasts.Show($"'{t.Name}' is for {t.Map} - the game is on {here}. Switch the map first (MATCH → MAP & MODE).", LogLevel.Warn);
            return;
        }
        if (Live is { State: 1 or 2 }) { _m.Toasts.Show("Stop the race first", LogLevel.Warn); return; }
        if (_gates.Count > 0 && !_m.Confirm($"Replace the game's {_gates.Count}-gate track with '{t.Name}' ({t.Gates.Count} gates)?")) return;
        // the course it was built for
        if (_m.Setting("gf_race_sprint") is { } sp && sp.Value != (t.Sprint ? 1 : 0)) sp.Value = t.Sprint ? 1 : 0;
        if (!t.Sprint && t.Laps > 0 && _m.Setting("gf_race_laps") is { } lp && lp.Value != t.Laps) lp.Value = t.Laps;
        Loading = true;
        var ok = await _m.Tracks.LoadIntoGame(t, (i, n) => LoadProgress = $"sending gate {i} of {n}…");
        Loading = false;
        LoadProgress = ok ? $"'{t.Name}' sent - {t.Gates.Count} gates" : "load cancelled";
        _m.Link.RequestTrack();
    });
    public RelayCommand CancelLoad => new(() => _m.Tracks.CancelLoad());

    public RelayCommand TrackDelete => new(() =>
    {
        if (_selTrack is { } t && _m.Confirm($"Delete the saved '{t.Name}' ({t.Map}, {t.Gates.Count} gates)?")) _m.Tracks.Delete(t);
    });
    public RelayCommand TrackRename => new(() =>
    {
        if (_selTrack is not { } t) return;
        var name = _m.Prompt($"New name for '{t.Name}':", t.Name);
        if (string.IsNullOrWhiteSpace(name) || name.Trim() == t.Name) return;
        if (!_m.Tracks.Rename(t, name)) _m.Toasts.Show($"{t.Map} already has a track called '{name.Trim()}'", LogLevel.Warn);
    });
    public RelayCommand TrackDuplicate => new(() => { if (_selTrack is { } t) SelectedTrack = _m.Tracks.Duplicate(t); });
    public RelayCommand TrackExport => new(() =>
    {
        if (_selTrack is not { } t) return;
        var dlg = new SaveFileDialog { FileName = $"{t.Map} - {t.Name}.gftrack.json", Filter = "Race track (*.gftrack.json)|*.gftrack.json|JSON (*.json)|*.json", Title = "Export a race track" };
        if (dlg.ShowDialog() != true) return;
        try { _m.Tracks.Export(t, dlg.FileName); _m.Toasts.Show("Exported " + Path.GetFileName(dlg.FileName), LogLevel.Ok); }
        catch (Exception e) { _m.Toasts.Show("Export failed: " + e.Message, LogLevel.Err); }
    });
    public RelayCommand TrackImport => new(() =>
    {
        var dlg = new OpenFileDialog { Filter = "Race track (*.gftrack.json;*.json)|*.gftrack.json;*.json", Title = "Import a race track" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var t = _m.Tracks.Import(dlg.FileName, out var why);
            if (t == null) { _m.Toasts.Show("Not imported: " + why, LogLevel.Warn); return; }
            if (!string.Equals(t.Map, Map, StringComparison.OrdinalIgnoreCase)) AllMaps = true;
            RefreshLibrary();
            SelectedTrack = t;
            _m.Toasts.Show($"Imported '{t.Name}' for {t.Map}", LogLevel.Ok);
        }
        catch (Exception e) { _m.Toasts.Show("Import failed: " + e.Message, LogLevel.Err); }
    });

    /// <summary>--dry --fake: a sample track and live line through the real parsers (screenshot checks only).</summary>
    public void LoadFake()
    {
        var gates = new List<RaceGate>();
        for (var i = 0; i < 12; i++)
        {
            var a = i * 30.0 * Math.PI / 180;
            double x = Math.Cos(a) * 2600, y = Math.Sin(a) * 1500;
            gates.Add(new RaceGate((int)x, (int)y, 0, Game.RaceGate.YawTo(0, 0, -Math.Sin(a) * 2600, Math.Cos(a) * 1500), i == 0 ? 800 : 600));
        }
        var body = string.Join("|", "0", "1", "mp_sample_track", gates.Count.ToString(), string.Join(";", gates.Select(g => g.Text)));
        if (RaceTrack.FromHits(new[] { new Native.MemoryScanner.Hit("GFTRACK", 1, body, 0) }) is { } t) OnTrack(t);
        if (RaceLive.Parse(2, "2|3|0|12|1|41300|-1||0,2500,700,110,hvr,1,2,0,0;1,-900,1450,200,vr,1,5,0,0;2,1300,-1250,-40,r,2,10,0,0;3,-2400,-500,250,vrf,3,0,1,1023;4,300,-200,0,d,0,0,0,0") is { } l) OnLive(l);
    }
}
