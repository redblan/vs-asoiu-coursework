// dev_uart.v — MMIO-устройство UART с приёмной очередью на 16 байт.
//
//   смещение 0  RX_DATA  чтение: байт из головы очереди (чтение снимает его)
//   смещение 1  STATUS   чтение: бит 0 — в очереди есть байт,
//                                бит 1 — передатчик свободен,
//                                бит 2 — было переполнение очереди
//   смещение 2  TX_DATA  запись: отправить младший байт
//
// Устройство само проверяет, попал ли адрес в его окно (BASE..BASE+2).
// Вне окна rd = 0, поэтому выходы всех устройств объединяются по ИЛИ.
module dev_uart #(
    parameter [7:0] BASE = 8'h00,
    parameter CLKS_PER_BIT = 16
)(
    input         clk,
    input         reset,
    input  [7:0]  addr,      // смещение внутри области MMIO 0xFF00..0xFFFF
    input         re,
    input         we,
    /* verilator lint_off UNUSEDSIGNAL */
    input  [15:0] wd,        // передаётся младший байт
    /* verilator lint_on UNUSEDSIGNAL */
    output [15:0] rd,
    input         rx,        // последовательные линии
    output        tx
);
    wire       sel_rx   = (addr == BASE);
    wire       sel_st   = (addr == BASE + 8'd1);
    wire       sel_tx   = (addr == BASE + 8'd2);

    wire [7:0] rx_byte;
    wire       rx_valid;
    wire       tx_busy;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .reset(reset), .rx(rx), .data(rx_byte), .valid(rx_valid)
    );
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .reset(reset), .start(we && sel_tx), .data(wd[7:0]),
        .tx(tx), .busy(tx_busy)
    );

    // кольцевая очередь приёма
    reg [7:0] fifo [0:15];
    reg [3:0] head, tail;
    reg [4:0] count;
    reg       overrun;
    wire      empty = (count == 5'd0);
    wire      pop   = re && sel_rx && !empty;
    wire      push  = rx_valid && (count != 5'd16 || pop);

    always @(posedge clk) begin
        if (reset) begin
            head <= 4'd0; tail <= 4'd0; count <= 5'd0; overrun <= 1'b0;
        end else begin
            if (push) begin
                fifo[tail] <= rx_byte;
                tail <= tail + 4'd1;
            end
            if (rx_valid && !push) overrun <= 1'b1;
            if (pop) head <= head + 4'd1;
            count <= count + {4'd0, push} - {4'd0, pop};
        end
    end

    assign rd = sel_rx ? {8'h00, empty ? 8'h00 : fifo[head]} :
                sel_st ? {13'd0, overrun, !tx_busy, !empty} :
                16'h0000;
endmodule
