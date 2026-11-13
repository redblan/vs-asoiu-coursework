// imem.v — память команд (Instruction ROM), 1024 x 16 бит.
// Чтение комбинационное. Содержимое загружается из hex-файла:
//   +rom=<файл>   (плюс-аргумент симулятора)
module imem (
    input  [9:0]  addr,
    output [15:0] data
);
    reg [15:0] mem [0:1023];
`ifndef SYNTHESIS
    reg [1023:0] fname;
`endif
    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1) mem[i] = 16'hF000; // HALT
`ifdef SYNTHESIS
        $readmemh("build/marquee.rom.hex", mem);   // синтез: прошивка по умолчанию
`else
        if ($value$plusargs("rom=%s", fname)) $readmemh(fname, mem);
`endif
    end

    assign data = mem[addr];
endmodule
