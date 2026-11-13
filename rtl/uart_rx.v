// uart_rx.v — приёмник UART 8N1.
// Линия в покое 1. Старт-бит 0, 8 бит данных младшим вперёд, стоп-бит 1.
// Бит длится CLKS_PER_BIT тактов, отсчёт берётся в середине бита.
// По приёму байта на один такт выставляется valid.
module uart_rx #(
    parameter CLKS_PER_BIT = 16
)(
    input            clk,
    input            reset,
    input            rx,
    output reg [7:0] data,
    output reg       valid
);
    localparam IDLE = 2'd0, START = 2'd1, BITS = 2'd2, STOP = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bitn;
    reg [7:0]  shift;
    reg        rx_s1, rx_s;          // двойная синхронизация входа

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE; cnt <= 16'd0; bitn <= 3'd0; shift <= 8'h00;
            data <= 8'h00; valid <= 1'b0; rx_s1 <= 1'b1; rx_s <= 1'b1;
        end else begin
            rx_s1 <= rx;
            rx_s  <= rx_s1;
            valid <= 1'b0;
            case (state)
                IDLE: if (!rx_s) begin state <= START; cnt <= 16'd0; end
                START: begin
                    if (cnt == CLKS_PER_BIT / 2 - 1) begin
                        cnt <= 16'd0;
                        if (!rx_s) begin state <= BITS; bitn <= 3'd0; end
                        else state <= IDLE;            // ложный старт
                    end else cnt <= cnt + 16'd1;
                end
                BITS: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt   <= 16'd0;
                        shift <= {rx_s, shift[7:1]};
                        if (bitn == 3'd7) state <= STOP;
                        bitn  <= bitn + 3'd1;
                    end else cnt <= cnt + 16'd1;
                end
                STOP: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt   <= 16'd0;
                        state <= IDLE;
                        if (rx_s) begin data <= shift; valid <= 1'b1; end
                    end else cnt <= cnt + 16'd1;
                end
            endcase
        end
    end
endmodule
