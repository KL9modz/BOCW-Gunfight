M = 0xFFFFFFFF
def t89scr(s):
    h = 0x4B9ACE2F
    for ch in s:
        c = ord(ch)
        if 65 <= c <= 90: c += 32
        t = (c + h) & M
        t = (t ^ ((t << 10) & M)) & M
        h = (t + (t >> 6)) & M
    h9 = (9 * h) & M
    return (0x8001 * (h9 ^ (h9 >> 11))) & M
