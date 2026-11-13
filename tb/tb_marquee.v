// tb_marquee.v — тестбенч бегущей строки без интерактива.
// Запускает asm/marquee.asm, печатает несколько кадров псевдографикой,
// затем «печатает» по UART строку и проверяет, что она дописалась в ленту.
// Живая демонстрация — bridge/marquee_bridge.py (cocotb + pygame).
`timescale 1ns/1ps

module tb_marquee;
    localparam CPB = 16;
    reg clk = 1'b0, reset = 1'b1;
    always #5 clk = ~clk;

    reg          rx = 1'b1;
    reg  [2:0]   buttons = 3'b000;
    wire         tx, halted;
    wire [255:0] frame;
    wire [9:0]   pc;
    wire [2:0]   flags;
    wire [31:0]  retired, cycles, hits, misses, frames;

    soc_top #(.CLKS_PER_BIT(CPB), .TICK_DIV(64)) dut (
        .clk(clk), .reset(reset), .uart_rx(rx), .uart_tx(tx),
        .buttons(buttons), .frame(frame), .frame_count(frames), .halted(halted),
        .dbg_pc(pc), .dbg_flags(flags), .dbg_retired(retired),
        .dbg_cycles(cycles), .cache_hits(hits), .cache_misses(misses)
    );

    task show_frame;
        integer y, x;
        begin
            for (y = 0; y < 8; y = y + 1) begin
                $write("    |");
                for (x = 0; x < 32; x = x + 1) begin
                    $write("%s", frame[x*8 + y] ? "#" : " ");
                    if (x % 8 == 7 && x != 31) $write("|");
                end
                $display("|");
            end
        end
    endtask

    task send_byte(input [7:0] v);
        integer k;
        begin
            rx = 1'b0; repeat (CPB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin rx = v[k]; repeat (CPB) @(posedge clk); end
            rx = 1'b1; repeat (CPB) @(posedge clk);
        end
    endtask

    integer i, errors = 0;
    reg [15:0] end_before, end_after;

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk) reset = 1'b0;

        // окно сдвигается каждые speed * TICK_DIV = 4 * 64 тактов
        for (i = 0; i < 3; i = i + 1) begin
            repeat (30 * 256) @(posedge clk);
            $display("кадр через %0d тактов (sci = 0x%02h, scc = %0d):",
                     cycles, dut.u_ram.mem[1], dut.u_ram.mem[2]);
            show_frame;
        end
        if (frame == 256'd0) begin
            $display("FAIL: экран пустой"); errors = errors + 1;
        end

        end_before = dut.u_ram.mem[0];
        send_byte("O"); send_byte("K");
        repeat (2000) @(posedge clk);
        end_after = dut.u_ram.mem[0];
        if (end_after !== end_before + 2 ||
            dut.u_ram.mem[end_before] !== "O" || dut.u_ram.mem[end_before + 1] !== "K") begin
            $display("FAIL: текст не дописан (end 0x%h -> 0x%h)", end_before, end_after);
            errors = errors + 1;
        end else
            $display("PASS: \"OK\" дописан в ленту, end 0x%h -> 0x%h", end_before, end_after);

        // кнопка «пауза»: окно не должно двигаться
        buttons = 3'b100; repeat (2000) @(posedge clk); buttons = 3'b000;
        end_before = dut.u_ram.mem[1] * 8 + dut.u_ram.mem[2];
        repeat (8000) @(posedge clk);
        if (dut.u_ram.mem[1] * 8 + dut.u_ram.mem[2] !== end_before) begin
            $display("FAIL: на паузе окно двигается"); errors = errors + 1;
        end else
            $display("PASS: пауза останавливает прокрутку");

        $display("тактов %0d, команд %0d, CPI %0d.%02d, кэш: попаданий %0d, промахов %0d",
                 cycles, retired, cycles / retired, (cycles * 100 / retired) % 100, hits, misses);
        $display("кадров выведено %0d, один кадр — %0d тактов", frames, cycles / frames);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
