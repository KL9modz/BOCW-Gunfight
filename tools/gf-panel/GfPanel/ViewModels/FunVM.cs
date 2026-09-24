using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>The cloud branch's FUN PACK (claude/dazzling-wright-2xq7z3: fun pack 1 e1a3a2b + fun pack 2 afb5ac9),
/// ported by hand 2026-09-24 (bocw-84; ESP left out - TOOLS → RADAR &amp; MARKERS already owns those layers).
/// Every switch goes through ONE GSC verb, `fun &lt;what&gt; [args]` (gunfight_menu.gsc fun_verb): on / off are
/// explicit, so a retried command never flips a switch back. This block is host-scope; the per-player switches
/// are on a player's right-click menu (the same verb + gf_cmd_target). Picks travel as INDICES - a model or
/// weapon name would overflow the 47-byte bridge slot - and mirror the GSC fun_*_pick order.
/// NOTHING of it has run in game.</summary>
public sealed class FunVM : ObservableObject
{
    private readonly MainViewModel _m;
    public FunVM(MainViewModel m) { _m = m; }

    /// <summary>CommandParameter = the fun verb's argument, e.g. "slide 150" or "ft spin 0".</summary>
    public RelayCommand Send => new(p =>
    {
        if (p is not string arg || arg.Length == 0) return;
        _m.Link.Send("Fun: " + arg, Commands.Action("fun", arg));
    });

    /// <summary>Fast restart = the existing restartround verb (round_restart: replay this round, score kept).</summary>
    public RelayCommand FastRestart => new(() =>
    {
        if (_m.Confirm("Fast restart: replay THIS round (map_restart, score kept)?"))
            _m.Link.Send("Fast restart (replay the round)", Commands.Action("restartround"));
    });

    // fun_nade_pick order
    public static readonly Named[] NadeTypes =
    {
        new("Molotov", "0"), new("Semtex", "1"), new("Frag", "2"), new("C4", "3"), new("Stun", "4"), new("Flash", "5"),
        new("Smoke", "6"), new("Hatchet", "7"), new("M79 grenade", "8"), new("War Machine grenade", "9"), new("Monkey bomb (Zombies item - may do nothing)", "10"),
    };
    public Named[] NadeTypeList => NadeTypes;
    private Named _nade = NadeTypes[0];
    public Named SelectedNade { get => _nade; set { if (value != null && Set(ref _nade, value)) Send.Execute("nadeswapw " + value.Value); } }

    // fun_cannon_pick order
    public static readonly Named[] CannonModels =
    {
        new("Your forge pick", "0"), new("Chickens", "1"), new("Oil drums", "2"), new("Couches", "3"), new("Mannequins", "4"), new("Energy portals", "5"),
    };
    public Named[] CannonModelList => CannonModels;
    private Named _cannon = CannonModels[0];
    public Named SelectedCannon { get => _cannon; set { if (value != null && Set(ref _cannon, value)) Send.Execute("cannonmodel " + value.Value); } }

    // fun_disg_pick order
    public static readonly Named[] DisguisePicks =
    {
        new("Chicken", "0"), new("Mannequin", "1"), new("Couch", "2"), new("Oil drum", "3"), new("Dog tags", "4"), new("Energy portal", "5"),
    };
    public Named[] DisguiseList => DisguisePicks;
    private Named _disg = DisguisePicks[0];
    public Named SelectedDisguise { get => _disg; set => Set(ref _disg, value); }
    public RelayCommand DisguisePick => new(() => Send.Execute("disg pick " + _disg.Value));
}
