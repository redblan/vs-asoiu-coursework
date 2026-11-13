"""marquee_bridge.py — интерактивный мост «симулятор <-> ПК» (оценка «5»).

cocotb запускает SoC в Icarus Verilog, а этот модуль открывает окно pygame:
  * клавиатура ПК -> UART (побитово, по линии uart_rx) и кнопки SoC;
  * кадр с матриц (выход frame, 32 x 8 бит) -> 4 LED-матрицы 8x8 в окне;
  * всё, что процессор шлёт по uart_tx, печатается строкой в окне.

Управление:
    буквы, цифры, знаки  — дописать в бегущую строку
    Backspace / Enter    — стереть символ / очистить текст
    стрелка вверх / вниз — кнопки «быстрее» / «медленнее»
    Tab                  — кнопка «пауза»
    Esc или закрыть окно — выход

Время. Окно обновляется FPS раз в секунду, и между обновлениями SoC
получает ровно CYCLES_PER_FRAME тактов. Если компьютер считает быстрее,
мост ждёт, поэтому строка бежит с одной скоростью на любой машине.

Запуск: python3 bridge/run.py play   (подробнее — README.md)

Переменные окружения для запуска без человека (проверка, скриншот):
    BRIDGE_SCRIPT  — текст, который «печатается» сразу после старта
    BRIDGE_CYCLES  — остановиться через столько тактов
    BRIDGE_SHOT    — сохранить последний кадр окна в PNG
"""
import os
import time

import cocotb
import pygame as pg

from soc_io import SoC, BTN_FASTER, BTN_SLOWER, BTN_PAUSE

FPS = 60                 # обновлений окна в секунду
CYCLES_PER_FRAME = 500   # тактов SoC на одно обновление: 30 000 тактов/с

LED = 18                 # диаметр светодиода, px
STEP = 22                # шаг сетки
GAP = 14                 # промежуток между матрицами
MARGIN = 24

BG = (18, 18, 22)
PANEL = (30, 30, 36)
LED_OFF = (55, 20, 20)
LED_ON = (255, 70, 50)
TEXT = (220, 220, 220)
DIM = (140, 140, 150)

SPEED, PAUSED = 3, 6     # адреса переменных в asm/marquee.asm


def key_to_ascii(ev):
    """Печатный символ ASCII для нажатой клавиши или None.

    Шрифт SoC латинский. При русской раскладке ev.unicode — кириллица,
    тогда берётся латинская буква той же физической клавиши (Й -> q):
    scancode от раскладки не зависит, у клавиш A..Z он равен 4..29.
    """
    ch = ev.unicode
    if ch and 32 <= ord(ch) < 127:
        return ch
    if 4 <= ev.scancode <= 29:
        ch = chr(ord("a") + ev.scancode - 4)
        return ch.upper() if ev.mod & (pg.KMOD_SHIFT | pg.KMOD_CAPS) else ch
    return None


def draw(screen, font, frame, lines):
    screen.fill(BG)
    for m in range(4):
        x0 = MARGIN + m * (8 * STEP + GAP) - 6
        pg.draw.rect(screen, PANEL, (x0, MARGIN - 6, 8 * STEP + 8, 8 * STEP + 8),
                     border_radius=6)
    for col in range(32):
        cx = MARGIN + (col // 8) * (8 * STEP + GAP) + (col % 8) * STEP + LED // 2
        for row in range(8):
            on = (frame[col] >> row) & 1
            cy = MARGIN + row * STEP + LED // 2
            pg.draw.circle(screen, LED_ON if on else LED_OFF, (cx, cy), LED // 2)
    y = MARGIN + 8 * STEP + 18
    for i, text in enumerate(lines):
        screen.blit(font.render(text, True, TEXT if i == 0 else DIM), (MARGIN, y))
        y += 22


@cocotb.test()
async def play(dut):
    soc = SoC(dut)
    await soc.start()

    script = os.environ.get("BRIDGE_SCRIPT", "")
    max_cycles = int(os.environ.get("BRIDGE_CYCLES", "0"))
    shot = os.environ.get("BRIDGE_SHOT", "")
    marquee = os.environ.get("BRIDGE_PROG", "marquee") == "marquee"
    typed = script
    soc.type(script)

    pg.display.init()
    pg.font.init()
    width = MARGIN * 2 + 4 * 8 * STEP + 3 * GAP - 4
    screen = pg.display.set_mode((width, 8 * STEP + MARGIN + 32 + 22 * (3 if marquee else 4)))
    pg.display.set_caption("SoC Marquee — ИУ5-51Б, вариант 2")
    # системный шрифт с кириллицей (встроенный шрифт pygame её не содержит)
    font = pg.font.SysFont("dejavusans,arial,segoeui,helvetica,liberationsans", 16)
    pg.key.set_repeat(400, 40)
    clock = pg.time.Clock()

    t0 = last_t = time.time()
    last = soc.stats()
    rate = soc_fps = 0.0
    running = True
    while running:
        await soc.cycles(CYCLES_PER_FRAME)

        # ---------- клавиатура ПК -> UART и кнопки SoC ----------
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
                        typed += ch
        keys = pg.key.get_pressed()
        soc.set_buttons(BTN_FASTER * keys[pg.K_UP] | BTN_SLOWER * keys[pg.K_DOWN]
                        | BTN_PAUSE * keys[pg.K_TAB])

        # ---------- статистика раз в полсекунды ----------
        st = soc.stats()
        now = time.time()
        if now - last_t >= 0.5:
            rate = (st["cycles"] - last["cycles"]) / (now - last_t)
            soc_fps = (st["frames"] - last["frames"]) / (now - last_t)
            last, last_t = st, now

        # ---------- матрицы и строки состояния ----------
        if marquee:
            head = (f"скорость: {soc.ram(SPEED)} тик/сдвиг{'   ПАУЗА' if soc.ram(PAUSED) else ''}   "
                    f"(вверх/вниз — скорость, Tab — пауза, Enter — очистить, Esc — выход)")
            lines = [head, "введено: " + (typed[-70:] or "— кликните по окну и печатайте —")]
        else:
            lines = ["Chat Terminal: процессор возвращает текст заглавными   (Esc — выход)",
                     "введено:   " + typed[-70:],
                     "ответ SoC: " + soc.received.decode("ascii", errors="replace")[-70:]]
        stats = [f"{rate / 1000:.0f} тыс. тактов/с", f"CPI {st['cpi']:.2f}"]
        if marquee:
            stats.insert(1, f"{soc_fps:.0f} кадров SoC/с")
        if st["hit_rate"] is not None:
            stats.append(f"кэш: {st['hit_rate']:.0%} попаданий")
        lines.append("  ·  ".join(stats))
        draw(screen, font, soc.frame(), lines)
        pg.display.flip()

        if max_cycles and st["cycles"] >= max_cycles:
            running = False
        clock.tick(FPS)               # реальное время: не быстрее FPS обновлений в секунду

    if shot:
        pg.image.save(screen, shot)
    st = soc.stats()
    dut._log.info("итог: %d тактов за %.1f с, %d кадров SoC, CPI %.2f",
                  st["cycles"], time.time() - t0, st["frames"], st["cpi"])
    pg.quit()
