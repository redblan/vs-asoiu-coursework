// cpu_core.v — 16-битное RISC-ядро с 5-стадийным конвейером.
//
//   IF  — выборка команды из ROM по PC
//   ID  — декодирование (control), чтение регистров, обнаружение load-use
//   EX  — АЛУ, FONT_RENDER, сравнение и вычисление адреса перехода
//   MEM — обращение к шине данных (кэш RAM, видео-буфер, MMIO)
//   WB  — запись результата в регистровый файл
//
// Переходы решаются в EX: при выполненном переходе две младшие команды
// (в IF/ID и ID/EX) сбрасываются. Конфликты данных снимаются forwarding'ом
// и одним тактом простоя для load-use (см. hazard.v).
`include "isa.vh"

module cpu_core (
    input         clk,
    input         reset,
    // память команд
    output [9:0]  imem_addr,
    input  [15:0] imem_data,
    // шина данных
    output [15:0] dmem_addr,
    output        dmem_re,
    output        dmem_we,
    output [15:0] dmem_wd,
    input  [15:0] dmem_rd,
    input         dmem_stall,
    // состояние
    output reg        halted,
    output [9:0]      dbg_pc,
    output [2:0]      dbg_flags,     // {Z, N, C}
    output reg [31:0] dbg_retired,   // выполнено команд
    output reg [31:0] dbg_cycles
);
    // =====================================================================
    // Сигналы управления конвейером
    // =====================================================================
    wire [1:0] fwd_a, fwd_b;
    /* verilator lint_off UNUSEDSIGNAL */
    wire       load_use;            // для временных диаграмм
    /* verilator lint_on UNUSEDSIGNAL */
    wire       stall_front, bubble_ex, flush_id, freeze;
    wire       run = !freeze && !halted;

    // =====================================================================
    // IF
    // =====================================================================
    reg  [9:0] pc;
    reg        fetch_stop;          // после HALT новые команды не выбираются
    assign imem_addr = pc;
    assign dbg_pc    = pc;

    // IF/ID
    reg [15:0] ifid_instr;
    reg [9:0]  ifid_pc;
    reg        ifid_v;

    // =====================================================================
    // ID
    // =====================================================================
    wire [2:0]  c_ra1, c_ra2, c_wa;
    wire        c_use_a, c_use_b, c_reg_we, c_b_imm, c_flags_we;
    wire        c_mem_re, c_mem_we, c_halt, c_illegal;
    wire [15:0] c_imm;
    wire [3:0]  c_alu_op;
    wire [1:0]  c_res_sel;
    wire [2:0]  c_br;

    control u_ctrl (
        .instr(ifid_instr),
        .ra1(c_ra1), .ra2(c_ra2), .use_a(c_use_a), .use_b(c_use_b),
        .wa(c_wa), .reg_we(c_reg_we), .imm(c_imm), .b_imm(c_b_imm),
        .alu_op(c_alu_op), .res_sel(c_res_sel), .flags_we(c_flags_we),
        .mem_re(c_mem_re), .mem_we(c_mem_we), .br(c_br),
        .halt(c_halt), .illegal(c_illegal)
    );

    wire [15:0] rf_rd1, rf_rd2;
    wire        wb_we;
    wire [2:0]  wb_wa;
    wire [15:0] wb_wd;

    regfile u_rf (
        .clk(clk), .reset(reset),
        .ra1(c_ra1), .ra2(c_ra2), .rd1(rf_rd1), .rd2(rf_rd2),
        .we(wb_we), .wa(wb_wa), .wd(wb_wd)
    );

    wire id_halt = ifid_v && (c_halt || c_illegal);

    // ID/EX
    reg        idex_v;
    reg [9:0]  idex_pc;
    reg [15:0] idex_rd1, idex_rd2, idex_imm;
    reg [2:0]  idex_ra1, idex_ra2, idex_wa, idex_br;
    reg        idex_reg_we, idex_b_imm, idex_flags_we;
    reg        idex_mem_re, idex_mem_we, idex_halt;
    reg [3:0]  idex_alu_op;
    reg [1:0]  idex_res_sel;

    // =====================================================================
    // EX
    // =====================================================================
    reg  [15:0] exmem_res;
    wire [15:0] ex_a = (fwd_a == 2'd1) ? exmem_res :
                       (fwd_a == 2'd2) ? wb_wd     : idex_rd1;
    wire [15:0] ex_b = (fwd_b == 2'd1) ? exmem_res :
                       (fwd_b == 2'd2) ? wb_wd     : idex_rd2;
    wire [15:0] alu_b = idex_b_imm ? idex_imm : ex_b;

    wire [15:0] alu_y;
    wire        alu_z, alu_n, alu_c;
    alu u_alu (
        .a(ex_a), .b(alu_b), .op(idex_alu_op),
        .y(alu_y), .z(alu_z), .n(alu_n), .c(alu_c)
    );

    wire [15:0] font_y;
    font_render u_font (.ch(ex_a), .col(ex_b), .y(font_y));

    wire        eq = (ex_a == ex_b);
    wire        lt = ($signed(ex_a) < $signed(ex_b));
    wire [9:0]  pc1 = idex_pc + 10'd1;

    wire ex_taken = idex_v && (
        (idex_br == `BR_BEQ &&  eq) ||
        (idex_br == `BR_BNE && !eq) ||
        (idex_br == `BR_BLT &&  lt) ||
        (idex_br == `BR_JMP) ||
        (idex_br == `BR_JR));

    wire [9:0] ex_target = (idex_br == `BR_JMP) ? idex_imm[9:0] :
                           (idex_br == `BR_JR)  ? ex_a[9:0] :
                           pc1 + idex_imm[9:0];

    wire [15:0] ex_res = (idex_res_sel == `RES_PC1)  ? {6'd0, pc1} :
                         (idex_res_sel == `RES_FONT) ? font_y : alu_y;

    reg flag_z, flag_n, flag_c;
    assign dbg_flags = {flag_z, flag_n, flag_c};

    // EX/MEM
    reg        exmem_v;
    reg [15:0] exmem_sd;            // данные для записи в память
    reg [2:0]  exmem_wa;
    reg        exmem_reg_we, exmem_mem_re, exmem_mem_we, exmem_halt;

    // =====================================================================
    // MEM
    // =====================================================================
    assign dmem_addr = exmem_res;
    assign dmem_re   = exmem_v && exmem_mem_re;
    assign dmem_we   = exmem_v && exmem_mem_we && !halted;
    assign dmem_wd   = exmem_sd;
    wire [15:0] mem_val = exmem_mem_re ? dmem_rd : exmem_res;

    // MEM/WB
    reg        memwb_v;
    reg [15:0] memwb_wd;
    reg [2:0]  memwb_wa;
    reg        memwb_reg_we, memwb_halt;

    // =====================================================================
    // WB
    // =====================================================================
    assign wb_we = memwb_v && memwb_reg_we;
    assign wb_wa = memwb_wa;
    assign wb_wd = memwb_wd;

    // =====================================================================
    // Hazard Unit
    // =====================================================================
    hazard u_hz (
        .id_ra1(c_ra1), .id_ra2(c_ra2),
        .id_use_a(ifid_v && c_use_a), .id_use_b(ifid_v && c_use_b),
        .ex_ra1(idex_ra1), .ex_ra2(idex_ra2), .ex_wa(idex_wa),
        .ex_reg_we(idex_v && idex_reg_we), .ex_mem_re(idex_v && idex_mem_re),
        .ex_taken(ex_taken),
        .mem_wa(exmem_wa), .mem_reg_we(exmem_v && exmem_reg_we),
        .wb_wa(memwb_wa),  .wb_reg_we(memwb_v && memwb_reg_we),
        .mem_stall(dmem_stall),
        .fwd_a(fwd_a), .fwd_b(fwd_b), .load_use(load_use),
        .stall_front(stall_front), .bubble_ex(bubble_ex),
        .flush_id(flush_id), .freeze(freeze)
    );

    // =====================================================================
    // Регистры конвейера
    // =====================================================================
    always @(posedge clk) begin
        if (reset) begin
            pc <= 10'd0; fetch_stop <= 1'b0;
            ifid_v <= 1'b0; ifid_instr <= 16'h0000; ifid_pc <= 10'd0;
            idex_v <= 1'b0; exmem_v <= 1'b0; memwb_v <= 1'b0;
            idex_pc <= 10'd0; idex_rd1 <= 16'd0; idex_rd2 <= 16'd0;
            idex_imm <= 16'd0; idex_ra1 <= 3'd0; idex_ra2 <= 3'd0;
            idex_wa <= 3'd0; idex_br <= `BR_NONE; idex_reg_we <= 1'b0;
            idex_b_imm <= 1'b0; idex_flags_we <= 1'b0; idex_mem_re <= 1'b0;
            idex_mem_we <= 1'b0; idex_halt <= 1'b0; idex_alu_op <= `ALU_ADD;
            idex_res_sel <= `RES_ALU;
            exmem_res <= 16'd0; exmem_sd <= 16'd0; exmem_wa <= 3'd0;
            exmem_reg_we <= 1'b0; exmem_mem_re <= 1'b0; exmem_mem_we <= 1'b0;
            exmem_halt <= 1'b0;
            memwb_wd <= 16'd0; memwb_wa <= 3'd0; memwb_reg_we <= 1'b0;
            memwb_halt <= 1'b0;
            flag_z <= 1'b0; flag_n <= 1'b0; flag_c <= 1'b0;
            halted <= 1'b0; dbg_retired <= 32'd0; dbg_cycles <= 32'd0;
        end else begin
            if (!halted) dbg_cycles <= dbg_cycles + 32'd1;

            if (run) begin
                // ---------- PC и IF/ID ----------
                if (flush_id) begin
                    pc     <= ex_target;
                    ifid_v <= 1'b0;
                end else if (stall_front) begin
                    // держим PC и IF/ID
                end else if (fetch_stop || id_halt) begin
                    ifid_v <= 1'b0;                 // дальше HALT не выбираем
                    if (id_halt) fetch_stop <= 1'b1;
                end else begin
                    ifid_instr <= imem_data;
                    ifid_pc    <= pc;
                    ifid_v     <= 1'b1;
                    pc         <= pc + 10'd1;
                end

                // ---------- ID/EX ----------
                if (bubble_ex) begin
                    idex_v <= 1'b0;
                end else begin
                    idex_v        <= ifid_v;
                    idex_pc       <= ifid_pc;
                    idex_rd1      <= rf_rd1;
                    idex_rd2      <= rf_rd2;
                    idex_imm      <= c_imm;
                    idex_ra1      <= c_ra1;
                    idex_ra2      <= c_ra2;
                    idex_wa       <= c_wa;
                    idex_br       <= c_br;
                    idex_reg_we   <= c_reg_we;
                    idex_b_imm    <= c_b_imm;
                    idex_flags_we <= c_flags_we;
                    idex_mem_re   <= c_mem_re;
                    idex_mem_we   <= c_mem_we;
                    idex_halt     <= c_halt || c_illegal;
                    idex_alu_op   <= c_alu_op;
                    idex_res_sel  <= c_res_sel;
                end

                // ---------- флаги ----------
                if (idex_v && idex_flags_we) begin
                    flag_z <= alu_z; flag_n <= alu_n; flag_c <= alu_c;
                end

                // ---------- EX/MEM ----------
                exmem_v      <= idex_v;
                exmem_res    <= ex_res;
                exmem_sd     <= ex_b;
                exmem_wa     <= idex_wa;
                exmem_reg_we <= idex_reg_we;
                exmem_mem_re <= idex_mem_re;
                exmem_mem_we <= idex_mem_we;
                exmem_halt   <= idex_halt;

                // ---------- MEM/WB ----------
                memwb_v      <= exmem_v;
                memwb_wd     <= mem_val;
                memwb_wa     <= exmem_wa;
                memwb_reg_we <= exmem_reg_we;
                memwb_halt   <= exmem_halt;
                if (exmem_v) dbg_retired <= dbg_retired + 32'd1;

                // ---------- останов ----------
                if (memwb_v && memwb_halt) halted <= 1'b1;
            end
        end
    end
endmodule
