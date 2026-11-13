// dcache.v — кэш данных прямого отображения перед Data RAM.
//
// 16 строк по одному слову. Адрес RAM 8 бит: [3:0] — индекс строки,
// [7:4] — тег. Запись сквозная (write-through) без выделения строки:
// RAM обновляется всегда, строка — только при попадании.
// Промах чтения: конвейер стоит MISS_PENALTY тактов, имитируя медленную
// основную память, затем строка заполняется и данные выдаются.
// Счётчики hits/misses — для отчёта.
module dcache #(
    parameter MISS_PENALTY = 4
)(
    input         clk,
    input         reset,
    input  [7:0]  addr,
    input         re,
    input         we,
    input  [15:0] wd,
    output [15:0] rd,
    output        stall,
    // сторона основной памяти
    output [7:0]  ram_addr,
    output        ram_we,
    output [15:0] ram_wd,
    input  [15:0] ram_rd,
    // статистика
    output reg [31:0] hits,
    output reg [31:0] misses
);
    reg        valid [0:15];
    reg [3:0]  tag   [0:15];
    reg [15:0] data  [0:15];
    reg [3:0]  wait_cnt;
    integer i;

    wire [3:0] idx = addr[3:0];
    wire [3:0] tg  = addr[7:4];
    wire       hit = valid[idx] && tag[idx] == tg;

    assign stall    = re && !hit;
    assign rd       = data[idx];
    assign ram_addr = addr;
    assign ram_we   = we;
    assign ram_wd   = wd;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i]   <= 4'h0;
                data[i]  <= 16'h0000;
            end
            wait_cnt <= 4'd0;
            hits     <= 32'd0;
            misses   <= 32'd0;
        end else begin
            if (re && !hit) begin
                if (wait_cnt == MISS_PENALTY - 1) begin
                    valid[idx] <= 1'b1;          // строка заполняется
                    tag[idx]   <= tg;
                    data[idx]  <= ram_rd;
                    wait_cnt   <= 4'd0;
                    misses     <= misses + 32'd1;
                end else begin
                    wait_cnt <= wait_cnt + 4'd1;
                end
            end
            if (re && hit) hits <= hits + 32'd1;
            if (we && hit) data[idx] <= wd;      // write-through
        end
    end
endmodule
