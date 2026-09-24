using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace GfPanel;

public partial class App : Application
{
    /// <summary>Folder the exe runs from: the bundle root (acts/, gf-bridge/, vendor/, payloads/ sit beside it).</summary>
    public static string BaseDir { get; } = AppContext.BaseDirectory;

    /// <summary>Per-user data folder (prefs.json, logs\, crash.log). Never inside the bundle - it may be read-only /
    /// replaced on update. GFPANEL_DATADIR overrides it (a test instance beside the real one must not share prefs).</summary>
    public static string DataDir { get; } = Environment.GetEnvironmentVariable("GFPANEL_DATADIR") is { Length: > 0 } d ? d
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GfPanel");

    /// <summary>The repo the exe runs from, when it does (dev box: tools/gf-panel/dist/... or bin/...): the first
    /// folder up with bootstrap.ps1 + tools\ (InjectVM's rule). null in a friend's bundle.</summary>
    public static string? RepoDir { get; } = FindRepo();

    private static string? FindRepo()
    {
        for (var d = new DirectoryInfo(BaseDir); d != null; d = d.Parent)
            if (File.Exists(Path.Combine(d.FullName, "bootstrap.ps1")) && Directory.Exists(Path.Combine(d.FullName, "tools"))) return d.FullName;
        return null;
    }

    public static bool DryRun { get; private set; }
    public static string? StartTab { get; private set; }
    /// <summary>--export-spawns: render every scanned map (SPAWNS tab, "Save all maps") to Pictures and exit.</summary>
    public static bool ExportSpawns { get; private set; }
    /// <summary>--dry --fake: a sample roster + entity list pushed through the real parsers, for screenshot checks
    /// of the player badges / right-click menu / ENTITIES tab without a game (bocw-84 2026-09-23). Dry run only.</summary>
    public static bool Fake { get; private set; }
    /// <summary>--dry --fake --fake-menu: also open a player's right-click menu (Teleport > Them to player) for a screenshot.</summary>
    public static bool FakeMenu { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Directory.CreateDirectory(DataDir);
        DryRun = e.Args.Any(a => string.Equals(a, "--dry", StringComparison.OrdinalIgnoreCase));
        var ti = Array.FindIndex(e.Args, a => a == "--tab");
        if (ti >= 0 && ti + 1 < e.Args.Length) StartTab = e.Args[ti + 1];
        ExportSpawns = e.Args.Any(a => string.Equals(a, "--export-spawns", StringComparison.OrdinalIgnoreCase));
        Fake = DryRun && e.Args.Any(a => string.Equals(a, "--fake", StringComparison.OrdinalIgnoreCase));
        FakeMenu = Fake && e.Args.Any(a => string.Equals(a, "--fake-menu", StringComparison.OrdinalIgnoreCase));
        DispatcherUnhandledException += (_, ex) =>
        {
            try { File.AppendAllText(Path.Combine(DataDir, "crash.log"), $"{DateTime.Now:s} {ex.Exception}\n"); } catch { }
            MessageBox.Show(ex.Exception.Message, "Gunfight Host Panel - error", MessageBoxButton.OK, MessageBoxImage.Error);
            ex.Handled = true;
        };
    }
}
