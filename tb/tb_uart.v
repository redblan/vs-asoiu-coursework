// tb_uart.v — юнит-тест MMIO-устройства UART.
// 1. Тестбенч передаёт байты по линии rx (как ПК) — они должны
//    появиться в очереди и читаться через RX_DATA, STATUS[0] гаснет.
// 2. Запись в TX_DATA — байт должен уйти по линии tx в формате 8N1.
// 3. 17 байт без чтения — очередь переполняется, STATUS[2] = 1.
`timescale 1ns/1ps

module tb_uart;
    localparam CPB = 8;
    reg clk = 1'b0, reset = 1'b1;
    always #5 clk = ~clk;

    reg  [7:0]  addr = 8'h00;
    reg         re = 1'b0, we = 1'b0;
    reg  [15:0] wd = 16'h0000;
    wire [15:0] rd;
    reg         rx = 1'b1;
    wire        tx;

    dev_uart #(.BASE(8'h00), .CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .reset(reset), .addr(addr), .re(re), .we(we),
        .wd(wd), .rd(rd), .rx(rx), .tx(tx)
    );

    integer errors = 0, i;
    reg [7:0] got;

    task send_byte(input [7:0] b);
        integer j;
        begin
            rx = 1'b0; repeat (CPB) @(posedge clk);
            for (j = 0; j < 8; j = j + 1) begin rx = b[j]; repeat (CPB) @(posedge clk); end
            rx = 1'b1; repeat (CPB) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask

    task mmio_read(input [7:0] a, output [15:0] v);
        begin
            @(negedge clk); addr = a; re = 1'b1; #1 v = rd;
            @(negedge clk); re = 1'b0;
        end
    endtask

    reg [15:0] v;

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;

        // ---------- приём ----------
        send_byte("h"); send_byte("i");
        mmio_read(8'd1, v);
        if (v[0] !== 1'b1) begin $display("FAIL: STATUS.rx_valid = 0"); errors = errors + 1; end
        mmio_read(8'd0, v);
        if (v[7:0] !== "h") begin $display("FAIL: RX 1 = %h", v); errors = errors + 1; end
        mmio_read(8'd0, v);
        if (v[7:0] !== "i") begin $display("FAIL: RX 2 = %h", v); errors = errors + 1; end
        mmio_read(8'd1, v);
        if (v[0] !== 1'b0) begin $display("FAIL: очередь не пуста"); errors = errors + 1; end
        else $display("PASS приём: 'h', 'i', очередь пуста");

        // ---------- передача ----------
        @(negedge clk); addr = 8'd2; we = 1'b1; wd = 16'h0041;   // 'A'
        @(negedge clk); we = 1'b0;
        wait (tx == 1'b0);                       // старт-бит
        repeat (CPB / 2) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            repeat (CPB) @(posedge clk);
            got[i] = tx;
        end
        repeat (CPB) @(posedge clk);
        if (got !== 8'h41 || tx !== 1'b1) begin
            $display("FAIL передача: %h, стоп %b", got, tx); errors = errors + 1;
        end else $display("PASS передача: 'A' ушёл по линии tx");

        // ---------- переполнение ----------
        for (i = 0; i < 17; i = i + 1) send_byte(8'h30 + i);
        mmio_read(8'd1, v);
        if (v[2] !== 1'b1) begin $display("FAIL: нет флага переполнения"); errors = errors + 1; end
        mmio_read(8'd0, v);
        if (v[7:0] !== 8'h30) begin $display("FAIL: голова очереди %h", v); errors = errors + 1; end
        else $display("PASS переполнение: флаг поднят, первые 16 байт сохранены");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
