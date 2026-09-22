using System.Collections.ObjectModel;
using GfPanel.Game;

namespace GfPanel.ViewModels;

/// <summary>A roster row with every per-client verb the Players page has (gf_cmd_target + *one verbs).</summary>
public sealed class PlayerRowVM : ObservableObject
{
    private readonly MainViewModel _main;
    public GfPlayer P { get; private set; }
    public string Name => P.Name;
    public string Team => P.Team;
    public string TeamLabel => P.Team switch { "allies" => "A", "axis" => "X", "spec" => "S", _ => "?" };
    public string Kind => P.Kind;
    public bool IsBot => P.IsBot;
    public bool IsHost => P.IsHost;
    public bool IsHuman => !P.IsBot;
    public bool Alive => P.Alive;
    public int Score => P.Score;
    public string Kd => $"{P.Kills}/{P.Deaths}";
    public string Xuid => P.Xuid;
    public int EntNum => P.EntNum;
    public string Tag => P.IsBot ? "BOT" : P.IsHost ? "HOST" : "";
    public string Flags => string.Concat(P.God ? "god " : "", P.Fly ? "fly " : "", P.ThirdPerson ? "3p " : "", P.Frozen ? "frozen " : "", P.Riding ? "riding " : "").Trim();
    public bool God => P.God;
    public bool Frozen => P.Frozen;
    public bool Fly => P.Fly;
    public bool ThirdPerson => P.ThirdPerson;
    public string StageCode => _main.Prefs.TeamPlan.TryGetValue(P.Xuid, out var c) ? c : "";
    public bool IsBanned => !string.IsNullOrEmpty(P.Xuid) && _main.Prefs.Bans.Contains(P.Xuid);
    public string Row => $"{Name}";

    public PlayerRowVM(MainViewModel main, GfPlayer p) { _main = main; P = p; }

    public void Update(GfPlayer p)
    {
        P = p;
        foreach (var n in new[] { nameof(Name), nameof(Team), nameof(TeamLabel), nameof(Kind), nameof(Alive), nameof(Score), nameof(Kd), nameof(Tag), nameof(Flags), nameof(God), nameof(Frozen), nameof(Fly), nameof(ThirdPerson), nameof(StageCode), nameof(IsBanned) })
            OnPropertyChanged(n);
    }
    public void NotifyPlan() { OnPropertyChanged(nameof(StageCode)); OnPropertyChanged(nameof(IsBanned)); }

    // ── verbs (each = one acked bridge command aimed at this player by name) ──
    private void Do(string label, string action, string? arg = null) => _main.Link.Send($"{label} → {Name}", Commands.Action(action, arg, Name));
    public RelayCommand MoveAllies => new(() => Do("Move to allies", "move", "allies"));
    public RelayCommand MoveAxis => new(() => Do("Move to axis", "move", "axis"));
    public RelayCommand Spectate => new(() => Do("Spectator", "spectate"));
    public RelayCommand Freeze => new(() => Do("Freeze / unfreeze", "freezeone"));
    public RelayCommand GodMode => new(() => Do("God mode", "godone"));
    public RelayCommand MaxAmmo => new(() => Do("Max ammo", "ammoone"));
    public RelayCommand ThirdPersonCmd => new(() => Do("Third person", "thirdone"));
    public RelayCommand FlyCmd => new(() => Do("Fly", "flyone"));
    public RelayCommand Kill => new(() => Do("Kill", "killone"));
    public RelayCommand TakeWeapon => new(() => Do("Take weapon", "takeone"));
    public RelayCommand Strip => new(() => Do("Strip weapons", "stripone"));
    // forge session 2026-09-20 (klaze: a FULL personal client menu, not just forge): a granted player opens
    // their own mini mod-menu with ADS + Melee - Forge (props + vehicles), Teleport, God / Ammo / 3rd person /
    // Fly, personal speed + jump, Weapons / Camo / Operator / Skin, soft Unlock-all, Display - NOT host admin
    // (kick / team / match) and NOT the globals (gravity / vision). Verb unchanged: forgegrant on|off + target.
    public RelayCommand StreakRcxd => new(() => Do("Give RC-XD", "streak", "recon_car"));
    public RelayCommand StreakBow => new(() => Do("Give Bow (Sparrow)", "streak", "sig_bow_flame"));
    public RelayCommand StreakNuke => new(() => Do("Give Nuke", "streak", "nuke"));
    public RelayCommand StreakPicked => new(() => Do("Give " + _main.Tools.SelectedStreak.Label, "streak", _main.Tools.SelectedStreak.Value));
    public RelayCommand ForgeModeOn => new(() => Do("Forge mode ON", "forgemode", "on"));
    public RelayCommand ForgeModeOff => new(() => Do("Forge mode OFF", "forgemode", "off"));
    public RelayCommand ForgeGrant => new(() => Do("Give client menu", "forgegrant", "on"));
    public RelayCommand ForgeRevoke => new(() => Do("Revoke client menu", "forgegrant", "off"));
    public RelayCommand Kick => new(() => { if (_main.Confirm($"Kick {Name}?")) Do("Kick", "kickone"); });
    public RelayCommand Ban => new(() => { if (_main.Confirm($"Ban {Name}?\n\nKicks now and refuses this XUID at connect (this session, and re-sent by the panel at every match start).")) _main.BanPlayer(this); });
    public RelayCommand Unban => new(() => _main.UnbanXuid(P.Xuid));
    public RelayCommand TpToMe => new(() => Do("Teleport to me", "tpplayer", "tome"));
    public RelayCommand TpMeToThem => new(() => Do("Teleport me to them", "tpplayer", "metothem"));
    public RelayCommand TpSwap => new(() => Do("Swap places", "tpplayer", "swap"));
    public RelayCommand GiveWeapon => new(() => _main.Tools.GiveTo(Name));
    public RelayCommand GivePerks => new(() => Do("Give perks", "perkone", _main.Tools.SelectedPerk?.Key ?? "fastreload"));
    public RelayCommand Speed0 => new(() => Do("Speed global", "speedone", "0"));
    public RelayCommand Speed150 => new(() => Do("Speed 150%", "speedone", "150"));
    public RelayCommand Speed200 => new(() => Do("Speed 200%", "speedone", "200"));
    public RelayCommand Speed50 => new(() => Do("Speed 50%", "speedone", "50"));
    public RelayCommand Camo => new(() => { var v = Math.Clamp(_main.Tools.CamoId, 0, 149); Do("Camo " + v, "camoone", v.ToString()); });
    public RelayCommand Operator => new(() => { var v = Math.Clamp(_main.Tools.OperatorId, 0, 60); Do("Operator " + v, "operatorone", v.ToString()); });
    public RelayCommand Outfit => new(() => { var v = Math.Clamp(_main.Tools.OutfitId, 0, 60); Do("Outfit " + v, "outfitone", v.ToString()); });
    public RelayCommand Message => new(() => _main.Message.TargetPlayer(Name));
    public RelayCommand StageA => new(() => _main.StagePlayer(this, "a"));
    public RelayCommand StageX => new(() => _main.StagePlayer(this, "x"));
    public RelayCommand StageS => new(() => _main.StagePlayer(this, "s"));
    public RelayCommand StageClear => new(() => _main.StagePlayer(this, ""));
    public RelayCommand CopyXuid => new(() => _main.CopyText(P.Xuid, "Copied XUID"));
    public RelayCommand CopyName => new(() => _main.CopyText(P.Name, "Copied name"));
}

public sealed class PlayersVM : ObservableObject
{
    private readonly MainViewModel _main;
    public ObservableCollection<PlayerRowVM> Rows { get; } = new();
    public ObservableCollection<PlayerRowVM> Allies { get; } = new();
    public ObservableCollection<PlayerRowVM> Axis { get; } = new();
    public ObservableCollection<PlayerRowVM> Spectators { get; } = new();
    private string _summary = "Not connected";
    public string Summary { get => _summary; set => Set(ref _summary, value); }
    public bool Rich { get; private set; }
    public bool Any => Rows.Count > 0;

    public PlayersVM(MainViewModel main) { _main = main; }

    public void Update(IReadOnlyList<GfPlayer> list, bool rich)
    {
        Rich = rich;
        var byKey = Rows.ToDictionary(r => r.P.Key);
        var keep = new HashSet<string>();
        foreach (var p in list)
        {
            keep.Add(p.Key);
            if (byKey.TryGetValue(p.Key, out var row)) row.Update(p);
            else Rows.Add(new PlayerRowVM(_main, p));
        }
        foreach (var r in Rows.Where(r => !keep.Contains(r.P.Key)).ToList()) Rows.Remove(r);
        Regroup();
        var humans = list.Count(p => !p.IsBot);
        Summary = list.Count == 0 ? "No players" : $"{list.Count} in the match · {humans} human{(humans == 1 ? "" : "s")} · {list.Count - humans} bot{(list.Count - humans == 1 ? "" : "s")}";
        OnPropertyChanged(nameof(Any));
    }

    private void Regroup()
    {
        void Fill(ObservableCollection<PlayerRowVM> col, string team)
        {
            var want = Rows.Where(r => r.Team == team).OrderBy(r => r.IsBot).ThenBy(r => r.Name).ToList();
            if (col.Select(r => r.P.Key).SequenceEqual(want.Select(r => r.P.Key))) return;
            col.Clear();
            foreach (var r in want) col.Add(r);
        }
        Fill(Allies, "allies"); Fill(Axis, "axis");
        var spec = Rows.Where(r => r.Team != "allies" && r.Team != "axis").ToList();
        if (!Spectators.Select(r => r.P.Key).SequenceEqual(spec.Select(r => r.P.Key))) { Spectators.Clear(); foreach (var r in spec) Spectators.Add(r); }
    }

    public void NotifyPlan() { foreach (var r in Rows) r.NotifyPlan(); }
}
