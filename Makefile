# Makefile — сборка прошивок, тесты и запуск SoC.
#
#   make            шрифт + все программы (build/*.hex, build/*.lst)
#   make test       все тесты: Verilog-тестбенчи (Icarus) + cocotb
#   make play       интерактивная бегущая строка в окне pygame
#   make play-echo  Chat Terminal в том же окне
#   make wave       временные диаграммы Фибоначчи -> build/fib.vcd (GTKWave)
#   make lint       verilator --lint-only -Wall
#   make synth      синтез Yosys: ресурсы (нужен yosys)

PY      ?= python3
IVERILOG = iverilog -g2012 -Irtl
B        = build
RTL      = $(wildcard rtl/*.v)
PROGS    = fib echo marquee isa_test

.PHONY: all test test-rtl test-cocotb crosscheck play play-echo demo wave lint synth clean

all: $(B)/font.hex $(B)/font_expect.hex $(PROGS:%=$(B)/%.rom.hex)

$(B):
	mkdir -p $(B)

$(B)/font.hex: tools/gen_font.py | $(B)
	$(PY) tools/gen_font.py $@

$(B)/font_expect.hex: tools/gen_font.py | $(B)
	$(PY) tools/gen_font.py --expect $@

$(B)/%.rom.hex: asm/%.asm tools/asm.py | $(B)
	$(PY) tools/asm.py $< -o $(B)/$*

# ---------- тесты ----------
test: test-rtl test-cocotb

ARGS = +font=$(B)/font.hex

test-rtl: all crosscheck
	$(IVERILOG) -o $(B)/tb_font.vvp tb/tb_font.v rtl/font_render.v
	vvp -n $(B)/tb_font.vvp $(ARGS) +expect=$(B)/font_expect.hex | tee $(B)/tb_font.log
	$(IVERILOG) -o $(B)/tb_uart.vvp tb/tb_uart.v rtl/dev_uart.v rtl/uart_rx.v rtl/uart_tx.v
	vvp -n $(B)/tb_uart.vvp | tee $(B)/tb_uart.log
	$(IVERILOG) -o $(B)/tb_fib.vvp -s tb_fib tb/tb_fib.v $(RTL)
	@echo "== Фибоначчи: машинный код, составленный вручную"
	vvp -n $(B)/tb_fib.vvp $(ARGS) +rom=asm/fib_manual.rom.hex +ram=asm/fib_manual.ram.hex | tee $(B)/tb_fib_manual.log
	@echo "== Фибоначчи: код из ассемблера"
	vvp -n $(B)/tb_fib.vvp $(ARGS) +rom=$(B)/fib.rom.hex +ram=$(B)/fib.ram.hex | tee $(B)/tb_fib.log
	$(IVERILOG) -o $(B)/tb_isa.vvp -s tb_isa tb/tb_isa.v $(RTL)
	vvp -n $(B)/tb_isa.vvp $(ARGS) +rom=$(B)/isa_test.rom.hex +ram=$(B)/isa_test.ram.hex | tee $(B)/tb_isa.log
	$(IVERILOG) -o $(B)/tb_echo.vvp -s tb_echo tb/tb_echo.v $(RTL)
	vvp -n $(B)/tb_echo.vvp $(ARGS) +rom=$(B)/echo.rom.hex +ram=$(B)/echo.ram.hex | tee $(B)/tb_echo.log
	$(IVERILOG) -o $(B)/tb_marquee.vvp -s tb_marquee tb/tb_marquee.v $(RTL)
	vvp -n $(B)/tb_marquee.vvp $(ARGS) +rom=$(B)/marquee.rom.hex +ram=$(B)/marquee.ram.hex | tee $(B)/tb_marquee.log
	@! grep -h "FAIL" $(B)/tb_*.log && echo "== Verilog-тесты: все прошли"

# машинный код, составленный вручную, совпадает с выводом ассемблера
crosscheck: $(B)/fib.rom.hex
	sed 's#//.*##;/^[[:space:]]*$$/d;s/[[:space:]]*$$//' asm/fib_manual.rom.hex > $(B)/fib_manual.clean.hex
	diff $(B)/fib_manual.clean.hex $(B)/fib.rom.hex && echo "== cross-verification: машинный код совпадает"

test-cocotb:
	$(PY) bridge/run.py test

# ---------- интерактив ----------
play:
	$(PY) bridge/run.py play

play-echo:
	$(PY) bridge/run.py play --prog echo

demo:
	$(PY) bridge/run.py demo

# ---------- диаграммы, lint, синтез ----------
wave: all
	$(IVERILOG) -o $(B)/tb_fib.vvp -s tb_fib tb/tb_fib.v $(RTL)
	vvp -n $(B)/tb_fib.vvp $(ARGS) +rom=$(B)/fib.rom.hex +ram=$(B)/fib.ram.hex +vcd=$(B)/fib.vcd
	@echo "открыть: gtkwave $(B)/fib.vcd docs/fib.gtkw"

lint:
	verilator --lint-only -Wall -Irtl --top-module soc_top $(RTL)
	@echo "== lint: без предупреждений"

# Синтез под Xilinx 7-series (Artix-7): число LUT, триггеров, LUT-RAM, BRAM.
# Fmax Yosys не считает — для него нужен Vivado (см. docs/SYNTH.md).
# Вторым проходом — глубина логики: самый длинный путь в уровнях LUT6.
synth: all
	yosys -q -l $(B)/synth.log -p "read_verilog -DSYNTHESIS -Irtl $(RTL); synth_xilinx -top soc_top -flatten; tee -o $(B)/synth_stat.txt stat" > /dev/null
	yosys -q -p "read_verilog -DSYNTHESIS -Irtl $(RTL); synth -top soc_top -flatten; abc -lut 6; opt_clean; tee -o $(B)/synth_ltp.txt ltp -noff" > /dev/null
	@grep -E "Number of cells|LUT|FD|RAM|CARRY|MUXF|SRL" $(B)/synth_stat.txt
	@grep -i "longest" $(B)/synth_ltp.txt

clean:
	rm -rf $(B)
