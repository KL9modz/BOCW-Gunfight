using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>Forge (the in-game prop placer, forge-system session 2026-09-20: docs/notes/forge.md) and the
/// hint-bar lines. The place-mode controls live on the host's body (W/S distance, A/D yaw, jump/crouch
/// height, ADS+W/S scale, attack place, melee next, use prev, frag exit); the app fires the same verbs.</summary>
public sealed class ForgeVM : ObservableObject
{
    private readonly MainViewModel _m;
    public ForgeVM(MainViewModel m) { _m = m; }

    private void Do(string label, string verb, string arg) => _m.Link.Send(label, Commands.Action(verb, arg));

    public RelayCommand Enter => new(() => Do("Forge: enter", "forge", "enter"));
    public RelayCommand Exit => new(() => Do("Forge: exit", "forge", "exit"));
    public RelayCommand Place => new(() => Do("Forge: place", "forge", "place"));
    public RelayCommand Next => new(() => Do("Forge: next model", "forge", "next"));
    public RelayCommand Prev => new(() => Do("Forge: previous model", "forge", "prev"));
    public RelayCommand Clear => new(() => { if (_m.Confirm("Delete ALL props on this map?\n\nRemoves every placed prop and the saved forge layout (game.gf_forge) for this map, so nothing comes back next round.")) Do("Delete all props (forge clear)", "forge", "clear"); });

    // ── grant forge to a non-host player (forgegrant on|off + target; forge session) ──
    public PlayerRowVM? GrantTarget { get; set; }
    public IEnumerable<PlayerRowVM> Humans => _m.Players.Rows.Where(r => !r.IsBot && !r.IsHost);
    public void RefreshHumans() => OnPropertyChanged(nameof(Humans));
    public RelayCommand GrantOn => new(() => { if (GrantTarget == null) { _m.Toasts.Show("Pick a player first", LogLevel.Warn); return; } GrantTarget.ForgeGrant.Execute(null); });
    public RelayCommand GrantOff => new(() => { if (GrantTarget == null) { _m.Toasts.Show("Pick a player first", LogLevel.Warn); return; } GrantTarget.ForgeRevoke.Execute(null); });

    // ── forge MODE (bocw-1c 2026-09-22): tap-to-grab prompts on props (ours + map props within gf_grab_dist)
    //    and move / turn / scale / delete for whoever has it; host grants, not a client-menu feature ──
    public RelayCommand ModeHostOn => new(() => Do("Forge mode ON (host)", "forgemode", "on"));
    public RelayCommand ModeHostOff => new(() => Do("Forge mode OFF (host)", "forgemode", "off"));
    public RelayCommand ModeAllOn => new(() => _m.Link.Send("Forge mode ON for everyone", Commands.Action("forgemode", "all on")));
    public RelayCommand ModeAllOff => new(() => _m.Link.Send("Forge mode OFF for everyone", Commands.Action("forgemode", "all off")));
    public RelayCommand ModeTargetOn => new(() => { if (GrantTarget == null) { _m.Toasts.Show("Pick a player first", LogLevel.Warn); return; } GrantTarget.ForgeModeOn.Execute(null); });
    public RelayCommand ModeTargetOff => new(() => { if (GrantTarget == null) { _m.Toasts.Show("Pick a player first", LogLevel.Warn); return; } GrantTarget.ForgeModeOff.Execute(null); });

    // ── hint bar ──
    public const int ChunkChars = 34;   // `set gf_ho0 "` (12) + 34 + `"` = 47
    private string _others = "Welcome to ^3KL9^7's Gunfight lobby! Join us at ^4discord.gg/blackops";
    public string OthersText { get => _others; set => Set(ref _others, value); }
    private string _build = "^1DO NOT KILL - host is building";
    public string BuildText { get => _build; set => Set(ref _build, value); }
    // klaze 2026-09-23: "Select | Next | Last | Back", capitalised with spacers. 31 chars = the 47-byte slot
    // (`set gf_hint_nav ` + 31), so the mouse buttons read M1 / M2 here; the in-game default keeps LMB / RMB.
    private string _nav = "R Select|M1 Next|M2 Last|V Back";
    public string NavText { get => _nav; set => Set(ref _nav, value); }
    public int MaxHintChars => ChunkChars * 3;
    public int MaxNavChars => 47 - "set gf_hint_nav ".Length;

    /// <summary>gf_ho0/1/2 (always all three, so a shorter text clears the old tail) + hintset arg.</summary>
    public static List<string>? HintLines(string text, string which)
    {
        var t = Commands.Clean(text, ChunkChars * 3);
        var lines = new List<string>();
        for (var c = 0; c < 3; c++)
        {
            var from = c * ChunkChars;
            var chunk = from < t.Length ? t.Substring(from, Math.Min(ChunkChars, t.Length - from)) : "";
            lines.Add($"set gf_ho{c} \"{chunk}\"");
        }
        lines.AddRange(Commands.Action("hintset", which));
        return lines;
    }

    public RelayCommand SetOthers => new(() =>
    {
        if (string.IsNullOrWhiteSpace(OthersText)) { _m.Toasts.Show("Type the line first", LogLevel.Warn); return; }
        _m.Link.Send("Hint bar: others line", HintLines(OthersText, "others")!);
    });
    public RelayCommand SetBuild => new(() =>
    {
        if (string.IsNullOrWhiteSpace(BuildText)) { _m.Toasts.Show("Type the line first", LogLevel.Warn); return; }
        _m.Link.Send("Hint bar: build warning", HintLines(BuildText, "build")!);
    });
    public RelayCommand SetNav => new(async () =>
    {
        // a plain dvar the menu reads live; the whole line must fit the 47-byte slot
        var t = Commands.Clean(NavText, MaxNavChars);
        if (t.Length == 0) { _m.Toasts.Show("Type the legend first", LogLevel.Warn); return; }
        await _m.Link.SendRaw(new[] { $"set gf_hint_nav {t}" }, 8);
        _m.Link.Log("hint bar: nav legend set - " + t, LogLevel.Info);
    });
}
