"""marquee_bridge.py — интерактивный мост «симулятор <-> ПК» (оценка «5»).

cocotb запускает SoC в Icarus Verilog, а этот модуль открывает окно pygame:
  * клавиатура ПК -> UART (побитово, по линии uart_rx) и кнопки SoC;
  * видео-буфер (выход frame, 32 x 8 бит) -> 4 LED-матрицы 8x8 в окне;
  * всё, что процессор шлёт по uart_tx, печатается строкой внизу окна.

Управление:
    буквы, цифры, знаки  — дописать в бегущую строку
    Backspace / Enter    — стереть символ / очистить текст
    стрелка вверх / вниз — кнопки «быстрее» / «медленнее»
    Tab                  — кнопка «пауза»
    Esc или закрыть окно — выход

Запуск: python3 bridge/run.py play   (подробнее — README.md)

Переменные окружения для запуска без человека (проверка, скриншот):
    BRIDGE_SCRIPT  — текст, который «печатается» сразу после старта
    BRIDGE_CYCLES  — остановиться через столько тактов
    BRIDGE_SHOT    — сохранить последний кадр окна в PNG
"""
import os
import time

import cocotb
from cocotb.triggers import ClockCycles

from soc_io import SoC, BTN_FASTER, BTN_SLOWER, BTN_PAUSE

CHUNK = 2000            # тактов симуляции между обновлениями окна
LED = 18                # диаметр светодиода, px
STEP = 22               # шаг сетки
GAP = 14                # промежуток между матрицами
MARGIN = 24

BG = (18, 18, 22)
PANEL = (30, 30, 36)
LED_OFF = (55, 20, 20)
LED_ON = (255, 70, 50)
TEXT = (220, 220, 220)
DIM = (140, 140, 150)


def matrix_x(col):
    m = col // 8
    return MARGIN + m * (8 * STEP + GAP) + (col % 8) * STEP


def key_to_ascii(ev):
    """Печатный символ ASCII для нажатой клавиши или None.

    Шрифт SoC латинский. При русской раскладке ev.unicode — кириллица,
    тогда берём латинскую букву той же клавиши (Й -> Q): код клавиши
    у SDL на macOS и Windows остаётся латинским.
    """
    ch = ev.unicode
    if ch and 32 <= ord(ch) < 127:
        return ch
    if 32 <= ev.key < 127:
        return chr(ev.key).upper()
    return None


def draw(pg, screen, font, frame, lines, uart_text):
    screen.fill(BG)
    for m in range(4):
        x0 = MARGIN + m * (8 * STEP + GAP) - 6
        pg.draw.rect(screen, PANEL, (x0, MARGIN - 6, 8 * STEP + 8, 8 * STEP + 8),
                     border_radius=6)
    for col in range(32):
        for row in range(8):
            on = (frame[col] >> row) & 1
            cx = matrix_x(col) + LED // 2
            cy = MARGIN + row * STEP + LED // 2
            pg.draw.circle(screen, LED_ON if on else LED_OFF, (cx, cy), LED // 2)
    y = MARGIN + 8 * STEP + 18
    for i, text in enumerate(lines):
        screen.blit(font.render(text, True, TEXT if i == 0 else DIM), (MARGIN, y))
        y += 22
    if uart_text:
        screen.blit(font.render("UART TX: " + uart_text[-70:], True, DIM), (MARGIN, y))


@cocotb.test()
async def play(dut):
    import pygame as pg

    soc = SoC(dut)
    await soc.start()

    script = os.environ.get("BRIDGE_SCRIPT", "")
    max_cycles = int(os.environ.get("BRIDGE_CYCLES", "0"))
    shot = os.environ.get("BRIDGE_SHOT", "")
    prog = os.environ.get("BRIDGE_PROG", "marquee")
    if script:
        soc.type(script)

    pg.init()
    width = MARGIN * 2 + 4 * 8 * STEP + 3 * GAP - 4
    screen = pg.display.set_mode((width, 8 * STEP + 2 * MARGIN + 106))
    pg.display.set_caption("SoC Marquee — ИУ5-51Б, вариант 2")
    # системный шрифт с кириллицей (встроенный шрифт pygame её не содержит)
    font = pg.font.SysFont("dejavusans,arial,segoeui,helvetica,liberationsans", 16)
    pg.key.set_repeat(400, 40)
    typed = ""

    t0 = time.time()
    last_cycles, last_t, rate = 0, t0, 0.0
    running = True
    while running:
        await ClockCycles(dut.clk, CHUNK)

        for ev in pg.event.get():
            if ev.type == pg.QUIT:
                running = False
            elif ev.type == pg.KEYDOWN:
                if ev.key == pg.K_ESCAPE:
                    running = False
                elif ev.key == pg.K_BACKSPACE:
                    soc.type(b"\x08")
                    typed = typed[:-1]
                elif ev.key in (pg.K_RETURN, pg.K_KP_ENTER):
                    soc.type(b"\r")
                    typed = ""
                else:
                    ch = key_to_ascii(ev)
                    if ch:
                        soc.type(ch)
                        typed = (typed + ch)[-60:]

        keys = pg.key.get_pressed()
        mask = 0
        if keys[pg.K_UP]:
            mask |= BTN_FASTER
        if keys[pg.K_DOWN]:
            mask |= BTN_SLOWER
        if keys[pg.K_TAB]:
            mask |= BTN_PAUSE
        soc.set_buttons(mask)

        st = soc.stats()
        now = time.time()
        if now - last_t >= 0.5:
            rate = (st["cycles"] - last_cycles) / (now - last_t)
            last_cycles, last_t = st["cycles"], now

        if prog == "marquee":
            speed = await soc.ram(3)
            paused = await soc.ram(6)
            head = (f"скорость: {speed} тик/сдвиг{'   ПАУЗА' if paused else ''}   "
                    f"(вверх/вниз — скорость, Tab — пауза, Enter — очистить, Esc — выход)")
        else:
            head = "Chat Terminal: печатайте — ответ процессора в строке UART TX   (Esc — выход)"
        lines = [
            head,
            f"такт {st['cycles']:,}  ·  CPI {st['cpi']:.2f}  ·  "
            f"кэш {st['hits']:,} попаданий / {st['misses']:,} промахов  ·  "
            f"{rate / 1000:.0f} тыс. тактов/с".replace(",", " "),
        ]
        if prog == "marquee":
            lines.append("введено: " + (typed or "— кликните по окну и печатайте латиницей —")
                         + (f"   (в очереди UART {len(soc.tx_queue)})" if soc.tx_queue else ""))
        draw(pg, screen, font, soc.frame(), lines,
             soc.received.decode("ascii", errors="replace"))
        pg.display.flip()

        if max_cycles and st["cycles"] >= max_cycles:
            running = False

    if shot:
        pg.image.save(screen, shot)
        dut._log.info("скриншот сохранён: %s", shot)
    st = soc.stats()
    dut._log.info("итог: %d тактов за %.1f с, CPI %.2f, кэш %d/%d",
                  st["cycles"], time.time() - t0, st["cpi"], st["hits"], st["misses"])
    pg.quit()
