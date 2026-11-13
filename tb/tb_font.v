// tb_font.v — юнит-тест блока FONT_RENDER.
// Перебирает все коды 0..127 и столбцы 0..7 и сравнивает выход
// с эталонной моделью из tools/gen_font.py (+expect=build/font_expect.hex).
`timescale 1ns/1ps

module tb_font;
    reg  [15:0] ch, col;
    wire [15:0] y;
    font_render dut (.ch(ch), .col(col), .y(y));

    reg [7:0] expect_mem [0:1023];
    reg [1023:0] fname;
    integer c, k, errors = 0, checked = 0;

    initial begin
        if (!$value$plusargs("expect=%s", fname)) fname = "build/font_expect.hex";
        $readmemh(fname, expect_mem);
        for (c = 0; c < 128; c = c + 1)
            for (k = 0; k < 8; k = k + 1) begin
                ch = c; col = k;
                #1;
                checked = checked + 1;
                if (y !== {8'h00, expect_mem[c * 8 + k]}) begin
                    errors = errors + 1;
                    if (errors < 10)
                        $display("FAIL ch=0x%02h col=%0d: 0x%02h, ожидалось 0x%02h",
                                 c, k, y, expect_mem[c * 8 + k]);
                end
            end
        // код вне таблицы
        ch = 16'h1234; col = 0; #1;
        if (y !== 16'h0000) begin $display("FAIL ch=0x1234"); errors = errors + 1; end
        if (errors == 0) $display("ALL TESTS PASSED (%0d комбинаций)", checked);
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
