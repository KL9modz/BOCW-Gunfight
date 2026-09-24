using System.Globalization;
using GfPanel.Native;

namespace GfPanel.Game;

/// <summary>One menu action from the GFLOG channel (gunfight_menu.gsc gflog_add): who ran which page's row,
/// when (the game's getrealtime() ms), and the confirmation it printed. The record is published BEFORE the
/// action runs and the result is filled in after it returns, so an empty result on a match's last record
/// means the action never finished (the level died inside it).</summary>
public sealed record MenuAction(long Match, long Seq, long Ms, int Ent, string Who, string Page, string Item, string Result)
{
    public bool HasResult => Result.Length > 0;

    /// <summary>"KL9 › Vehicle spawner › Hind → vehicle spawned ahead ..." (colour codes stripped).</summary>
    public string Describe(bool finished = true)
    {
        var page = Page is "" or "-" ? "" : Page + " › ";
        var res = HasResult ? " → " + Result : finished ? "" : " → (never finished)";
        return $"{Who} › {page}{Item}{res}";
    }
}

/// <summary>GFLOG|&lt;tick&gt;|&lt;mid&gt;|&lt;seq,ms,ent,who,page,item,result&gt;;...|END - the newest records of the
/// match that fit one line (880 chars). Every copy still in memory holds an overlapping window, so the
/// panel unions all of them (MemoryScanner.CollectAll) to recover records a single read would miss.</summary>
public static class MenuLog
{
    /// <summary>The records of one match across every copy of the line, by seq. <paramref name="match"/> &gt; 0 picks
    /// that match; otherwise the newest match among the hits (a match id is getrealtime() at its first load, so
    /// newer = larger). A copy that carries a record's result wins over one taken before the result was filled.</summary>
    public static (long Match, List<MenuAction> Actions)? FromHits(IEnumerable<MemoryScanner.Hit> hits, long match)
    {
        var byMatch = new Dictionary<long, Dictionary<long, MenuAction>>();
        foreach (var h in hits)
        {
            foreach (var a in ParseBody(h.Body))
            {
                if (!byMatch.TryGetValue(a.Match, out var d)) byMatch[a.Match] = d = new Dictionary<long, MenuAction>();
                if (!d.TryGetValue(a.Seq, out var cur) || (!cur.HasResult && a.HasResult)) d[a.Seq] = a;
            }
        }
        if (byMatch.Count == 0) return null;
        var pick = match > 0 ? match : byMatch.Keys.Max();
        if (!byMatch.TryGetValue(pick, out var recs)) return null;
        return (pick, recs.Values.OrderBy(a => a.Seq).ToList());
    }

    /// <summary>One line's body (what follows the tick): "&lt;mid&gt;|&lt;rec&gt;;&lt;rec&gt;...". Malformed records are skipped.</summary>
    public static List<MenuAction> ParseBody(string body)
    {
        var list = new List<MenuAction>();
        var bar = body.IndexOf('|');
        if (bar <= 0 || !long.TryParse(body[..bar], NumberStyles.Integer, CultureInfo.InvariantCulture, out var mid)) return list;
        foreach (var rec in body[(bar + 1)..].Split(';'))
        {
            var f = rec.Split(',');
            if (f.Length != 7) continue;
            if (!long.TryParse(f[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var seq) || seq <= 0) continue;
            long.TryParse(f[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var ms);
            int.TryParse(f[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out var ent);
            list.Add(new MenuAction(mid, seq, ms, ent, Clean(f[3]), Clean(f[4]), Clean(f[5]), Clean(f[6])));
        }
        return list;
    }

    private static string Clean(string s) => GfState.StripColors(s).Trim();
}
