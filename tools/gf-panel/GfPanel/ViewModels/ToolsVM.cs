using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>Every action page of the in-game menu (Player / Weapons / Camo / Operator / Outfit / Teleport /
/// Vehicles / Destructibles / Projectiles / Props / Race) plus the rcon-style everyone-state and fun toys
/// the GSC increment added. Each button = one acked bridge command.</summary>
public sealed class ToolsVM : ObservableObject
{
    private readonly MainViewModel _m;
    public ToolsVM(MainViewModel m)
    {
        _m = m;
        WeaponGroups = Catalog.Weapons.Select(g => new WeaponGroupVM(g.Group, g.Items)).ToList();
        SelectedWeapon = WeaponList[0];
        SelectedProjectile = Catalog.Projectiles[0];
        SelectedProp = Catalog.Props[0];
        SelectedVehicle = Catalog.Vehicles.First(v => v.Index == 3);
        SelectedOtherVehicle = Catalog.Vehicles.First(v => v.Kind == 1);
        SelectedSound = Catalog.Sounds[0];
        SelectedVision = Catalog.Visions[0];
        SelectedPerk = Catalog.Perks[0];
        foreach (var p in Catalog.Perks) Perks.Add(new PerkRowVM(this, p));
    }

    private void Do(string label, string action, string? arg = null, string? target = null) => _m.Link.Send(label, Commands.Action(action, arg, target));

    // ── host tools ──
    public RelayCommand Fly => new(() => Do("Fly (host)", "fly"));
    public RelayCommand GodMode => new(() => Do("God mode (host)", "godmode"));
    public RelayCommand ThirdPerson => new(() => Do("Third person (host)", "thirdperson"));
    public RelayCommand MaxAmmo => new(() => Do("Max ammo (host)", "maxammo"));
    public RelayCommand DropWeapon => new(() => Do("Drop weapon", "dropweapon"));
    public RelayCommand UnlockAll => new(() => Do("Unlock all", "unlockall"));
    // the in-game rows these replace are app-only since the 2026-09-23 menu trim (bocw-84)
    public RelayCommand MatchInfo => new(() => Do("Match info to the feed", "matchinfo"));
    public RelayCommand SpawnReport => new(() => Do("Spawn report to the feed", "spawnreport"));
    public RelayCommand ZoneCensus => new(() => Do("Overtime-zone census to the feed", "zonecensus"));
    // klaze 2026-09-24 "lets try \n line breaks" - MEASURED that night: EVERY newline byte closed the match
    // ("Kilo 946 Sick Crocodile": hint bar, centre mid-text x2, centre trailing x3, feed x1) - the text transport,
    // not a widget. These probes send NO newline byte (GSC nltest_run): wrap / wrapfeed = one long line, does the
    // widget wrap; escape = a literal backslash + n; parts = plain text + stock localized keys in one print (all
    // four measured one line). loca..locf = the LOCALIZED separator: a stock string whose own text holds the
    // break (read from the exe: the drop is the client's check on raw text; key text is spliced in after it).
    // CommandParameter = the nltest argument. Close the in-game menu first (its own prints share the screen).
    public RelayCommand TextTest => new(p => { if (p is string a && a.Length > 0) Do("Text test: " + a, "nltest", a); });

    // ── everyone-state (the rcon PLAYER STATE block) ──
    public RelayCommand GodAllOn => new(() => Do("God mode ALL on", "godall", "on"));
    public RelayCommand GodAllOff => new(() => Do("God mode ALL off", "godall", "off"));
    public RelayCommand AmmoAll => new(() => Do("Max ammo ALL", "ammoall"));
    public RelayCommand ThirdAllOn => new(() => Do("Third person ALL on", "thirdall", "on"));
    public RelayCommand ThirdAllOff => new(() => Do("Third person ALL off", "thirdall", "off"));
    // freeze everyone: MATCH → EVERYONE → FREEZE ALL (MainViewModel.FreezeAll - one state-aware toggle read from GFSTATE frz)
    public RelayCommand InvisOn => new(() => Do("Invisible players on", "invisall", "on"));
    public RelayCommand InvisOff => new(() => Do("Invisible players off", "invisall", "off"));
    public RelayCommand DrunkOn => new(() => Do("Drunk mode on", "drunk", "on"));
    public RelayCommand DrunkOff => new(() => Do("Drunk mode off", "drunk", "off"));
    public RelayCommand Quake => new(() => Do("Earthquake", "quake"));
    public RelayCommand FadeProbe => new(() => Do("Fade probe (time the two lines)", "fadeprobe"));
    public RelayCommand PlaySound => new(() => Do("Sound " + SelectedSound.Label, "sound", SelectedSound.Value));
    public RelayCommand VisionApply => new(() => Do("Vision " + VisionName, "vision", VisionName));
    public RelayCommand VisionDefault => new(() => Do("Vision default", "vision", "default"));
    public RelayCommand PerksClear => new(() => { foreach (var p in Perks) p.SetSilently(false); Do("Perks ALL clear", "perkall", "clear"); });
    // ONE command (perkall all - GSC perk_keys()); 39 single toggles would take ~30 s through the paced bridge
    public RelayCommand PerksAll => new(() => { foreach (var p in Perks) p.SetSilently(true); Do("Perks ALL - every perk", "perkall", "all"); });
    public RelayCommand SlowmoApply => new(() => { var t = Math.Clamp(Timescale, 10, 300); Timescale = t; Do($"Timescale {t}%", "slowmo", t.ToString()); });
    public RelayCommand SlowmoReset => new(() => { Timescale = 100; Do("Timescale 100%", "slowmo", "100"); });

    private int _timescale = 100;
    public int Timescale { get => _timescale; set => Set(ref _timescale, value); }   // clamped where used (typing-safe)
    public Named SelectedSound { get; set; }
    public Named SelectedVision { get => _vision; set { _vision = value; VisionName = value.Value; OnPropertyChanged(); } }
    private Named _vision = Catalog.Visions[0];
    private string _visionName = "default";
    public string VisionName { get => _visionName; set => Set(ref _visionName, value); }
    public ObservableCollection<PerkRowVM> Perks { get; } = new();
    public PerkDef? SelectedPerk { get; set; }
    internal void PerkToggled(PerkRowVM p) => Do((p.IsOn ? "Perk ALL +" : "Perk ALL -") + p.Key, "perkall", (p.IsOn ? "" : "-") + p.Key);

    public Named[] VisionSets => Catalog.Visions;
    public Named[] SoundList => Catalog.Sounds;
    public Named[] ProjectileList => Catalog.Projectiles;
    public Named[] PropList => Catalog.Props;
    public int[] ProjMethods => new[] { 0, 1, 2, 3, 4, 5, 6, 7 };   // 0 = AUTO (bocw-c7, the GSC default since 2026-09-20); 7 = magicmissile (fun pack 2)
    private int _projMethod = 0;
    public int ProjMethod { get => _projMethod; set => Set(ref _projMethod, value); }
    public RelayCommand ProjMethodSet => new(() => Do($"Projectile method {ProjMethod}", "projmethod", ProjMethod.ToString()));
    public RelayCommand ProjDebug => new(() => Do("PROJ debug line", "projdbg"));

    // ── weapons ──
    public List<WeaponGroupVM> WeaponGroups { get; }
    /// <summary>Every weapon, flat, labelled "group › name" for one long picker.</summary>
    public Named[] WeaponList { get; } = Catalog.Weapons.SelectMany(g => g.Items.Select(i => new Named(g.Group + " › " + i.Label, i.Value, i.Note))).ToArray();
    private Named _weapon = null!;
    public Named SelectedWeapon { get => _weapon; set => Set(ref _weapon, value); }
    public RelayCommand GiveHost => new(() => Do("Give " + SelectedWeapon.Label, "giveweapon", SelectedWeapon.Value));
    public RelayCommand GiveAll => new(() => Do("Give ALL " + SelectedWeapon.Label, "giveall", SelectedWeapon.Value));
    public void GiveTo(string name) => Do("Give " + SelectedWeapon.Label, "giveone", SelectedWeapon.Value, name);

    // ── cosmetics ──
    private int _camo = 61, _op = 1, _outfit;
    public int CamoId { get => _camo; set => Set(ref _camo, value); }          // ranges applied on use, not per keystroke
    public int OperatorId { get => _op; set => Set(ref _op, value); }
    public int OutfitId { get => _outfit; set => Set(ref _outfit, value); }
    public Named[] CamoNames => Catalog.Camos;
    public Named[] OperatorNames => Catalog.Operators;
    public Named? SelectedCamo { get => null; set { if (value != null) CamoId = int.Parse(value.Value); } }
    public Named? SelectedOperator { get => null; set { if (value != null) OperatorId = int.Parse(value.Value); } }
    public RelayCommand CamoHost => new(() => { CamoId = Math.Clamp(CamoId, 0, 149); Do("Camo " + CamoId, "camo", CamoId.ToString()); });
    // id 0 = the invisible operator: removed (klaze 2026-09-23), so a typed id is clamped from 1
    public RelayCommand OperatorHost => new(() => { OperatorId = Math.Clamp(OperatorId, 1, 60); Do("Operator " + OperatorId, "operator", OperatorId.ToString()); });
    public RelayCommand OutfitHost => new(() => { OutfitId = Math.Clamp(OutfitId, 0, 60); Do("Outfit " + OutfitId, "outfit", OutfitId.ToString()); });

    // ── teleport hub ──
    public RelayCommand TpAllMe => new(() => Do("Everyone to me", "tpall", "me"));
    public RelayCommand TpAllAim => new(() => Do("Everyone to crosshair", "tpall", "aim"));
    public RelayCommand TpAllSaved => new(() => Do("Everyone to saved point", "tpall", "saved"));
    public RelayCommand TpAllCentre => new(() => Do("Everyone to map centre", "tpall", "centre"));
    public RelayCommand TpTeamMe => new(() => Do("My team to me", "tpteam", "me"));
    public RelayCommand TpTeamAim => new(() => Do("My team to crosshair", "tpteam", "aim"));
    public RelayCommand TpEnemyMe => new(() => Do("Other team to me", "tpenemy", "me"));
    public RelayCommand TpEnemyAim => new(() => Do("Other team to crosshair", "tpenemy", "aim"));
    public RelayCommand TpMeAim => new(() => Do("Me to crosshair", "tpme", "aim"));
    public RelayCommand TpMeSaved => new(() => Do("Me to saved point", "tpme", "saved"));
    public RelayCommand TpMeCentre => new(() => Do("Me to map centre", "tpme", "centre"));
    public RelayCommand TpSave => new(() => Do("Save point", "tpsave"));
    public RelayCommand TpGunHost => new(() => Do("Teleport gun (host)", "tpgun", "host"));
    public RelayCommand TpGunAll => new(() => Do("Teleport gun (everyone)", "tpgun", "all"));
    public RelayCommand TpNadeHost => new(() => Do("Teleport grenade (host)", "tpnade", "host"));
    public RelayCommand TpNadeAll => new(() => Do("Teleport grenade (everyone)", "tpnade", "all"));

    // ── vehicles ──
    public VehicleDef[] DrivableVehicles => Catalog.Vehicles.Where(v => v.Drivable).ToArray();
    public VehicleDef[] OtherVehicles => Catalog.Vehicles.Where(v => !v.Drivable).ToArray();
    private VehicleDef _veh = null!, _vehOther = null!;
    public VehicleDef SelectedVehicle { get => _veh; set => Set(ref _veh, value); }
    public VehicleDef SelectedOtherVehicle { get => _vehOther; set => Set(ref _vehOther, value); }
    // ── streaks (bocw-1c 2026-09-21): `streak <kstype>` = killstreaks::give (the care-package inventory path);
    //    target = a named player via gf_cmd_target, else the host. Host + client pages in-game; not the client menu.
    private PlayerRowVM? _streakTarget;
    public PlayerRowVM? StreakTarget { get => _streakTarget; set => Set(ref _streakTarget, value); }
    public IEnumerable<PlayerRowVM> StreakTargets => _m.Players.Rows.Where(r => !r.IsBot);
    public void RefreshStreakTargets() => OnPropertyChanged(nameof(StreakTargets));
    private void Streak(string label, string kstype) => Do("Streak " + label + (StreakTarget != null ? " -> " + StreakTarget.Name : " -> host"), "streak", kstype, StreakTarget?.Name);
    public RelayCommand StreakRcxd => new(() => Streak("RC-XD", "recon_car"));
    public RelayCommand StreakBow => new(() => Streak("Bow (Sparrow)", "sig_bow_flame"));
    public RelayCommand StreakNuke => new(() => Streak("Nuke", "nuke"));
    public Named[] StreakList => Catalog.Streaks;
    public Named SelectedStreak { get; set; } = Catalog.Streaks[0];
    public RelayCommand StreakGive => new(() => Streak(SelectedStreak.Label, SelectedStreak.Value));

    public RelayCommand VehSpawn => new(() => Do("Spawn " + SelectedVehicle.Label, "vehspawn", SelectedVehicle.Index.ToString()));
    public RelayCommand VehSpawnOther => new(() => Do("Spawn " + SelectedOtherVehicle.Label, "vehspawn", SelectedOtherVehicle.Index.ToString()));
    public RelayCommand VehEnter => new(() => Do("Enter aimed vehicle", "vehenter"));
    // confirms like ENTITIES' own Delete all vehicles (one rule: deleting more than one thing asks first)
    public RelayCommand VehClear => new(() => { if (_m.Confirm("Delete every EMPTY vehicle the menu / app spawned?\n\nOccupied ones stay.")) Do("Delete all vehicles (empty ones)", "vehclear"); });
    // liveries (bocw-1c 2026-09-21): model variants of the same body - steps the vehicle the host sits in,
    // else the one aimed at / nearest within 300 u (the vehicle placer is gone since 2026-09-22). Host-only.
    public RelayCommand VehLiveryPrev => new(() => Do("Vehicle livery: previous", "vehlivery", "prev"));
    public RelayCommand VehLiveryNext => new(() => Do("Vehicle livery: next", "vehlivery", "next"));
    public string VehicleNote => _m.Link.State is { } s && _m.Link.MapVeh.TryGetValue(s.Map, out var d)
        ? "resident here: " + string.Join(", ", d.VehiclesDrive) : "spawns ahead of you (aircraft above); a class this map lacks just says so";
    /// <summary>A new state line (map / census may have changed): VehicleNote is computed, so it has to be told.</summary>
    public void NotifyMap() => OnPropertyChanged(nameof(VehicleNote));

    // ── map toys ──
    public RelayCommand DestructAim => new(() => Do("Break aimed", "destruct", "aim"));
    public RelayCommand DestructNear => new(() => Do("Break near me", "destruct", "near"));
    public RelayCommand DestructAll => new(() => { if (_m.Confirm("Break EVERY destructible on the map?")) Do("Break ALL", "destruct", "all"); });
    public RelayCommand ExpNext => new(() => Do("Exploder next", "exploder", "next"));
    public RelayCommand ExpPrev => new(() => Do("Exploder previous", "exploder", "prev"));
    public RelayCommand ExpAgain => new(() => Do("Exploder again", "exploder", "again"));
    public RelayCommand ExpStop => new(() => Do("Exploder stop", "exploder", "stop"));
    public RelayCommand ExpAll => new(() => Do("Exploders ALL", "exploder", "all"));
    public RelayCommand ExpStopAll => new(() => Do("Exploder walk stop", "exploder", "stopall"));
    public RelayCommand ProjHost => new(() => Do("Projectiles: host", "proj", "host"));
    public RelayCommand ProjAll => new(() => Do("Projectiles: everyone", "proj", "all"));
    public RelayCommand ProjOff => new(() => Do("Projectiles off", "proj", "off"));
    public RelayCommand ProjHoming => new(() => Do("Projectiles homing", "projhoming"));
    public RelayCommand ProjTrail => new(() => Do("Projectiles trail FX", "projtrail"));
    private Named _proj = null!;
    public Named SelectedProjectile { get => _proj; set => Set(ref _proj, value); }
    public RelayCommand ProjWeapon => new(() => Do("Projectile " + SelectedProjectile.Label, "projweapon", SelectedProjectile.Value));
    public int[] ProjRates => new[] { 0, 150, 300, 600, 1000 };
    private int _projRate = 300;
    public int ProjRate { get => _projRate; set => Set(ref _projRate, value); }
    public RelayCommand ProjRateSet => new(() => Do($"Projectile rate {ProjRate} ms", "projrate", ProjRate.ToString()));
    private Named _prop = null!;
    public Named SelectedProp { get => _prop; set => Set(ref _prop, value); }
    public RelayCommand PropPlace => new(() => Do("Place " + SelectedProp.Label, "prop", "\"" + SelectedProp.Label + "\""));
    public RelayCommand PropUndo => new(() => Do("Remove last prop", "propundo"));
    public RelayCommand PropClear => new(() => Do("Remove all props", "propclear"));

    // ── race ──
    // race: the RACING page (RaceVM - the same command names, 2026-09-24)
}

public sealed class WeaponGroupVM
{
    public string Group { get; }
    public Named[] Items { get; }
    public WeaponGroupVM(string g, Named[] items) { Group = g; Items = items; }
}

public sealed class PerkRowVM : ObservableObject
{
    private readonly ToolsVM _tools;
    public PerkDef Def { get; }
    public string Key => Def.Key;
    public string Label => Def.Label;
    public string Note => Def.Note;
    private bool _on;
    public bool IsOn { get => _on; set { if (Set(ref _on, value)) _tools.PerkToggled(this); } }
    public PerkRowVM(ToolsVM t, PerkDef d) { _tools = t; Def = d; }
    public void SetSilently(bool on) { _on = on; OnPropertyChanged(nameof(IsOn)); }
}
