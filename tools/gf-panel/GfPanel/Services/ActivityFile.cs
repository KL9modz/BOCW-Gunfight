using System.Diagnostics;
using System.IO;
using System.Text;

namespace GfPanel.Services;

/// <summary>
/// The saved activity log (klaze 2026-09-23: "build out the log system with saves", after a Miami match
/// dropped everyone to the lobby and the only record - the panel's in-memory Activity list - was gone).
/// Every Activity entry is appended, as it is logged, to %LOCALAPPDATA%\GfPanel\logs\activity-YYYY-MM-DD.log
/// (one file per day, local time), plus detail lines only the file carries: the last raw state line of a
/// match, the roster when a match stops, a match summary. A dry run writes activity-dry-*.log instead.
/// Each write opens, appends and closes (shared read/write/delete): the file is never held, so it can be
/// opened, copied or deleted while the panel runs, and a killed panel loses nothing.
/// </summary>
public static class ActivityFile
{
    private static readonly object Gate = new();
    private static readonly UTF8Encoding Utf8 = new(false);
    private static DateTime _headerDay = DateTime.MinValue;
    private static bool _pruned;

    /// <summary>Days a daily file is kept; older ones are deleted once per start.</summary>
    public const int KeepDays = 90;

    public static string Dir => Path.Combine(App.DataDir, "logs");
    public static string? CurrentPath { get; private set; }
    /// <summary>The last write failure (disk full, folder gone) - logging never throws.</summary>
    public static string? LastError { get; private set; }

    private static string FileFor(DateTime day) =>
        Path.Combine(Dir, (App.DryRun ? "activity-dry-" : "activity-") + day.ToString("yyyy-MM-dd") + ".log");

    private static string Tag(LogLevel level) => level switch
    {
        LogLevel.Ok => "ok   ",
        LogLevel.Warn => "WARN ",
        LogLevel.Err => "ERR  ",
        LogLevel.In => "sent ",
        LogLevel.Menu => "MENU ",
        _ => "info ",
    };

    /// <summary>One Activity entry. Multi-line text keeps its lines, indented under the first.</summary>
    public static void Write(DateTime at, string text, LogLevel level) =>
        Append(at.ToString("yyyy-MM-dd HH:mm:ss.fff") + "  " + Tag(level) + Indent(text));

    /// <summary>A line only the file carries (raw state lines, rosters, summaries), under the entry before it.</summary>
    public static void Detail(string text) => Append(new string(' ', 30) + "| " + Indent(text));

    // "yyyy-MM-dd HH:mm:ss.fff" + 2 spaces + a 5-char tag = the text starts at column 30
    private static string Indent(string text) =>
        text.Replace("\r\n", "\n").Replace("\r", "\n").Replace("\n", Environment.NewLine + new string(' ', 30));

    private static void Append(string line)
    {
        lock (Gate)
        {
            try
            {
                var now = DateTime.Now;
                Directory.CreateDirectory(Dir);
                if (!_pruned) { _pruned = true; Prune(); }
                CurrentPath = FileFor(now.Date);
                using var fs = new FileStream(CurrentPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                using var w = new StreamWriter(fs, Utf8);
                if (_headerDay != now.Date)
                {
                    // once per process per day: which panel wrote what follows
                    _headerDay = now.Date;
                    var v = typeof(ActivityFile).Assembly.GetName().Version;
                    w.WriteLine();
                    w.WriteLine($"===== Gunfight Host Panel {v?.ToString(3)} · {now:yyyy-MM-dd HH:mm:ss} · pid {Environment.ProcessId}{(App.DryRun ? " · DRY RUN" : "")} =====");
                }
                w.WriteLine(line);
                LastError = null;
            }
            catch (Exception e) { LastError = e.Message; }
        }
    }

    private static void Prune()
    {
        try
        {
            var cutoff = DateTime.Now.Date.AddDays(-KeepDays);
            foreach (var f in Directory.EnumerateFiles(Dir, "activity-*.log"))
                if (File.GetLastWriteTime(f) < cutoff) File.Delete(f);
        }
        catch { /* an old file that will not delete is not worth a word */ }
    }

    /// <summary>Explorer on the logs folder, today's file selected when it exists.</summary>
    public static void OpenFolder()
    {
        Directory.CreateDirectory(Dir);
        var today = CurrentPath ?? FileFor(DateTime.Now.Date);
        var args = File.Exists(today) ? $"/select,\"{today}\"" : $"\"{Dir}\"";
        Process.Start(new ProcessStartInfo("explorer.exe", args) { UseShellExecute = true });
    }
}
