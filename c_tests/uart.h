// ============================================================================
// File: uart.h
// Description: Bare-Metal Header for Feature 1 Memory-Mapped UART (115200 Baud)
// Address Map:
//   0x80000000 : UART_TX_DATA (Write: 8-bit character)
//   0x80000004 : UART_STATUS  (Read: Bit 0 = Busy, Bit 1 = Full, Bit 2 = Empty)
// ============================================================================

#ifndef UART_H
#define UART_H

#define UART_TX_REG    (*(volatile unsigned int *)0x80000000)
#define UART_STAT_REG  (*(volatile unsigned int *)0x80000004)

static inline __attribute__((always_inline)) void uart_putc(char c) {
    while (UART_STAT_REG & 0x01); // Wait until transmitter / FIFO ready
    UART_TX_REG = (unsigned int)(unsigned char)c;
}

static inline __attribute__((always_inline)) void uart_puts(const char *str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

static inline __attribute__((always_inline)) void uart_puthex(unsigned int val) {
    const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 7; i >= 0; i--) {
        uart_putc(hex[(val >> (i * 4)) & 0xF]);
    }
}

static inline __attribute__((always_inline)) void uart_putdec(int val) {
    if (val < 0) {
        uart_putc('-');
        val = -val;
    }
    if (val == 0) {
        uart_putc('0');
        return;
    }
    static const unsigned int p10[10] = {
        1000000000, 100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1
    };
    int started = 0;
    unsigned int uval = (unsigned int)val;
    for (int i = 0; i < 10; i++) {
        unsigned int p = p10[i];
        char digit = '0';
        while (uval >= p) {
            uval -= p;
            digit++;
        }
        if (digit != '0' || started || i == 9) {
            uart_putc(digit);
            started = 1;
        }
    }
}

#endif // UART_H
