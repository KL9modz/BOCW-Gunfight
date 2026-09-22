using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows.Threading;
using GfPanel.Game;
using GfPanel.Native;
using GfPanel.ViewModels;

namespace GfPanel.Services;

public enum LogLevel { Info, Ok, Warn, Err, In }

public sealed record LogEntry(DateTime At, string Text, LogLevel Level)
{
    public string Time => At.ToString("HH:mm:ss");
}

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
    public string State { get => _state; set => Set(ref _state, value); }
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
    private int _refreshRequested;
    /// <summary>The PLAYERS ↻ button: the next tick sweeps for NEWER copies of every marker (see MemoryScanner.Sweep force).</summary>
    public void RequestRefresh() { Interlocked.Exchange(ref _refreshRequested, 1); Log("re-scanning the game for the current roster / state", LogLevel.Info); }
    private DateTime _lastStateAt = DateTime.MinValue;
    private long _lastStateTick = -1;
    private long _lastPlayersTick = -1;
    private long _lastCfgTick = -1;
    private long _lastRosterTick = -1;
    private readonly Dictionary<string, string> _mapKinds = new();

    private static readonly string[] Markers = { "GFSTATE", "GFPLAYERS", "GFCFG", "GFROSTER", "GFMAPVEH", "GFMAPPROP", "GFMAPSPAWN", "GFMAPDEST" };
    public static readonly TimeSpan TickPeriod = TimeSpan.FromMilliseconds(1500);
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

    public event Action? StatusChanged;
    public event Action<GfState?>? StateChanged;
    public event Action<IReadOnlyList<GfPlayer>, IReadOnlyList<GfPlayer>, IReadOnlyList<GfPlayer>>? PlayersChanged;   // (all, joined, left)
    public event Action<GfConfig>? ConfigChanged;
    public event Action<string, LogLevel>? Toast;
    public event Action<string>? MapDataChanged;

    public GameLink(Dispatcher ui, Prefs prefs)
    {
        _ui = ui;
        _prefs = prefs;
        Sender.DryRun = App.DryRun;
        Sender.LineSent += (line, listening) => _ui.BeginInvoke(() => Log((App.DryRun ? "[dry] " : "") + line + (listening ? "" : "   (bridge not listening)"), LogLevel.In));
        _timer = new Timer(_ => Tick(), null, 300, (int)TickPeriod.TotalMilliseconds);
    }

    public void Dispose()
    {
        _timer.Dispose();
        _scanner?.Dispose();
    }

    public void Log(string text, LogLevel level = LogLevel.Info)
    {
        if (!_ui.CheckAccess()) { _ui.BeginInvoke(() => Log(text, level)); return; }
        Activity.Insert(0, new LogEntry(DateTime.Now, text, level));
        while (Activity.Count > 200) Activity.RemoveAt(Activity.Count - 1);
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
        try { TickBody(); }
        catch (Exception e) { LastError = e.Message; }
        finally { _busy = 0; }
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
        if (pid > 0)
        {
            if (_scanner == null || _scanner.Pid != pid)
            {
                _scanner?.Dispose();
                try { _scanner = new MemoryScanner(pid); } catch (Exception e) { _scanner = null; LastError = e.Message; }
                _lastStateTick = _lastPlayersTick = _lastCfgTick = _lastRosterTick = -1;
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
                var idle = !_scanner.LastSweepHit && _lastSweep != DateTime.MinValue;
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
                }
                sweepInfo = $"{_scanner.LastSweepHow} {_scanner.LastSweepBytes / 1048576} MB";
                sweepMs = _scanner.LastSweepMs;
            }
        }
        else if (_scanner != null)
        {
            _scanner.Dispose();
            _scanner = null;
        }

        _ui.BeginInvoke(() => Apply(pid, probe, cwp.Item1 && cwp.Item2 == Injector.CwpatchImageSize, gameDir, hits, sweepInfo, sweepMs));
    }

    private void Apply(int pid, BridgeChannel.ProbeResult probe, bool cwpatch, string? gameDir,
                       Dictionary<string, MemoryScanner.Hit>? hits, string sweepInfo, double sweepMs)
    {
        var wasRunning = GameRunning;
        Pid = pid; BridgeListening = probe.Listening; BridgeSeq = probe.Seq; CwpatchLoaded = cwpatch; GameDir = gameDir ?? GameDir;
        SweepInfo = sweepInfo; SweepMs = sweepMs;
        if (pid == 0 && wasRunning)
        {
            State = null; Players = Array.Empty<GfPlayer>(); Config = null;
            Log("game closed", LogLevel.Warn);
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
                    if (s.Err > 0 && (prev == null || prev.Err != s.Err)) Log($"GSC state_build FAILED ×{s.Err} at stage {s.Stage} (phase {s.Phase}) - report this", LogLevel.Err);
                    if (prev == null) Log($"mod live: {s.Gametype} on {s.Map}, round {s.Round}", LogLevel.Ok);
                    else if (prev.Say != s.Say && !string.IsNullOrEmpty(s.Say)) Log("game: " + (s.Say.Length > 160 ? s.Say[..160] + "…" : s.Say), s.Say.StartsWith("app: ") ? LogLevel.Ok : LogLevel.Info);
                    StateChanged?.Invoke(s);
                }
            }
            if (hits.TryGetValue("GFPLAYERS", out var pl) && pl.Tick > _lastPlayersTick)
            {
                var list = Roster.ParsePlayers(pl.Body);
                if (list != null) { _lastPlayersTick = pl.Tick; PlayersRich = true; UpdatePlayers(list); }
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
        CheckTimeouts();
        StatusChanged?.Invoke();
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
    /// <summary>Verbs that change or end the level: sent once, never retried, and every retry is paused
    /// until the NEXT state line arrives from the new level (or 40 s pass).</summary>
    private static readonly HashSet<string> OneShot = new(StringComparer.OrdinalIgnoreCase) { "restart", "restartround", "relaunch", "endmatch", "endround", "switch" };
    private DateTime _retryPausedUntil = DateTime.MinValue;

    /// <summary>Queue a command: payload lines + seq + go. Returns the queue entry (state flips on the ack).</summary>
    public QueuedCommand Send(string label, IEnumerable<string> payload, int priority = 10)
    {
        var seq = ++_prefs.CommandSeq;
        var lines = Commands.Fire(payload, seq);
        var action = lines.Select(l => l.StartsWith("set gf_cmd_action ", StringComparison.Ordinal) ? l["set gf_cmd_action ".Length..].Trim() : null).FirstOrDefault(a => a != null);
        var oneShot = action != null && OneShot.Contains(action);
        if (oneShot) _retryPausedUntil = DateTime.UtcNow.AddSeconds(40);
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
