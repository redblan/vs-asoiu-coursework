#!/usr/bin/env python3
"""vcd_plot.py — временные диаграммы из VCD в PNG (для отчёта без GTKWave).

    python3 tools/vcd_plot.py build/fib.vcd docs/img/fib_wave.png --run 5 --cycles 44

--run K     — начать с K-го снятия сброса (у tb_fib каждый N — свой прогон)
--cycles C  — сколько тактов показать
Сигналы задаются списком SIGNALS ниже: (полное имя в VCD, подпись, формат).
"""
import argparse
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

SIGNALS = [
    ("tb_fib.clk", "clk", "bit"),
    ("tb_fib.dut.u_core.pc", "PC (IF)", "dec"),
    ("tb_fib.dut.u_core.ifid_instr", "команда в ID", "hex"),
    ("tb_fib.dut.u_core.ex_taken", "переход в EX", "bit"),
    ("tb_fib.dut.u_core.fwd_a", "forward A", "dec"),
    ("tb_fib.dut.u_core.fwd_b", "forward B", "dec"),
    ("tb_fib.dut.u_core.load_use", "load-use stall", "bit"),
    ("tb_fib.dut.u_core.freeze", "промах кэша", "bit"),
    ("tb_fib.dut.u_core.ex_res", "результат EX", "dec"),
    ("tb_fib.dut.u_core.wb_wa", "WB: регистр", "dec"),
    ("tb_fib.dut.u_core.wb_wd", "WB: значение", "dec"),
    ("tb_fib.dut.u_core.u_rf.dbg_r1", "R1 = N", "dec"),
    ("tb_fib.dut.u_core.u_rf.dbg_r2", "R2 = a", "dec"),
    ("tb_fib.dut.u_core.u_rf.dbg_r3", "R3 = b", "dec"),
    ("tb_fib.halted", "halted", "bit"),
]


def parse_vcd(path, wanted):
    ids, scope, changes = {}, [], {}
    t = 0
    with open(path) as f:
        defs = True
        for line in f:
            line = line.strip()
            if defs:
                if line.startswith("$scope"):
                    scope.append(line.split()[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    p = line.split()
                    name = ".".join(scope + [p[4]])
                    if name in wanted:
                        ids.setdefault(p[3], []).append(name)
                        changes[name] = []
                elif line.startswith("$enddefinitions"):
                    defs = False
                continue
            if not line:
                continue
            if line[0] == "#":
                t = int(line[1:])
            elif line[0] in "01xz" and len(line) > 1 and line[1:] in ids:
                for n in ids[line[1:]]:
                    changes[n].append((t, line[0]))
            elif line[0] == "b":
                val, code = line[1:].split()
                if code in ids:
                    for n in ids[code]:
                        changes[n].append((t, val))
    return changes


def value_at(ch, t):
    v = "x"
    for tt, vv in ch:
        if tt > t:
            break
        v = vv
    return v


def fmt(v, kind):
    if re.search("[xz]", v):
        return "x"
    n = int(v, 2)
    return f"{n:04x}" if kind == "hex" else str(n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("png")
    ap.add_argument("--run", type=int, default=1)
    ap.add_argument("--cycles", type=int, default=40)
    ap.add_argument("--period", type=int, default=10000, help="период такта в единицах VCD")
    a = ap.parse_args()

    wanted = {s[0] for s in SIGNALS} | {"tb_fib.reset"}
    ch = parse_vcd(a.vcd, wanted)
    falls = [t for t, v in ch["tb_fib.reset"] if v == "0"]
    t0 = falls[a.run - 1]
    # первый фронт после снятия сброса
    t0 = next(t for t, v in ch["tb_fib.clk"] if t >= t0 and v == "1")
    ts = [t0 + k * a.period for k in range(a.cycles + 1)]

    h = 0.42
    fig, ax = plt.subplots(figsize=(max(10, a.cycles * 0.34), len(SIGNALS) * h + 0.8))
    for row, (name, label, kind) in enumerate(SIGNALS):
        y = len(SIGNALS) - 1 - row
        ax.text(-0.5, y + 0.3, label, ha="right", va="center", fontsize=9)
        if name.endswith(".clk"):
            xs, ys = [], []
            for k in range(a.cycles):
                xs += [k, k, k + 0.5, k + 0.5]
                ys += [y, y + 0.6, y + 0.6, y]
            ax.plot(xs, ys, color="#555", lw=0.8)
            continue
        vals = [value_at(ch[name], t + 1) for t in ts[:-1]]   # сразу после фронта
        if kind == "bit":
            xs, ys = [], []
            for k, v in enumerate(vals):
                lvl = y + (0.6 if v == "1" else 0)
                xs += [k, k + 1]
                ys += [lvl, lvl]
            ax.plot(xs, ys, color="#c0392b", lw=1.2)
        else:
            k = 0
            while k < len(vals):
                j = k
                while j + 1 < len(vals) and vals[j + 1] == vals[k]:
                    j += 1
                x0, x1 = k + 0.06, j + 1 - 0.06
                ax.fill([x0, x0 + 0.1, x1 - 0.1, x1, x1 - 0.1, x0 + 0.1],
                        [y + 0.3, y + 0.6, y + 0.6, y + 0.3, y, y], color="#eaf2fb",
                        edgecolor="#2e86c1", lw=0.8)
                if x1 - x0 > 0.55:
                    ax.text((x0 + x1) / 2, y + 0.3, fmt(vals[k], kind), ha="center",
                            va="center", fontsize=7)
                k = j + 1
    for k in range(a.cycles + 1):
        ax.axvline(k, color="#eee", lw=0.5, zorder=0)
    ax.set_xlim(-0.2, a.cycles)
    ax.set_ylim(-0.3, len(SIGNALS))
    ax.set_yticks([])
    ax.set_xticks(range(0, a.cycles + 1, 2))
    ax.set_xlabel("такт после снятия сброса")
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    fig.subplots_adjust(left=0.13, right=0.99, top=0.98, bottom=0.08)
    fig.savefig(a.png, dpi=130)
    print(f"{a.png}: {a.cycles} тактов, прогон {a.run}")


if __name__ == "__main__":
    main()
