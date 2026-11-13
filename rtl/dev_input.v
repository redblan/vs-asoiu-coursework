// dev_input.v — MMIO-устройство кнопок и таймера кадров.
//
//   смещение 0  BUTTONS  чтение: бит 0 — «быстрее», бит 1 — «медленнее»,
//                                бит 2 — «пауза» (1 — кнопка нажата)
//   смещение 1  TIMER    чтение: счётчик тиков; тик — TICK_DIV тактов
//
// Таймер нужен, чтобы скорость бегущей строки не зависела от того,
// сколько команд выполнила программа за кадр.
module dev_input #(
    parameter [7:0] BASE = 8'h03,
    parameter TICK_DIV = 512
)(
    input         clk,
    input         reset,
    input  [7:0]  addr,
    output [15:0] rd,
    input  [2:0]  buttons
);
    reg [15:0] div;
    reg [15:0] ticks;
    reg [2:0]  btn_s;    // кнопки синхронизированы с тактом

    always @(posedge clk) begin
        if (reset) begin
            div <= 16'd0; ticks <= 16'd0; btn_s <= 3'b000;
        end else begin
            btn_s <= buttons;
            if (div == TICK_DIV - 1) begin
                div   <= 16'd0;
                ticks <= ticks + 16'd1;
            end else begin
                div <= div + 16'd1;
            end
        end
    end

    assign rd = (addr == BASE)         ? {13'd0, btn_s} :
                (addr == BASE + 8'd1)  ? ticks :
                16'h0000;
endmodule
