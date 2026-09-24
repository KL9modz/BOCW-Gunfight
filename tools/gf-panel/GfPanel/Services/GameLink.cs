using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows.Threading;
using GfPanel.Game;
using GfPanel.Native;
using GfPanel.ViewModels;

namespace GfPanel.Services;

/// <summary>A command in flight: sent -> received (the GSC ack reached us) / timeout / failed.</summary>
public sealed class QueuedCommand : ObservableObject
{
    public long Seq { get; init; }
    public string Label { get; init; } = "";
    public IReadOnlyList<string> Lines { get; init; } = Array.Empty<string>();
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    public int Tries { get; set; } = 1;
    /// <summary>One pulse only, never re-sent: a level-changing verb (restart / relaunch / switch / end) whose
    /// ack is lost in the reload - a retry ran map_restart AGAIN (klaze 2026-09-22: "restart round and restart
    /// match fire multiple quick restarts in a row and leave the match glitched with no HUD").</summary>
    public bool NoRetry { get; init; }
    private string _state = "sent";
    public string State { get => _state; set { if (Set(ref _state, value)) OnPropertyChanged(nameof(Icon)); } }
    private string _detail = "";
    public string Detail { get => _detail; set => Set(ref _detail, value); }
    public string Icon => State switch { "ack" => "✓", "timeout" => "✗", "fail" => "⚠", _ => "⏳" };
}

/// <summary>
/// The live link to the game: one background tick (every 1.5 s) finds the process, probes the bridge,
/// sweeps the marked strings (state / players / config / map census) and raises events on the UI
/// thread; every write goes through the paced BridgeSender with a seq the GSC acks back in GFSTATE.
/// </summary>
public sealed class GameLink : IDisposable
{
    private readonly Dispatcher _ui;
    private readonly Prefs _prefs;
    private readonly Timer _timer;
    private MemoryScanner? _scanner;
    private int _busy;
    private DateTime _scannerSince = DateTime.MinValue, _lastSweep = DateTime.MinValue, _lastForce = DateTime.MinValue;
    private bool _fullDone;
    // the main sweep's own result + readout: the RACING page's fast race sweep shares the scanner, and its
    // LastSweepHit / How must not make the main tick think it is idle (a miss backs the main sweep off to 5 s)
    private bool _mainSweepHit;
    private string _mainSweepInfo = "";
    private double _mainSweepMs;
    private int _refreshRequested;
    /// <summary>The PLAYERS ↻ button: the next tick sweeps for NEWER copies of every marker (see MemoryScanner.Sweep force).</summary>
    public void RequestRefresh() { Interlocked.Exchange(ref _refreshRequested, 1); Log("re-scanning the game for the current roster / state", LogLevel.Info); }
    private DateTime _lastStateAt = DateTime.MinValue;
    private long _lastStateTick = -1;
    private long _lastPlayersTick = -1;
    private long _lastCfgTick = -1;
    private long _lastRosterTick = -1;
    private readonly Dictionary<string, string> _mapKinds = new();

    private static readonly string[] Markers = { "GFSTATE", "GFPLAYERS", "GFCFG", "GFROSTER", "GFMAPVEH", "GFMAPPROP", "GFMAPSPAWN", "GFMAPDEST", "GFLOBBY" };
    public static readonly TimeSpan TickPeriod = TimeSpan.FromMilliseconds(1500);
    /// <summary>The timer's own period: the full tick runs every third one, the RACING page's live read in between.</summary>
    public static readonly TimeSpan FastPeriod = TimeSpan.FromMilliseconds(500);
    public static readonly TimeSpan StateFresh = TimeSpan.FromSeconds(6);

    public BridgeSender Sender { get; } = new();

    // ── observable status (UI thread) ──
    public int Pid { get; private set; }
    public bool GameRunning => Pid > 0;
    public bool BridgeListening { get; private set; }
    public uint BridgeSeq { get; private set; }
    public bool CwpatchLoaded { get; private set; }
    public string? GameDir { get; private set; }
    public GfState? State { get; private set; }
    public bool StateFreshNow => State != null && DateTime.UtcNow - _lastStateAt < StateFresh;
    /// <summary>A state line was seen in THIS game process at some point (so a stale one now = the match
    /// ended / the lobby, not an older payload).</summary>
    public bool StateSeenThisProcess => _lastStateTick >= 0;
    public TimeSpan SinceState => _lastStateAt == DateTime.MinValue ? TimeSpan.MaxValue : DateTime.UtcNow - _lastStateAt;
    private DateTime _lastCfgAt = DateTime.MinValue;
    public bool ConfigFreshNow => Config != null && DateTime.UtcNow - _lastCfgAt < StateFresh;
    // ── the lobby payload's readback (GFLOBBY, src/gunfight_lobby): only while the game sits in the lobby ──
    private long _lastLobbyTick = -1;
    private DateTime _lastLobbyAt = DateTime.MinValue;
    private string _lastLobbySummary = "";
    public GfLobby? Lobby { get; private set; }
    public bool LobbyFreshNow => Lobby != null && DateTime.UtcNow - _lastLobbyAt < StateFresh;
    public IReadOnlyList<GfPlayer> Players { get; private set; } = Array.Empty<GfPlayer>();
    public bool PlayersRich { get; private set; }
    public GfConfig? Config { get; private set; }
    public Dictionary<string, int> Baseline { get; } = new();     // the game's live values (from GFCFG) - what a chunk rebuild neighbours on
    public Dictionary<string, GfMapData> MapVeh { get; } = new();
    public Dictionary<string, GfMapData> MapProp { get; } = new();
    public string SweepInfo { get; private set; } = "";
    public double SweepMs { get; private set; }
    public ObservableCollection<QueuedCommand> Queue { get; } = new();
    public ObservableCollection<LogEntry> Activity { get; } = new();
    public string? LastError { get; private set; }
    /// <summary>How each match went + every player's menu actions, into the Activity list and the saved log.</summary>
    public MatchTracker Matches { get; }

    // ── the menu log (GFLOG): collected when GFSTATE lg= moves past what was collected, and while records
    // wait for their result; the last gasp collects GFSTATE + GFLOG once when the feed goes quiet ──
    private int _logWanted, _gaspWanted, _logTries;
    private long _logMatch, _logSeqWanted, _logSeqSeen;
    private DateTime _lastLogCollect = DateTime.MinValue;

    public event Action? StatusChanged;
    public event Action<GfState?>? StateChanged;
    public event Action<IReadOnlyList<GfPlayer>, IReadOnlyList<GfPlayer>, IReadOnlyList<GfPlayer>>? PlayersChanged;   // (all, joined, left)
    public event Action<GfConfig>? ConfigChanged;
    public event Action<GfLobby>? LobbyChanged;
    public event Action<string, LogLevel>? Toast;
    public event Action<string>? MapDataChanged;
    /// <summary>A complete spawn-atlas scan arrived (the SPAWNS tab's Scan / auto-scan).</summary>
    public event Action<SpawnAtlas>? AtlasReceived;
    /// <summary>The atlas request timed out: the reason, for a toast.</summary>
    public event Action<string>? AtlasFailed;

    // ── the spawn atlas: a multi-chunk channel (GFSPAWN), collected on request, not every tick ──
    private int _atlasWanted;
    private long _atlasSince;
    private string _atlasMap = "";
    private DateTime _atlasDeadline;
    private int _atlasTries;
    public bool AtlasPending => Volatile.Read(ref _atlasWanted) == 1;

    // ── the spawned-entity list (GFENTS, bocw-84 2026-09-23): collected when GFSTATE ev= moves while the ENTITIES
    //    tab is open (WantEntities), or on its Refresh; at most every 2.5 s (a driven vehicle moves the stamp) ──
    /// <summary>A complete entity list arrived: (stamp, entities).</summary>
    public event Action<long, List<GfEntity>>? EntitiesReceived;
    private long _evWanted, _evSeen;
    private int _evTries, _entRefresh;
    private DateTime _lastEntCollect = DateTime.MinValue;
    private volatile bool _wantEntities;
    /// <summary>The ENTITIES tab is showing: collect the list whenever the game republishes it.</summary>
    public bool WantEntities { get => _wantEntities; set => _wantEntities = value; }
    /// <summary>The ENTITIES tab's Refresh: collect on the next tick whatever the stamp says.</summary>
    public void RequestEntities() => Interlocked.Exchange(ref _entRefresh, 1);

    // ── the RACING page (2026-09-24): GFRACE - every player's position + the race, published every 0.5 s while
    //    gf_race_live is 1 - read on the fast tick while the page shows; GFTRACK - the whole track - collected
    //    when its version moves (GFRACE ver, else GFSTATE rtv=) or on request ──
    private static readonly string[] RaceMarkers = { "GFRACE" };
    /// <summary>A newer live race line arrived.</summary>
    public event Action<RaceLive>? RaceLiveReceived;
    /// <summary>A complete track arrived (also when its version did not move - a requested re-read).</summary>
    public event Action<RaceTrack>? TrackReceived;
    private volatile bool _wantRace;
    private long _lastRaceTick = -1, _trackWanted, _trackSeen = -1;
    private int _trackRefresh, _trackTries, _trackForceTries, _fastN;
    private DateTime _lastTrackCollect = DateTime.MinValue, _lastRaceRegion = DateTime.MinValue, _lastRaceAt = DateTime.MinValue, _lastLiveAsk = DateTime.MinValue;
    /// <summary>The RACING page is showing: the game is asked for the live line (gf_race_live) and it is read every 0.5 s.</summary>
    public bool WantRace
    {
        get => _wantRace;
        set
        {
            if (_wantRace == value) return;
            _wantRace = value;
            AskLive(value);
            if (value) RequestTrack();
        }
    }
    private void AskLive(bool on)
    {
        _lastLiveAsk = DateTime.UtcNow;
        _ = SendRaw(new[] { "set gf_race_live " + (on ? 1 : 0) }, 5);
    }
    /// <summary>Collect the track on the next fast tick whatever its version says (after an edit, before a Save).</summary>
    public void RequestTrack() { Interlocked.Exchange(ref _trackRefresh, 1); _trackForceTries = 0; }

    // ── the live spawn events (GFSPAWNED): collected when GFSTATE spv= moves, never on a timer ──
    /// <summary>The match's spawn events arrived: (map, match id, events).</summary>
    public event Action<string, long, List<SpawnEvent>>? SpawnEventsReceived;
    private string _spvSeen = "", _spvWanted = "", _spvMap = "";
    private int _spvTries;

    /// <summary>Collect the next complete GFSPAWN scan of <paramref name="map"/> stamped after the current state
    /// tick (the scan starts after the spawnscan verb lands), for up to 30 s.</summary>
    public void RequestAtlas(string map)
    {
        _atlasSince = Math.Max(0, _lastStateTick);
        _atlasMap = map ?? "";
        _atlasDeadline = DateTime.UtcNow.AddSeconds(30);
        _atlasTries = 0;
        Interlocked.Exchange(ref _atlasWanted, 1);
    }

    public GameLink(Dispatcher ui, Prefs prefs)
    {
        _ui = ui;
        _prefs = prefs;
        Sender.DryRun = App.DryRun;
        Sender.LineSent += (line, listening) => _ui.BeginInvoke(() => Log((App.DryRun ? "[dry] " : "") + line + (listening ? "" : "   (bridge not listening)"), LogLevel.In));
        Matches = new MatchTracker(LogAt, ActivityFile.Detail, () => Players);
        _timer = new Timer(_ => Tick(), null, 300, (int)FastPeriod.TotalMilliseconds);
    }

    public void Dispose()
    {
        _timer.Dispose();
        _scanner?.Dispose();
    }

    public void Log(string text, LogLevel level = LogLevel.Info) => LogAt(DateTime.Now, text, level);

    /// <summary>An Activity entry stamped <paramref name="at"/> (a menu action carries the game-side time it
    /// happened). Every entry is also appended to the saved log (ActivityFile); the list keeps the last 300.</summary>
    public void LogAt(DateTime at, string text, LogLevel level)
    {
        if (!_ui.CheckAccess()) { _ui.BeginInvoke(() => LogAt(at, text, level)); return; }
        Activity.Insert(0, new LogEntry(at, text, level));
        while (Activity.Count > 300) Activity.RemoveAt(Activity.Count - 1);
        ActivityFile.Write(at, text, level);
    }

    public void ShowToast(string text, LogLevel level = LogLevel.Info)
    {
        if (!_ui.CheckAccess()) { _ui.BeginInvoke(() => ShowToast(text, level)); return; }
        Toast?.Invoke(text, level);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // the tick
    // ─────────────────────────────────────────────────────────────────────────
    private void Tick()
    {
        if (Interlocked.Exchange(ref _busy, 1) == 1) return;    // never overlap sweeps
        try
        {
            if (_fastN++ % 3 == 0) TickBody();                  // the full tick: every TickPeriod
            if (_wantRace) RaceTick();                           // the RACING page: every FastPeriod
        }
        catch (Exception e) { LastError = e.Message; }
        finally { _busy = 0; }
    }

    /// <summary>The RACING page's read: the newest live line (the window around its last address - every line is a
    /// new string near the last; the pool region at most every 3 s), and the whole track when its version moved.</summary>
    private void RaceTick()
    {
        var scanner = _scanner;
        if (scanner == null) return;
        RaceLive? live = null;
        RaceTrack? track = null;
        var now = DateTime.UtcNow;
        try
        {
            var regionOk = now - _lastRaceRegion >= TimeSpan.FromSeconds(3);
            var hits = scanner.Sweep(RaceMarkers, false, 400, force: true, regionOk: regionOk);
            if (scanner.LastSweepHow == "region") _lastRaceRegion = now;
            if (hits.TryGetValue("GFRACE", out var h) && h.Tick > _lastRaceTick && RaceLive.Parse(h.Tick, h.Body) is { } l)
            {
                live = l;
                _lastRaceTick = h.Tick; _lastRaceAt = now;
                if (l.TrackVer != 0 && l.TrackVer != Interlocked.Read(ref _trackWanted)) Interlocked.Exchange(ref _trackWanted, l.TrackVer);
            }
            // no live line for 5 s while the game is up: it forgot gf_race_live (a relaunch clears dvars) - ask again
            if (now - _lastRaceAt > TimeSpan.FromSeconds(5) && now - _lastLiveAsk > TimeSpan.FromSeconds(10) && SinceState < StateFresh) AskLive(true);

            var tw = Interlocked.Read(ref _trackWanted);
            var force = Interlocked.Exchange(ref _trackRefresh, 0) == 1;
            if ((force || (tw != 0 && tw != _trackSeen)) && now - _lastTrackCollect >= TimeSpan.FromSeconds(1))
            {
                _lastTrackCollect = now;
                track = RaceTrack.FromHits(scanner.CollectAll("GFTRACK", wide: _trackTries++ >= 2));
                if (track != null && (tw == 0 || track.Ver == tw)) { _trackSeen = track.Ver; _trackTries = 0; }
                else if (_trackTries > 8) { _trackSeen = tw; _trackTries = 0; }      // give up on this version; the next change retries
                if (force && track == null && ++_trackForceTries < 6) Interlocked.Exchange(ref _trackRefresh, 1);
            }
            else if (force) Interlocked.Exchange(ref _trackRefresh, 1);            // throttled: keep the request for the next tick
        }
        catch (Exception e) { LastError = "race: " + e.Message; }
        if (live != null || track != null)
            _ui.BeginInvoke(() =>
            {
                if (live != null) RaceLiveReceived?.Invoke(live);
                if (track != null) TrackReceived?.Invoke(track);
            });
    }

    private void TickBody()
    {
        var pid = GameProcess.FindPid();
        var probe = BridgeChannel.Probe();
        var cwp = pid > 0 ? GameProcess.DiscordModule(pid) : (false, 0u);
        var gameDir = GameProcess.FindGameDir(pid);   // falls back to the known install folders when the game is down

        Dictionary<string, MemoryScanner.Hit>? hits = null;
        var sweepInfo = "";
        double sweepMs = 0;
        SpawnAtlas? atlas = null;
        string? atlasFail = null;
        (string Map, long Match, List<SpawnEvent> Events)? spawns = null;
        (long Match, List<MenuAction> Actions)? menu = null;
        (long Stamp, List<GfEntity> Items)? ents = null;
        (GfState? State, string? Raw, (long Match, List<MenuAction> Actions)? Actions)? gasp = null;
        if (pid > 0)
        {
            if (_scanner == null || _scanner.Pid != pid)
            {
                _scanner?.Dispose();
                try { _scanner = new MemoryScanner(pid); } catch (Exception e) { _scanner = null; LastError = e.Message; }
                _lastStateTick = _lastPlayersTick = _lastCfgTick = _lastRosterTick = -1;
                _lastRaceTick = -1; _mainSweepHit = false;
                _scannerSince = DateTime.UtcNow; _lastSweep = DateTime.MinValue; _fullDone = false;
            }
            if (_scanner != null)
            {
                // Cost control (measured 2026-09-20 with the game in the lobby: a whole-process sweep read
                // 9 GB in 21 s and found nothing, every 15 s). The pool lives inside the exe image range,
                // so the region step is the real search; while it keeps missing (lobby, no match) it
                // runs every 5 s, not every tick, and the whole-process fallback runs ONCE per game
                // process, a minute in, then never again.
                var now = DateTime.UtcNow;
                var idle = !_mainSweepHit && _lastSweep != DateTime.MinValue;
                // every 5 s (or on the ↻ button) distrust the quick probes and look for newer copies:
                // an on-change line's old copy stays put while the new one lands elsewhere
                var force = Interlocked.Exchange(ref _refreshRequested, 0) == 1 || (_scanner.HasEverHit && now - _lastForce >= TimeSpan.FromSeconds(5));
                if (force) _lastForce = now;
                if (!idle || force || now - _lastSweep >= TimeSpan.FromSeconds(5))
                {
                    var allowFull = !_fullDone && !_scanner.HasEverHit && now - _scannerSince > TimeSpan.FromSeconds(60);
                    if (allowFull) _fullDone = true;
                    hits = _scanner.Sweep(Markers, allowFull, allowFull ? 20000 : 4000, force);
                    _lastSweep = now;
                    _mainSweepHit = _scanner.LastSweepHit;
                    _mainSweepInfo = $"{_scanner.LastSweepHow} {_scanner.LastSweepBytes / 1048576} MB";
                    _mainSweepMs = _scanner.LastSweepMs;
                }
                sweepInfo = _mainSweepInfo;
                sweepMs = _mainSweepMs;

                // the spawn atlas: every copy of every GFSPAWN chunk, newest complete scan wins. The pool
                // region first (where the other markers live), the whole exe range from the 3rd try.
                if (Volatile.Read(ref _atlasWanted) == 1)
                {
                    if (DateTime.UtcNow > _atlasDeadline)
                    {
                        Interlocked.Exchange(ref _atlasWanted, 0);
                        atlasFail = $"no complete spawn scan of {_atlasMap} came back in 30 s - is the injected build the atlas build (gunfight_menu.atlas.gscc or newer)?";
                    }
                    else
                    {
                        try
                        {
                            var all = _scanner.CollectAll("GFSPAWN", wide: _atlasTries++ >= 2);
                            atlas = SpawnAtlas.FromHits(all, _atlasSince, _atlasMap);
                            if (atlas != null) Interlocked.Exchange(ref _atlasWanted, 0);
                        }
                        catch (Exception e) { LastError = "atlas: " + e.Message; }
                    }
                }

                // the spawn events: GFSTATE's spv= moved since the last complete read -> collect the chunks
                var want = Volatile.Read(ref _spvWanted);
                if (want.Length > 0 && want != _spvSeen && Volatile.Read(ref _atlasWanted) == 0)
                {
                    try
                    {
                        var all = _scanner.CollectAll("GFSPAWNED", wide: _spvTries++ >= 2);
                        var r = SpawnEvents.FromHits(all, _spvMap);
                        // the newest complete set goes out even when it trails the announced version (the
                        // publisher republishes up to 1 s after a spawn); keep collecting until it matches
                        if (r != null) spawns = (_spvMap, r.Value.Match, r.Value.Events);
                        if (r != null && $"{r.Value.Match}.{r.Value.Ver}" == want) { _spvSeen = want; _spvTries = 0; }
                        else if (_spvTries > 8) { _spvSeen = want; _spvTries = 0; }   // give up on this version; the next spawn retries
                    }
                    catch (Exception e) { LastError = "spawns: " + e.Message; }
                }

                // the entity list (GFENTS): ev= moved while the ENTITIES tab is open, or its Refresh asked
                var evw = Interlocked.Read(ref _evWanted);
                var forceEnt = Interlocked.Exchange(ref _entRefresh, 0) == 1;
                if ((forceEnt || (_wantEntities && evw > 0 && evw != _evSeen)) && (forceEnt || DateTime.UtcNow - _lastEntCollect >= TimeSpan.FromSeconds(2.5)))
                {
                    _lastEntCollect = DateTime.UtcNow;
                    try
                    {
                        var r = EntityList.FromHits(_scanner.CollectAll("GFENTS", wide: _evTries++ >= 2));
                        if (r != null) ents = r;
                        if (r != null && (evw == 0 || r.Value.Stamp >= evw)) { _evSeen = evw; _evTries = 0; }
                        else if (_evTries > 8) { _evSeen = evw; _evTries = 0; }   // give up on this stamp; the next change retries
                    }
                    catch (Exception e) { LastError = "entities: " + e.Message; }
                }

                // the last gasp: the state feed just went quiet - every copy of the state line and of the menu
                // log still in memory, once (a dead level's strings linger until the pool is reused)
                if (Interlocked.Exchange(ref _gaspWanted, 0) == 1)
                {
                    try
                    {
                        var top = _scanner.CollectAll("GFSTATE", wide: true).OrderByDescending(h => h.Tick).FirstOrDefault();
                        var gs = top != null ? GfState.Parse(top.Tick, top.Body) : null;
                        gasp = (gs, top != null ? top.Tick + "|" + top.Body : null, MenuLog.FromHits(_scanner.CollectAll("GFLOG", wide: true), Volatile.Read(ref _logMatch)));
                    }
                    catch (Exception e) { LastError = "last gasp: " + e.Message; gasp = (null, null, null); }
                }
                // the menu log: GFSTATE lg= moved past what was collected, or records wait for their result.
                // Every copy of the line (each holds an overlapping window of records), unioned by seq.
                else if (Volatile.Read(ref _logWanted) == 1 && DateTime.UtcNow - _lastLogCollect >= TimeSpan.FromSeconds(1.4))
                {
                    _lastLogCollect = DateTime.UtcNow;
                    try { menu = MenuLog.FromHits(_scanner.CollectAll("GFLOG", wide: Volatile.Read(ref _logTries) >= 2), Volatile.Read(ref _logMatch)); }
                    catch (Exception e) { LastError = "menu log: " + e.Message; }
                }
            }
        }
        else if (_scanner != null)
        {
            _scanner.Dispose();
            _scanner = null;
        }

        _ui.BeginInvoke(() =>
        {
            // the last gasp first: it can close the match, and Apply's tick must then not ask for another
            if (gasp is { } g) Matches.OnLastGasp(g.State, g.Raw, g.Actions, DateTime.Now);
            Apply(pid, probe, cwp.Item1 && cwp.Item2 == Injector.CwpatchImageSize, gameDir, hits, sweepInfo, sweepMs);
            if (menu is { } mn) OnMenuLog(mn.Match, mn.Actions);
            if (atlas != null)
            {
                Log($"spawn atlas: {atlas.Map} - {atlas.Markers.Count} markers, {atlas.Named.Count} named, {atlas.Groups.Count} groups, {atlas.Lists.Count} engine lists ({atlas.Chunks} chunks)", LogLevel.Ok);
                AtlasReceived?.Invoke(atlas);
            }
            if (atlasFail != null)
            {
                Log("spawn atlas: " + atlasFail, LogLevel.Warn);
                AtlasFailed?.Invoke(atlasFail);
            }
            if (spawns is { } sp) SpawnEventsReceived?.Invoke(sp.Map, sp.Match, sp.Events);
            if (ents is { } en) EntitiesReceived?.Invoke(en.Stamp, en.Items);
        });
    }

    private void Apply(int pid, BridgeChannel.ProbeResult probe, bool cwpatch, string? gameDir,
                       Dictionary<string, MemoryScanner.Hit>? hits, string sweepInfo, double sweepMs)
    {
        var wasRunning = GameRunning;
        Pid = pid; BridgeListening = probe.Listening; BridgeSeq = probe.Seq; CwpatchLoaded = cwpatch; GameDir = gameDir ?? GameDir;
        SweepInfo = sweepInfo; SweepMs = sweepMs;
        if (pid == 0 && wasRunning)
        {
            Log("game closed", LogLevel.Warn);
            Interlocked.Exchange(ref _gaspWanted, 0);
            Matches.OnGameClosed(DateTime.Now);      // before the roster is cleared: an abrupt end lists it
            State = null; Players = Array.Empty<GfPlayer>(); Config = null;
            StateChanged?.Invoke(null);
            PlayersChanged?.Invoke(Players, Array.Empty<GfPlayer>(), Array.Empty<GfPlayer>());
        }
        else if (pid > 0 && !wasRunning) Log($"game running (pid {pid})", LogLevel.Ok);

        if (hits != null)
        {
            if (hits.TryGetValue("GFSTATE", out var st) && st.Tick > _lastStateTick)   // ticks are getrealtime() ms: monotonic, so only NEWER lines are taken
            {
                var s = GfState.Parse(st.Tick, st.Body);
                if (s != null)
                {
                    var prev = State;
                    _retryPausedUntil = DateTime.MinValue;   // a state line from the (new) level: retries may resume
                    // a fallback line (the GSC's state_build died this tick) keeps the tick fresh but has no
                    // fields: keep the previous full state's values, surface the error count + stage
                    if (s.IsFallback && prev != null) s = prev with { Tick = s.Tick, Phase = s.Phase, Err = s.Err, Stage = s.Stage };
                    State = s; _lastStateTick = st.Tick; _lastStateAt = DateTime.UtcNow;
                    ResolveAcks(s.AckSeq);
                    // the saved log: match boundaries / rounds / how it ended, and the menu log's high-water mark
                    Matches.OnState(s, st.Tick + "|" + st.Body, DateTime.Now, Players);
                    if (s.MatchId != Volatile.Read(ref _logMatch))
                    {
                        Volatile.Write(ref _logMatch, s.MatchId);
                        _logSeqSeen = 0; _logSeqWanted = 0; Volatile.Write(ref _logTries, 0);
                    }
                    if (s.LogSeq > _logSeqWanted) _logSeqWanted = s.LogSeq;
                    if (s.EntVersion > 0 && s.EntVersion != Interlocked.Read(ref _evWanted)) Interlocked.Exchange(ref _evWanted, s.EntVersion);
                    // the race track's version, when the live line is not there to say it (it is faster and newer)
                    if (s.RaceTrackVer != 0 && DateTime.UtcNow - _lastRaceAt > TimeSpan.FromSeconds(5) && s.RaceTrackVer != Interlocked.Read(ref _trackWanted))
                        Interlocked.Exchange(ref _trackWanted, s.RaceTrackVer);
                    UpdateLogWanted();
                    // a spawn landed (spv= moved): the tick collects the GFSPAWNED chunks for this map
                    if (s.SpawnEvVersion.Length > 0 && s.SpawnEvVersion != "0" && s.SpawnEvVersion != _spvWanted)
                    {
                        _spvMap = s.Map;
                        _spvTries = 0;
                        Volatile.Write(ref _spvWanted, s.SpawnEvVersion);
                    }
                    if (s.Err > 0 && (prev == null || prev.Err != s.Err)) Log($"GSC state_build FAILED ×{s.Err} at stage {s.Stage} (phase {s.Phase}) - report this", LogLevel.Err);
                    if (prev == null) Log($"mod live: {s.Gametype} on {s.Map}, round {s.Round}", LogLevel.Ok);
                    else if (prev.Say != s.Say && !string.IsNullOrEmpty(s.Say)) Log("game: " + (s.Say.Length > 160 ? s.Say[..160] + "…" : s.Say), s.Say.StartsWith("app: ") ? LogLevel.Ok : LogLevel.Info);
                    StateChanged?.Invoke(s);
                }
            }
            if (hits.TryGetValue("GFPLAYERS", out var pl) && pl.Tick > _lastPlayersTick)
            {
                var list = Roster.ParsePlayers(pl.Body, out var unlisted);
                if (list != null)
                {
                    _lastPlayersTick = pl.Tick; PlayersRich = true;
                    NoteUnlisted(list.Count, unlisted);
                    UpdatePlayers(Roster.KeepUnlisted(list, Players, unlisted));
                }
            }
            else if (!PlayersRich && hits.TryGetValue("GFROSTER", out var ro) && ro.Tick > _lastRosterTick)
            {
                var list = Roster.ParseRoster(ro.Body);
                if (list != null) { _lastRosterTick = ro.Tick; UpdatePlayers(list); }
            }
            if (hits.TryGetValue("GFCFG", out var cf) && cf.Tick > _lastCfgTick)
            {
                var c = GfConfig.Parse(cf.Tick, cf.Body);
                if (c != null)
                {
                    _lastCfgTick = cf.Tick; _lastCfgAt = DateTime.UtcNow; Config = c;
                    foreach (var kv in c.Values) Baseline[kv.Key] = kv.Value;
                    ConfigChanged?.Invoke(c);
                }
            }
            // the lobby payload (GFLOBBY): what the LOBBY's store holds + the two settings it read. Baseline gets the
            // app-side values so the dashboard rows show them; a changed summary goes to the activity + saved log.
            if (hits.TryGetValue("GFLOBBY", out var lb) && lb.Tick > _lastLobbyTick)
            {
                var l = GfLobby.Parse(lb.Tick, lb.Body);
                if (l != null)
                {
                    _lastLobbyTick = lb.Tick; _lastLobbyAt = DateTime.UtcNow; Lobby = l;
                    Baseline["gf_lobby_maxp"] = l.Want;
                    Baseline["gf_lobby_spec"] = l.Spec;
                    if (l.Summary != _lastLobbySummary)
                    {
                        _lastLobbySummary = l.Summary;
                        Log("lobby: " + l.Summary, l.Warn ? LogLevel.Warn : l.Ok ? LogLevel.Ok : LogLevel.Info);
                    }
                    LobbyChanged?.Invoke(l);
                }
            }
            foreach (var m in new[] { "GFMAPVEH", "GFMAPPROP", "GFMAPSPAWN", "GFMAPDEST" })
            {
                if (!hits.TryGetValue(m, out var h)) continue;
                var parsed = GfMapData.Parse(m, h.Body);
                if (parsed == null) continue;
                var (kind, map, data) = parsed.Value;
                var key = kind + ":" + map;
                if (_mapKinds.TryGetValue(key, out var seen) && seen == h.Body) continue;
                _mapKinds[key] = h.Body;
                if (kind == "VEH") MapVeh[map] = data;
                if (kind == "PROP") MapProp[map] = data;
                MapDataChanged?.Invoke(map);
            }
        }
        // a quiet feed: the tracker decides when it is a stop, and asks for one last-gasp read
        Matches.OnTick(DateTime.Now, pid > 0);
        if (Matches.WantLastGasp && pid > 0) Interlocked.Exchange(ref _gaspWanted, 1);
        CheckTimeouts();
        StatusChanged?.Invoke();
    }

    /// <summary>A GFLOG collection landed (UI thread): hand it to the tracker, move the high-water mark, and
    /// keep collecting while lg= is ahead of it or records wait for their result.</summary>
    private void OnMenuLog(long match, List<MenuAction> actions)
    {
        if (match == Volatile.Read(ref _logMatch))
        {
            var max = actions.Count > 0 ? actions.Max(a => a.Seq) : 0;
            if (max >= _logSeqWanted) Volatile.Write(ref _logTries, 0);
            else Interlocked.Increment(ref _logTries);
            if (max > _logSeqSeen) _logSeqSeen = max;
        }
        Matches.OnMenuActions(match, actions, DateTime.Now, final: false);
        UpdateLogWanted();
    }

    private void UpdateLogWanted()
    {
        // a record the pool already reused never shows up: after 5 misses, stop asking for it
        if (_logSeqWanted > _logSeqSeen && Volatile.Read(ref _logTries) > 5) _logSeqSeen = _logSeqWanted;
        var want = (_logSeqWanted > _logSeqSeen || Matches.HasPending) && Volatile.Read(ref _logMatch) > 0;
        Volatile.Write(ref _logWanted, want ? 1 : 0);
    }

    /// <summary>Players in the game that the last GFPLAYERS line had no room for (players_build stops at 940 chars;
    /// a player still connecting has no name yet and is skipped too). Their last known rows are kept meanwhile.</summary>
    public int PlayersUnlisted { get; private set; }

    private void NoteUnlisted(int listed, int unlisted)
    {
        if (unlisted == PlayersUnlisted) return;
        PlayersUnlisted = unlisted;
        // a small lobby only ever skips a player who is still connecting - not worth a line
        if (unlisted > 0 && listed + unlisted >= 8)
            Log($"roster: {listed} of {listed + unlisted} players listed - the game's player line is full (or someone is still connecting); the rest keep their last known row", LogLevel.Info);
    }

    private void UpdatePlayers(List<GfPlayer> list)
    {
        var prev = Players;
        var prevKeys = prev.Where(p => !p.IsBot).Select(p => p.Key).ToHashSet();
        var curKeys = list.Where(p => !p.IsBot).Select(p => p.Key).ToHashSet();
        var joined = prev.Count == 0 && State == null ? new List<GfPlayer>() : list.Where(p => !p.IsBot && !prevKeys.Contains(p.Key)).ToList();
        var left = prev.Where(p => !p.IsBot && !curKeys.Contains(p.Key)).ToList();
        Players = list;
        foreach (var p in list.Where(p => !string.IsNullOrEmpty(p.Xuid))) _prefs.KnownNames[p.Xuid] = p.Name;
        PlayersChanged?.Invoke(list, joined, left);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // writes
    // ─────────────────────────────────────────────────────────────────────────
    private const int RetryAfterMs = 5000, MaxTries = 3, GiveUpMs = 16000;
    /// <summary>After a level-changing command (Commands.LevelChange: sent once, never retried) every retry is paused
    /// until the NEXT state line arrives from the new level (or 40 s pass).</summary>
    private DateTime _retryPausedUntil = DateTime.MinValue;

    /// <summary>Queue a command: payload lines + seq + go. Returns the queue entry (state flips on the ack).</summary>
    public QueuedCommand Send(string label, IEnumerable<string> payload, int priority = 10)
    {
        var seq = ++_prefs.CommandSeq;
        var lines = Commands.Fire(payload, seq);
        // a level verb (restart / end ...), `race endmatch`, or a map switch / stage (gf_cmd_map, MAPS + the SPAWNS scan
        // tour): its ack is lost in the level change, and a retry would restart / end / switch again
        var level = Commands.LevelChange(lines);
        var oneShot = level != null;
        if (oneShot)
        {
            _retryPausedUntil = DateTime.UtcNow.AddSeconds(40);
            Matches.NoteLevelVerb(level!, DateTime.Now);   // a stop right after is the panel's doing
        }
        var q = new QueuedCommand { Seq = seq, Label = label, Lines = lines, NoRetry = oneShot };
        Queue.Insert(0, q);
        while (Queue.Count > 8) Queue.RemoveAt(Queue.Count - 1);
        Dispatch(q, priority);
        return q;
    }

    /// <summary>Plain dvar writes with no pulse (a config chunk / a plain setting). No ack is possible;
    /// the GFCFG readback is the confirmation.</summary>
    public Task<BridgeSender.SendResult> SendRaw(IEnumerable<string> lines, int priority = 5) => Sender.SendAsync(lines, priority);

    private async void Dispatch(QueuedCommand q, int priority)
    {
        var r = await Sender.SendAsync(q.Lines, priority);
        _ui.BeginInvoke(() =>
        {
            q.SentAt = DateTime.UtcNow;
            if (r.Refused > 0)
            {
                q.State = "fail"; q.Detail = "refused (>47 B): " + string.Join(" / ", r.RefusedLines);
                Log("✗ " + q.Label + " - " + q.Detail, LogLevel.Err);
                ShowToast(q.Label + " refused: a line exceeds the 47-byte bridge slot", LogLevel.Err);
            }
            else if (!r.Listening)
            {
                q.Detail = "bridge not listening";
            }
        });
    }

    private void ResolveAcks(long ack)
    {
        foreach (var q in Queue.Where(q => q.State == "sent" && q.Seq <= ack))
        {
            q.State = "ack";
            q.Detail = $"received · {(DateTime.UtcNow - q.CreatedAt).TotalSeconds:0.0}s";
        }
        // keep our counter above the game's mark (another panel may drive the same game)
        if (ack > _prefs.CommandSeq) _prefs.CommandSeq = ack;
    }

    private void CheckTimeouts()
    {
        var now = DateTime.UtcNow;
        foreach (var q in Queue.Where(q => q.State == "sent").ToList())
        {
            if (!StateFreshNow) continue;   // no ack channel at all (old payload / no match): leave it as sent
            if ((now - q.SentAt).TotalMilliseconds < RetryAfterMs) continue;
            if (q.NoRetry) { if ((now - q.CreatedAt).TotalMilliseconds > GiveUpMs) { q.State = "ack"; q.Detail = "one-shot (no retry)"; } continue; }
            if (now < _retryPausedUntil) continue;   // a level change is in flight: its acks are lost, retries would re-fire
            if (q.Tries < MaxTries)
            {
                q.Tries++; q.SentAt = now; q.Detail = $"retry {q.Tries}/{MaxTries}";
                Dispatch(q, 10);                       // same seq: the GSC ignores a repeat, never double-fires
            }
            else if ((now - q.CreatedAt).TotalMilliseconds > GiveUpMs)
            {
                q.State = "timeout"; q.Detail = "no ack";
                Log("✗ " + q.Label + " - no ack from the game", LogLevel.Warn);
            }
        }
        foreach (var q in Queue.Where(q => q.State != "sent" && (now - q.SentAt).TotalSeconds > 8).ToList()) Queue.Remove(q);
    }

    /// <summary>Seed the seq above the game's ack so a fresh panel never re-uses an acked number.</summary>
    public void SeedSeq()
    {
        if (State != null && State.AckSeq >= _prefs.CommandSeq) _prefs.CommandSeq = State.AckSeq;
    }
}
