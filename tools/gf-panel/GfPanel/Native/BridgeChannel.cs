using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Channels;

namespace GfPanel.Native;

/// <summary>
/// The app->game transport: the named shared-memory block gf_bridge.dll polls from inside the
/// game and runs through cwpatch's command executor (tools/gf-bridge/bridge_channel.py, 1:1).
/// Touches no game memory - plain shared memory between two processes of the same session.
///
/// Rules, all MEASURED (memory bridge-command-limit / app-bridge-multiline-fix):
///   - ONE console command per message. The loaded DLL runs only the first line of a block.
///   - a `set` longer than 47 bytes overflows cwpatch's 48-byte command slot and HARD-CRASHES
///     the game: such a line is refused here, never truncated, never sent.
///   - messages are spaced 80 ms apart (> the DLL's 50 ms poll) so every seq is consumed.
/// Everything goes through one paced queue with two lanes: clicks (high) jump ahead of
/// background config writes, the gap is enforced globally.
/// </summary>
public sealed class BridgeChannel
{
    public const string Name = "gf_bridge";
    public const int Size = 4096;
    public const uint Magic = 0x31424647;      // 'GFB1'
    private const int Hdr = 12;                // magic(4) + seq(4) + len(4)
    public const int MaxCommandBytes = 47;
    public static readonly TimeSpan Gap = TimeSpan.FromMilliseconds(80);

    public sealed record ProbeResult(bool Listening, uint Seq, uint LastLen);

    private static readonly object Lock = new();

    /// <summary>Open the mapping (create it if the DLL has not yet) and return the view.</summary>
    private static IntPtr Map(out IntPtr mapping)
    {
        mapping = Win32.OpenFileMappingW(Win32.FILE_MAP_ALL_ACCESS, false, Name);
        if (mapping == IntPtr.Zero)
            mapping = Win32.CreateFileMappingW(new IntPtr(-1), IntPtr.Zero, Win32.PAGE_READWRITE, 0, Size, Name);
        if (mapping == IntPtr.Zero) throw new InvalidOperationException("shared memory unavailable, error " + Marshal.GetLastWin32Error());
        var view = Win32.MapViewOfFile(mapping, Win32.FILE_MAP_ALL_ACCESS, 0, 0, (IntPtr)Size);
        if (view == IntPtr.Zero)
        {
            Win32.CloseHandle(mapping);
            throw new InvalidOperationException("MapViewOfFile failed, error " + Marshal.GetLastWin32Error());
        }
        return view;
    }

    /// <summary>Is the DLL listening (it stamps the magic when loaded)? Never throws.</summary>
    public static ProbeResult Probe()
    {
        try
        {
            lock (Lock)
            {
                var view = Map(out var mapping);
                try
                {
                    var magic = (uint)Marshal.ReadInt32(view, 0);
                    var seq = (uint)Marshal.ReadInt32(view, 4);
                    var len = (uint)Marshal.ReadInt32(view, 8);
                    return new ProbeResult(magic == Magic, seq, len);
                }
                finally { Win32.UnmapViewOfFile(view); Win32.CloseHandle(mapping); }
            }
        }
        catch { return new ProbeResult(false, 0, 0); }
    }

    /// <summary>Write ONE command (body, then header, seq bumped last so the DLL never reads a torn command).
    /// Returns (seq, listening). Throws on an oversize command - the caller must never send one.</summary>
    public static (uint Seq, bool Listening) SendRaw(string command)
    {
        var payload = Encoding.ASCII.GetBytes(command);
        if (payload.Length > MaxCommandBytes)
            throw new ArgumentException($"command is {payload.Length} B, the bridge slot takes {MaxCommandBytes}: {command}");
        lock (Lock)
        {
            var view = Map(out var mapping);
            try
            {
                var magic = (uint)Marshal.ReadInt32(view, 0);
                var seq = (uint)Marshal.ReadInt32(view, 4) + 1;
                Marshal.Copy(payload, 0, view + Hdr, payload.Length);
                Marshal.WriteInt32(view, 8, payload.Length);
                Marshal.WriteInt32(view, 0, unchecked((int)Magic));
                Marshal.WriteInt32(view, 4, unchecked((int)seq));
                return (seq, magic == Magic);
            }
            finally { Win32.UnmapViewOfFile(view); Win32.CloseHandle(mapping); }
        }
    }
}

/// <summary>The paced send queue. Every sender in the app goes through this, so the 80 ms gap
/// and the 47-byte guard hold no matter how many buttons are clicked at once.</summary>
public sealed class BridgeSender
{
    public sealed record Job(IReadOnlyList<string> Lines, int Priority, TaskCompletionSource<SendResult> Done, DateTime Enqueued);
    public sealed record SendResult(int Sent, int Refused, bool Listening, IReadOnlyList<string> RefusedLines);

    private readonly List<Job> _queue = new();
    private readonly SemaphoreSlim _signal = new(0);
    private readonly object _lock = new();
    private DateTime _lastSend = DateTime.MinValue;
    private DateTime _holdUntil = DateTime.MinValue;
    /// <summary>After a `set gf_cmd_go 1` pulse the GSC's cmd_poll (0.25 s cadence) still has to READ
    /// gf_cmd_action / arg / target - the next job's `set gf_cmd_action` must not land before it does,
    /// or two quick clicks run a mixed command. Line pacing inside a job is untouched.</summary>
    public static readonly TimeSpan CommandSettle = TimeSpan.FromMilliseconds(450);
    public bool DryRun { get; set; }
    public event Action<string, bool>? LineSent;      // (line, listening) for the log
    public int Pending { get { lock (_lock) return _queue.Count; } }

    public BridgeSender()
    {
        var t = new Thread(Worker) { IsBackground = true, Name = "bridge-sender" };
        t.Start();
    }

    /// <summary>Queue the lines as one job (sent in order, one message each). Priority 10 = a click, 0 = background.</summary>
    public Task<SendResult> SendAsync(IEnumerable<string> lines, int priority = 10)
    {
        var job = new Job(lines.ToList(), priority, new TaskCompletionSource<SendResult>(TaskCreationOptions.RunContinuationsAsynchronously), DateTime.UtcNow);
        lock (_lock) _queue.Add(job);
        _signal.Release();
        return job.Done.Task;
    }

    private void Worker()
    {
        for (;;)
        {
            _signal.Wait();
            Job? job;
            lock (_lock)
            {
                if (_queue.Count == 0) continue;
                // highest priority first, FIFO within a lane
                job = _queue.OrderByDescending(j => j.Priority).ThenBy(j => j.Enqueued).First();
                _queue.Remove(job);
            }
            var hold = _holdUntil - DateTime.UtcNow;
            if (hold > TimeSpan.Zero) Thread.Sleep(hold);
            var sent = 0; var refused = new List<string>(); var listening = true;
            foreach (var line in job.Lines)
            {
                if (Encoding.ASCII.GetByteCount(line) > BridgeChannel.MaxCommandBytes)
                {
                    refused.Add(line);
                    continue;
                }
                var wait = BridgeChannel.Gap - (DateTime.UtcNow - _lastSend);
                if (wait > TimeSpan.Zero) Thread.Sleep(wait);
                if (DryRun) listening = BridgeChannel.Probe().Listening;
                else
                {
                    try { (_, listening) = BridgeChannel.SendRaw(line); }
                    catch (Exception) { refused.Add(line); continue; }
                }
                _lastSend = DateTime.UtcNow;
                sent++;
                LineSent?.Invoke(line, listening);
            }
            if (job.Lines.Count > 0 && job.Lines[^1].StartsWith("set gf_cmd_go", StringComparison.Ordinal)) _holdUntil = DateTime.UtcNow + CommandSettle;
            job.Done.TrySetResult(new SendResult(sent, refused.Count, listening, refused));
        }
    }
}
