// vram.v — видео-буфер с защёлкой кадра: 32 столбца x 8 бит = 4 LED-матрицы 8x8.
//
//   0x8000 + k   столбец k (0..31) теневого буфера; бит 0 — верхний светодиод
//   0x8020       LATCH: запись любого значения выводит теневой буфер на
//                светодиоды целиком за один такт (как RCLK у 74HC595)
//
// Программа рисует кадр в теневой буфер 32 записями, а на матрицах он
// появляется атомарно. Без защёлки экран, прочитанный посреди отрисовки,
// наполовину новый и наполовину старый — буквы «рвутся».
module vram (
    input              clk,
    input              reset,
    input  [5:0]       addr,
    input              we,
    input  [7:0]       wd,
    output [7:0]       rd,
    output reg [255:0] frame,         // то, что горит на матрицах
    output reg [31:0]  frame_count    // сколько кадров выведено
);
    reg  [7:0]   col [0:31];          // теневой буфер
    wire [255:0] shadow;
    wire         latch = we && addr[5];
    integer i;

    genvar k;
    generate
        for (k = 0; k < 32; k = k + 1) begin : g_shadow
            assign shadow[k*8 +: 8] = col[k];
        end
    endgenerate

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) col[i] <= 8'h00;
            frame       <= 256'd0;
            frame_count <= 32'd0;
        end else if (latch) begin
            frame       <= shadow;
            frame_count <= frame_count + 32'd1;
        end else if (we) begin
            col[addr[4:0]] <= wd;
        end
    end

    assign rd = addr[5] ? 8'h00 : col[addr[4:0]];
endmodule
