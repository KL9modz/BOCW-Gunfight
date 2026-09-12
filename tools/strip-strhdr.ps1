# Strip the 3-byte "encrypted string" header ACTS writes in front of every T9
# string literal (8B <len+1> 00 <text> 00) by sliding the text left over the
# header in place: <text> 00 00 00 00. Same offset, same byte count, so nothing
# else in the file (string table, exports, imports, bytecode) needs to move.
param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'

$b = [System.IO.File]::ReadAllBytes((Resolve-Path $In).Path)

$magic = [System.BitConverter]::ToUInt64($b, 0)
if ($magic -ne 0x38000a0d43534780) { throw ("not a CW VM38 gscc: magic 0x{0:x16}" -f $magic) }

$count  = [System.BitConverter]::ToUInt16($b, 0x18)
$table  = [System.BitConverter]::ToUInt32($b, 0x30)
$size   = [System.BitConverter]::ToUInt32($b, 0x28)
if ($size -ne $b.Length) { throw "header size $size != file size $($b.Length)" }

$patched = 0; $plain = 0; $odd = @()
$pos = [int]$table
for ($i = 0; $i -lt $count; $i++) {
    $off  = [int][System.BitConverter]::ToUInt32($b, $pos)
    $nref = [int]$b[$pos + 4]
    $type = [int]$b[$pos + 5]
    $pos += 8 + 4 * $nref

    if ($type -ne 0) { $odd += ("entry {0} @0x{1:x}: type=0x{2:x2}" -f $i, $off, $type) }

    if ($b[$off] -eq 0x8B -and $b[$off + 2] -eq 0x00) {
        $L = [int]$b[$off + 1]                    # text length + terminator
        if ($b[$off + 3 + $L - 1] -ne 0) { throw ("entry {0} @0x{1:x}: no terminator where expected" -f $i, $off) }
        $text = [System.Text.Encoding]::ASCII.GetString($b, $off + 3, $L - 1)
        [Array]::Copy($b, $off + 3, $b, $off, $L)  # slide "<text>\0" left by 3
        $b[$off + $L] = 0; $b[$off + $L + 1] = 0; $b[$off + $L + 2] = 0
        $patched++
    } else {
        $plain++
        $odd += ("entry {0} @0x{1:x}: no 8B header (first byte 0x{2:x2})" -f $i, $off, $b[$off])
    }
}

[System.IO.File]::WriteAllBytes($Out, $b)
"strings: $count  patched: $patched  already-plain: $plain"
if ($odd.Count) { "notes:"; $odd | ForEach-Object { "  $_" } }
