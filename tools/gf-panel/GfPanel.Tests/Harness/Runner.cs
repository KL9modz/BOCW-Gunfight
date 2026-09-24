using System.Diagnostics;
using System.Reflection;

namespace GfPanel.Tests;

/// <summary>Marks a public static void method as a check. The runner finds every one by reflection.</summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class TestAttribute : Attribute { }

public static class Program
{
    public static int Main(string[] args)
    {
        var listOnly = args.Contains("--list");
        var filters = args.Where(a => !a.StartsWith("--", StringComparison.Ordinal)).ToArray();

        var tests = typeof(Program).Assembly.GetTypes()
            .Where(t => t.Namespace == typeof(Program).Namespace)
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static).Select(m => (Type: t, Method: m)))
            .Where(x => x.Method.GetCustomAttribute<TestAttribute>() != null)
            .Select(x => (Name: $"{x.Type.Name}.{x.Method.Name}", x.Method))
            .Where(x => filters.Length == 0 || filters.Any(f => x.Name.Contains(f, StringComparison.OrdinalIgnoreCase)))
            .OrderBy(x => x.Name, StringComparer.Ordinal)
            .ToList();

        if (listOnly)
        {
            foreach (var t in tests) Console.WriteLine(t.Name);
            return 0;
        }
        if (tests.Count == 0)
        {
            Console.WriteLine("no checks match " + string.Join(" ", filters));
            return 1;
        }

        var failed = new List<string>();
        var total = Stopwatch.StartNew();
        foreach (var (name, method) in tests)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                method.Invoke(null, null);
                Console.WriteLine($"  ok    {name}  ({sw.ElapsedMilliseconds} ms)");
            }
            catch (TargetInvocationException tie) when (tie.InnerException != null)
            {
                failed.Add(name);
                Console.WriteLine($"  FAIL  {name}");
                Console.WriteLine(Indent(Describe(tie.InnerException)));
            }
        }

        Console.WriteLine();
        Console.WriteLine($"{tests.Count - failed.Count} passed, {failed.Count} failed ({total.ElapsedMilliseconds} ms)");
        foreach (var f in failed) Console.WriteLine("  failed: " + f);
        return failed.Count == 0 ? 0 : 1;
    }

    private static string Describe(Exception e) => e is CheckFailed ? e.Message : e.ToString();

    private static string Indent(string s) => string.Join("\n", s.Split('\n').Select(l => "        " + l.TrimEnd('\r')));
}
