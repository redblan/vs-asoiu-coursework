// regfile.v — регистровый файл 8 x 16 бит.
// R0 всегда читается как 0, запись в него игнорируется.
// Запись синхронная, чтение комбинационное. Если в том же такте
// стадия WB пишет читаемый регистр, на выход сразу идёт новое значение
// (сквозная запись) — так снимается конфликт WB -> ID.
module regfile (
    input         clk,
    input         reset,        // синхронный сброс всех регистров в 0
    input  [2:0]  ra1,
    input  [2:0]  ra2,
    output [15:0] rd1,
    output [15:0] rd2,
    input         we,
    input  [2:0]  wa,
    input  [15:0] wd
);
    reg [15:0] r [1:7];
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 1; i < 8; i = i + 1) r[i] <= 16'h0000;
        end else if (we && wa != 3'd0) begin
            r[wa] <= wd;
        end
    end

    // копии регистров для временных диаграмм: массивы в VCD не попадают
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] dbg_r1 = r[1], dbg_r2 = r[2], dbg_r3 = r[3], dbg_r4 = r[4];
    wire [15:0] dbg_r5 = r[5], dbg_r6 = r[6], dbg_r7 = r[7];
    /* verilator lint_on UNUSEDSIGNAL */

    assign rd1 = (ra1 == 3'd0)          ? 16'h0000 :
                 (we && wa == ra1)      ? wd : r[ra1];
    assign rd2 = (ra2 == 3'd0)          ? 16'h0000 :
                 (we && wa == ra2)      ? wd : r[ra2];
endmodule
