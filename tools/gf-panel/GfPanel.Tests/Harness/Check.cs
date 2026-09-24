namespace GfPanel.Tests;

/// <summary>A failed check: the runner prints only its message (no stack trace).</summary>
public sealed class CheckFailed : Exception
{
    public CheckFailed(string message) : base(message) { }
}

public static class Check
{
    public static void True(bool condition, string message)
    {
        if (!condition) throw new CheckFailed(message);
    }

    public static void Equal<T>(T expected, T actual, string what)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new CheckFailed($"{what}: expected {Show(expected)}, got {Show(actual)}");
    }

    public static void Sequence<T>(IReadOnlyList<T> expected, IReadOnlyList<T> actual, string what)
    {
        var problems = new Problems();
        for (var i = 0; i < Math.Max(expected.Count, actual.Count); i++)
        {
            var e = i < expected.Count ? Show(expected[i]) : "(nothing)";
            var a = i < actual.Count ? Show(actual[i]) : "(nothing)";
            if (e != a) problems.Add($"[{i}] expected {e}, got {a}");
        }
        problems.ThrowIfAny(what);
    }

    public static T NotNull<T>(T? value, string what) where T : class =>
        value ?? throw new CheckFailed(what + ": got null");

    public static T HasValue<T>(T? value, string what) where T : struct =>
        value ?? throw new CheckFailed(what + ": got null");

    public static void Null(object? value, string what)
    {
        if (value != null) throw new CheckFailed($"{what}: expected null, got {Show(value)}");
    }

    public static void Fail(string message) => throw new CheckFailed(message);

    public static string Show(object? o) => o switch
    {
        null => "null",
        string s => "\"" + s + "\"",
        char c => "'" + c + "'",
        _ => o.ToString() ?? "",
    };
}

/// <summary>Collects every problem a contract check finds, so one run lists all of them instead of the first.</summary>
public sealed class Problems
{
    private readonly List<string> _items = new();

    public int Count => _items.Count;

    public void Add(string problem) => _items.Add(problem);

    public void ThrowIfAny(string title)
    {
        if (_items.Count == 0) return;
        throw new CheckFailed($"{title} - {_items.Count} problem{(_items.Count == 1 ? "" : "s")}:\n" +
                              string.Join("\n", _items.Select(i => "  - " + i)));
    }
}
