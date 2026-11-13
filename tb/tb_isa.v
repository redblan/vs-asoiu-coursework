// tb_isa.v — прогон самопроверяющегося теста asm/isa_test.asm на SoC.
// Проверяет итоговое слово RAM[0x1F] = 0x600D и несколько значений,
// которые программа записала в RAM и вывела на матрицы через LATCH.
`timescale 1ns/1ps

module tb_isa;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    wire         halted, tx;
    wire [255:0] frame;
    wire [9:0]   pc;
    wire [2:0]   flags;
    wire [31:0]  retired, cycles, hits, misses, frames;

    soc_top dut (
        .clk(clk), .reset(reset), .uart_rx(1'b1), .uart_tx(tx),
        .buttons(3'b000), .frame(frame), .frame_count(frames), .halted(halted),
        .dbg_pc(pc), .dbg_flags(flags), .dbg_retired(retired),
        .dbg_cycles(cycles), .cache_hits(hits), .cache_misses(misses)
    );

    integer errors = 0;
    reg [1023:0] vcd;

    task check(input [255:0] name, input [15:0] got, input [15:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s: 0x%04h, ожидалось 0x%04h", name, got, exp);
            errors = errors + 1;
        end else
            $display("PASS %0s = 0x%04h", name, got);
    endtask

    initial begin
        if ($value$plusargs("vcd=%s", vcd)) begin
            $dumpfile(vcd);
            $dumpvars(0, tb_isa);
        end
        repeat (2) @(posedge clk);
        @(negedge clk) reset = 1'b0;
        wait (halted || cycles > 5000);
        @(posedge clk);

        if (!halted) begin
            $display("FAIL: нет HALT, PC = %0d", pc);
            errors = errors + 1;
        end
        check("RAM[0x1F] status", dut.u_ram.mem[8'h1F], 16'h600D);
        check("RAM[0x10] SW/LW", dut.u_ram.mem[8'h10], 16'h00EF);
        check("RAM[0x11] FONT_RENDER", dut.u_ram.mem[8'h11], 16'h007F);
        check("RAM[0x08] write-through", dut.u_ram.mem[8'h08], 16'h00EF);
        check("LED col 0", {8'h00, frame[7:0]}, 16'h0015);
        check("LED col 31", {8'h00, frame[255:248]}, 16'h007F);
        check("frames latched", frames[15:0], 16'd1);
        $display("тактов %0d, команд %0d, кэш: попаданий %0d, промахов %0d",
                 cycles, retired, hits, misses);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
