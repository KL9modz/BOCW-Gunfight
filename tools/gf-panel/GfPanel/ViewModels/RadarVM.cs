using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>One radar feature row: a host checkbox and an everyone checkbox.</summary>
public sealed class RadarFeatureVM : ObservableObject
{
    private readonly RadarVM _vm;
    public int Bit { get; }
    public string Label { get; }
    public string Tip { get; }
    private bool _host, _all;
    public bool Host { get => _host; set { if (Set(ref _host, value)) _vm.Push(Label + (value ? " ON" : " OFF") + " (host)"); } }
    public bool All { get => _all; set { if (Set(ref _all, value)) _vm.Push(Label + (value ? " ON" : " OFF") + " (everyone)"); } }
    public RadarFeatureVM(RadarVM vm, int bit, string label, string tip) { _vm = vm; Bit = bit; Label = label; Tip = tip; }
    public void SetSilently(bool host, bool all) { _host = host; _all = all; OnPropertyChanged(nameof(Host)); OnPropertyChanged(nameof(All)); }
}

/// <summary>klaze 2026-09-23: instant radar toggles - constant enemies on the minimap, spy plane, H.A.R.P. (the
/// advanced / Blackbird one), a marker on every enemy, the air-streak enemy glow. ONE plain dvar, gf_radar, written
/// through the acked `radar &lt;n&gt;` verb: bits 0-7 = the host's features, 8-15 = everyone's, 16-18 = the marker icon.
/// The GSC (RADAR &amp; MARKERS block) re-asserts every 0.5 s. Read back from GFCFG misc=.</summary>
public sealed class RadarVM : ObservableObject
{
    private readonly MainViewModel _m;
    private bool _sync;
    public ObservableCollection<RadarFeatureVM> Features { get; } = new();

    public static readonly Named[] Icons =
    {
        new("Enemy ping (red diamond)", "0", "#\"enemy_waypoint\" - the ping system's 'enemy spotted' marker, resident every match; UNMEASURED as a server objective"),
        new("Escort goal (measured)", "1", "#\"escort_goal\" - the race gate icon, MEASURED rendering"),
        new("VIP waypoint", "2", "#\"vip_waypoint\""),
        new("Gunship waypoint", "3", "#\"gunship_waypoint\""),
        new("Teammate ping", "4", "#\"teammate_waypoint\""),
    };

    public RadarVM(MainViewModel m)
    {
        _m = m;
        Features.Add(new RadarFeatureVM(this, 1, "Enemies on minimap", "Constant enemy dots on the minimap - the custom-games 'Radar: Constant' flag, per player (g_compassShowEnemies). Works in every mode."));
        Features.Add(new RadarFeatureVM(this, 2, "Spy plane (UAV)", "The UAV sweep. Free-for-all: per player, stock's FFA UAV (radar_client + hasspyplane) - 'host' = only you. Team modes: team-wide (setteamspyplane + the radar match flag) - 'host' = your whole team. 2026-09-23: the first build had only the team form and did nothing in FFA (measured); the FFA form is untested."));
        Features.Add(new RadarFeatureVM(this, 4, "H.A.R.P. (advanced)", "The advanced spy plane / Blackbird - direction arrows, constant. Free-for-all: per player (radar_client + the H.A.R.P. player field). Team modes: team-wide (function_e72ac8f4, what the streak raises). The FFA form is untested."));
        Features.Add(new RadarFeatureVM(this, 8, "Enemy markers", "A marker over every enemy, through walls, seen only by the viewer (an objective per player). The 'red boxes' stand-in - real debug boxes are dev-only builtins that crash retail. MEASURED working 2026-09-23."));
        Features.Add(new RadarFeatureVM(this, 16, "Enemy glow (pilot view only)", "The glow an AC-130 / cruise-missile pilot sees (thermal_glow_enemies_only). MEASURED 2026-09-23: not drawn on foot - the client only draws it inside a streak's pilot view. Kept to try while riding a menu-spawned AC-130 / Chopper Gunner (VEHICLES → Other) - untested there."));
    }

    public Named[] IconList => Icons;
    private Named _icon = Icons[0];
    public Named SelectedIcon { get => _icon; set { if (value != null && Set(ref _icon, value)) Push("marker icon " + value.Label); } }

    public int Value
    {
        get
        {
            var host = Features.Where(f => f.Host).Sum(f => f.Bit);
            var all = Features.Where(f => f.All).Sum(f => f.Bit);
            return host + all * 256 + int.Parse(_icon.Value) * 65536;
        }
    }

    public void Push(string what)
    {
        if (_sync) return;
        _m.Link.Send("Radar: " + what, Commands.Action("radar", Value.ToString()));
    }

    /// <summary>The game's gf_radar (GFCFG misc=): mirror it without sending anything back.</summary>
    public void FromConfig(int v)
    {
        _sync = true;
        try
        {
            var host = v % 256;
            var all = v / 256 % 256;
            foreach (var f in Features) f.SetSilently(host / f.Bit % 2 == 1, all / f.Bit % 2 == 1);
            var icon = v / 65536 % 8;
            var pick = Icons.FirstOrDefault(i => i.Value == icon.ToString()) ?? Icons[0];
            if (!ReferenceEquals(pick, _icon)) { _icon = pick; OnPropertyChanged(nameof(SelectedIcon)); }
        }
        finally { _sync = false; }
    }

    public RelayCommand AllOff => new(() =>
    {
        _sync = true;
        foreach (var f in Features) f.SetSilently(false, false);
        _sync = false;
        Push("everything OFF");
    });

    // parachutes (gf_parachute 0 off / 1 everyone / 2 host) - also a MOVEMENT setting row on the DASHBOARD
    // the parachute quick-set buttons went in the 2026-09-24 redesign: RULES → MOVEMENT → Parachutes (gf_parachute) sets
    // the same 0 / 1 / 2 with the game's readback
}
