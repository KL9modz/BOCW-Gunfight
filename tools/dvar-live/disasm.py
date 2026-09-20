import sys, csv
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from dvar_pool_scan import Proc
proc = Proc()
live = {int(r["hash"],16): r for r in csv.DictReader(open("dvars_cw_live_named.csv", newline="", encoding="utf-8"))}
md = Cs(CS_ARCH_X86, CS_MODE_64); md.detail = True
def dis(rva, n):
    a = proc.base + rva
    code = proc.read(a, n)
    for ins in md.disasm(code, a):
        note = ""
        if ins.mnemonic == "movabs" or (ins.mnemonic == "mov" and len(ins.operands) == 2 and ins.operands[1].type == 2):
            imm = ins.operands[1].imm & 0xFFFFFFFFFFFFFFFF
            if imm in live: note = f"   ; dvar {live[imm]['name'] or '?'} ({live[imm]['type']} cur={live[imm]['cur']})"
        # rip-relative memory operand -> print target rva
        for op in ins.operands:
            if op.type == 3 and op.mem.base == 41:  # X86_REG_RIP
                tgt = ins.address + ins.size + op.mem.disp
                note += f"   ; [{proc.rva(tgt)}]"
        if ins.mnemonic == "call" and ins.operands[0].type == 2:
            note += f"   ; -> {proc.rva(ins.operands[0].imm)}"
        print(f"  {proc.rva(ins.address):>16}: {ins.bytes.hex():24s} {ins.mnemonic} {ins.op_str}{note}")
for arg in sys.argv[1:]:
    rva, n = arg.split(":")
    print(f"\n=== {rva}")
    dis(int(rva,16), int(n,16))
