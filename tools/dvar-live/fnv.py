def fnv1a63(s):
    h = 0xcbf29ce484222325
    for c in s.lower().encode():
        h ^= c
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h & 0x7FFFFFFFFFFFFFFF
if __name__ == "__main__":
    import sys
    for s in sys.argv[1:]:
        print(f"{s:40s} {fnv1a63(s):016x}")
