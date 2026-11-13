; isa_test.asm — самопроверяющийся тест всех команд и конфликтов конвейера.
; Каждый тест кладёт свой номер в R6 и сравнивает результат с эталоном.
; LBNE/LBEQ/LBLT — «длинные» переходы ассемблера: fail лежит дальше ±31.
; Итог в RAM[STATUS]: 0x600D — всё прошло, иначе номер упавшего теста.
; Тестбенч tb/tb_isa.v дополнительно проверяет RAM[0x10..] и видео-буфер.

        .equ STATUS, 0x1F         ; imm6 со знаком достаёт адреса 0..31
        .equ VIDEO,  0x8000

        .data
        .org 0x08
val:    .word 0x1234, 0x00F0, 0xFFFF
        .org 0x10
out:    .space 8

        .text
; ---------- 1. ADD/SUB и forwarding EX/MEM -> EX ----------
        ADDI R6, R0, 1
        ADDI R1, R0, 7
        ADDI R2, R1, 5          ; R1 только что вычислен -> forwarding из EX/MEM
        ADD  R3, R2, R1         ; 12 + 7 = 19, оба операнда из конвейера
        ADDI R4, R0, 19
        LBNE R3, R4, fail
        SUB  R3, R3, R1         ; 19 - 7 = 12
        LBNE R3, R2, fail

; ---------- 2. Логика ----------
        ADDI R6, R0, 2
        LI   R1, 0x0FF0
        LI   R2, 0x00FF
        AND  R3, R1, R2         ; 0x00F0
        LI   R4, 0x00F0
        LBNE R3, R4, fail
        OR   R3, R1, R2         ; 0x0FFF
        LI   R4, 0x0FFF
        LBNE R3, R4, fail
        XOR  R3, R1, R2         ; 0x0F0F
        LI   R4, 0x0F0F
        LBNE R3, R4, fail
        NOT  R3, R1             ; 0xF00F
        LI   R4, 0xF00F
        LBNE R3, R4, fail

; ---------- 3. Сдвиги ----------
        ADDI R6, R0, 3
        ADDI R1, R0, 1
        ADDI R2, R0, 15
        SHL  R3, R1, R2         ; 0x8000
        LI   R4, 0x8000
        LBNE R3, R4, fail
        SHR  R3, R3, R2         ; 0x0001
        LBNE R3, R1, fail

; ---------- 4. LUI / LLI ----------
        ADDI R6, R0, 4
        LUI  R1, 0xAB           ; 0xAB00
        LLI  R1, 0xCD           ; 0xABCD
        LI   R2, 0xABCD
        LBNE R1, R2, fail

; ---------- 5. LW, load-use stall, SW ----------
        ADDI R6, R0, 5
        LW   R1, val(R0)        ; 0x1234 (промах кэша)
        ADDI R2, R1, 1          ; load-use: конвейер обязан подождать
        LI   R3, 0x1235
        LBNE R2, R3, fail
        LW   R1, val+1(R0)      ; 0x00F0
        LW   R2, val+2(R0)      ; 0xFFFF
        ADD  R3, R1, R2         ; 0x00EF (перенос теряется)
        LI   R4, 0x00EF
        LBNE R3, R4, fail
        SW   R3, out(R0)        ; RAM[0x10] = 0x00EF
        LW   R5, out(R0)        ; читаем обратно
        LBNE R5, R4, fail
        SW   R5, val(R0)        ; запись в строку, которая уже в кэше
        LW   R1, val(R0)        ; попадание: должно вернуть новое значение
        LBNE R1, R4, fail

; ---------- 6. BLT со знаком, BEQ ----------
        ADDI R6, R0, 6
        ADDI R1, R0, -3
        ADDI R2, R0, 2
        LBLT R2, R1, fail       ; 2 < -3 — ложь
        BLT  R1, R2, blt_ok     ; -3 < 2 — истина
        JMP  fail
blt_ok: LBEQ R1, R2, fail

; ---------- 7. Сброс конвейера после перехода ----------
        ADDI R6, R0, 7
        ADDI R1, R0, 0
        B    skip
        ADDI R1, R1, 1          ; эти две команды уже в конвейере —
        ADDI R1, R1, 1          ; flush не даёт им выполниться
skip:   LBNE R1, R0, fail

; ---------- 8. CALL / RET (JAL / JR) ----------
        ADDI R6, R0, 8
        ADDI R1, R0, 5
        CALL double
        ADDI R2, R0, 10
        LBNE R1, R2, fail

; ---------- 9. FONT_RENDER ----------
        ADDI R6, R0, 9
        LI   R1, 'H'
        ADDI R2, R0, 0
        FONT_RENDER R3, R1, R2  ; левый столбец «H» — все 7 точек: 0x7F
        LI   R4, 0x7F
        LBNE R3, R4, fail
        LI   R1, 'h'            ; строчная сворачивается на «H»
        FONT_RENDER R5, R1, R2
        LBNE R5, R4, fail
        ADDI R2, R0, 5
        FONT_RENDER R3, R1, R2  ; 6-й столбец — пустой разделитель
        LBNE R3, R0, fail
        SW   R4, out+1(R0)      ; RAM[0x11] = 0x7F

; ---------- 10. Видео-буфер и защёлка кадра ----------
        ADDI R6, R0, 10
        LUI  R5, hi(VIDEO)      ; R5 = 0x8000
        ADDI R1, R0, 0x15
        SW   R1, 0(R5)          ; столбец 0
        SW   R4, 31(R5)         ; столбец 31
        LW   R2, 0(R5)
        LBNE R2, R1, fail
        ADDI R2, R5, 31
        SW   R0, 1(R2)          ; LATCH (0x8020): кадр на матрицы

; ---------- всё прошло ----------
        LI   R1, 0x600D
        SW   R1, STATUS(R0)
        HALT

fail:   SW   R6, STATUS(R0)
        HALT

double: ADD  R1, R1, R1
        RET
