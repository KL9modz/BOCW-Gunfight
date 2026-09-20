using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace GfPanel;

public partial class App : Application
{
    /// <summary>Folder the exe runs from: the bundle root (acts/, gf-bridge/, vendor/, payloads/ sit beside it).</summary>
    public static string BaseDir { get; } = AppContext.BaseDirectory;

    /// <summary>Per-user data folder (prefs.json, log). Never inside the bundle - it may be read-only / replaced on update.</summary>
    public static string DataDir { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GfPanel");

    public static bool DryRun { get; private set; }
    public static string? StartTab { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Directory.CreateDirectory(DataDir);
        DryRun = e.Args.Any(a => string.Equals(a, "--dry", StringComparison.OrdinalIgnoreCase));
        var ti = Array.FindIndex(e.Args, a => a == "--tab");
        if (ti >= 0 && ti + 1 < e.Args.Length) StartTab = e.Args[ti + 1];
        DispatcherUnhandledException += (_, ex) =>
        {
            try { File.AppendAllText(Path.Combine(DataDir, "crash.log"), $"{DateTime.Now:s} {ex.Exception}\n"); } catch { }
            MessageBox.Show(ex.Exception.Message, "Gunfight Host Panel - error", MessageBoxButton.OK, MessageBoxImage.Error);
            ex.Handled = true;
        };
    }
}
