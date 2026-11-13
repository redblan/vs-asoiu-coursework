; fib.asm — задание на «3»/«4»: N-е число Фибоначчи.
; Вход:  RAM[0x00] = N (0..24; F(24) = 46368 — последнее, что влезает в 16 бит)
; Выход: RAM[0x01] = F(N)
;
; Цикл крутится N раз: (a, b) <- (b, a + b). Ответ — a.
; Каждая команда тела цикла зависит от предыдущей (RAW), поэтому
; программа проверяет forwarding и load-use stall конвейера.

        .data
n:      .word 10            ; N, тестбенч может подменить RAM
result: .word 0

        .text
start:  LW   R1, n(R0)      ; R1 = N
        ADDI R2, R0, 0      ; R2 = a = F(0)
        ADDI R3, R0, 1      ; R3 = b = F(1)
loop:   BEQ  R1, R0, done   ; N == 0 -> готово
        ADD  R4, R2, R3     ; t = a + b
        ADD  R2, R3, R0     ; a = b
        ADD  R3, R4, R0     ; b = t
        ADDI R1, R1, -1     ; N = N - 1
        BEQ  R0, R0, loop
done:   SW   R2, result(R0) ; RAM[1] = a
        HALT
