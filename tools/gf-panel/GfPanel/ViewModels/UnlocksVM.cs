using System.Windows.Threading;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>The UNLOCKS tab (klaze 2026-09-24: "proceed incorperating the full entire unlock system and all features
/// into the app") - the GSC `unlock` verb, gunfight_menu.gsc ACCOUNT UNLOCKS block; docs/notes/unlocks.md.
/// Target = you (no gf_cmd_target), one player (gf_cmd_target) or everyone else ("&lt;what&gt; all"). Anyone but the host
/// must ACCEPT on their own screen (hold Use 1 s within 20 s) before the game writes anything to their account.
/// Progress arrives as the game's "say" line (GFSTATE say=, also in ACTIVITY as "game: ..."). NEVER RUN.</summary>
public sealed class UnlocksVM : ObservableObject
{
    private readonly MainViewModel _m;
    private readonly DispatcherTimer _tick;
    private string _humansSig = "";

    public UnlocksVM(MainViewModel m)
    {
        _m = m;
        _tick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _tick.Tick += (_, _) => Poll();
        _tick.Start();
    }

    // ── target ──
    private int _scope;
    public bool ScopeMe { get => _scope == 0; set { if (value) SetScope(0); } }
    public bool ScopePlayer { get => _scope == 1; set { if (value) SetScope(1); } }
    public bool ScopeAll { get => _scope == 2; set { if (value) SetScope(2); } }

    private void SetScope(int s)
    {
        _scope = s;
        OnPropertyChanged(nameof(ScopeMe));
        OnPropertyChanged(nameof(ScopePlayer));
        OnPropertyChanged(nameof(ScopeAll));
    }

    /// <summary>Humans other than the host (bots have no account).</summary>
    public IEnumerable<PlayerRowVM> Humans => _m.Players.Rows.Where(r => !r.IsBot && !r.IsHost);
    private PlayerRowVM? _target;
    public PlayerRowVM? Target { get => _target; set => Set(ref _target, value); }

    // ── the game's latest progress line ──
    private string _lastSay = "";
    public string LastSay { get => _lastSay; private set => Set(ref _lastSay, value); }

    private void Poll()
    {
        var say = _m.Link.State?.Say ?? "";
        if (say.StartsWith("unlock", StringComparison.OrdinalIgnoreCase) && say != _lastSay) LastSay = say;
        var sig = string.Join("|", Humans.Select(h => h.Name));
        if (sig != _humansSig) { _humansSig = sig; OnPropertyChanged(nameof(Humans)); }
    }

    // ── actions ──
    private static string Label(string what) => what switch
    {
        "probe" => "Write check (changes nothing)",
        "weapons" => "Max weapon levels",
        "challenges" => "Complete all challenges",
        "level" => "Max player level",
        "ach" => "All 44 achievements",
        "achmp" => "MP achievements (5)",
        "achzm" => "Zombies achievements (9)",
        "achcp" => "Campaign achievements (25)",
        "achdoa" => "Dead Ops achievements (5)",
        "everything" => "Everything (weapons, challenges, level, achievements)",
        "save" => "Save now (upload stats)",
        _ => what,
    };

    /// <summary>CommandParameter = the verb's first word (probe / weapons / challenges / level / ach* / everything / save).</summary>
    public RelayCommand Run => new(p =>
    {
        if (p is not string what || what.Length == 0) return;
        var label = Label(what);
        var permanent = what is not ("probe" or "save");
        var warn = permanent ? "\n\nThis is a PERMANENT write to the Activision account (the \"manipulation of game data\" Activision bans for)." : "";

        if (_scope == 0)
        {
            if (permanent && !_m.Confirm($"{label} on YOUR account?{warn}")) return;
            _m.Link.Send("Unlock: " + label + " (me)", Commands.Action("unlock", what));
        }
        else if (_scope == 1)
        {
            if (Target == null) { _m.Toasts.Show("Pick a player first", LogLevel.Warn); return; }
            if (!_m.Confirm($"Ask {Target.Name} to accept: {label}?\n\nThey must hold Use for 1 second on their own screen within 20 s. If they don't, nothing is written to their account.{warn}")) return;
            _m.Link.Send($"Unlock: {label} → {Target.Name}", Commands.Action("unlock", what, Target.Name));
        }
        else
        {
            var names = Humans.Select(h => h.Name).ToList();
            if (names.Count == 0) { _m.Toasts.Show("No other humans in the match", LogLevel.Warn); return; }
            if (!_m.Confirm($"Ask everyone else ({string.Join(", ", names)}) to accept: {label}?\n\nEach player must hold Use for 1 second on their own screen within 20 s. Anyone who doesn't is skipped.{warn}")) return;
            _m.Link.Send($"Unlock: {label} → everyone else", Commands.Action("unlock", what + " all"));
        }
    });

    public RelayCommand Stop => new(() => _m.Link.Send("Unlock: stop", Commands.Action("unlock", "stop")));
    public RelayCommand Local => new(() => _m.Link.Send("Unlock: local (loot_fakeall, this PC only)", Commands.Action("unlock", "local")));
}
