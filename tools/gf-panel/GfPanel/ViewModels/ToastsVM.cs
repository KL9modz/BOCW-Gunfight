using System.Collections.ObjectModel;
using System.Windows.Threading;
using GfPanel.Services;

namespace GfPanel.ViewModels;

public sealed class ToastVM
{
    public string Text { get; init; } = "";
    public LogLevel Level { get; init; }
    public string Kind => Level switch { LogLevel.Ok => "ok", LogLevel.Err => "err", LogLevel.Warn => "wn", _ => "info" };
}

public sealed class ToastsVM
{
    public ObservableCollection<ToastVM> Items { get; } = new();

    public void Show(string text, LogLevel level = LogLevel.Info)
    {
        var t = new ToastVM { Text = text, Level = level };
        Items.Add(t);
        while (Items.Count > 5) Items.RemoveAt(0);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(level == LogLevel.Err ? 6000 : 3200) };
        timer.Tick += (_, _) => { timer.Stop(); Items.Remove(t); };
        timer.Start();
    }
}
