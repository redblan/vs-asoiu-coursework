// control.v — блок управления (декодер команды) стадии ID.
// Жёсткая логика: по opcode/funct формирует управляющие сигналы,
// номера читаемых регистров и непосредственный операнд.
`include "isa.vh"

module control (
    input  [15:0] instr,

    output reg [2:0]  ra1,       // номер регистра для порта A
    output reg [2:0]  ra2,       // номер регистра для порта B
    output reg        use_a,     // команда реально читает ra1
    output reg        use_b,     // команда реально читает ra2
    output reg [2:0]  wa,        // регистр-приёмник
    output reg        reg_we,
    output reg [15:0] imm,       // непосредственный операнд (уже расширен)
    output reg        b_imm,     // второй операнд АЛУ — imm
    output reg [3:0]  alu_op,
    output reg [1:0]  res_sel,   // RES_ALU / RES_PC1 / RES_FONT
    output reg        flags_we,  // обновить флаги Z, N, C
    output reg        mem_re,
    output reg        mem_we,
    output reg [2:0]  br,        // вид перехода
    output reg        halt,
    output reg        illegal
);
    wire [3:0] op    = instr[15:12];
    wire [2:0] f_rd  = instr[11:9];
    wire [2:0] f_rs1 = instr[8:6];
    wire [2:0] f_rs2 = instr[5:3];
    wire [2:0] funct = instr[2:0];
    wire [15:0] sext6 = {{10{instr[5]}}, instr[5:0]};
    wire [15:0] zext8 = {8'h00, instr[7:0]};
    wire [15:0] addr12 = {4'h0, instr[11:0]};

    always @(*) begin
        // значения по умолчанию — «пустая» команда
        ra1 = f_rs1;  ra2 = f_rs2;
        use_a = 1'b0; use_b = 1'b0;
        wa = f_rd;    reg_we = 1'b0;
        imm = sext6;  b_imm = 1'b0;
        alu_op = `ALU_ADD; res_sel = `RES_ALU; flags_we = 1'b0;
        mem_re = 1'b0; mem_we = 1'b0;
        br = `BR_NONE; halt = 1'b0; illegal = 1'b0;

        case (op)
            `OP_ALU: begin
                use_a = 1'b1; use_b = (funct != `F_NOT);
                reg_we = 1'b1; flags_we = 1'b1;
                alu_op = {1'b0, funct};       // funct совпадает с ALU_*
            end
            `OP_ADDI: begin
                use_a = 1'b1; b_imm = 1'b1; reg_we = 1'b1;
            end
            `OP_LW: begin
                use_a = 1'b1; b_imm = 1'b1; reg_we = 1'b1; mem_re = 1'b1;
            end
            `OP_SW: begin
                ra2 = f_rd;                   // сохраняемое значение
                use_a = 1'b1; use_b = 1'b1; b_imm = 1'b1; mem_we = 1'b1;
            end
            `OP_BEQ, `OP_BNE, `OP_BLT: begin
                ra1 = f_rd; ra2 = f_rs1;      // сравниваются rd и rs1
                use_a = 1'b1; use_b = 1'b1;
                alu_op = `ALU_SUB;
                br = (op == `OP_BEQ) ? `BR_BEQ :
                     (op == `OP_BNE) ? `BR_BNE : `BR_BLT;
            end
            `OP_JMP: begin
                imm = addr12; br = `BR_JMP;
            end
            `OP_JAL: begin
                imm = addr12; br = `BR_JMP;
                wa = 3'd7; reg_we = 1'b1; res_sel = `RES_PC1;
            end
            `OP_JR: begin
                use_a = 1'b1; br = `BR_JR;
            end
            `OP_LUI: begin
                imm = zext8; b_imm = 1'b1; reg_we = 1'b1; alu_op = `ALU_LUI;
            end
            `OP_LLI: begin
                ra1 = f_rd; use_a = 1'b1;     // старший байт берётся из rd
                imm = zext8; b_imm = 1'b1; reg_we = 1'b1; alu_op = `ALU_LLI;
            end
            `OP_FONT: begin
                use_a = 1'b1; use_b = 1'b1; reg_we = 1'b1; res_sel = `RES_FONT;
            end
            `OP_HALT: begin
                halt = 1'b1;
            end
            default: illegal = 1'b1;          // 0xD, 0xE — свободны
        endcase
    end
endmodule
