"""test_marquee.py — автотесты бегущей строки на cocotb (без окна).

Сверяют то, что SoC рисует в видео-буфере, с эталонной моделью на Python:
для текущего окна (sci, scc) и ленты из RAM модель вычисляет 32 столбца
через ту же таблицу шрифта, что лежит в Font ROM.

Запуск: python3 bridge/run.py test
"""
import os
import sys

import cocotb
from cocotb.triggers import ClockCycles

from soc_io import SoC, BTN_FASTER, BTN_SLOWER, BTN_PAUSE

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from gen_font import render_column  # noqa: E402

# адреса переменных из asm/marquee.asm
END, SCI, SCC, SPEED, LAST_T, PREV_B, PAUSED = range(7)
TAPE, PAD = 0x20, 6


async def tape(soc):
    end = await soc.ram(END)
    return [await soc.ram(a) for a in range(TAPE, end)], end


async def model_frame(soc):
    chars, end = await tape(soc)
    ci = await soc.ram(SCI) - TAPE
    cc = await soc.ram(SCC)
    if ci >= len(chars):
        ci = 0
    cols = []
    for _ in range(32):
        cols.append(render_column(chars[ci], cc))
        cc += 1
        if cc == 6:
            cc, ci = 0, ci + 1
            if ci >= len(chars):
                ci = 0
    return cols


def ascii_art(frame):
    return "\n".join("".join("#" if c >> y & 1 else "." for c in frame) for y in range(8))


async def paused_soc(dut):
    soc = SoC(dut)
    await soc.start()
    await ClockCycles(dut.clk, 20000)          # пусть текст немного уедет
    await soc.press(BTN_PAUSE)
    await ClockCycles(dut.clk, 3000)           # полный проход отрисовки
    assert await soc.ram(PAUSED) == 1
    return soc


@cocotb.test()
async def frame_matches_model(dut):
    """Кадр в видео-буфере совпадает с моделью на Python."""
    soc = await paused_soc(dut)
    got, want = soc.frame(), await model_frame(soc)
    dut._log.info("кадр SoC:\n%s", ascii_art(got))
    assert got == want, f"\nSoC:\n{ascii_art(got)}\nмодель:\n{ascii_art(want)}"
    assert any(got), "экран пустой"


@cocotb.test()
async def scroll_moves_one_column(dut):
    """После снятия паузы окно сдвигается ровно по одному столбцу за шаг."""
    soc = await paused_soc(dut)
    pos0 = (await soc.ram(SCI)) * 6 + await soc.ram(SCC)
    await soc.press(BTN_PAUSE)                 # снять паузу
    speed = await soc.ram(SPEED)
    await ClockCycles(dut.clk, speed * 64 * 30)
    pos1 = (await soc.ram(SCI)) * 6 + await soc.ram(SCC)
    dut._log.info("позиция окна %d -> %d", pos0, pos1)
    assert pos1 > pos0, "текст не двигается"


@cocotb.test()
async def typing_edits_tape(dut):
    """UART: печать дописывает, Backspace стирает, Enter очищает."""
    soc = await paused_soc(dut)
    _, end0 = await tape(soc)
    soc.type("Hi!")
    await soc.wait_tx_idle()
    await ClockCycles(dut.clk, 2000)
    chars, end1 = await tape(soc)
    assert end1 == end0 + 3, (end0, end1)
    assert bytes(chars[-3:]) == b"Hi!"

    soc.type(b"\x08")
    await soc.wait_tx_idle()
    await ClockCycles(dut.clk, 2000)
    chars, end2 = await tape(soc)
    assert end2 == end1 - 1 and bytes(chars[-2:]) == b"Hi"

    soc.type(b"\r")
    await soc.wait_tx_idle()
    await ClockCycles(dut.clk, 2000)
    chars, end3 = await tape(soc)
    assert end3 == TAPE + PAD and chars == [0x20] * PAD
    await ClockCycles(dut.clk, 3000)
    assert soc.frame() == [0] * 32, "после Enter экран должен погаснуть"

    soc.type("OK")
    await soc.wait_tx_idle()
    await ClockCycles(dut.clk, 3000)
    got, want = soc.frame(), await model_frame(soc)
    assert got == want


@cocotb.test()
async def speed_buttons(dut):
    """Кнопки скорости: 4 -> 2 -> 1 -> 1 (минимум) и обратно до 64 (максимум)."""
    soc = SoC(dut)
    await soc.start()
    await ClockCycles(dut.clk, 2000)
    seen = [await soc.ram(SPEED)]
    for _ in range(3):
        await soc.press(BTN_FASTER)
        seen.append(await soc.ram(SPEED))
    assert seen == [4, 2, 1, 1], seen
    seen = []
    for _ in range(8):
        await soc.press(BTN_SLOWER)
        seen.append(await soc.ram(SPEED))
    assert seen == [2, 4, 8, 16, 32, 64, 64, 64], seen


@cocotb.test()
async def stress_long_run(dut):
    """Стресс-тест: долгая работа с вводом, лента не выходит за RAM."""
    soc = SoC(dut)
    await soc.start()
    for i in range(30):
        soc.type(f"LINE{i} ")
        await ClockCycles(dut.clk, 20000)
        if i % 7 == 6:
            soc.type(b"\x08\x08")
    await soc.wait_tx_idle()
    await ClockCycles(dut.clk, 5000)
    end = await soc.ram(END)
    st = soc.stats()
    dut._log.info("после %d тактов: конец ленты 0x%02x, CPI %.2f, кэш %d/%d",
                  st["cycles"], end, st["cpi"], st["hits"], st["misses"])
    assert TAPE + PAD <= end <= 0x100
    assert not st["halted"]
