; marquee.asm — задание на «5»: бегущая строка (Marquee).
;
; Текст хранится в RAM как «лента» символов: 6 пробелов (зазор между
; повторами) + сообщение. Лента крутится по кругу, на 4 матрицы 8x8
; (32 столбца) выводится окно, которое сдвигается на 1 пиксель за шаг.
;
; Игровой цикл (Game Loop):
;   1. ввод   — все байты из UART: печатные дописываются в ленту,
;               Backspace стирает последний, Enter очищает текст;
;               кнопки (по фронту): быстрее, медленнее, пауза
;   2. логика — по аппаратному таймеру окно сдвигается на 1 столбец
;   3. отрисовка — 32 столбца через FONT_RENDER в видео-буфер
;
; Регистры: R5 — база MMIO (0xFF00) на всю программу,
;           остальные — временные внутри каждого этапа.

        .equ MMIO,     0xFF00
        .equ RX_DATA,  0
        .equ STATUS,   1
        .equ BUTTONS,  3
        .equ TIMER,    4
        .equ VIDEO,    0x8000
        .equ TAPE,     0x20          ; начало ленты в RAM
        .equ TAPE_MAX, 0x100         ; конец RAM
        .equ PAD,      6             ; пробелов-зазоров в начале ленты
        .equ GLYPH_W,  6             ; столбцов на символ
        .equ COLS,     32            ; столбцов на экране
        .equ MAX_SPEED_TICKS, 64

; ---------------- переменные (адреса 0..31 доступны как imm(R0)) -------
        .data
end:    .word tape_end               ; адрес за последним символом ленты
sci:    .word TAPE                   ; адрес символа в левом столбце окна
scc:    .word 0                      ; номер столбца этого символа (0..5)
speed:  .word 4                      ; тиков таймера на один сдвиг
last_t: .word 0                      ; тик последнего сдвига
prev_b: .word 0                      ; кнопки на прошлом проходе
paused: .word 0

        .org TAPE
message: .string "      HELLO FROM IU5-51B SOC! TYPE HERE: "
tape_end:

; ---------------- программа ----------------
        .text
start:  LUI  R5, hi(MMIO)            ; R5 = 0xFF00

main:
; ======== 1. ввод: UART ========
rx_loop:
        LW   R1, STATUS(R5)
        ADDI R2, R0, 1
        AND  R1, R1, R2
        LBEQ R1, R0, rx_done         ; очередь пуста (длинный переход)
        LW   R1, RX_DATA(R5)

        ADDI R2, R0, 13              ; Enter -> очистить
        BEQ  R1, R2, do_clear
        ADDI R2, R0, 10
        BEQ  R1, R2, do_clear
        ADDI R2, R0, 8               ; Backspace -> стереть
        BEQ  R1, R2, do_bs
        LI   R2, 127
        BEQ  R1, R2, do_bs
        LI   R2, ' '                 ; прочие управляющие — пропустить
        BLT  R1, R2, rx_loop

        LW   R3, end(R0)             ; дописать символ, если есть место
        LI   R2, TAPE_MAX
        BLT  R3, R2, append
        JMP  rx_loop
append: SW   R1, 0(R3)
        ADDI R3, R3, 1
        SW   R3, end(R0)
        JMP  rx_loop

do_clear:
        LI   R3, TAPE + PAD
        SW   R3, end(R0)
        LI   R3, TAPE
        SW   R3, sci(R0)
        SW   R0, scc(R0)
        JMP  rx_loop

do_bs:  LW   R3, end(R0)
        LI   R2, TAPE + PAD
        LBEQ R3, R2, rx_loop         ; текста нет — стирать нечего
        ADDI R3, R3, -1
        SW   R3, end(R0)
        JMP  rx_loop
rx_done:

; ======== 1. ввод: кнопки (по фронту нажатия) ========
        LW   R1, BUTTONS(R5)
        LW   R2, prev_b(R0)
        SW   R1, prev_b(R0)
        NOT  R2, R2
        AND  R1, R1, R2              ; R1 = только что нажатые

        ADDI R2, R0, 1               ; бит 0 — быстрее: speed / 2, не меньше 1
        AND  R3, R1, R2
        BEQZ R3, no_fast
        LW   R4, speed(R0)
        SHR  R4, R4, R2
        BNEZ R4, fast_st
        ADDI R4, R0, 1
fast_st: SW  R4, speed(R0)
no_fast:
        ADDI R2, R0, 2               ; бит 1 — медленнее: speed * 2, не больше 64
        AND  R3, R1, R2
        BEQZ R3, no_slow
        LW   R4, speed(R0)
        ADDI R2, R0, 1
        SHL  R4, R4, R2
        LI   R2, MAX_SPEED_TICKS
        BLT  R4, R2, slow_st
        MOV  R4, R2
slow_st: SW  R4, speed(R0)
no_slow:
        ADDI R2, R0, 4               ; бит 2 — пауза
        AND  R3, R1, R2
        BEQZ R3, no_pause
        LW   R4, paused(R0)
        ADDI R2, R0, 1
        XOR  R4, R4, R2
        SW   R4, paused(R0)
no_pause:

; ======== 2. логика: сдвиг окна по таймеру ========
        LW   R1, TIMER(R5)
        LW   R4, paused(R0)
        BEQZ R4, run_t
        SW   R1, last_t(R0)          ; на паузе время «стоит»
        B    render
run_t:  LW   R2, last_t(R0)
        SUB  R3, R1, R2              ; прошло тиков (по модулю 2^16)
        LW   R4, speed(R0)
        BLT  R3, R4, render          ; рано
        SW   R1, last_t(R0)

        LW   R1, sci(R0)             ; окно на 1 столбец вправо по ленте
        LW   R2, scc(R0)
        ADDI R2, R2, 1
        ADDI R3, R0, GLYPH_W
        BNE  R2, R3, step_st
        ADDI R2, R0, 0
        ADDI R1, R1, 1
step_st:
        SW   R1, sci(R0)
        SW   R2, scc(R0)

; ======== 3. отрисовка: 32 столбца через FONT_RENDER ========
; R1 — адрес символа, R2 — столбец глифа, R3 — адрес в видео-буфере,
; R6 — конец ленты, R7 — сколько столбцов осталось
render:
        LW   R1, sci(R0)
        LW   R2, scc(R0)
        LW   R6, end(R0)
        BLT  R1, R6, r_start         ; после Backspace окно могло уйти за конец
        LI   R1, TAPE
        SW   R1, sci(R0)
r_start:
        LUI  R3, hi(VIDEO)           ; R3 = 0x8000
        LI   R7, COLS
col_loop:
        LW   R4, 0(R1)               ; код символа
        FONT_RENDER R4, R4, R2       ; столбец пикселей — одна команда
        SW   R4, 0(R3)
        ADDI R3, R3, 1
        ADDI R2, R2, 1
        ADDI R4, R0, GLYPH_W
        BNE  R2, R4, col_next
        ADDI R2, R0, 0               ; следующий символ ленты
        ADDI R1, R1, 1
        BLT  R1, R6, col_next
        LI   R1, TAPE                ; лента замкнута в кольцо
col_next:
        ADDI R7, R7, -1
        BNEZ R7, col_loop

        JMP  main
