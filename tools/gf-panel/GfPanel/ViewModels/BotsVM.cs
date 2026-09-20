using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>The BOTS block: add / remove / even up / fill / remove all, the four stock difficulty presets + CUSTOM
/// per side or both, the GSC's four custom presets, and NAMED profiles (the 15 knobs saved under a name, like
/// the rcon tool's bot profiles).</summary>
public sealed class BotsVM : ObservableObject
{
    private readonly MainViewModel _m;
    public ObservableCollection<BotProfile> Profiles { get; } = new();
    private BotProfile? _profile;
    public BotProfile? SelectedProfile { get => _profile; set { if (Set(ref _profile, value)) OnPropertyChanged(nameof(ProfileNote)); } }
    public string ProfileNote => SelectedProfile == null ? "" : $"{SelectedProfile.Note}  ({SelectedProfile.Values.Count} knobs)";
    private string _liveDiff = "";
    public string LiveDifficulty { get => _liveDiff; set => Set(ref _liveDiff, value); }

    public BotsVM(MainViewModel m)
    {
        _m = m;
        foreach (var p in m.Prefs.BotProfiles) Profiles.Add(p);
    }

    private void Do(string label, string action, string? arg = null) => _m.Link.Send(label, Commands.Action(action, arg));
    public RelayCommand AddAuto => new(() => Do("Add bot (auto)", "addbot", "auto"));
    public RelayCommand AddAllies => new(() => Do("Add bot → allies", "addbot", "allies"));
    public RelayCommand AddAxis => new(() => Do("Add bot → axis", "addbot", "axis"));
    public RelayCommand RemoveOne => new(() => Do("Remove one bot", "removebot"));
    public RelayCommand EvenUp => new(() => Do("Even up teams", "evenbots"));
    public RelayCommand Fill => new(() => Do("Fill with bots", "fillbots"));
    public RelayCommand RemoveAll => new(() => Do("Remove all bots", "removebots"));
    public RelayCommand Balance => new(() => Do("Balance humans", "balance"));

    /// <summary>Both sides to a stock preset (-1 lobby, 0-3 recruit..veteran, 4 custom): two packed fields, one bots apply.</summary>
    public RelayCommand SetBoth => new(p => { if (p is string s && int.TryParse(s, out var d)) _m.ApplySettings(new() { ["gf_bot_diff_allies"] = d, ["gf_bot_diff_axis"] = d }, "bot difficulty"); });

    private static readonly (string Name, int[] V)[] GscPresets =
    {
        ("Veteran+ (custom default)", new[] { 100, 50, 100, 1000, 100, 90, 100, 100, 1, 1, 1, 1, 1, 1, 1 }),
        ("Godlike", new[] { 100, 100, 0, 2000, 100, 100, 50, 50, 1, 2, 1, 1, 1, 1, 1 }),
        ("Stock Veteran copy", new[] { 90, 20, 300, 700, 70, 50, 150, 250, 1, 1, 1, 1, 1, 1, 1 }),
        ("Potato", new[] { 10, 0, 2000, 300, 25, 25, 800, 1200, 0, 0, 0, 0, 0, 0, 0 }),
    };
    public string[] PresetNames => GscPresets.Select(p => p.Name).ToArray();
    /// <summary>The GSC's act_bot_preset values, applied as a CUSTOM difficulty on both sides.</summary>
    public RelayCommand ApplyPreset => new(p =>
    {
        var idx = p is string s ? Array.IndexOf(PresetNames, s) : -1;
        if (idx < 0) return;
        var changes = new Dictionary<string, int> { ["gf_bot_diff_allies"] = 4, ["gf_bot_diff_axis"] = 4 };
        for (var i = 0; i < Packing.BotPack.Length; i++) changes[Packing.BotPack[i]] = GscPresets[idx].V[i];
        _m.ApplySettings(changes, "bot preset " + GscPresets[idx].Name);
    });

    public RelayCommand ApplyProfile => new(() =>
    {
        if (SelectedProfile == null) return;
        var changes = new Dictionary<string, int>(SelectedProfile.Values) { ["gf_bot_diff_allies"] = 4, ["gf_bot_diff_axis"] = 4 };
        _m.ApplySettings(changes, "bot profile " + SelectedProfile.Name);
    });
    public RelayCommand SaveProfile => new(() =>
    {
        var name = _m.Prompt("Save the current bot tuning as profile:", SelectedProfile?.Name ?? "");
        if (string.IsNullOrWhiteSpace(name)) return;
        var note = _m.Prompt("One-line note (optional):", SelectedProfile?.Note ?? "") ?? "";
        var vals = Packing.BotPack.ToDictionary(k => k, k => _m.RowValue(k));
        var existing = Profiles.FirstOrDefault(x => string.Equals(x.Name, name, StringComparison.OrdinalIgnoreCase));
        if (existing != null) { existing.Values = vals; existing.Note = note; }
        else Profiles.Add(existing = new BotProfile { Name = name.Trim(), Note = note, Values = vals });
        Persist(); SelectedProfile = existing;
        _m.Toasts.Show("Saved bot profile " + name, LogLevel.Ok);
    });
    public RelayCommand DeleteProfile => new(() =>
    {
        if (SelectedProfile == null || !_m.Confirm($"Delete bot profile \"{SelectedProfile.Name}\"?")) return;
        Profiles.Remove(SelectedProfile); SelectedProfile = null; Persist();
    });
    private void Persist() { _m.Prefs.BotProfiles = Profiles.ToList(); _m.Prefs.Save(); }

    public void OnConfig()
    {
        var a = _m.RowValue("gf_bot_diff_allies"); var x = _m.RowValue("gf_bot_diff_axis");
        string N(int v) => v switch { -1 => "lobby", 0 => "Recruit", 1 => "Regular", 2 => "Hardened", 3 => "Veteran", 4 => "CUSTOM", _ => v.ToString() };
        LiveDifficulty = a == x ? N(a) : $"A {N(a)} / X {N(x)}";
    }
}
