; echo.asm — задание на «4»: Chat Terminal (Echo).
; Бесконечный цикл: ждать байт по UART -> строчную латинскую букву
; перевести в заглавную -> дождаться свободного передатчика -> отправить.
;
; Регистры:  R5 — база MMIO 0xFF00, R3 = 'a', R4 = 'z' + 1,
;            R6 = маска rx_valid, R7 = маска tx_ready

        .equ MMIO,    0xFF00
        .equ RX_DATA, 0         ; смещения регистров UART от базы
        .equ STATUS,  1
        .equ TX_DATA, 2

        .text
start:  LUI  R5, hi(MMIO)       ; R5 = 0xFF00
        LI   R3, 'a'
        LI   R4, 'z' + 1
        ADDI R6, R0, 1
        ADDI R7, R0, 2

wait_rx:
        LW   R1, STATUS(R5)
        AND  R2, R1, R6
        BEQZ R2, wait_rx        ; очередь пуста — ждём
        LW   R1, RX_DATA(R5)    ; забираем байт (чтение снимает его с очереди)

        BLT  R1, R3, wait_tx    ; меньше 'a' — без изменений
        BLT  R1, R4, upper      ; 'a'..'z' — перевести
        B    wait_tx
upper:  ADDI R1, R1, -32        ; 'a' - 'A' = 0x20

wait_tx:
        LW   R2, STATUS(R5)
        AND  R2, R2, R7
        BEQZ R2, wait_tx        ; передатчик занят
        SW   R1, TX_DATA(R5)
        B    wait_rx
