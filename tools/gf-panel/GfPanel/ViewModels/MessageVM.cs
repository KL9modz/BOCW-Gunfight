using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>The message composer (the rcon ADMIN block): channel, audience, duration, colour codes, presets.
/// Rides the gf_cmd_say channel; the banner (loc 2) is the persistent hint line held until Clear.</summary>
public sealed class MessageVM : ObservableObject
{
    private readonly MainViewModel _m;
    public MessageVM(MainViewModel m)
    {
        _m = m;
        foreach (var p in m.Prefs.Messages) Presets.Add(p);
        if (Presets.Count == 0)
            foreach (var d in Catalog.MessagePresets) Presets.Add(new MessagePreset { Name = d.Label, Text = d.Value, Loc = 0, Dur = 0, Audience = "all" });
    }

    private string _text = "";
    public string Text { get => _text; set { if (Set(ref _text, value)) OnPropertyChanged(nameof(CharsLeft)); } }
    public int CharsLeft => Commands.MaxSayChars - Text.Length;
    private int _loc;
    public int Loc { get => _loc; set { if (Set(ref _loc, value)) { OnPropertyChanged(nameof(IsBanner)); OnPropertyChanged(nameof(DurationNote)); } } }
    public bool IsBanner => Loc == 2;
    public string DurationNote => Loc switch { 0 => "centre print: re-sent every 2 s for the duration", 1 => "feed: printed once per 2 s for the duration", _ => "banner: held until Clear (duration ignored)" };
    private int _dur;
    public int Dur { get => _dur; set => Set(ref _dur, value); }
    public DurDef[] Durations { get; } = { new("Once", 0), new("5 s", 5), new("10 s", 10), new("30 s", 30), new("60 s", 60), new("Held", -1) };
    private int _indent;
    public int Indent { get => _indent; set => Set(ref _indent, value); }   // clamped on send (typing-safe)
    private string _audience = "all";
    public string Audience { get => _audience; set => Set(ref _audience, value); }
    public string[] AudienceChoices => new[] { "all", "allies", "axis" }.Concat(_m.Players.Rows.Where(r => !r.IsBot).Select(r => r.Name)).Distinct().ToArray();
    public void RefreshAudiences() => OnPropertyChanged(nameof(AudienceChoices));
    public void TargetPlayer(string name) { Audience = name; _m.SelectTab("dashboard"); _m.Toasts.Show("Composer targeted at " + name, LogLevel.Ok); }

    public ObservableCollection<MessagePreset> Presets { get; } = new();
    private MessagePreset? _preset;
    public MessagePreset? SelectedPreset
    {
        get => _preset;
        set { if (Set(ref _preset, value) && value != null) { Text = value.Text; Loc = value.Loc; Dur = value.Dur; Audience = value.Audience; } }
    }
    public ColorDef[] Colors => Catalog.Colors;

    public RelayCommand InsertColor => new(p => { if (p is string code) Text += code; });
    public RelayCommand Send => new(() =>
    {
        var t = Text.Trim();
        if (t.Length == 0) { _m.Toasts.Show("Type a message first", LogLevel.Warn); return; }
        _m.Link.Send($"msg[{(Loc == 2 ? "banner" : Loc == 1 ? "feed" : "centre")}→{Audience}] {t}", Commands.Say(t, Loc, Dur, Math.Clamp(Indent, 0, 40), Audience));
        Text = "";
    });
    public RelayCommand Clear => new(() => _m.Link.Send("clear broadcast / banner", Commands.Action("sayclear")));
    public RelayCommand Countdown => new(() => _m.Link.Send("Countdown 5..1 GO", Commands.Action("countdown")));
    public RelayCommand Announce => new(() => _m.Link.Send("Announce settings", Commands.Action("announce")));
    public RelayCommand SavePreset => new(() =>
    {
        if (Text.Trim().Length == 0) return;
        var name = _m.Prompt("Preset name:", SelectedPreset?.Name ?? "");
        if (string.IsNullOrWhiteSpace(name)) return;
        var existing = Presets.FirstOrDefault(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
        var entry = existing ?? new MessagePreset();
        entry.Name = name.Trim(); entry.Text = Text.Trim(); entry.Loc = Loc; entry.Dur = Dur; entry.Audience = Audience;
        if (existing == null) Presets.Add(entry);
        Persist();
        SelectedPreset = entry;
    });
    public RelayCommand DeletePreset => new(() => { if (SelectedPreset != null) { Presets.Remove(SelectedPreset); SelectedPreset = null; Persist(); } });
    private void Persist() { _m.Prefs.Messages = Presets.ToList(); _m.Prefs.Save(); }
}
