// alu.v — арифметико-логическое устройство, 16 бит.
// Комбинационное. Флаги: Z — результат 0, N — старший бит результата,
// C — перенос (ADD) или отсутствие заёма (SUB, как в ARM).
`include "isa.vh"

module alu (
    input  [15:0] a,
    input  [15:0] b,
    input  [3:0]  op,
    output reg [15:0] y,
    output        z,
    output        n,
    output reg    c
);
    wire [16:0] sum  = {1'b0, a} + {1'b0, b};
    wire [16:0] diff = {1'b0, a} + {1'b0, ~b} + 17'd1;

    always @(*) begin
        c = 1'b0;
        case (op)
            `ALU_ADD: begin y = sum[15:0];  c = sum[16];  end
            `ALU_SUB: begin y = diff[15:0]; c = diff[16]; end
            `ALU_AND: y = a & b;
            `ALU_OR : y = a | b;
            `ALU_XOR: y = a ^ b;
            `ALU_NOT: y = ~a;
            `ALU_SHL: y = a << b[3:0];
            `ALU_SHR: y = a >> b[3:0];
            `ALU_LUI: y = {b[7:0], 8'h00};
            `ALU_LLI: y = {a[15:8], b[7:0]};
            default : y = 16'h0000;
        endcase
    end

    assign z = (y == 16'h0000);
    assign n = y[15];
endmodule
