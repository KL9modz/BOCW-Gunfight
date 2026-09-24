namespace GfPanel.Services;

// Kept out of GameLink.cs (which needs WPF's Dispatcher) so the offline tests (GfPanel.Tests) can compile
// MatchTracker, which logs through these.

/// <summary>In = a line the panel sent; Menu = a player's menu action read back from the game (GFLOG).</summary>
public enum LogLevel { Info, Ok, Warn, Err, In, Menu }

public sealed record LogEntry(DateTime At, string Text, LogLevel Level)
{
    public string Time => At.ToString("HH:mm:ss");
}
