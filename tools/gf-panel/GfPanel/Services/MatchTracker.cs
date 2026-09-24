using GfPanel.Game;

namespace GfPanel.Services;

/// <summary>
/// How every match went, for the saved log (klaze 2026-09-23: "build out the log system with saves. can we
/// log what users do in their menus too?" - after a Miami match dropped everyone to the lobby and nothing
/// on the box could say why). UI thread only. Fed each NEW state line, each tick, each menu-log (GFLOG)
/// collection and the game closing; it writes Activity entries (screen + file) and file-only detail lines.
///
///  - a match starts: map / mode / match id ("already running" when the panel met it mid-match);
///  - rounds start and end; the match ends (mo=1 = the FINAL round's end screen, not any round's);
///  - the state feed stops: after the match-over screen = a normal end; after a level-changing command the
///    panel sent = ended by the panel; otherwise ABRUPT - mid-round, or after a round end with no next
///    round (the "crashed the lobby" case). An abrupt end writes the last raw state line, the roster, the
///    last menu actions and flags a last action that printed no confirmation;
///  - every menu action, in seq order, stamped with the game-side time it happened;
///  - a one-line summary per match (file).
/// A feed that goes quiet and comes back under the same match id was a stall, and says so.
/// </summary>
public sealed class MatchTracker
{
    private readonly Action<DateTime, string, LogLevel> _log;
    private readonly Action<string> _detail;
    private readonly Func<IReadOnlyList<GfPlayer>> _roster;

    public MatchTracker(Action<DateTime, string, LogLevel> log, Action<string> detail, Func<IReadOnlyList<GfPlayer>> roster)
    {
        _log = log;
        _detail = detail;
        _roster = roster;
    }

    private sealed class Match
    {
        public string Key = "";
        public long Mid;
        public string Map = "", Gametype = "";
        public DateTime FirstAt, LastAt;
        public GfState Last = null!;
        public string LastRaw = "";
        public bool Attached, Silent, Closed;
        public DateTime GaspDeadline;
        public int PeakEnts = -1, PeakHumans, MaxRound = 1;
        public long LoggedSeq;
        public readonly SortedDictionary<long, (MenuAction A, DateTime FirstSeen)> Pending = new();
        public readonly List<(MenuAction A, DateTime At)> Recent = new();
        public int MenuCount;
        public string EndedHow = "";
    }

    private Match? _cur;
    private Match? _prev;                       // the last closed match: a late GFLOG read may still be its
    private (string Verb, DateTime At)? _levelVerb;

    /// <summary>A quiet period between rounds of a round-based mode (end screen, map_restart, pre-round).</summary>
    public static readonly TimeSpan RoundGap = TimeSpan.FromSeconds(75);
    /// <summary>Quiet while the match was playing: the feed publishes every second, so this is a stop.</summary>
    public static readonly TimeSpan PlayGap = TimeSpan.FromSeconds(12);
    /// <summary>Quiet after the match-over screen: the level is leaving for the lobby.</summary>
    public static readonly TimeSpan OverGap = TimeSpan.FromSeconds(20);

    public long CurrentMatchId => _cur?.Mid ?? 0;
    public long LoggedSeq => _cur?.LoggedSeq ?? 0;
    public bool HasPending => _cur is { Pending.Count: > 0 };
    /// <summary>The feed just went quiet: GameLink collects every copy of GFSTATE and GFLOG once (the last gasp)
    /// and hands them to <see cref="OnLastGasp"/>.</summary>
    public bool WantLastGasp { get; private set; }

    /// <summary>The panel sent a level-changing command (restart / relaunch / end / switch): a stop right after
    /// it is the panel's doing, not a crash.</summary>
    public void NoteLevelVerb(string verb, DateTime at) => _levelVerb = (verb, at);

    // ─────────────────────────────────────────────────────────────────────────
    // the state feed
    // ─────────────────────────────────────────────────────────────────────────
    public void OnState(GfState s, string raw, DateTime now, IReadOnlyList<GfPlayer> players)
    {
        var m = _cur;
        var key = Key(s);
        // an older payload has no match id: a round count that went DOWN on the same map/mode is a new match
        if (m != null && s.MatchId <= 0 && m.Key == key && s.Round < m.Last.Round) key = m.Key + "#" + s.Tick;

        if (m != null && m.Key == key)
        {
            if (m.Closed)
            {
                _log(now, $"↺ the same match is back after {Span(now - m.LastAt)} quiet - it stalled, it did not end (ignore \"{m.EndedHow}\" above)", LogLevel.Warn);
                m.Closed = false;
                m.EndedHow = "";
            }
            m.Silent = false;
            Transitions(m, s, now);
        }
        else
        {
            if (m != null && !m.Closed) Classify(m, now, "the next match loaded");
            if (m != null) _prev = m;
            m = _cur = Start(s, raw, now);
        }

        m.Last = s;
        m.LastRaw = raw;
        m.LastAt = now;
        m.MaxRound = Math.Max(m.MaxRound, s.Round);
        if (s.Entities > m.PeakEnts) m.PeakEnts = s.Entities;
        var humans = players.Count(p => !p.IsBot);
        if (humans > m.PeakHumans) m.PeakHumans = humans;
    }

    private static string Key(GfState s) => s.MatchId > 0 ? "m:" + s.MatchId : "l:" + s.Map + "|" + s.Gametype;

    private Match Start(GfState s, string raw, DateTime now)
    {
        var m = new Match
        {
            Key = Key(s), Mid = s.MatchId, Map = s.Map, Gametype = s.Gametype, FirstAt = now, LastAt = now, Last = s, LastRaw = raw,
            Attached = s.Round > 1 || s.TimePassedMs > 45000 || s.Phase is "ended" or "roundend",
            MaxRound = s.Round, PeakEnts = s.Entities,
        };
        _log(now, $"▶ match: {s.Gametype} on {Catalog.MapName(s.Map)}" +
                  (m.Attached ? $" (already running: round {s.Round}, {Clock(s.TimePassedMs)} in)" : "") +
                  (s.MatchId > 0 ? $" · id {s.MatchId}" : " · older payload (no match id / menu log)"), LogLevel.Ok);
        _detail("state " + raw);
        return m;
    }

    private void Transitions(Match m, GfState s, DateTime now)
    {
        var p = m.Last;
        if (s.Round != p.Round)
            _log(now, $"▶ round {s.Round} · {Score(s)}", LogLevel.Info);

        if (s.Phase != p.Phase && s.Phase == "ended")
            _log(now, s.MatchOver ? $"■ match over · {Score(s)}" : $"round {s.Round} over · {Score(s)}", s.MatchOver ? LogLevel.Ok : LogLevel.Info);
        else if (s.Phase == "ended" && s.MatchOver && !p.MatchOver)
            _log(now, $"■ match over · {Score(s)}", LogLevel.Ok);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // silence: the tick, the last gasp, the game closing
    // ─────────────────────────────────────────────────────────────────────────
    public void OnTick(DateTime now, bool gameRunning)
    {
        var m = _cur;
        if (m == null || m.Closed || !gameRunning) return;

        if (m.Silent)
        {
            // the last gasp never came back (scanner gone / busy): classify on what we have
            if (now > m.GaspDeadline) { WantLastGasp = false; Classify(m, now, null); }
            return;
        }

        var limit = m.Last.Phase == "ended" ? (m.Last.MatchOver ? OverGap : RoundGap) : PlayGap;
        if (now - m.LastAt < limit) return;
        m.Silent = true;
        m.GaspDeadline = now.AddSeconds(8);
        WantLastGasp = true;
    }

    /// <summary>Every copy of GFSTATE / GFLOG still in the game's memory when the feed went quiet: a newer state
    /// line the regular sweep missed (then the feed is alive, or this is its true last word) and any menu
    /// records not logged yet (flushed now, finished or not).</summary>
    public void OnLastGasp(GfState? newest, string? raw, (long Match, List<MenuAction> Actions)? actions, DateTime now)
    {
        WantLastGasp = false;
        var m = _cur;
        if (m == null) return;

        if (actions is { } a) OnMenuActions(a.Match, a.Actions, now, final: true);

        if (newest != null && raw != null && Key(newest) == m.Key && newest.Tick > m.Last.Tick)
        {
            // where the game clock should be now, by the last line we had
            var expected = m.Last.Tick + (long)(now - m.LastAt).TotalMilliseconds;
            var at = m.LastAt + TimeSpan.FromMilliseconds(newest.Tick - m.Last.Tick);
            m.Last = newest;
            m.LastRaw = raw;
            m.LastAt = at;
            if (newest.Tick >= expected - 5000)
            {
                m.Silent = false;          // the sweep had just missed it - the feed is alive
                return;
            }
        }

        if (m.Silent && !m.Closed) Classify(m, now, null);
    }

    public void OnGameClosed(DateTime now)
    {
        WantLastGasp = false;
        var m = _cur;
        if (m != null && !m.Closed) Classify(m, now, "the game closed");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // how it ended
    // ─────────────────────────────────────────────────────────────────────────
    private void Classify(Match m, DateTime now, string? why)
    {
        m.Closed = true;
        m.Silent = false;
        var s = m.Last;
        var at = m.LastAt;
        // a level-changing command the panel sent up to 20 s before the last state line (or after it)
        var verb = _levelVerb is { } lv && lv.At >= at.AddSeconds(-20) && lv.At <= now ? lv.Verb : null;
        string text;
        LogLevel level;

        if (s.MatchOver)
        {
            m.EndedHow = "normal end";
            text = why == "the game closed" ? "■ the match was over, then the game closed" : "■ match over → lobby";
            level = LogLevel.Ok;
        }
        else if (verb != null)
        {
            m.EndedHow = "ended by the panel (" + verb + ")";
            text = $"the level ended after the panel's '{verb}' (sent {_levelVerb!.Value.At:HH:mm:ss})";
            level = LogLevel.Info;
        }
        else if (why == "the next match loaded")
        {
            m.EndedHow = "replaced before its end was seen";
            text = $"⚠ a new match loaded while this one was still {PhaseWords(s)} - nothing from the panel ended it";
            level = LogLevel.Warn;
        }
        else if (why == "the game closed")
        {
            m.EndedHow = "the game closed mid-match";
            text = $"⚠ the game closed while the match was {PhaseWords(s)} - if nobody quit it, look in crash_reports";
            level = LogLevel.Warn;
        }
        else if (s.Phase == "ended")
        {
            m.EndedHow = "ABRUPT: no next round";
            text = $"⚠ MATCH DROPPED: round {s.Round} ended at {at:HH:mm:ss} and the next round never started - the feed has been quiet {Span(now - at)}";
            level = LogLevel.Warn;
        }
        else
        {
            m.EndedHow = "ABRUPT: mid-round";
            text = $"⚠ MATCH DROPPED mid-round at {at:HH:mm:ss}: the mod went silent while {PhaseWords(s)} and nothing from the panel ended it";
            level = LogLevel.Warn;
        }

        _log(now, text, level);

        if (level == LogLevel.Warn)
        {
            _detail($"last state line ({at:HH:mm:ss.fff}): {m.LastRaw}");
            var players = _roster();
            if (players.Count > 0)
                _detail("roster: " + string.Join(", ", players.Select(p => $"{p.Name} ({p.Kind} {p.Team}{(p.Alive ? "" : ", dead")})")));
            var last = m.Recent.Count > 0 ? m.Recent[^1] : default;
            if (last.A != null)
            {
                var before = at - last.At;
                _detail($"last menu action: {last.At:HH:mm:ss} {last.A.Describe()}  ({Span(before)} before the last state line)");
                if (!last.A.HasResult && before < TimeSpan.FromSeconds(10))
                    _log(now, $"⚠ the last menu action before the stop printed no confirmation: {last.A.Describe()} ({last.At:HH:mm:ss})", LogLevel.Warn);
            }
            foreach (var (a, t) in m.Recent.TakeLast(8))
                _detail($"  {t:HH:mm:ss}  {a.Describe()}");
        }

        _detail($"match summary · {m.Gametype} on {m.Map} · id {m.Mid} · {m.FirstAt:HH:mm:ss}–{at:HH:mm:ss} ({Span(at - m.FirstAt)}{(m.Attached ? ", joined late" : "")})" +
                $" · rounds {m.MaxRound} · {Score(s)} · peak {m.PeakHumans} humans · peak entities {(m.PeakEnts < 0 ? "n/a" : m.PeakEnts.ToString())}" +
                $" · {m.MenuCount} menu actions · {m.EndedHow}");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // menu actions (GFLOG)
    // ─────────────────────────────────────────────────────────────────────────
    /// <summary>Records from a GFLOG collection. Logged in seq order once each has its result, has waited 4 s
    /// without one (plenty of actions print nothing), or <paramref name="final"/> (the last gasp) flushes them.</summary>
    public void OnMenuActions(long match, List<MenuAction> actions, DateTime now, bool final)
    {
        var m = _cur != null && (_cur.Mid == match || _cur.Mid <= 0) ? _cur
              : _prev != null && _prev.Mid == match ? _prev : null;
        if (m == null) return;

        foreach (var a in actions)
        {
            if (a.Seq <= m.LoggedSeq) continue;
            if (!m.Pending.TryGetValue(a.Seq, out var p)) m.Pending[a.Seq] = (a, now);
            else if (!p.A.HasResult && a.HasResult) m.Pending[a.Seq] = (a, p.FirstSeen);
        }

        foreach (var seq in m.Pending.Keys.ToList())
        {
            var (a, first) = m.Pending[seq];
            if (!(a.HasResult || final || now - first >= TimeSpan.FromSeconds(4))) break;   // order: later ones wait behind it
            m.Pending.Remove(seq);
            m.LoggedSeq = seq;
            m.MenuCount++;
            var at = GameTime(m, a.Ms, now);
            m.Recent.Add((a, at));
            if (m.Recent.Count > 16) m.Recent.RemoveAt(0);
            _log(at, "menu · " + a.Describe(), LogLevel.Menu);
        }
    }

    /// <summary>A game-side getrealtime() ms as wall time, through the last state line's tick.</summary>
    private static DateTime GameTime(Match m, long ms, DateTime now)
    {
        if (ms <= 0 || m.Last.Tick <= 0) return now;
        var at = m.LastAt - TimeSpan.FromMilliseconds(m.Last.Tick - ms);
        return at > now.AddSeconds(2) || at < now.AddHours(-2) ? now : at;
    }

    // ─────────────────────────────────────────────────────────────────────────
    private static string Score(GfState s) => $"score {s.ScoreA}–{s.ScoreX}";

    private static string PhaseWords(GfState s) => (s.Phase switch
    {
        "playing" => "playing",
        "prematch" => "in its pre-match countdown",
        "roundend" => "ending a round",
        "ended" => "on a round's end screen",
        "" => "in an unknown phase",
        _ => "in phase " + s.Phase,
    }) + $" (round {s.Round}, {Clock(s.TimePassedMs)} in)";

    private static string Clock(int ms) => ms <= 0 ? "0:00" : $"{ms / 60000}:{ms / 1000 % 60:00}";

    private static string Span(TimeSpan t) =>
        t.TotalSeconds < 90 ? $"{t.TotalSeconds:0} s" : t.TotalMinutes < 90 ? $"{(int)t.TotalMinutes}:{t.Seconds:00} min" : $"{t.TotalHours:0.0} h";
}
