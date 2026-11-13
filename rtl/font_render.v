// font_render.v — аппаратный блок кастомной инструкции FONT_RENDER.
//
//   FONT_RENDER rd, rs1, rs2   ->   rd = { 8'h00, FONT_ROM[(rs1 - 0x20) * 6 + rs2] }
//
// rs1 — код ASCII, rs2 — номер столбца глифа (0..5). Результат — столбец
// из 8 пикселей (бит 0 — верхняя строка). Работает за один такт в стадии EX
// (комбинационно). Строчные буквы и 0x60..0x7E сворачиваются на 0x40..0x5E.
// Код вне 0x20..0x7E или столбец >= 6 дают пустой столбец.
//
// Программная замена этой команды — вычитание 0x20, умножение на 6
// (два сдвига и сложение), сложение со столбцом и базой таблицы, LW —
// около 7 команд и обращение к памяти данных.
module font_render (
    input  [15:0] ch,
    input  [15:0] col,
    output [15:0] y
);
    reg [7:0] rom [0:383];        // 64 глифа x 6 столбцов
`ifndef SYNTHESIS
    reg [1023:0] fname;
`endif
    integer i;

    initial begin
        for (i = 0; i < 384; i = i + 1) rom[i] = 8'h00;
`ifdef SYNTHESIS
        $readmemh("build/font.hex", rom);
`else
        if ($value$plusargs("font=%s", fname)) $readmemh(fname, rom);
        else $readmemh("build/font.hex", rom);
`endif
    end

    // свёртка строчных
    wire        lower  = (ch >= 16'h0060) && (ch <= 16'h007E);
    wire [15:0] code   = lower ? ch - 16'h0020 : ch;
    wire        ok     = (code >= 16'h0020) && (code <= 16'h005F) && (col < 16'd6);
    wire [5:0]  gi     = code[5:0] - 6'h20;          // номер глифа 0..63
    wire [8:0]  base   = {gi, 2'b00} + {1'b0, gi, 1'b0}; // gi * 6
    wire [8:0]  idx    = base + {6'b0, col[2:0]};

    assign y = ok ? {8'h00, rom[idx]} : 16'h0000;
endmodule
