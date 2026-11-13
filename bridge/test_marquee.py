"""test_marquee.py — автотесты бегущей строки на cocotb (без окна).

Главная проверка: каждый кадр, который SoC вывел на матрицы, сверяется
с эталонной моделью на Python. Модель берёт из RAM положение окна и
ленту с текстом и строит те же 32 столбца по той же таблице шрифта.

Запуск: python3 bridge/run.py test
"""
import os
import random
import sys

import cocotb

from soc_io import SoC, BTN_FASTER, BTN_SLOWER, BTN_PAUSE

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from gen_font import render_column  # noqa: E402

# переменные и константы из asm/marquee.asm
END, SCI, SCC, SPEED, LAST_T, PREV_B, PAUSED = range(7)
TAPE, PAD, TAPE_MAX = 0x20, 6, 0x100


def tape(soc):
    return bytes(soc.ram(a) for a in range(TAPE, soc.ram(END)))


def position(soc):
    """Положение окна: номер столбца от начала ленты."""
    return (soc.ram(SCI) - TAPE) * 6 + soc.ram(SCC)


def model_frame(soc):
    """Кадр, который должна была нарисовать прошивка."""
    text = tape(soc)
    ci, cc = soc.ram(SCI) - TAPE, soc.ram(SCC)
    cols = []
    for _ in range(32):
        cols.append(render_column(text[ci], cc))
        cc += 1
        if cc == 6:
            cc, ci = 0, (ci + 1) % len(text)
    return cols


def art(frame):
    return "\n".join("".join("#" if c >> y & 1 else "." for c in frame) for y in range(8))


async def check_frame(soc):
    """Дождаться кадра и сверить его с моделью."""
    await soc.next_frame()
    got, want = soc.frame(), model_frame(soc)
    assert got == want, f"кадр не совпал с моделью\nSoC:\n{art(got)}\nмодель:\n{art(want)}"
    return got


async def started(dut):
    soc = SoC(dut)
    await soc.start()
    await check_frame(soc)
    return soc


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def frames_match_model(dut):
    """Сто кадров подряд совпадают с моделью; между кадрами экран не меняется."""
    soc = await started(dut)
    for _ in range(100):
        shown = await check_frame(soc)
        await soc.cycles(200)                  # прошивка уже рисует следующий кадр,
        assert soc.frame() == shown, "кадр на матрицах изменился до записи в LATCH"
    dut._log.info("кадр SoC:\n%s", art(shown))
    assert any(shown), "экран пустой"


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def scroll_is_pixel_by_pixel(dut):
    """Окно сдвигается по таймеру и ровно на один столбец за шаг."""
    soc = await started(dut)
    await soc.press(BTN_SLOWER)                # 16 тиков на сдвиг: кадров больше,
    await soc.press(BTN_SLOWER)                # чем сдвигов
    total = len(tape(soc)) * 6
    steps = []
    prev = position(soc)
    for _ in range(200):
        await check_frame(soc)
        steps.append((position(soc) - prev) % total)
        prev = position(soc)
    dut._log.info("за 200 кадров окно прошло %d столбцов", sum(steps))
    assert set(steps) == {0, 1}, f"шаги окна: {sorted(set(steps))}"

    await soc.press(BTN_PAUSE)
    await check_frame(soc)
    stopped = position(soc)
    await soc.cycles(20000)
    assert position(soc) == stopped, "на паузе окно двигается"


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def typing_edits_text(dut):
    """UART: печать дописывает, Backspace стирает, Enter очищает; правка видна сразу."""
    soc = await started(dut)
    await soc.press(BTN_PAUSE)                 # чтобы окно стояло на месте
    before = tape(soc)

    async def send(text):
        soc.type(text)
        await soc.sent()
        await soc.cycles(1500)                 # прошивка забрала байты из очереди
        return await check_frame(soc)

    frame = await send("Hi!")
    assert tape(soc) == before + b"Hi!"
    # окно встало на хвост текста: последний символ — в правых шести столбцах
    assert frame[26:] == [render_column(ord("!"), c) for c in range(6)]

    frame = await send(b"\x08")
    assert tape(soc) == before + b"Hi"
    assert frame[26:] == [render_column(ord("i"), c) for c in range(6)]

    frame = await send(b"\r")
    assert tape(soc) == b" " * PAD
    assert frame == [0] * 32, "после Enter экран должен погаснуть"

    await send(b"\x08\x08")                    # стирать нечего — зазор остаётся
    assert tape(soc) == b" " * PAD

    await send("x" * 300)                      # лента не выходит за RAM
    assert soc.ram(END) == TAPE_MAX and soc.ram(SPEED) == 4


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def speed_buttons(dut):
    """Кнопки скорости: 4 -> 2 -> 1 -> 1 (минимум), затем до 64 (максимум)."""
    soc = await started(dut)
    seen = []
    for _ in range(3):
        await soc.press(BTN_FASTER)
        seen.append(soc.ram(SPEED))
    assert seen == [2, 1, 1], seen
    seen = []
    for _ in range(8):
        await soc.press(BTN_SLOWER)
        seen.append(soc.ram(SPEED))
    assert seen == [2, 4, 8, 16, 32, 64, 64, 64], seen


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def stress_random_input(dut):
    """Стресс-тест: 1000 кадров со случайным вводом и кнопками. Каждый кадр
    совпадает с моделью, а время кадра не растёт (FPS не проседает)."""
    soc = await started(dut)
    rng = random.Random(2026)
    keys = [chr(c) for c in range(32, 127)] * 3 + ["\x08"] * 40 + ["\r"]
    gaps = []
    prev = soc.stats()["cycles"]
    for n in range(1000):
        if rng.random() < 0.25:
            soc.type("".join(rng.choice(keys) for _ in range(rng.randrange(1, 6))))
        if n % 50 == 0:
            soc.set_buttons(rng.choice([0, 0, BTN_FASTER, BTN_SLOWER, BTN_PAUSE]))
        await check_frame(soc)
        now = soc.stats()["cycles"]
        gaps.append(now - prev)
        prev = now
    st = soc.stats()
    dut._log.info("кадр: %d..%d тактов, в среднем %.0f; CPI %.2f, кэш: %.0f%% попаданий",
                  min(gaps), max(gaps), sum(gaps) / len(gaps), st["cpi"], st["hit_rate"] * 100)
    assert TAPE + PAD <= soc.ram(END) <= TAPE_MAX
    assert not st["halted"]
    assert max(gaps) < 2000, "кадр дольше 2000 тактов"
