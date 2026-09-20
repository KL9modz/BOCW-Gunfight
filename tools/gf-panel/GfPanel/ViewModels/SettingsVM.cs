using System.Collections.ObjectModel;
using GfPanel.Game;

namespace GfPanel.ViewModels;

/// <summary>One settings row: a gf_* dvar with its control. Applies the moment it is changed (a toggle /
/// choice) or on Set (a number) - the in-game menu's behaviour - unless "apply on change" is off.</summary>
public sealed class SettingRowVM : ObservableObject
{
    private readonly MainViewModel _main;
    public SettingDef Def { get; }
    public string Dvar => Def.Dvar;
    public string Label => Def.Label;
    public string Tip => Def.Tip;
    public SettingKind Kind => Def.Kind;
    public bool IsToggle => Def.Kind == SettingKind.Toggle;
    public bool IsChoice => Def.Kind == SettingKind.Choice;
    public bool IsInt => Def.Kind == SettingKind.Int;
    public Choice[] Choices => Def.Choices ?? Array.Empty<Choice>();
    public string? Group => Def.Group;
    public bool HasGroup => !string.IsNullOrEmpty(Def.Group);
    public string EffLabel => Def.EffLabel;
    public string EffTip => Def.Eff switch
    {
        Eff.Live => "Applies to the running match (one apply pulse).",
        Eff.Restart => "The engine applies it by reloading the match: lands at the next match start, or Restart match now.",
        _ => "Lands next round (mod_apply re-reads it at every round start).",
    };
    public string SectionTitle { get; init; } = "";

    private int _value;
    /// <summary>The control's value. Setting it from the UI applies (see OnUserChange); the readback sets it silently.</summary>
    public int Value
    {
        get => _value;
        set
        {
            if (_value == value) return;
            _value = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsOn));
            OnPropertyChanged(nameof(SelectedChoice));
            OnPropertyChanged(nameof(Pending));
            if (!_silent) OnUserChange();
        }
    }
    private bool _silent;
    public void SetSilently(int v) { _silent = true; try { Value = v; Unsynced = false; } finally { _silent = false; } }

    public bool IsOn { get => _value == 1; set => Value = value ? 1 : 0; }
    public Choice? SelectedChoice
    {
        get => Choices.FirstOrDefault(c => c.Value == _value) ?? (Choices.Length > 0 ? new Choice(_value.ToString(), _value) : null);
        set { if (value != null) Value = value.Value; }
    }

    private bool _unsynced = true;
    /// <summary>No readback has confirmed this value (the game may hold something else).</summary>
    public bool Unsynced { get => _unsynced; set { if (Set(ref _unsynced, value)) OnPropertyChanged(nameof(ShowUnread)); } }
    /// <summary>The UNREAD pill: only once a GFCFG readback has arrived (before it EVERY row is unconfirmed,
    /// which says nothing - measured 2026-09-20: 60 pills while the game sat in the lobby).</summary>
    public bool ShowUnread => _unsynced && _main.IsLive && _main.Link.Config != null;
    public void NotifyLive() => OnPropertyChanged(nameof(ShowUnread));
    private bool _favorite;
    public bool IsFavorite { get => _favorite; set { if (Set(ref _favorite, value)) OnPropertyChanged(nameof(StarGlyph)); } }
    public string StarGlyph => IsFavorite ? "★" : "☆";
    public int Baseline => _main.Link.Baseline.TryGetValue(Dvar, out var b) ? b : Def.Default;
    public bool Pending => IsInt && _value != Baseline;
    public string ValueText => Services.ConfigWriter.ValueLabel(Dvar, _value);

    public RelayCommand SetCommand { get; }
    public RelayCommand ResetCommand { get; }
    public RelayCommand PinCommand { get; }
    public RelayCommand CopyCommand { get; }
    public RelayCommand StepUp { get; }
    public RelayCommand StepDown { get; }

    public SettingRowVM(MainViewModel main, SettingDef def, string section)
    {
        _main = main; Def = def; SectionTitle = section;
        _value = def.Default;
        SetCommand = new RelayCommand(() => _main.ApplySetting(this, Value));
        ResetCommand = new RelayCommand(() => { if (IsInt) { SetSilently(Def.Default); Unsynced = true; } _main.ApplySetting(this, Def.Default); });
        PinCommand = new RelayCommand(() => _main.TogglePin(this));
        CopyCommand = new RelayCommand(() => _main.CopyText(Dvar, "Copied " + Dvar));
        StepUp = new RelayCommand(() => { _silent = true; Value = Math.Min(Def.Max, _value + Math.Max(1, Def.Step)); _silent = false; OnPropertyChanged(nameof(Pending)); });
        StepDown = new RelayCommand(() => { _silent = true; Value = Math.Max(Def.Min, _value - Math.Max(1, Def.Step)); _silent = false; OnPropertyChanged(nameof(Pending)); });
    }

    private void OnUserChange()
    {
        if (IsInt) return;                       // numbers apply on Set
        _main.ApplySetting(this, _value);
    }

    public void NotifyBaseline() { OnPropertyChanged(nameof(Pending)); }
}

public sealed class SectionVM : ObservableObject
{
    public SectionDef Def { get; }
    public string Title => Def.Title;
    public string Note => Def.Note;
    public string Tab => Def.Tab;
    public ObservableCollection<SettingRowVM> Rows { get; } = new();
    private bool _expanded = true;
    public bool IsExpanded { get => _expanded; set { if (Set(ref _expanded, value)) ExpandedChanged?.Invoke(this); } }
    public event Action<SectionVM>? ExpandedChanged;
    private bool _favorite;
    public bool IsFavorite { get => _favorite; set { if (Set(ref _favorite, value)) OnPropertyChanged(nameof(StarGlyph)); } }
    public string StarGlyph => IsFavorite ? "★" : "☆";
    public RelayCommand PinCommand { get; }
    public RelayCommand ResetAllCommand { get; }
    public string Key => "sec:" + Title;

    public SectionVM(MainViewModel main, SectionDef def)
    {
        Def = def;
        foreach (var r in def.Rows) Rows.Add(new SettingRowVM(main, r, def.Title));
        PinCommand = new RelayCommand(() => main.TogglePin(this));
        ResetAllCommand = new RelayCommand(() => main.ResetSection(this));
    }
}
