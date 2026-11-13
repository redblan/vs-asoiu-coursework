// uart_tx.v — передатчик UART 8N1.
// По start (один такт) защёлкивает байт и выдвигает 10 бит:
// старт 0, 8 бит данных младшим вперёд, стоп 1. busy = 1 во время передачи.
module uart_tx #(
    parameter CLKS_PER_BIT = 16
)(
    input        clk,
    input        reset,
    input        start,
    input  [7:0] data,
    output       tx,
    output       busy
);
    reg [9:0]  shift;
    reg [3:0]  left;      // сколько бит осталось выдвинуть
    reg [15:0] cnt;

    assign tx   = (left == 4'd0) ? 1'b1 : shift[0];
    assign busy = (left != 4'd0);

    always @(posedge clk) begin
        if (reset) begin
            shift <= 10'h3FF; left <= 4'd0; cnt <= 16'd0;
        end else if (left == 4'd0) begin
            if (start) begin
                shift <= {1'b1, data, 1'b0};
                left  <= 4'd10;
                cnt   <= 16'd0;
            end
        end else if (cnt == CLKS_PER_BIT - 1) begin
            cnt   <= 16'd0;
            shift <= {1'b1, shift[9:1]};
            left  <= left - 4'd1;
        end else begin
            cnt <= cnt + 16'd1;
        end
    end
endmodule
