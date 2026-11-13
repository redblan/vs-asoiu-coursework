"""soc_io.py — связь Python (cocotb) с выводами soc_top.

Общий код для интерактивного моста и автотестов:
  * тактовый сигнал и сброс;
  * UART «со стороны ПК»: очередь байтов на передачу по линии uart_rx
    и приём всего, что процессор шлёт по uart_tx (8N1, побитово);
  * кнопки, кадр видео-буфера, просмотр RAM, счётчики производительности.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer

CLK_PERIOD_NS = 10
CLKS_PER_BIT = 16            # должно совпадать с параметром soc_top

BTN_FASTER = 0b001
BTN_SLOWER = 0b010
BTN_PAUSE = 0b100


class SoC:
    def __init__(self, dut, clks_per_bit=CLKS_PER_BIT):
        self.dut = dut
        self.cpb = clks_per_bit
        self.tx_queue = bytearray()   # ПК -> процессор
        self.received = bytearray()   # процессор -> ПК

    def load_ram(self, path=None):
        """Записать образ RAM заново (cocotb гоняет все тесты в одной
        симуляции, а сброс RAM не очищает)."""
        path = path or os.environ.get("SOC_RAM_HEX")
        if not path:
            return
        words = []
        with open(path) as f:
            for line in f:
                line = line.split("//")[0].strip()
                if line:
                    words.append(int(line, 16))
        mem = self.dut.u_ram.mem
        for a in range(256):
            mem[a].value = words[a] if a < len(words) else 0

    async def start(self):
        d = self.dut
        cocotb.start_soon(Clock(d.clk, CLK_PERIOD_NS, unit="ns").start())
        self.load_ram()
        d.reset.value = 1
        d.uart_rx.value = 1
        d.buttons.value = 0
        d.ram_view_addr.value = 0
        await ClockCycles(d.clk, 3)
        d.reset.value = 0
        cocotb.start_soon(self._uart_sender())
        cocotb.start_soon(self._uart_receiver())

    # ---------------- UART ----------------
    def type(self, text):
        """Поставить строку в очередь на передачу процессору."""
        if isinstance(text, str):
            text = text.encode("ascii", errors="ignore")
        self.tx_queue.extend(text)

    async def _uart_sender(self):
        d = self.dut
        while True:
            if not self.tx_queue:
                await ClockCycles(d.clk, self.cpb)
                continue
            b = self.tx_queue.pop(0)
            d.uart_rx.value = 0                       # старт-бит
            await ClockCycles(d.clk, self.cpb)
            for i in range(8):                        # данные, младший бит первым
                d.uart_rx.value = (b >> i) & 1
                await ClockCycles(d.clk, self.cpb)
            d.uart_rx.value = 1                       # стоп-бит
            await ClockCycles(d.clk, self.cpb)

    async def _uart_receiver(self):
        d = self.dut
        while True:
            await FallingEdge(d.uart_tx)
            await ClockCycles(d.clk, self.cpb // 2)   # середина старт-бита
            b = 0
            for i in range(8):
                await ClockCycles(d.clk, self.cpb)
                b |= int(d.uart_tx.value) << i
            await ClockCycles(d.clk, self.cpb)
            self.received.append(b)

    async def wait_tx_idle(self):
        while self.tx_queue:
            await ClockCycles(self.dut.clk, self.cpb * 10)
        await ClockCycles(self.dut.clk, self.cpb * 12)

    # ---------------- кнопки ----------------
    def set_buttons(self, mask):
        self.dut.buttons.value = mask & 0b111

    async def press(self, mask, cycles=3000):
        """Нажать и отпустить: программа ловит фронт, держим дольше прохода цикла."""
        self.set_buttons(mask)
        await ClockCycles(self.dut.clk, cycles)
        self.set_buttons(0)
        await ClockCycles(self.dut.clk, cycles)

    # ---------------- чтение состояния ----------------
    def frame(self):
        """32 столбца по 8 бит; бит 0 — верхний светодиод."""
        v = int(self.dut.frame.value)
        return [(v >> (8 * x)) & 0xFF for x in range(32)]

    async def ram(self, addr):
        self.dut.ram_view_addr.value = addr & 0xFF
        await Timer(1, unit="ns")
        return int(self.dut.ram_view_data.value)

    def stats(self):
        d = self.dut
        cycles = int(d.dbg_cycles.value)
        retired = int(d.dbg_retired.value)
        return {
            "cycles": cycles,
            "retired": retired,
            "cpi": cycles / retired if retired else 0.0,
            "hits": int(d.cache_hits.value),
            "misses": int(d.cache_misses.value),
            "pc": int(d.dbg_pc.value),
            "halted": int(d.halted.value),
        }
