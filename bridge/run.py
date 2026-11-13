#!/usr/bin/env python3
"""run.py — сборка прошивки и запуск SoC под cocotb + Icarus Verilog.

    python3 bridge/run.py play               окно pygame: играть руками
    python3 bridge/run.py play --prog echo   то же для Chat Terminal (ответ процессора — строкой в окне)
    python3 bridge/run.py test               автотесты бегущей строки (без окна)
    python3 bridge/run.py demo               без человека: печатает текст, сохраняет build/bridge_<prog>.png

Параметры SoC: --tick-div (тактов на тик таймера), --miss-penalty.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RTL = ROOT / "rtl"


def sh(*args):
    subprocess.run([sys.executable, *map(str, args)], check=True, cwd=ROOT)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["play", "test", "demo"])
    ap.add_argument("--prog", default="marquee", help="программа из asm/ (по умолчанию marquee)")
    ap.add_argument("--tick-div", type=int, default=None)
    ap.add_argument("--miss-penalty", type=int, default=4)
    args = ap.parse_args()

    from cocotb_tools.runner import get_runner

    BUILD.mkdir(exist_ok=True)
    sh(ROOT / "tools" / "gen_font.py", BUILD / "font.hex")
    sh(ROOT / "tools" / "asm.py", ROOT / "asm" / f"{args.prog}.asm", "-o", BUILD / args.prog)

    # В окне SoC получает 30 000 тактов в секунду: тик 512 тактов и 4 тика на
    # сдвиг дают около 15 столбцов в секунду. Автотестам ждать незачем — тик 64.
    tick_div = args.tick_div or (64 if args.mode == "test" else 512)
    params = {"TICK_DIV": tick_div, "MISS_PENALTY": args.miss_penalty, "CLKS_PER_BIT": 16}

    runner = get_runner("icarus")
    sim_dir = BUILD / f"cocotb_{args.mode}"
    runner.build(
        sources=sorted(RTL.glob("*.v")),
        includes=[RTL],
        hdl_toplevel="soc_top",
        parameters=params,
        build_dir=sim_dir,
        always=True,
        timescale=("1ns", "1ps"),
    )

    # модули тестов cocotb ищет в sys.path, а папка этого скрипта там уже есть
    env = {"SOC_RAM_HEX": str(BUILD / (args.prog + ".ram.hex")),
           "BRIDGE_PROG": args.prog}
    module = "test_marquee" if args.mode == "test" else "marquee_bridge"
    if args.mode == "demo":
        env.update({
            "SDL_VIDEODRIVER": os.environ.get("SDL_VIDEODRIVER", "dummy"),
            "BRIDGE_SCRIPT": "Hello",
            "BRIDGE_CYCLES": "140000",
            "BRIDGE_SHOT": str(BUILD / f"bridge_{args.prog}.png"),
        })

    results = runner.test(
        hdl_toplevel="soc_top",
        test_module=module,
        build_dir=sim_dir,
        test_dir=sim_dir,
        plusargs=[f"+rom={BUILD / (args.prog + '.rom.hex')}",
                  f"+ram={BUILD / (args.prog + '.ram.hex')}",
                  f"+font={BUILD / 'font.hex'}"],
        extra_env=env,
    )
    from cocotb_tools.check_results import get_results
    total, failed = get_results(results)
    print(f"cocotb: тестов {total}, упало {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
