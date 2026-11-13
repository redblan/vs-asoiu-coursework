// dram.v — основная память данных (Data RAM), 256 x 16 бит.
// Запись синхронная, чтение комбинационное.
// Начальное содержимое: плюс-аргумент +ram=<файл>.
module dram (
    input         clk,
    input  [7:0]  addr,
    input         we,
    input  [15:0] wd,
    output [15:0] rd
);
    reg [15:0] mem [0:255];
`ifndef SYNTHESIS
    reg [1023:0] fname;
`endif
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) mem[i] = 16'h0000;
`ifdef SYNTHESIS
        $readmemh("build/marquee.ram.hex", mem);
`else
        if ($value$plusargs("ram=%s", fname)) $readmemh(fname, mem);
`endif
    end

    always @(posedge clk)
        if (we) mem[addr] <= wd;

    assign rd = mem[addr];
endmodule
