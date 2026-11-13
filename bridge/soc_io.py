"""soc_io.py — связь Python (cocotb) с выводами soc_top.

Общий код интерактивного моста и автотестов:
  * тактовый сигнал и сброс;
  * UART «со стороны ПК»: байты уходят процессору побитово по линии
    uart_rx, а всё, что он шлёт по uart_tx, собирается в received;
  * кнопки, кадр на матрицах, RAM и счётчики производительности.

Ждём всегда одним таймером симулятора на нужное число тактов, а не
каждого фронта clk: Python просыпается, только когда ему есть что делать,
и симуляция идёт в несколько раз быстрее.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Event, FallingEdge, Timer, ValueChange

CLK_NS = 10                  # период такта
CLKS_PER_BIT = 16            # длительность бита UART, как в soc_top

BTN_FASTER = 0b001
BTN_SLOWER = 0b010
BTN_PAUSE = 0b100


class SoC:
    def __init__(self, dut, clks_per_bit=CLKS_PER_BIT):
        self.dut = dut
        self.bit_ns = clks_per_bit * CLK_NS
        self.tx_queue = bytearray()   # ПК -> процессор, ещё не отправлено
        self.received = bytearray()   # процессор -> ПК
        self._tx_wake = Event()
        self._tx_busy = False

    async def start(self):
        """Запустить такт, загрузить RAM, сбросить SoC."""
        d = self.dut
        cocotb.start_soon(Clock(d.clk, CLK_NS, unit="ns", impl="gpi").start())
        self.load_ram()
        d.reset.value = 1
        d.uart_rx.value = 1
        d.buttons.value = 0
        for _ in range(3):
            await FallingEdge(d.clk)
        d.reset.value = 0             # дальше все действия — на спаде clk,
        cocotb.start_soon(self._uart_sender())      # посередине между фронтами
        cocotb.start_soon(self._uart_receiver())

    def load_ram(self, path=None):
        """Записать образ RAM заново: cocotb гоняет все тесты в одной
        симуляции, а сброс содержимое RAM не трогает."""
        path = path or os.environ.get("SOC_RAM_HEX")
        if not path:
            return
        with open(path) as f:
            words = [int(line, 16) for line in f if line.strip()]
        mem = self.dut.u_ram.mem
        for a in range(256):
            mem[a].value = words[a] if a < len(words) else 0

    async def cycles(self, n):
        """Подождать n тактов."""
        await Timer(n * CLK_NS, unit="ns")

    # ---------------- UART ----------------
    def type(self, text):
        """Поставить текст в очередь на передачу процессору."""
        if isinstance(text, str):
            text = text.encode("ascii", errors="ignore")
        self.tx_queue.extend(text)
        self._tx_wake.set()

    async def _uart_sender(self):
        while True:
            if not self.tx_queue:
                self._tx_busy = False
                self._tx_wake.clear()
                await self._tx_wake.wait()
            self._tx_busy = True
            b = self.tx_queue.pop(0)
            bits = [0] + [(b >> i) & 1 for i in range(8)] + [1]   # старт, данные, стоп
            for bit in bits:
                self.dut.uart_rx.value = bit
                await Timer(self.bit_ns, unit="ns")

    async def _uart_receiver(self):
        tx = self.dut.uart_tx
        while True:
            await FallingEdge(tx)                                 # старт-бит
            await Timer(self.bit_ns * 3 // 2 + CLK_NS // 2, unit="ns")   # середина бита 0
            b = 0
            for i in range(8):
                b |= int(tx.value) << i
                await Timer(self.bit_ns, unit="ns")
            self.received.append(b)

    async def sent(self):
        """Дождаться, пока вся очередь уйдёт в процессор."""
        while self.tx_queue or self._tx_busy:
            await self.cycles(CLKS_PER_BIT)

    # ---------------- кнопки ----------------
    def set_buttons(self, mask):
        self.dut.buttons.value = mask & 0b111

    async def press(self, mask, cycles=3000):
        """Нажать и отпустить. Программа ловит фронт нажатия, поэтому
        держим дольше одного прохода её цикла."""
        self.set_buttons(mask)
        await self.cycles(cycles)
        self.set_buttons(0)
        await self.cycles(cycles)

    # ---------------- состояние SoC ----------------
    def frame(self):
        """Кадр на матрицах: 32 столбца по 8 бит, бит 0 — верхний светодиод."""
        v = int(self.dut.frame.value)
        return [(v >> (8 * x)) & 0xFF for x in range(32)]

    async def next_frame(self):
        """Дождаться, пока программа выведет следующий кадр (запись в LATCH)."""
        await ValueChange(self.dut.frame_count)
        await Timer(CLK_NS // 2, unit="ns")       # до спада clk: всё установилось

    def ram(self, addr):
        return int(self.dut.u_ram.mem[addr].value)

    def stats(self):
        d = self.dut
        cycles = int(d.dbg_cycles.value)
        retired = int(d.dbg_retired.value)
        hits = int(d.cache_hits.value)
        misses = int(d.cache_misses.value)
        return {
            "cycles": cycles,
            "frames": int(d.frame_count.value),
            "cpi": cycles / retired if retired else 0.0,
            "hit_rate": hits / (hits + misses) if hits + misses else None,
            "halted": int(d.halted.value),
        }
