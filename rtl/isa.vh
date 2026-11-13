// isa.vh — коды операций и функций 16-битной ISA.
// Подробное описание: docs/ISA.md
//
// Форматы команды (16 бит):
//   R: [15:12] op | [11:9] rd | [8:6] rs1 | [5:3] rs2 | [2:0] funct
//   I: [15:12] op | [11:9] rd | [8:6] rs1 | [5:0] imm6 (со знаком)
//   U: [15:12] op | [11:9] rd | [8]  0    | [7:0] imm8
//   J: [15:12] op | [11:0] addr12

`ifndef ISA_VH
`define ISA_VH

// ---------- коды операций ----------
`define OP_ALU   4'h0   // R: rd = rs1 <funct> rs2
`define OP_ADDI  4'h1   // I: rd = rs1 + sext(imm6)
`define OP_LW    4'h2   // I: rd = MEM[rs1 + sext(imm6)]
`define OP_SW    4'h3   // I: MEM[rs1 + sext(imm6)] = rd
`define OP_BEQ   4'h4   // I: if (rd == rs1) PC = PC + 1 + sext(imm6)
`define OP_BNE   4'h5   // I: if (rd != rs1) PC = PC + 1 + sext(imm6)
`define OP_BLT   4'h6   // I: if (rd <  rs1) PC = PC + 1 + sext(imm6), со знаком
`define OP_JMP   4'h7   // J: PC = addr12
`define OP_JAL   4'h8   // J: R7 = PC + 1; PC = addr12
`define OP_JR    4'h9   // I: PC = rs1
`define OP_LUI   4'hA   // U: rd = imm8 << 8
`define OP_LLI   4'hB   // U: rd = (rd & 0xFF00) | imm8
`define OP_FONT  4'hC   // R: rd = FONT_ROM[rs1 (ASCII)][rs2 (столбец)] — кастомная
`define OP_HALT  4'hF   // J: остановка процессора

// ---------- поле funct для OP_ALU ----------
`define F_ADD    3'd0
`define F_SUB    3'd1
`define F_AND    3'd2
`define F_OR     3'd3
`define F_XOR    3'd4
`define F_NOT    3'd5   // rd = ~rs1
`define F_SHL    3'd6   // rd = rs1 << rs2[3:0]
`define F_SHR    3'd7   // rd = rs1 >> rs2[3:0] (логический)

// ---------- внутренние операции АЛУ ----------
`define ALU_ADD  4'd0
`define ALU_SUB  4'd1
`define ALU_AND  4'd2
`define ALU_OR   4'd3
`define ALU_XOR  4'd4
`define ALU_NOT  4'd5
`define ALU_SHL  4'd6
`define ALU_SHR  4'd7
`define ALU_LUI  4'd8   // B << 8
`define ALU_LLI  4'd9   // {A[15:8], B[7:0]}

// ---------- источник результата стадии EX ----------
`define RES_ALU  2'd0
`define RES_PC1  2'd1   // PC + 1 (адрес возврата JAL)
`define RES_FONT 2'd2   // FONT_RENDER

// ---------- вид перехода ----------
`define BR_NONE  3'd0
`define BR_BEQ   3'd1
`define BR_BNE   3'd2
`define BR_BLT   3'd3
`define BR_JMP   3'd4   // JMP и JAL: адрес из команды
`define BR_JR    3'd5   // адрес из регистра

`endif
