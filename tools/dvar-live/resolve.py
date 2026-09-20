import csv, re, os, sys, glob
from fnv import fnv1a63
live = list(csv.DictReader(open("dvars_cw_live.csv", newline="", encoding="utf-8")))
hashes = {int(r["hash"], 16): r for r in live}
names = set()
# 1. BO4 resolved list
for row in csv.reader(open(r"C:\bocw\t8-atian-menu\docs\notes\dvars.csv", newline="")):
    if row and not row[0].startswith("hash_") and row[0] != "name": names.add(row[0])
n_bo4 = len(names)
# 2. dump script literals: #"..." and "..." tokens that look like identifiers
tok = re.compile(rb'#?"([A-Za-z_][A-Za-z0-9_\.]{2,60})"')
for root in [r"C:\bocw\bocw-source-main\scripts", r"C:\bocw\bocw-source-main\hashed\script"]:
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if f.endswith((".gsc", ".csc")):
                try:
                    data = open(os.path.join(dp, f), "rb").read()
                except OSError: continue
                for m in tok.finditer(data):
                    names.add(m.group(1).decode())
# 3. project gsc + cfg files
for f in glob.glob(r"C:\bocw\BOCW-Gunfight\src\**\*.gsc", recursive=True) + glob.glob(r"C:\bocw\bocw-source-main\*.cfg"):
    data = open(f, "rb").read()
    for m in tok.finditer(data): names.add(m.group(1).decode())
    for m in re.finditer(rb'(?:set|seta|setdvar)\s+([A-Za-z_][A-Za-z0-9_]+)', data): names.add(m.group(1).decode())
print(f"candidate names: {len(names)} (bo4 list {n_bo4})")
resolved = {}
for n in names:
    h = fnv1a63(n)
    if h in hashes: resolved[h] = n
print(f"resolved {len(resolved)} / {len(hashes)} live dvars")
with open("dvars_cw_live_named.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["addr","name","hash","type","flags","min","max","cur","reset"])
    for r in live:
        h = int(r["hash"], 16)
        w.writerow([r["addr"], resolved.get(h, ""), r["hash"], r["type"], r["flags"], r["min"], r["max"], r["cur"], r["reset"]])
print("wrote dvars_cw_live_named.csv")
# show all resolved names containing key words
for kw in ["slide", "sprint", "jump", "dive", "mantle", "gravity", "speed"]:
    hits = sorted(n for n in resolved.values() if kw in n)
    print(f"\n[{kw}] {len(hits)}: ", ", ".join(hits))
