// hazard.v — блок разрешения конфликтов конвейера (Hazard Unit).
//
// 1. Forwarding: операнд стадии EX берётся из EX/MEM или MEM/WB, если
//    более старая команда пишет тот же регистр (EX/MEM приоритетнее).
// 2. Load-use stall: команда в ID читает регистр, который загружает LW
//    в EX, — PC и IF/ID держатся, в ID/EX уходит пузырь (1 такт).
// 3. Flush: переход в EX выполнен — IF/ID и ID/EX сбрасываются.
// 4. Промах кэша: замораживается весь конвейер (mem_stall).
module hazard (
    // команда в ID
    input  [2:0] id_ra1,
    input  [2:0] id_ra2,
    input        id_use_a,
    input        id_use_b,
    // команда в EX
    input  [2:0] ex_ra1,
    input  [2:0] ex_ra2,
    input  [2:0] ex_wa,
    input        ex_reg_we,
    input        ex_mem_re,
    input        ex_taken,     // переход в EX выполнен
    // команда в MEM
    input  [2:0] mem_wa,
    input        mem_reg_we,
    // команда в WB
    input  [2:0] wb_wa,
    input        wb_reg_we,
    input        mem_stall,    // промах кэша данных

    output [1:0] fwd_a,        // 0 — регистр, 1 — EX/MEM, 2 — MEM/WB
    output [1:0] fwd_b,
    output       load_use,
    output       stall_front,  // держать PC и IF/ID
    output       bubble_ex,    // записать пузырь в ID/EX
    output       flush_id,     // сбросить IF/ID
    output       freeze        // заморозить весь конвейер
);
    // Явные выражения, а не функция: continuous assign с функцией,
    // читающей сигналы модуля, в Icarus не пересчитывается при их смене.
    wire a_mem = ex_ra1 != 3'd0 && mem_reg_we && mem_wa == ex_ra1;
    wire a_wb  = ex_ra1 != 3'd0 && wb_reg_we  && wb_wa  == ex_ra1;
    wire b_mem = ex_ra2 != 3'd0 && mem_reg_we && mem_wa == ex_ra2;
    wire b_wb  = ex_ra2 != 3'd0 && wb_reg_we  && wb_wa  == ex_ra2;

    assign fwd_a = a_mem ? 2'd1 : a_wb ? 2'd2 : 2'd0;
    assign fwd_b = b_mem ? 2'd1 : b_wb ? 2'd2 : 2'd0;

    assign load_use = ex_mem_re && ex_reg_we && ex_wa != 3'd0 &&
                      ((id_use_a && id_ra1 == ex_wa) ||
                       (id_use_b && id_ra2 == ex_wa));

    assign freeze      = mem_stall;
    assign flush_id    = !freeze && ex_taken;
    assign bubble_ex   = !freeze && (ex_taken || load_use);
    assign stall_front = !freeze && !ex_taken && load_use;
endmodule
