using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

public sealed record QuickCmd(string Label, string Command, string Tip);

/// <summary>The CONSOLE tab: any console command over the bridge (the DLL runs it through cwpatch's executor -
/// the same slot the F4/F6/F7 hotkeys use), a history, and quick commands. There is no reply channel: a
/// console command echoes nothing back to the panel; the readback lines (GFSTATE / GFCFG) are the confirmation.</summary>
public sealed class ConsoleVM : ObservableObject
{
    private readonly MainViewModel _m;
    private readonly List<string> _history = new();
    private int _histIdx = -1;
    public ObservableCollection<string> Lines { get; } = new();
    private string _input = "";
    public string Input { get => _input; set { if (Set(ref _input, value)) OnPropertyChanged(nameof(ByteCount)); } }
    public string ByteCount => $"{Commands.ByteLength(Input)} / {Native.BridgeChannel.MaxCommandBytes} B";

    public QuickCmd[] Quick { get; } =
    {
        new("apply all", "set gf_cmd_action apply", "Re-run every live subsystem (movement / bots / periods / timer) - what the old app's Apply-now did. Needs a go pulse: Run (or Send + go) adds seq + go; plain Send does not."),
        new("restart match", "set gf_cmd_action restart", "map_restart() - scores 0-0, same map."),
        new("fill bots", "set gf_cmd_action fillbots", "Fill both sides to the team size."),
        new("remove bots", "set gf_cmd_action removebots", ""),
        new("pause", "set gf_cmd_action pause", "The esports pause + BLINKER CHECKPOINT banner."),
        new("resume", "set gf_cmd_action resume", "5 s countdown then play."),
        new("freeze all", "set gf_cmd_action freeze", "Toggle: freeze / unfreeze everyone."),
    };

    public ConsoleVM(MainViewModel m) { _m = m; }

    public void Add(string line, string cls = "in")
    {
        Lines.Add($"{DateTime.Now:HH:mm:ss}  {(cls == "out" ? "> " : "  ")}{line}");
        while (Lines.Count > 400) Lines.RemoveAt(0);
    }

    public RelayCommand Send => new(() => SendLine(false));
    public RelayCommand SendPulsed => new(() => SendLine(true));
    public RelayCommand Clear => new(() => Lines.Clear());
    public RelayCommand Run => new(p => { if (p is QuickCmd q) { Input = q.Command; SendLine(true); } });
    public RelayCommand Fill => new(p => { if (p is QuickCmd q) Input = q.Command; });

    private async void SendLine(bool pulse)
    {
        var c = Input.Trim();
        if (c.Length == 0) return;
        if (Commands.ByteLength(c) > Native.BridgeChannel.MaxCommandBytes)
        {
            Add($"REFUSED ({Commands.ByteLength(c)} B > {Native.BridgeChannel.MaxCommandBytes}): a longer command overflows cwpatch's slot and hard-crashes the game", "out");
            return;
        }
        // the same rule as the buttons: a pulsed line that restarts / ends / switches the level asks first
        if (pulse && Commands.LevelChange(new[] { c }) is { } level &&
            !_m.Confirm($"Send '{c}'?\n\nIt {(level == "switch" ? "switches the map" : "restarts or ends the match")} ({level})."))
            return;
        _history.Insert(0, c); if (_history.Count > 100) _history.RemoveAt(_history.Count - 1);
        _histIdx = -1;
        Input = "";
        Add(c, "out");
        if (pulse)
        {
            var q = _m.Link.Send("console: " + c, new[] { c });
            Add($"queued as seq {q.Seq} (+ gf_cmd_seq + gf_cmd_go)", "in");
        }
        else
        {
            var r = await _m.Link.SendRaw(new[] { c }, 10);
            Add(r.Listening ? "sent (no echo channel - watch the readback / the game)" : "sent, but the bridge DLL is NOT listening", "in");
        }
    }

    public void HistoryUp() { if (_history.Count == 0) return; _histIdx = Math.Min(_histIdx + 1, _history.Count - 1); Input = _history[_histIdx]; }
    public void HistoryDown() { _histIdx = Math.Max(_histIdx - 1, -1); Input = _histIdx < 0 ? "" : _history[_histIdx]; }
}
