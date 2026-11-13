// tb_echo.v — тестбенч задания «Chat Terminal» на всей SoC.
// Тестбенч играет роль ПК: передаёт строку по линии uart_rx и собирает
// всё, что процессор отправляет по uart_tx. Ожидается та же строка
// заглавными буквами.
`timescale 1ns/1ps

module tb_echo;
    localparam CPB = 16;                       // как в soc_top по умолчанию
    reg clk = 1'b0, reset = 1'b1;
    always #5 clk = ~clk;

    reg          rx = 1'b1;
    wire         tx, halted;
    wire [255:0] frame;
    wire [15:0]  view_data, hits, misses;
    wire [9:0]   pc;
    wire [2:0]   flags;
    wire [31:0]  retired, cycles;

    soc_top #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .reset(reset), .uart_rx(rx), .uart_tx(tx),
        .buttons(3'b000), .frame(frame), .halted(halted),
        .ram_view_addr(8'd0), .ram_view_data(view_data),
        .dbg_pc(pc), .dbg_flags(flags), .dbg_retired(retired),
        .dbg_cycles(cycles), .cache_hits(hits), .cache_misses(misses)
    );

    localparam LEN = 13;
    reg [8*LEN-1:0] send_str = "hello, World!";
    reg [8*LEN-1:0] want_str = "HELLO, WORLD!";
    reg [7:0] got [0:63];
    integer ngot = 0;

    // ---------- приёмник на стороне «ПК» ----------
    integer j;
    reg [7:0] b;
    always begin
        @(negedge tx);
        repeat (CPB / 2) @(posedge clk);       // середина старт-бита
        for (j = 0; j < 8; j = j + 1) begin
            repeat (CPB) @(posedge clk);
            b[j] = tx;
        end
        repeat (CPB) @(posedge clk);           // стоп-бит
        got[ngot] = b;
        ngot = ngot + 1;
    end

    task send_byte(input [7:0] v);
        integer k;
        begin
            rx = 1'b0; repeat (CPB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin rx = v[k]; repeat (CPB) @(posedge clk); end
            rx = 1'b1; repeat (CPB) @(posedge clk);
        end
    endtask

    integer i, errors = 0;
    reg [1023:0] vcd;

    initial begin
        if ($value$plusargs("vcd=%s", vcd)) begin
            $dumpfile(vcd);
            $dumpvars(0, tb_echo);
        end
        repeat (2) @(posedge clk);
        @(negedge clk) reset = 1'b0;
        repeat (20) @(posedge clk);

        // символы идут подряд, без пауз — как при вставке текста
        for (i = LEN - 1; i >= 0; i = i - 1) send_byte(send_str[i*8 +: 8]);

        i = 0;
        while (ngot < LEN && i < 20000) begin @(posedge clk); i = i + 1; end

        $write("отправлено: \"%0s\"\nполучено:   \"", send_str);
        for (i = 0; i < ngot; i = i + 1) $write("%c", got[i]);
        $display("\"");

        if (ngot != LEN) begin
            $display("FAIL: получено %0d байт из %0d", ngot, LEN); errors = errors + 1;
        end
        for (i = 0; i < LEN && i < ngot; i = i + 1)
            if (got[i] !== want_str[(LEN - 1 - i)*8 +: 8]) begin
                $display("FAIL байт %0d: '%c', ожидалось '%c'", i, got[i], want_str[(LEN-1-i)*8 +: 8]);
                errors = errors + 1;
            end
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
