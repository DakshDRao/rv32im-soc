/* ============================================================
   uart.h  -  UART Driver  (polling, no interrupts)
   Step 20 — Hello World

   Register Map  (base = 0x4000_1000)
     +0x00  TXDATA   W    write byte → start TX
     +0x04  RXDATA   R    read received byte (clears rx_ready)
     +0x08  STATUS   R    [0]=tx_busy [1]=rx_ready [2]=rx_overrun
     +0x0C  CTRL     R/W  [0]=rx_ie   [1]=tx_ie
   ============================================================ */

#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART_BASE       0x40001000UL

#define UART_TXDATA     (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_RXDATA     (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STATUS     (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_CTRL       (*(volatile uint32_t *)(UART_BASE + 0x0C))

#define UART_TX_BUSY    (1u << 0)
#define UART_RX_READY   (1u << 1)

/* Block until TX is free, then send one byte */
static inline void uart_putc(char c)
{
    while (UART_STATUS & UART_TX_BUSY)
        ;
    UART_TXDATA = (uint32_t)(unsigned char)c;
}

/* Poll for a received byte; returns -1 if none ready */
static inline int uart_getc(void)
{
    if (!(UART_STATUS & UART_RX_READY))
        return -1;
    return (int)(UART_RXDATA & 0xFF);
}

/* Block until a byte arrives */
static inline char uart_getc_blocking(void)
{
    int c;
    do { c = uart_getc(); } while (c < 0);
    return (char)c;
}

/* Print a null-terminated string */
static inline void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* Print a 32-bit hex value with 0x prefix */
static inline void uart_puthex(uint32_t v)
{
    const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(v >> i) & 0xF]);
}

/* Print decimal unsigned */
static inline void uart_putdec(uint32_t v)
{
    char buf[11];
    int  i = 10;
    buf[10] = '\0';
    if (v == 0) { uart_putc('0'); return; }
    while (v && i > 0) {
        buf[--i] = '0' + (v % 10);
        v /= 10;
    }
    uart_puts(&buf[i]);
}

#endif /* UART_H */
