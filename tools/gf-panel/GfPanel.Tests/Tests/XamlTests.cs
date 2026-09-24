using System.Text.RegularExpressions;

namespace GfPanel.Tests;

/// <summary>The two XAML failures the compiler lets through: a {StaticResource} key that does not exist (the app
/// throws at startup, or when that view first opens) and a {Binding} that names nothing on the DataContext the
/// element really runs under (WPF shows nothing and says nothing). Both matter most when blocks move between views.</summary>
public static class XamlTests
{
    [Test]
    public static void Every_binding_resolves_against_the_datacontext_it_runs_under()
    {
        var w = new BindingWalker(TypeModel.Load());
        w.Run();
        var total = Repo.PanelFiles("*.xaml").Where(f => !Path.GetFileName(f).StartsWith("Theme", StringComparison.Ordinal))
                        .Sum(f => Regex.Matches(File.ReadAllText(f), @"\{Binding").Count);
        Check.True(w.Checked >= total * 9 / 10, $"only {w.Checked} of {total} bindings were resolved - has the walker lost track of a view's DataContext?");
        var p = new Problems();
        foreach (var x in w.Problems) p.Add(x);
        p.ThrowIfAny("bindings that resolve to nothing under their DataContext");
    }

    private static readonly Regex KeyDef = new(@"x:Key=""([^""{}]+)""");
    private static readonly Regex KeyUse = new(@"\{(?:StaticResource|DynamicResource)\s+([\w.]+)\s*\}");

    [Test]
    public static void Every_static_resource_key_is_defined_before_it_is_used()
    {
        // App.xaml merges Theme.xaml, then Templates.xaml: those keys are global (in that order)
        var app = Repo.Read("tools", "gf-panel", "GfPanel", "App.xaml");
        var merged = Regex.Matches(app, @"ResourceDictionary Source=""([^""]+)""").Select(m => m.Groups[1].Value.Replace('/', Path.DirectorySeparatorChar)).ToList();
        Check.True(merged.Count >= 2, "App.xaml merges fewer dictionaries than expected");
        var global = new HashSet<string>(StringComparer.Ordinal);
        var p = new Problems();
        foreach (var rel in merged)
        {
            var path = Path.Combine(Repo.PanelDir, rel);
            var lines = File.ReadAllLines(path);
            // inside a merged dictionary a StaticResource must be defined ABOVE its use (or in an earlier dictionary)
            for (var i = 0; i < lines.Length; i++)
            {
                foreach (Match u in KeyUse.Matches(lines[i]))
                    if (!global.Contains(u.Groups[1].Value)) p.Add($"{Repo.Rel(path)}:{i + 1} {{StaticResource {u.Groups[1].Value}}} - not defined above this line");
                foreach (Match d in KeyDef.Matches(lines[i])) global.Add(d.Groups[1].Value);
            }
        }
        foreach (var file in Repo.PanelFiles("*.xaml"))
        {
            if (merged.Any(m => file.EndsWith(m, StringComparison.Ordinal)) || file.EndsWith("App.xaml", StringComparison.Ordinal)) continue;
            var lines = File.ReadAllLines(file);
            var local = new HashSet<string>(StringComparer.Ordinal);
            for (var i = 0; i < lines.Length; i++)
            {
                foreach (Match u in KeyUse.Matches(lines[i]))
                    if (!global.Contains(u.Groups[1].Value) && !local.Contains(u.Groups[1].Value))
                        p.Add($"{Repo.Rel(file)}:{i + 1} {{StaticResource {u.Groups[1].Value}}} - no such key (App dictionaries or this file, above this line)");
                foreach (Match d in KeyDef.Matches(lines[i])) local.Add(d.Groups[1].Value);
            }
        }
        p.ThrowIfAny("resource keys");
    }
}
