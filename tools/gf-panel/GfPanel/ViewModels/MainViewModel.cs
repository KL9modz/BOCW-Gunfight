using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Data;
using System.Windows.Threading;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

public sealed class SearchHit
{
    public required string Label { get; init; }
    public required string Sub { get; init; }
    public required string Where { get; init; }
    public SettingRowVM? Row { get; init; }
    public string? Tab { get; init; }
}

/// <summary>One banned XUID with its own Unban button: a banned player never reappears in the roster, so the
/// row's right-click Unban could not be reached - the only way out was Clear bans (2026-09-24 panel review).</summary>
public sealed record BanRowVM(string Xuid, string Name, RelayCommand Unban);

public sealed class FavGroupVM
{
    public string Title { get; init; } = "";
    public ObservableCollection<object> Items { get; } = new();   // SettingRowVM or SectionVM
}

/// <summary>The window's model: the link, the settings, the sidebar, the tabs. One instance for the app's life.</summary>
public sealed class MainViewModel : ObservableObject
{
    public Prefs Prefs { get; }
    public GameLink Link { get; }
    public ConfigWriter Writer { get; }
    public TracksService Tracks { get; }
    public PlayersVM Players { get; }
    public ToolsVM Tools { get; }
    public MessageVM Message { get; }
    public MapsVM Maps { get; }
    public SpawnsVM Spawns { get; }
    public ConsoleVM Console { get; }
    public InjectVM Inject { get; }
    public BotsVM Bots { get; }
    public PropsVM Props { get; }
    public ForgeVM Forge { get; }
    /// <summary>The ENTITIES tab: every prop / barrel / vehicle the mod spawned (GFENTS) - bocw-84 2026-09-23.</summary>
    public EntitiesVM Entities { get; }
    /// <summary>TOOLS → RADAR &amp; MARKERS (gf_radar) + the parachute quick-set.</summary>
    public RadarVM Radar { get; }
    /// <summary>TOOLS → FUN PACK (the cloud branch's fun pack, ported 2026-09-24): the GSC `fun` verb.</summary>
    public FunVM Fun { get; }
    /// <summary>TOOLS → MENU BACKDROP: the two LUIelemBar boxes behind the centre line (gf_hb0) and the hint row (gf_hb1).</summary>
    public HudBoxVM[] HudBoxes { get; }
    /// <summary>The ACTIVITY list through the filter chips (all / menu log / no sent lines / one player's menu log).</summary>
    public ICollectionView ActivityView { get; }
    public ToastsVM Toasts { get; } = new();
    public List<SectionVM> Sections { get; } = new();
    public IEnumerable<SectionVM> DashboardSections => Sections.Where(s => s.Tab == "dashboard");
    public IEnumerable<SectionVM> AdvancedSections => Sections.Where(s => s.Tab == "advanced");
    public IEnumerable<SectionVM> ToolsSections => Sections.Where(s => s.Tab == "tools");
    public ObservableCollection<FavGroupVM> Favorites { get; } = new();
    public ObservableCollection<SearchHit> SearchHits { get; } = new();
    private readonly Dictionary<string, SettingRowVM> _rows = new();
    public Window? Owner { get; set; }
    private readonly DispatcherTimer _clock;

    public MainViewModel(Prefs prefs)
    {
        Prefs = prefs;
        Link = new GameLink(Application.Current.Dispatcher, prefs);
        Writer = new ConfigWriter(Link);
        Tracks = new TracksService(Link);
        foreach (var s in Schema.Sections)
        {
            var vm = new SectionVM(this, s) { IsExpanded = !prefs.Collapsed.Contains("sec:" + s.Title) };
            vm.ExpandedChanged += sec =>
            {
                if (sec.IsExpanded) prefs.Collapsed.Remove(sec.Key); else if (!prefs.Collapsed.Contains(sec.Key)) prefs.Collapsed.Add(sec.Key);
                prefs.Save();
            };
            Sections.Add(vm);
            foreach (var r in vm.Rows) { _rows[r.Dvar] = r; r.IsFavorite = prefs.Favorites.Contains(r.Dvar); }
            vm.IsFavorite = prefs.Favorites.Contains(vm.Key);
        }
        Players = new PlayersVM(this);
        Tools = new ToolsVM(this);
        Message = new MessageVM(this);
        Spawns = new SpawnsVM(this);
        Maps = new MapsVM(this);
        Console = new ConsoleVM(this);
        Inject = new InjectVM(this);
        Bots = new BotsVM(this);
        Props = new PropsVM(this);
        Forge = new ForgeVM(this);
        Entities = new EntitiesVM(this);
        Radar = new RadarVM(this);
        Fun = new FunVM(this);
        // defaults = the GSC's hudbox_think fallbacks (guesses to tune live)
        HudBoxes = new[]
        {
            new HudBoxVM(this, "Behind the centre line", "gf_hb0", 30, 18, 128, 12, 8),
            new HudBoxVM(this, "Behind the hint row", "gf_hb1", 30, 46, 128, 12, 8),
        };
        ActivityView = CollectionViewSource.GetDefaultView(Link.Activity);
        ActivityView.Filter = o => o is LogEntry e && ActivityPass(e);
        Tracks.Changed += RefreshTracks;
        RefreshTracks();
        RebuildFavorites();
        Link.StatusChanged += OnStatus;
        Link.StateChanged += OnState;
        Link.PlayersChanged += OnPlayers;
        Link.ConfigChanged += OnConfig;
        Link.LobbyChanged += OnLobby;
        Link.Toast += (t, l) => Toasts.Show(t, l);
        Link.Sender.LineSent += (line, _) => Application.Current.Dispatcher.BeginInvoke(() => Console.Add(line, "in"));
        Link.Log(App.DryRun ? "DRY RUN - commands are logged, nothing is sent" : "Gunfight Host Panel ready - waiting for the game", App.DryRun ? LogLevel.Warn : LogLevel.Info);
        if (App.Fake) LoadFake();
        _clock = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _clock.Tick += (_, _) => UpdateClock();
        _clock.Start();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // header / status
    // ─────────────────────────────────────────────────────────────────────────
    private string _statusText = "● Disconnected", _statusKind = "off", _sweepText = "";
    private bool _wasLive;
    public string StatusText { get => _statusText; set => Set(ref _statusText, value); }
    public string StatusKind { get => _statusKind; set => Set(ref _statusKind, value); }
    public string SweepText { get => _sweepText; set => Set(ref _sweepText, value); }
    public bool IsLive => Link.BridgeListening && Link.GameRunning;
    public bool MenuLive => Link.StateFreshNow;
    public string DryRunBadge => App.DryRun ? "DRY RUN" : "";

    private void OnStatus()
    {
        if (!Link.GameRunning) { StatusText = "● Game not running"; StatusKind = "off"; }
        else if (!Link.BridgeListening) { StatusText = "● Game up · bridge NOT loaded"; StatusKind = "err"; }
        else if (!Link.StateFreshNow)
        {
            // stale strings from an ended match stay in the pool: tell the two cases apart
            if (Link.StateSeenThisProcess) StatusText = $"● Bridge up · no match running (last state {(int)Link.SinceState.TotalSeconds} s ago)";
            else if (Link.ConfigFreshNow || Link.Players.Count > 0) StatusText = "● Bridge up · older payload (no state line)";
            else StatusText = "● Bridge up · menu not linked";
            StatusKind = "warn";
        }
        else if (Link.State!.Err > 0) { StatusText = $"● Connected · state_build error ×{Link.State.Err} (stage {Link.State.Stage})"; StatusKind = "err"; }
        else { StatusText = "● Connected"; StatusKind = "on"; }
        SweepText = Link.GameRunning ? $"sweep {Link.SweepMs:0} ms · {Link.SweepInfo}" + (Link.LastError != null ? " · " + Link.LastError : "") : "";
        var live = IsLive;
        OnPropertyChanged(nameof(IsLive)); OnPropertyChanged(nameof(MenuLive));
        if (live != _wasLive) { _wasLive = live; foreach (var r in _rows.Values) r.NotifyLive(); }
        Inject.Refresh();
        UpdateClock();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // sidebar: server card, scoreboard, match control
    // ─────────────────────────────────────────────────────────────────────────
    private string _mapText = "—", _gtText = "—", _playersText = "—", _phaseText = "—", _timerText = "—", _roundText = "R —",
                   _scoreA = "—", _scoreX = "—", _aliveA = "—", _aliveX = "—", _teamsText = "", _stagedText = "", _hostText = "", _spawnText = "";
    public string MapText { get => _mapText; set => Set(ref _mapText, value); }
    public string GametypeText { get => _gtText; set => Set(ref _gtText, value); }
    public string PlayersText { get => _playersText; set => Set(ref _playersText, value); }
    public string PhaseText { get => _phaseText; set => Set(ref _phaseText, value); }
    public string TimerText { get => _timerText; set => Set(ref _timerText, value); }
    public string RoundText { get => _roundText; set => Set(ref _roundText, value); }
    public string ScoreA { get => _scoreA; set => Set(ref _scoreA, value); }
    public string ScoreX { get => _scoreX; set => Set(ref _scoreX, value); }
    public string AliveA { get => _aliveA; set => Set(ref _aliveA, value); }
    public string AliveX { get => _aliveX; set => Set(ref _aliveX, value); }
    public string TeamsText { get => _teamsText; set => Set(ref _teamsText, value); }
    public string StagedText { get => _stagedText; set => Set(ref _stagedText, value); }
    public string HostText { get => _hostText; set => Set(ref _hostText, value); }
    public string SpawnText { get => _spawnText; set => Set(ref _spawnText, value); }
    private bool _paused;
    public bool Paused { get => _paused; set { if (Set(ref _paused, value)) OnPropertyChanged(nameof(PauseLabel)); } }
    public string PauseLabel => Paused ? "▶  RESUME MATCH" : "⏸  PAUSE MATCH";
    private bool _frozen;
    public bool Frozen { get => _frozen; set { if (Set(ref _frozen, value)) OnPropertyChanged(nameof(FreezeLabel)); } }
    public string FreezeLabel => Frozen ? "UNFREEZE ALL" : "FREEZE ALL";

    private string _lastMap = "";
    private int _lastRound = -1;
    private DateTime _matchStartedAt;

    private void OnState(GfState? s)
    {
        if (s == null)
        {
            MapText = GametypeText = PlayersText = PhaseText = TimerText = "—"; RoundText = "R —";
            ScoreA = ScoreX = AliveA = AliveX = "—"; TeamsText = StagedText = HostText = SpawnText = "";
            Maps.OnState(null);
            Spawns.OnState(null);
            Entities.Clear();
            return;
        }
        MapText = Catalog.MapName(s.Map) + "  " + s.Map;
        GametypeText = s.Gametype;
        PlayersText = $"{s.PlayersA + s.PlayersX + s.Spectators} online · A {s.PlayersA} ({s.BotsA}b) · X {s.PlayersX} ({s.BotsX}b)" + (s.Spectators > 0 ? $" · {s.Spectators} spec" : "");
        PhaseText = (s.Phase switch { "prematch" => "PRE-MATCH", "ended" => s.MatchOver ? "MATCH OVER" : "ROUND OVER", "roundend" => "ROUND ENDING", "playing" => s.Overtime ? "OVERTIME" : "PLAYING", _ => s.Phase.ToUpperInvariant() }) + (s.Paused ? " · PAUSED" : "");
        RoundText = "R " + s.Round;
        ScoreA = s.ScoreA.ToString(); ScoreX = s.ScoreX.ToString();
        AliveA = s.AliveA.ToString(); AliveX = s.AliveX.ToString();
        TeamsText = $"{s.TeamSize}v{s.TeamSize} · budget {s.MaxClients}";
        StagedText = s.StagedMap.Length > 0 ? $"next: {Catalog.MapName(s.StagedMap)} / {s.StagedGametype}" : "";
        HostText = s.Host;
        SpawnText = s.SpawnNote.Length > 0 ? s.SpawnNote : "—";
        Paused = s.Paused; Frozen = s.FrozenAll;
        Maps.OnState(s);
        Spawns.OnState(s);
        Props.OnState();
        Tools.NotifyMap();
        UpdateClock();
        // a new match / map: re-push the bans + the staged team plan, stage the rotation's next map
        var newMatch = s.Map != _lastMap || (s.Round == 1 && _lastRound > 1);
        if (newMatch)
        {
            _lastMap = s.Map; _matchStartedAt = DateTime.UtcNow;
            Link.SeedSeq();
            RepushSession();
            if (Prefs.PlaylistEnabled) Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Background, async () => { await Task.Delay(20000); Maps.StageNext("new match"); });
        }
        _lastRound = s.Round;
        OnPropertyChanged(nameof(MenuLive));
    }

    private void UpdateClock()
    {
        var s = Link.State;
        if (s == null || !Link.StateFreshNow) { if (s == null) TimerText = "—"; return; }
        if (s.Overtime) { TimerText = "OT"; return; }
        if (s.TimeLimitMs <= 0) { TimerText = "∞"; return; }
        var left = s.TimeLeftMs - (s.Paused ? 0 : (int)(DateTime.UtcNow - _stateAtUtc).TotalMilliseconds);
        left = Math.Max(0, left);
        TimerText = $"{left / 60000}:{left % 60000 / 1000:00}";
    }
    private DateTime _stateAtUtc => DateTime.UtcNow - TimeSpan.FromMilliseconds(Math.Max(0, (DateTime.UtcNow - _lastStateLocal).TotalMilliseconds));
    private DateTime _lastStateLocal = DateTime.UtcNow;

    private void RepushSession()
    {
        foreach (var x in Prefs.Bans) Link.Send("ban " + x, Commands.Action("banx", x), 3);
        // the menu's Props → Favourites page reads gf_prop_favs live when it opens (bocw-c2): keep the
        // dvars in the game without a pulse, so the page is right even if nobody clicked Push
        if (Prefs.PropFavorites.Count > 0) _ = Link.SendRaw(PropCatalog.FavLines(Prefs.PropFavorites).Lines, 3);
    }

    public RelayCommand RefreshPlayers => new(() => { Link.RequestRefresh(); Toasts.Show("Re-scanning for the current roster", LogLevel.Info); });
    /// <summary>The ACTIVITY header's folder button: the saved daily logs (ActivityFile), today's selected.</summary>
    public RelayCommand OpenLogs => new(() =>
    {
        try { ActivityFile.OpenFolder(); }
        catch (Exception e) { Toasts.Show("Could not open the log folder: " + e.Message, LogLevel.Err); }
    });
    public RelayCommand PauseResume => new(() => Link.Send(Paused ? "Resume match" : "Pause match", Commands.Action(Paused ? "resume" : "pause")));
    // explicit pair (the toggle label only flips on a GFSTATE readback, which an older payload never sends);
    // the flag flips optimistically on the click and the next state line corrects it
    public RelayCommand PauseCmd => new(() => { Link.Send("Pause match", Commands.Action("pause")); Paused = true; });
    public RelayCommand ResumeCmd => new(() => { Link.Send("Resume match", Commands.Action("resume")); Paused = false; });
    public RelayCommand FreezeAll => new(() => { var on = !Frozen; Link.Send(on ? "Freeze all" : "Unfreeze all", Commands.Action("freezeall", on ? "on" : "off")); Frozen = on; });
    public RelayCommand EndRoundAllies => new(() => Link.Send("End round → allies", Commands.Action("endround", "allies")));
    public RelayCommand EndRoundAxis => new(() => Link.Send("End round → axis", Commands.Action("endround", "axis")));
    public RelayCommand EndRoundDraw => new(() => Link.Send("End round → draw", Commands.Action("endround", "draw")));
    public RelayCommand RestartRound => new(() => { if (Confirm("Restart the ROUND?\n\nmap_restart(true): the current round starts over, scores and round count kept.")) Link.Send("Restart round", Commands.Action("restartround")); });
    public RelayCommand RelaunchMatch => new(() => { if (Confirm("RELAUNCH the match?\n\nThe full reload F7 gives: a session switch to the current map + mode. Takes ~25 s (the switch wait) - everyone sees the loading screen.")) Link.Send("Relaunch match", Commands.Action("relaunch")); });
    public RelayCommand RestartMatchCmd => new(RestartMatch);
    public RelayCommand EndMatch => new(() => { if (Confirm("END the match now?\n\nThe host end (globallogic::forceend): the match ends immediately with the host-ended reason, the scoreboard shows, everyone returns to the lobby.")) Link.Send("End match", Commands.Action("endmatch")); });
    public void RestartMatch() { if (Confirm("Restart the MATCH?\n\nScores go back to 0-0 and the match starts again at round 1 on the same map.")) Link.Send("Restart match", Commands.Action("restart")); }
    public RelayCommand BalanceHumans => new(() => Link.Send("Balance humans", Commands.Action("balance")));
    public RelayCommand FillBots => new(() => Link.Send("Fill with bots", Commands.Action("fillbots")));
    public RelayCommand RemoveBots => new(() => Link.Send("Remove all bots", Commands.Action("removebots")));
    public RelayCommand Countdown => new(() => Link.Send("Countdown 5..1 GO", Commands.Action("countdown")));
    public RelayCommand ApplyAllLive => new(() => Link.Send("apply all", Commands.Action("apply", "all")));
    // klaze 2026-09-23: a give-all / take-all pair for the client menus (menuall on|off; host + bots skipped)
    public RelayCommand MenuAllOn => new(() => Link.Send("Give EVERYONE a client menu", Commands.Action("menuall", "on")));
    public RelayCommand MenuAllOff => new(() => { if (Confirm("Take back EVERY client menu?")) Link.Send("Take back all client menus", Commands.Action("menuall", "off")); });

    // ── ACTIVITY filter chips (klaze 2026-09-23 "can we see log what people do in their menu from app?": the menu
    //    log lines are "menu · <who> › <page> › <item> → <result>", saved to disk too) ──
    private string _activityFilter = "all";
    public string ActivityFilterText => _activityFilter switch
    {
        "menu" => "showing: menu actions",
        "nosent" => "showing: all but sent lines",
        var f when f.StartsWith("player:") => "showing: " + f[7..] + "'s menu actions",
        _ => "",
    };
    public bool ActivityFiltered => _activityFilter != "all";
    private void SetActivityFilter(string f)
    {
        _activityFilter = f;
        ActivityView.Refresh();
        OnPropertyChanged(nameof(ActivityFilterText)); OnPropertyChanged(nameof(ActivityFiltered));
    }
    private bool ActivityPass(LogEntry e) => _activityFilter switch
    {
        "menu" => e.Level == LogLevel.Menu,
        "nosent" => e.Level != LogLevel.In,
        var f when f.StartsWith("player:") => e.Level == LogLevel.Menu && e.Text.StartsWith("menu · " + Trim16(f[7..]), StringComparison.OrdinalIgnoreCase),
        _ => true,
    };
    // the GSC caps a record's player name at 16 characters (gflog_field)
    private static string Trim16(string s) => s.Length > 16 ? s[..16] : s;
    public RelayCommand ActivityAll => new(() => SetActivityFilter("all"));
    public RelayCommand ActivityMenu => new(() => SetActivityFilter("menu"));
    public RelayCommand ActivityNoSent => new(() => SetActivityFilter("nosent"));
    public void FilterActivityToPlayer(string name) { SetActivityFilter("player:" + name); Toasts.Show("ACTIVITY shows " + name + "'s menu actions - 'All' clears it", LogLevel.Info); }

    // ─────────────────────────────────────────────────────────────────────────
    // players / next match / bans
    // ─────────────────────────────────────────────────────────────────────────
    private void OnPlayers(IReadOnlyList<GfPlayer> all, IReadOnlyList<GfPlayer> joined, IReadOnlyList<GfPlayer> left)
    {
        Players.Update(all, Link.PlayersRich);
        Message.RefreshAudiences();
        Forge.RefreshHumans();
        Tools.RefreshStreakTargets();
        foreach (var p in joined)
        {
            Link.Log(p.Name + " joined", LogLevel.Ok);
            if (Prefs.JoinToast) Toasts.Show(p.Name + " joined", LogLevel.Ok);
            if (Prefs.JoinBeep) try { System.Media.SystemSounds.Asterisk.Play(); } catch { }
        }
        foreach (var p in left) Link.Log(p.Name + " left", LogLevel.Warn);
        if (Link.State == null && all.Count > 0 && StatusKind != "on") OnStatus();
    }

    public void StagePlayer(PlayerRowVM p, string code)
    {
        if (string.IsNullOrEmpty(p.Xuid)) { Toasts.Show("No XUID for " + p.Name, LogLevel.Err); return; }
        if (code == "") Prefs.TeamPlan.Remove(p.Xuid); else Prefs.TeamPlan[p.Xuid] = code;
        Prefs.Save();
        NotifySession();
        Link.Send($"stage {p.Name} → {(code == "" ? "unstaged" : code.ToUpperInvariant())}", Commands.Action("stage", code == "" ? "-" : code, p.Name));
    }
    public RelayCommand StageApply => new(() => Link.Send("Apply staged plan", Commands.Action("stageapply")));
    public RelayCommand StageClearAll => new(() => { Prefs.TeamPlan.Clear(); Prefs.Save(); NotifySession(); Link.Send("Clear staged plan", Commands.Action("stageclear")); });
    public string StagedPlanText => Prefs.TeamPlan.Count == 0 ? "no plan" : string.Join(", ", Prefs.TeamPlan.Select(kv => (Prefs.KnownNames.GetValueOrDefault(kv.Key) ?? kv.Key) + ":" + kv.Value.ToUpperInvariant()));

    public void BanPlayer(PlayerRowVM p)
    {
        if (!string.IsNullOrEmpty(p.Xuid) && !Prefs.Bans.Contains(p.Xuid)) { Prefs.Bans.Add(p.Xuid); Prefs.Save(); }
        Link.Send("Ban " + p.Name, Commands.Action("ban", null, p.Name));
        NotifySession();
    }
    public void UnbanXuid(string xuid)
    {
        Prefs.Bans.Remove(xuid); Prefs.Save(); NotifySession();
        Link.Send("Unban " + (Prefs.KnownNames.GetValueOrDefault(xuid) ?? xuid), Commands.Action("unbanx", xuid));
    }
    public string BansText => Prefs.Bans.Count == 0 ? "none" : string.Join(", ", Prefs.Bans.Select(x => Prefs.KnownNames.GetValueOrDefault(x) ?? x));
    public List<BanRowVM> BanRows => Prefs.Bans.Select(x => new BanRowVM(x, Prefs.KnownNames.GetValueOrDefault(x) ?? x, new RelayCommand(() => UnbanXuid(x)))).ToList();
    public bool HasBans => Prefs.Bans.Count > 0;
    public RelayCommand ClearBans => new(() => { if (!Confirm($"Clear all {Prefs.Bans.Count} ban(s)?")) return; Prefs.Bans.Clear(); Prefs.Save(); Link.Send("Clear bans", Commands.Action("banclear")); NotifySession(); });
    /// <summary>The team plan / bans changed: the roster pills AND the computed texts (StagedPlanText / BansText never
    /// refreshed after a Stage or a Ban until 2026-09-24).</summary>
    private void NotifySession()
    {
        Players.NotifyPlan();
        foreach (var n in new[] { nameof(StagedPlanText), nameof(BansText), nameof(BanRows), nameof(HasBans) }) OnPropertyChanged(n);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // settings: readback + writes
    // ─────────────────────────────────────────────────────────────────────────
    private void OnConfig(GfConfig c)
    {
        foreach (var (dvar, value) in c.Values)
            if (_rows.TryGetValue(dvar, out var row)) row.SetSilently(value);
        foreach (var row in _rows.Values) { row.NotifyBaseline(); row.NotifyLive(); }
        Bots.OnConfig();
        if (c.Values.TryGetValue("gf_radar", out var radar)) Radar.FromConfig(radar);
    }

    /// <summary>The lobby payload's readback (GFLOBBY): the two lobby rows show what it read, SETUP shows the rest.</summary>
    private void OnLobby(GfLobby l)
    {
        foreach (var (dvar, value) in new[] { ("gf_lobby_maxp", l.Want), ("gf_lobby_spec", l.Spec) })
            if (_rows.TryGetValue(dvar, out var row)) { row.SetSilently(value); row.NotifyBaseline(); }
        Inject.Refresh();
    }

    public int RowValue(string dvar) => _rows.TryGetValue(dvar, out var r) ? r.Value : Schema.ByDvar.GetValueOrDefault(dvar)?.Default ?? 0;

    public void ApplySetting(SettingRowVM row, int value)
    {
        // a typed number is clamped here, on Set, never per keystroke (the box would fight the typing)
        if (row.IsInt && row.Def.Max > row.Def.Min) { value = Math.Clamp(value, row.Def.Min, row.Def.Max); if (row.Value != value) row.SetSilently(value); }
        ApplySettings(new() { [row.Dvar] = value }, row.Label);
    }

    /// <summary>Write one or more settings the menu's way (chunk / bot pack / plain), then the live apply pulse.</summary>
    public async void ApplySettings(Dictionary<string, int> changes, string label)
    {
        if (changes.Count == 0) return;
        if (!IsLive && !App.DryRun) { Toasts.Show("Not connected - nothing sent", LogLevel.Warn); return; }
        var packed = changes.Keys.Any(k => Packing.PackedIndex(k) >= 0 || Packing.BotIndexOf(k) >= 0);
        if (packed && !Writer.CanWritePacked && !App.DryRun)
        {
            Toasts.Show("No config readback from the game yet - a packed write would overwrite its neighbours with defaults. Wait for the menu to link (or restart the match).", LogLevel.Err);
            Link.Log("refused " + label + ": no GFCFG readback yet", LogLevel.Err);
            return;
        }
        var plan = Writer.Compose(changes);
        foreach (var (k, v) in changes) if (_rows.TryGetValue(k, out var r)) r.SetSilently(v);
        var q = await Writer.WriteAsync(plan, Prefs.ApplyLiveOnChange);
        Link.Log((q != null ? "set + apply: " : "set: ") + plan.Summary, LogLevel.Ok);
        if (plan.NeedsRestart)
        {
            if (Confirm($"{plan.Summary}\n\nThe engine applies this by reloading the match. Restart the match now?\n\nNo = it lands at the next match start."))
                Link.Send("Restart match", Commands.Action("restart"));
            else Toasts.Show("Saved - applies at the next match start", LogLevel.Info);
        }
        else if (q == null && plan.Scope == null)
            Toasts.Show(plan.Summary + (changes.Keys.All(k => Schema.ByDvar.TryGetValue(k, out var d) && d.Eff == Eff.Live) ? "" : "  (next round)"), LogLevel.Ok);
        else Toasts.Show(plan.Summary, LogLevel.Ok);
    }

    public void ResetSection(SectionVM sec)
    {
        if (!Confirm($"Reset every setting in {sec.Title} to its default?")) return;
        ApplySettings(sec.Rows.ToDictionary(r => r.Dvar, r => r.Def.Default), sec.Title + " reset");
    }

    // ── config presets (the rcon "Save to cfg" equivalent) ──
    public ObservableCollection<ConfigPreset> ConfigPresets => new(Prefs.ConfigPresets);
    public RelayCommand SavePreset => new(() =>
    {
        var name = Prompt("Save the current settings (every row) as preset:", "");
        if (string.IsNullOrWhiteSpace(name)) return;
        var note = Prompt("Note (optional):", "") ?? "";
        var vals = _rows.ToDictionary(kv => kv.Key, kv => kv.Value.Value);
        var existing = Prefs.ConfigPresets.FirstOrDefault(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
        if (existing != null) { existing.Values = vals; existing.Note = note; }
        else Prefs.ConfigPresets.Add(new ConfigPreset { Name = name.Trim(), Note = note, Values = vals });
        Prefs.Save(); OnPropertyChanged(nameof(ConfigPresets));
        Toasts.Show("Preset saved: " + name, LogLevel.Ok);
    });
    public RelayCommand ApplyPresetCmd => new(p =>
    {
        if (p is not ConfigPreset pr) return;
        // only the fields that differ from what the game holds, so the dvar pool is never blasted
        var diff = pr.Values.Where(kv => _rows.ContainsKey(kv.Key) && RowValue(kv.Key) != kv.Value).ToDictionary(kv => kv.Key, kv => kv.Value);
        if (diff.Count == 0) { Toasts.Show("Preset " + pr.Name + " already matches the live settings", LogLevel.Info); return; }
        if (!Confirm($"Apply preset \"{pr.Name}\"?\n\n{diff.Count} setting(s) differ from the live values.")) return;
        ApplySettings(diff, "preset " + pr.Name);
    });
    public RelayCommand DeletePresetCmd => new(p => { if (p is ConfigPreset pr && Confirm($"Delete preset \"{pr.Name}\"?")) { Prefs.ConfigPresets.Remove(pr); Prefs.Save(); OnPropertyChanged(nameof(ConfigPresets)); } });

    // ─────────────────────────────────────────────────────────────────────────
    // favorites / search / tabs / helpers
    // ─────────────────────────────────────────────────────────────────────────
    public void TogglePin(SettingRowVM row)
    {
        row.IsFavorite = !row.IsFavorite;
        if (row.IsFavorite) Prefs.Favorites.Add(row.Dvar); else Prefs.Favorites.Remove(row.Dvar);
        Prefs.Save(); RebuildFavorites();
        Toasts.Show(row.IsFavorite ? "Pinned to FAVORITES" : "Unpinned", LogLevel.Info);
    }
    public void TogglePin(SectionVM sec)
    {
        sec.IsFavorite = !sec.IsFavorite;
        if (sec.IsFavorite) Prefs.Favorites.Add(sec.Key); else Prefs.Favorites.Remove(sec.Key);
        Prefs.Save(); RebuildFavorites();
        Toasts.Show(sec.IsFavorite ? "Panel pinned to FAVORITES" : "Panel unpinned", LogLevel.Info);
    }
    private void RebuildFavorites()
    {
        Favorites.Clear();
        foreach (var sec in Sections)
        {
            var g = new FavGroupVM { Title = sec.Title };
            if (sec.IsFavorite) { foreach (var r in sec.Rows) g.Items.Add(r); }
            else foreach (var r in sec.Rows.Where(r => r.IsFavorite)) g.Items.Add(r);
            if (g.Items.Count > 0) Favorites.Add(g);
        }
        OnPropertyChanged(nameof(HasFavorites));
    }
    public bool HasFavorites => Favorites.Count > 0;

    private string _search = "";
    public string Search { get => _search; set { if (Set(ref _search, value)) RunSearch(); } }
    public bool SearchOpen => SearchHits.Count > 0;
    private void RunSearch()
    {
        SearchHits.Clear();
        var q = Search.Trim().ToLowerInvariant();
        if (q.Length == 0) { OnPropertyChanged(nameof(SearchOpen)); return; }
        var terms = q.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var hits = Sections.SelectMany(s => s.Rows.Select(r => (s, r)))
            .Select(x => (x.s, x.r, hay: (x.r.Label + " " + x.r.Dvar + " " + x.s.Title + " " + x.r.Tip).ToLowerInvariant()))
            .Where(x => terms.All(t => x.hay.Contains(t)))
            .OrderByDescending(x => x.r.Label.ToLowerInvariant().StartsWith(q) ? 3 : x.r.Dvar.Contains(q) ? 2 : x.r.Label.ToLowerInvariant().Contains(q) ? 1 : 0)
            .Take(12);
        foreach (var (s, r, _) in hits)
            SearchHits.Add(new SearchHit { Label = r.Label, Sub = r.Dvar, Where = (s.Tab == "advanced" ? "ADVANCED › " : s.Tab == "tools" ? "TOOLS › " : s.Tab == "spawns" ? "SPAWNS › " : "DASHBOARD › ") + s.Title, Row = r, Tab = s.Tab });
        OnPropertyChanged(nameof(SearchOpen));
    }
    public event Action<SettingRowVM>? RevealRow;
    public RelayCommand GoToHit => new(p => { if (p is SearchHit h && h.Row != null) { Search = ""; SelectTab(h.Tab!); RevealRow?.Invoke(h.Row); } });

    public event Action<string>? TabRequested;
    public void SelectTab(string tab) => TabRequested?.Invoke(tab);

    public bool Confirm(string text) => MessageBox.Show(Owner!, text, "Gunfight Host Panel", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes;
    public string? Prompt(string text, string initial) => Views.PromptWindow.Ask(Owner, text, initial);
    public void CopyText(string text, string toast)
    {
        try { Clipboard.SetText(text); Toasts.Show(toast, LogLevel.Ok); }
        catch { Toasts.Show("Clipboard blocked", LogLevel.Err); }
    }

    private void RefreshTracks()
    {
        Tools.SavedTracks.Clear();
        foreach (var l in Tracks.Labels) Tools.SavedTracks.Add(l);
        if (Tools.SelectedTrack == null && Tools.SavedTracks.Count > 0) Tools.SelectedTrack = Tools.SavedTracks[0];
    }

    /// <summary>--dry --fake: sample GFPLAYERS / GFENTS bodies through the real parsers (screenshot checks only).</summary>
    private void LoadFake()
    {
        var roster = Roster.ParsePlayers("5|0;8bit;allies;host;1000001;1;350;7;2;gF|1;KL9;axis;human;a000000000000001;1;200;4;5;mF|2;[CLAN]Player0123;axis;human;a000000000000002;0;90;1;3;m|3;Player4;allies;human;a000000000000003;1;120;2;2;|4;bot Kasper;allies;bot;;1;50;1;4;");
        if (roster != null) Players.Update(roster, true);
        var ents = EntityList.Parse("v,41,RC-XD,8bit,300,1200,-450,50,;v,57,Hind gunship,KL9,1650,-200,900,400,o;p,63,usa_dumpster_01_full,8bit,250,1000,-600,0,;b,64,rus_oil_drum_01,KL9,800,300,50,0,;p,70,nt6_arcade_game,[CLAN]Player012,1200,-900,-1200,0,");
        Entities.LoadFake(ents);
        Radar.FromConfig(1 + 8 + 256 * 1);
    }

    public void Shutdown()
    {
        Prefs.Save();
        Link.Dispose();
    }
}
