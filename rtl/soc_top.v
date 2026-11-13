// soc_top.v — система на кристалле: ядро, память, шина и периферия.
//
//   cpu_core ──IF──> imem (ROM 1K x 16)
//      │
//      └──MEM──> bus ─┬─> dcache ─> dram (RAM 256 x 16)   0x0000..0x00FF
//                     ├─> vram (32 x 8 + LATCH)            0x8000..0x8020
//                     └─> MMIO: dev_uart                   0xFF00..0xFF02
//                               dev_input                  0xFF03..0xFF04
//
// Внешние выводы — то, что видит интерактивный мост (bridge/) или тестбенч.
module soc_top #(
    parameter CLKS_PER_BIT = 16,     // длительность бита UART в тактах
    parameter TICK_DIV     = 512,    // тактов на один тик таймера
    parameter MISS_PENALTY = 4       // такты простоя при промахе кэша
)(
    input          clk,
    input          reset,
    input          uart_rx,
    output         uart_tx,
    input  [2:0]   buttons,          // {пауза, медленнее, быстрее}
    output [255:0] frame,            // 32 столбца по 8 бит — кадр на матрицах
    output [31:0]  frame_count,      // сколько кадров программа вывела (LATCH)
    output         halted,
    // счётчики для отладки и отчёта
    output [9:0]   dbg_pc,
    output [2:0]   dbg_flags,
    output [31:0]  dbg_retired,
    output [31:0]  dbg_cycles,
    output [31:0]  cache_hits,
    output [31:0]  cache_misses
);
    // ---------------- ядро ----------------
    wire [9:0]  imem_addr;
    wire [15:0] imem_data;
    wire [15:0] d_addr, d_wd, d_rd;
    wire        d_re, d_we, d_stall;

    cpu_core u_core (
        .clk(clk), .reset(reset),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_addr(d_addr), .dmem_re(d_re), .dmem_we(d_we),
        .dmem_wd(d_wd), .dmem_rd(d_rd), .dmem_stall(d_stall),
        .halted(halted), .dbg_pc(dbg_pc), .dbg_flags(dbg_flags),
        .dbg_retired(dbg_retired), .dbg_cycles(dbg_cycles)
    );

    imem u_imem (.addr(imem_addr), .data(imem_data));

    // ---------------- шина ----------------
    wire        sel_ram, sel_vram, sel_mmio;
    wire [15:0] ram_rd, mmio_rd;
    wire [7:0]  vram_rd;

    bus u_bus (
        .addr(d_addr), .re(d_re),
        .sel_ram(sel_ram), .sel_vram(sel_vram), .sel_mmio(sel_mmio),
        .ram_rd(ram_rd), .vram_rd(vram_rd), .mmio_rd(mmio_rd), .rd(d_rd)
    );

    // ---------------- RAM через кэш ----------------
    wire [7:0]  m_addr;
    wire        m_we;
    wire [15:0] m_wd, m_rd;

    dcache #(.MISS_PENALTY(MISS_PENALTY)) u_cache (
        .clk(clk), .reset(reset),
        .addr(d_addr[7:0]), .re(d_re && sel_ram), .we(d_we && sel_ram),
        .wd(d_wd), .rd(ram_rd), .stall(d_stall),
        .ram_addr(m_addr), .ram_we(m_we), .ram_wd(m_wd), .ram_rd(m_rd),
        .hits(cache_hits), .misses(cache_misses)
    );

    dram u_ram (
        .clk(clk), .addr(m_addr), .we(m_we), .wd(m_wd), .rd(m_rd)
    );

    // ---------------- видео-буфер ----------------
    vram u_vram (
        .clk(clk), .reset(reset),
        .addr(d_addr[5:0]), .we(d_we && sel_vram), .wd(d_wd[7:0]),
        .rd(vram_rd), .frame(frame), .frame_count(frame_count)
    );

    // ---------------- MMIO ----------------
    wire [15:0] uart_rd, input_rd;

    dev_uart #(.BASE(8'h00), .CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk(clk), .reset(reset), .addr(d_addr[7:0]),
        .re(d_re && sel_mmio), .we(d_we && sel_mmio), .wd(d_wd),
        .rd(uart_rd), .rx(uart_rx), .tx(uart_tx)
    );

    dev_input #(.BASE(8'h03), .TICK_DIV(TICK_DIV)) u_input (
        .clk(clk), .reset(reset), .addr(d_addr[7:0]),
        .rd(input_rd), .buttons(buttons)
    );

    // устройства вне своего окна отдают 0 — объединяем по ИЛИ
    assign mmio_rd = uart_rd | input_rd;
endmodule
