// tb_fib.v — автоматический тестбенч задания «Фибоначчи» на всей SoC.
//
// Программа берётся из +rom=..., данные из +ram=... Для каждого N
// тестбенч сбрасывает SoC, кладёт N в RAM[0], ждёт HALT и сравнивает
// RAM[1] с эталоном. Временные диаграммы: +vcd=build/fib.vcd
`timescale 1ns/1ps

module tb_fib;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;                 // 100 МГц

    wire         halted;
    wire [255:0] frame;
    wire [9:0]   pc;
    wire [2:0]   flags;
    wire [31:0]  retired, cycles, hits, misses, frames;
    wire         tx;

    soc_top dut (
        .clk(clk), .reset(reset), .uart_rx(1'b1), .uart_tx(tx),
        .buttons(3'b000), .frame(frame), .frame_count(frames), .halted(halted),
        .dbg_pc(pc), .dbg_flags(flags), .dbg_retired(retired),
        .dbg_cycles(cycles), .cache_hits(hits), .cache_misses(misses)
    );

    wire [15:0] answer = dut.u_ram.mem[1];     // RAM[0x01] — ответ программы

    function [15:0] fib(input integer n);
        integer i;
        reg [15:0] a, b, t;
        begin
            a = 0; b = 1;
            for (i = 0; i < n; i = i + 1) begin t = a + b; a = b; b = t; end
            fib = a;
        end
    endfunction

    integer tests [0:6];
    integer k, n, timeout, errors;
    reg [1023:0] vcd;

    initial begin
        tests[0] = 0; tests[1] = 1; tests[2] = 2; tests[3] = 3;
        tests[4] = 10; tests[5] = 20; tests[6] = 24;
        errors = 0;
        if ($value$plusargs("vcd=%s", vcd)) begin
            $dumpfile(vcd);
            $dumpvars(0, tb_fib);
        end

        for (k = 0; k < 7; k = k + 1) begin
            n = tests[k];
            reset = 1'b1;
            @(posedge clk); @(posedge clk);
            dut.u_ram.mem[0] = n[15:0];
            dut.u_ram.mem[1] = 16'hDEAD;  // мусор: программа обязана перезаписать
            @(negedge clk);
            reset = 1'b0;

            timeout = 0;
            while (!halted && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (!halted) begin
                $display("FAIL N=%0d: нет HALT за 5000 тактов", n);
                errors = errors + 1;
            end else if (answer !== fib(n)) begin
                $display("FAIL N=%0d: RAM[1] = %0d, ожидалось %0d", n, answer, fib(n));
                errors = errors + 1;
            end else begin
                $display("PASS N=%2d: F(N) = %5d  тактов %4d, команд %3d, CPI %0d.%02d, кэш: попаданий %0d, промахов %0d",
                         n, answer, cycles, retired,
                         cycles / retired, (cycles * 100 / retired) % 100, hits, misses);
            end
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
