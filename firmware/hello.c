/* ============================================================
   hello.c  -  Step 20: First Real Program on Arty A7
   ============================================================
   Demonstrates:
     • UART TX: "Hello from RV32IM SoC!" banner + build info
     • LED blink: binary counter on LD0-LD3
     • Button echo: pressing BTN prints which button
     • CSR: reads cycle counter and prints elapsed cycles
   ============================================================ */

#include "uart.h"
#include "gpio.h"

/* ── CSR helpers ─────────────────────────────────────────── */
static inline uint32_t csr_cycle(void)
{
    uint32_t v;
    asm volatile ("csrr %0, cycle" : "=r"(v));
    return v;
}

/* ── Simple busy-wait delay using cycle CSR ───────────────── */
static void delay_cycles(uint32_t cycles)
{
    uint32_t start = csr_cycle();
    while ((csr_cycle() - start) < cycles)
        ;
}

/* delay_ms: pass CLK_HZ so firmware works at any clock speed.
   For simulation compile with -DCLK_HZ=100000 (100 kHz equivalent)
   so 1ms = 100 cycles instead of 100,000 cycles.
   For real board compile with -DCLK_HZ=100000000 (100 MHz). */
#ifndef CLK_HZ
#define CLK_HZ 100000000UL
#endif

static void delay_ms(uint32_t ms)
{
    delay_cycles((uint32_t)((uint64_t)ms * CLK_HZ / 1000));
}

/* ── Print a banner line ──────────────────────────────────── */
static void print_banner(void)
{
    uart_puts("\r\n");
    uart_puts("========================================\r\n");
    uart_puts("  Hello from RV32IM SoC!\r\n");
    uart_puts("  Arty A7 (XC7A35T)  |  100 MHz\r\n");
    uart_puts("  ISA: RV32IM + CSRs + Traps\r\n");
    uart_puts("========================================\r\n");
    uart_puts("\r\n");

    uart_puts("Cycle counter: ");
    uart_putdec(csr_cycle());
    uart_puts(" cycles since reset\r\n\r\n");
}

/* ── Main ─────────────────────────────────────────────────── */
int main(void)
{
    /* Initialise: all LEDs as outputs, off */
    gpio_set_leds(0x0);

    /* Print startup banner */
    print_banner();
    uart_puts("LED binary counter running. Press BTN1-BTN3 to echo.\r\n\r\n");

    uint8_t  led_val   = 0;
    uint8_t  btn_prev  = 0;
    uint32_t loop      = 0;

    while (1) {
        /* ── LED binary counter: increment every ~250 ms ── */
        gpio_set_leds(led_val);
        delay_ms(250);
        led_val = (led_val + 1) & 0xF;

        /* ── Button edge detection ── */
        uint8_t btn_now = gpio_read_btns();
        uint8_t btn_edge = btn_now & ~btn_prev;  /* rising edge */
        if (btn_edge) {
            uart_puts("BTN pressed: ");
            for (int i = 0; i < 4; i++) {
                if (btn_edge & (1u << i)) {
                    uart_putc('0' + i);
                    uart_putc(' ');
                }
            }
            uart_puts("\r\n");
        }
        btn_prev = btn_now;

        /* ── Print status every 16 loops (~4 seconds) ── */
        loop++;
        if ((loop & 0xF) == 0) {
            uart_puts("[tick] cycle=");
            uart_putdec(csr_cycle());
            uart_puts("  LED=");
            uart_puthex(led_val);
            uart_puts("\r\n");
        }
    }

    return 0;  /* never reached */
}
