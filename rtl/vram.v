// vram.v — видео-буфер: 32 столбца x 8 бит = 4 LED-матрицы 8x8.
// Столбец k (0..31) — адрес 0x8000 + k. Бит 0 — верхний светодиод.
// Весь кадр выведен наружу шиной frame (256 бит): мост читает его
// одним обращением и рисует окно.
module vram (
    input          clk,
    input          reset,
    input  [4:0]   addr,
    input          we,
    input  [7:0]   wd,
    output [7:0]   rd,
    output [255:0] frame
);
    reg [7:0] col [0:31];
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) col[i] <= 8'h00;
        end else if (we) begin
            col[addr] <= wd;
        end
    end

    assign rd = col[addr];

    genvar k;
    generate
        for (k = 0; k < 32; k = k + 1) begin : g_frame
            assign frame[k*8 +: 8] = col[k];
        end
    endgenerate
endmodule
