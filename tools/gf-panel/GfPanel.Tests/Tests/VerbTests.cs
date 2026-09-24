namespace GfPanel.Tests;

/// <summary>The command channel's vocabulary: a verb the GSC does not answer is a button that prints
/// "app: unknown action" in game and does nothing else.</summary>
public static class VerbTests
{
    [Test]
    public static void Every_verb_the_panel_sends_is_answered_by_the_gsc()
    {
        var gsc = Gsc.Verbs();
        Check.True(gsc.Count > 80, $"cmd_action + panel_verb parse found only {gsc.Count} verbs");
        var (sent, _) = Panel.Verbs();
        Check.True(sent.Count > 60, $"found only {sent.Count} verb call sites in the panel - has the sending code moved?");
        var p = new Problems();
        foreach (var g in sent.GroupBy(s => s.Verb).Where(g => !gsc.Contains(g.Key)).OrderBy(g => g.Key))
            p.Add($"'{g.Key}' is not a case in cmd_action or panel_verb - sent from {string.Join(", ", g.Select(s => s.Where))}");
        p.ThrowIfAny("unanswered verbs");
    }

    [Test]
    public static void Every_verb_call_site_names_its_verb_literally()
    {
        var (_, unresolved) = Panel.Verbs();
        var p = new Problems();
        foreach (var u in unresolved) p.Add(u);
        p.ThrowIfAny("call sites these checks cannot read (use a literal or a ternary of literals)");
    }

    [Test]
    public static void Every_fun_switch_the_panel_sends_is_a_fun_verb_case()
    {
        var cases = Gsc.FunVerbs();
        Check.True(cases.Count > 15, $"fun_verb parse found only {cases.Count} cases");
        var args = Panel.FunArgs();
        Check.True(args.Count > 40, $"found only {args.Count} fun arguments in the panel");
        var p = new Problems();
        foreach (var a in args)
        {
            var what = a.Verb.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
            if (!cases.Contains(what)) p.Add($"'fun {a.Verb}' - '{what}' is not a case in fun_verb ({a.Where})");
        }
        p.ThrowIfAny("fun switches");
    }
}
