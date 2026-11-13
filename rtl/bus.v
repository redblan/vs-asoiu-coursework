// bus.v — шина данных и декодер адресов (стадия MEM).
//
//   0x0000..0x00FF  Data RAM через кэш   (кэшируется)
//   0x8000..0x801F  видео-буфер          (не кэшируется)
//   0xFF00..0xFFFF  MMIO-устройства      (не кэшируется)
//   прочие адреса   чтение 0, запись игнорируется
// Запись каждая область берёт сама: we && sel_*.
module bus (
    /* verilator lint_off UNUSEDSIGNAL */
    input  [15:0] addr,      // [4:0] декодеру не нужны
    /* verilator lint_on UNUSEDSIGNAL */
    input         re,
    // выбор областей
    output        sel_ram,
    output        sel_vram,
    output        sel_mmio,
    // данные, прочитанные из областей
    input  [15:0] ram_rd,
    input  [7:0]  vram_rd,
    input  [15:0] mmio_rd,
    output [15:0] rd
);
    assign sel_ram  = (addr[15:8] == 8'h00);
    assign sel_vram = (addr[15:5] == 11'b1000_0000_000);
    assign sel_mmio = (addr[15:8] == 8'hFF);

    assign rd = !re      ? 16'h0000 :
                sel_ram  ? ram_rd :
                sel_vram ? {8'h00, vram_rd} :
                sel_mmio ? mmio_rd :
                16'h0000;
endmodule
