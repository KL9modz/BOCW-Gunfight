using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace GfPanel.Native;

/// <summary>
/// The game->app read channel: the mod keeps marked strings alive in level fields
/// (GFSTATE / GFPLAYERS / GFCFG / GFROSTER / GFMAP*), the script string heap holds them in plain
/// ASCII, and a read-only sweep of the game's private writable memory finds them. Ported from
/// tools/gf-control/roster_scan.py (the primitive proven safe mid-match: OpenProcess VM_READ +
/// VirtualQueryEx + ReadProcessMemory; no thread, no write, no lock).
///
/// Cost control, measured on the Python version: the string pool is ONE private RW region inside
/// the exe image range (~500 MB, ~0.5 s to sweep in Python) and the other 11 GB take a minute. So:
///   1. probe the last few addresses each marker was seen at (the pool reuses slots) - microseconds;
///   2. re-sweep the region the markers lived in last time;
///   3. the regions inside the exe image range;
///   4. everything else, only when a full sweep is allowed (first connect / long miss), time-boxed.
/// The newest tick wins over stale copies the pool has not reused yet.
/// </summary>
public sealed class MemoryScanner : IDisposable
{
    public sealed record Hit(string Marker, long Tick, string Body, long Addr);

    private const int Step = 0x400000;      // 4 MB read chunks
    private const int MaxLen = 8192;        // longest marked line we accept (overlap between chunks)
    private static readonly byte[] EndBytes = Encoding.ASCII.GetBytes("|END");

    public int Pid { get; }
    private IntPtr _h;
    private readonly byte[] _buf = new byte[Step + MaxLen];
    private (long Base, long Size)? _module;
    private (long Base, long Size)? _lastRegion;
    private List<(long Base, long Size)>? _regions;
    private readonly Dictionary<string, List<long>> _lastAddrs = new();
    private readonly Dictionary<string, long> _lastTick = new();

    public long LastSweepBytes { get; private set; }
    public double LastSweepMs { get; private set; }
    public string LastSweepHow { get; private set; } = "";
    /// <summary>The last sweep found at least one marker (the tick loop backs off while this stays false).</summary>
    public bool LastSweepHit { get; private set; }
    /// <summary>Some marker has been seen in this process at some point (the pool has been located).</summary>
    public bool HasEverHit => _lastTick.Count > 0;

    public MemoryScanner(int pid)
    {
        Pid = pid;
        _h = Win32.OpenProcess(Win32.PROCESS_QUERY_INFORMATION | Win32.PROCESS_VM_READ, false, (uint)pid);
        if (_h == IntPtr.Zero) throw new InvalidOperationException($"OpenProcess({pid}) failed, error {Marshal.GetLastWin32Error()}");
    }

    public void Dispose()
    {
        if (_h != IntPtr.Zero) { Win32.CloseHandle(_h); _h = IntPtr.Zero; }
    }

    private unsafe int Read(long addr, byte[] into, int want)
    {
        fixed (byte* p = into)
        {
            if (!Win32.ReadProcessMemory(_h, (IntPtr)addr, p, (IntPtr)want, out var got)) return 0;
            return (int)got;
        }
    }

    private IEnumerable<(long Base, long Size)> EnumRegions()
    {
        long addr = 0;
        while (addr < 0x7FFFFFFFFFFFL)
        {
            if (Win32.VirtualQueryEx(_h, (IntPtr)addr, out var mbi, (IntPtr)Marshal.SizeOf<Win32.MEMORY_BASIC_INFORMATION>()) == IntPtr.Zero) yield break;
            long b = mbi.BaseAddress.ToInt64(), s = mbi.RegionSize.ToInt64();
            if (s <= 0) yield break;
            var prot = mbi.Protect & 0xFF;
            if (mbi.State == Win32.MEM_COMMIT && mbi.Type == Win32.MEM_PRIVATE
                && (prot == Win32.PAGE_READWRITE || prot == Win32.PAGE_EXECUTE_READWRITE)
                && (mbi.Protect & Win32.PAGE_GUARD) == 0)
                yield return (b, s);
            addr = b + s;
        }
    }

    /// <summary>Parse one candidate at buf[i..n): "GF<MARKER>|<tick>|<body>|END". Null if not a whole line.
    /// The line is ONE NUL-terminated ASCII string in the pool: a stale slot that was partly overwritten
    /// has no |END of its own, and scanning past its NUL to some other line's |END turned dead memory into
    /// the "say" text (measured 2026-09-20: kilobytes of junk in the activity log). So: the |END must come
    /// before the first NUL, and every byte up to it must be printable ASCII.</summary>
    private static Hit? Parse(ReadOnlySpan<byte> span, string marker, long addr)
    {
        var nul = span.IndexOf((byte)0);
        if (nul >= 0) span = span[..nul];
        var end = span.IndexOf(EndBytes);
        if (end < 0) return null;
        var head = marker.Length + 1;                    // "GFSTATE|"
        if (end <= head) return null;
        foreach (var b in span[..end]) if (b < 0x20 || b > 0x7E) return null;
        var body = Encoding.ASCII.GetString(span.Slice(head, end - head));
        var bar = body.IndexOf('|');
        var tickStr = bar < 0 ? body : body[..bar];
        if (!long.TryParse(tickStr, out var tick)) return null;
        return new Hit(marker, tick, bar < 0 ? "" : body[(bar + 1)..], addr);
    }

    private void Remember(Hit h)
    {
        if (!_lastAddrs.TryGetValue(h.Marker, out var list)) _lastAddrs[h.Marker] = list = new List<long>();
        list.Remove(h.Addr);
        list.Insert(0, h.Addr);
        if (list.Count > 8) list.RemoveAt(list.Count - 1);
        _lastTick[h.Marker] = h.Tick;
    }

    /// <summary>Sweep for the given markers (names like "GFSTATE"). Returns the newest hit per marker found.
    /// <paramref name="allowFull"/> permits the whole-process sweep (slow); <paramref name="budgetMs"/> time-boxes it.</summary>
    /// <param name="force">Do not trust a quick-probe hit that merely EQUALS the last tick: a line that
    /// publishes on change (GFPLAYERS) leaves its old copy intact at the remembered address while the new
    /// one lands elsewhere, so the quick probe keeps "finding" the stale roster (measured 2026-09-21: the
    /// panel's player list never updated). With force the window / region steps run for every marker.</param>
    public Dictionary<string, Hit> Sweep(IReadOnlyList<string> markers, bool allowFull, int budgetMs = 4000, bool force = false)
    {
        var sw = Stopwatch.StartNew();
        var best = new Dictionary<string, Hit>();
        var patterns = markers.Select(m => (Marker: m, Bytes: Encoding.ASCII.GetBytes(m + "|"))).ToArray();
        long nbytes = 0;
        var how = "quick";

        // 1. quick probes of the remembered addresses
        var quickBuf = new byte[MaxLen];
        foreach (var (marker, pat) in patterns)
        {
            if (!_lastAddrs.TryGetValue(marker, out var addrs)) continue;
            foreach (var a in addrs.ToArray())
            {
                var n = Read(a, quickBuf, MaxLen);
                if (n < pat.Length) continue;
                var span = new ReadOnlySpan<byte>(quickBuf, 0, n);
                if (!span.StartsWith(pat)) continue;
                var hit = Parse(span, marker, a);
                if (hit != null && (!best.TryGetValue(marker, out var cur) || hit.Tick > cur.Tick)) best[marker] = hit;
            }
        }
        // A quick hit is only trusted when it is NEWER than what we last saw (a stale copy in a
        // reused slot carries an old tick). Markers that changed since then fall through to the sweep.
        (string Marker, byte[] Bytes)[] Missing() => patterns.Where(p => !best.TryGetValue(p.Marker, out var h)
                                          || (_lastTick.TryGetValue(p.Marker, out var lt) && h.Tick < lt)).ToArray();
        var missing = force ? patterns : Missing();
        if (missing.Length == 0) goto done;

        // 1b. a window around the remembered addresses: the pool hands out nearby slots, so a
        // changed string usually lands within a few MB of where it was (cheap before the region).
        if (_lastRegion is { } lreg)
        {
            how = "window";
            var seen = new HashSet<long>();
            foreach (var (marker, _) in missing)
            {
                if (!_lastAddrs.TryGetValue(marker, out var addrs)) continue;
                foreach (var a in addrs.Take(3))
                {
                    var wb = Math.Max(lreg.Base, (a - 0x800000) & ~0xFFFFL);
                    if (!seen.Add(wb)) continue;
                    var ws = Math.Min(lreg.Base + lreg.Size, wb + 0x1000000) - wb;
                    if (ws <= 0) continue;
                    SweepRegion((wb, ws), missing, best, ref nbytes);
                }
            }
            missing = Missing();
            if (missing.Length == 0) goto done;
        }

        how = "region";
        _module ??= GameProcess.ModuleRange(Pid);
        _regions ??= EnumRegions().ToList();

        int Rank((long Base, long Size) r)
        {
            if (_lastRegion is { } lr && r.Base <= lr.Base && lr.Base < r.Base + r.Size) return 0;
            if (_module is { } m && m.Base <= r.Base && r.Base < m.Base + m.Size) return 1;
            return 2;
        }

        var ordered = _regions.OrderBy(Rank).ThenBy(r => Rank(r) == 2 ? r.Base : -r.Size).ToList();
        var anyHitRegion = false;
        foreach (var region in ordered)
        {
            var rank = Rank(region);
            if (rank == 2)
            {
                if (!allowFull) break;
                // the pool was found and only never-seen markers are left: they are simply not
                // published by this payload (an older build) - never sweep 11 GB for them
                if (anyHitRegion && missing.All(p => !_lastTick.ContainsKey(p.Marker))) break;
                how = "full";
            }
            if (sw.ElapsedMilliseconds > budgetMs) break;

            if (SweepRegion(region, missing, best, ref nbytes))
            {
                anyHitRegion = true;
                _lastRegion = region;
                missing = Missing();
                if (missing.Length == 0) break;
            }
        }
        if (!anyHitRegion && allowFull) _regions = null;   // refresh the region list next time

    done:
        foreach (var h in best.Values) Remember(h);
        LastSweepBytes = nbytes;
        LastSweepMs = sw.Elapsed.TotalMilliseconds;
        LastSweepHow = how;
        LastSweepHit = best.Count > 0;
        return best;
    }

    /// <summary>EVERY whole line of one marker (stale copies included) for the multi-chunk channels (GFSPAWN,
    /// the spawn atlas), where Sweep's newest-per-marker rule would keep a single chunk. Reads the pool region
    /// the other markers live in; <paramref name="wide"/> adds every region inside the exe image range.
    /// Never the whole process.</summary>
    public List<Hit> CollectAll(string marker, bool wide)
    {
        var pat = Encoding.ASCII.GetBytes(marker + "|");
        var hits = new List<Hit>();
        var seen = new HashSet<long>();
        _module ??= GameProcess.ModuleRange(Pid);
        _regions ??= EnumRegions().ToList();
        var regions = new List<(long Base, long Size)>();
        if (_lastRegion is { } lr) regions.Add(lr);
        if (wide || regions.Count == 0)
            foreach (var r in _regions)
                if (_module is { } m && m.Base <= r.Base && r.Base < m.Base + m.Size && !regions.Contains(r)) regions.Add(r);

        foreach (var region in regions)
        {
            long off = 0;
            while (off < region.Size)
            {
                var want = (int)Math.Min(Step + MaxLen, region.Size - off);
                var n = Read(region.Base + off, _buf, want);
                if (n > 0)
                {
                    var span = new ReadOnlySpan<byte>(_buf, 0, n);
                    var from = 0;
                    while (from < n)
                    {
                        var idx = span[from..].IndexOf(pat);
                        if (idx < 0) break;
                        var at = from + idx;
                        if (at >= Step) break;                       // the next chunk owns it
                        var addr = region.Base + off + at;
                        var hit = Parse(span[at..Math.Min(n, at + MaxLen)], marker, addr);
                        if (hit != null && seen.Add(addr)) hits.Add(hit);
                        from = at + pat.Length;
                    }
                }
                off += Step;
            }
        }
        return hits;
    }

    private bool SweepRegion((long Base, long Size) region, (string Marker, byte[] Bytes)[] patterns,
                             Dictionary<string, Hit> best, ref long nbytes)
    {
        var found = false;
        long off = 0;
        while (off < region.Size)
        {
            var want = (int)Math.Min(Step + MaxLen, region.Size - off);
            var n = Read(region.Base + off, _buf, want);
            if (n > 0)
            {
                nbytes += n;
                var span = new ReadOnlySpan<byte>(_buf, 0, n);
                foreach (var (marker, pat) in patterns)
                {
                    var from = 0;
                    while (from < n)
                    {
                        var idx = span[from..].IndexOf(pat);
                        if (idx < 0) break;
                        var at = from + idx;
                        if (at >= Step) break;                       // the next chunk owns it
                        var hit = Parse(span[at..Math.Min(n, at + MaxLen)], marker, region.Base + off + at);
                        if (hit != null && (!best.TryGetValue(marker, out var cur) || hit.Tick > cur.Tick))
                        {
                            best[marker] = hit;
                            found = true;
                        }
                        from = at + pat.Length;
                    }
                }
            }
            off += Step;
        }
        return found;
    }
}
