/* ============================================================
   gpio.h  -  GPIO Driver
   Step 20 — Hello World

   Register Map  (base = 0x4000_0000)
     +0x00  DIR        R/W  [3:0] 1=output 0=input
     +0x04  DATA_OUT   R/W  [3:0] → gpio_led (masked by DIR)
     +0x08  DATA_IN    R    [7:0] {sw[3:0], btn[3:0]}
     +0x0C  CTRL       R/W  [0]=out_ie [1]=in_ie
     +0x10  IRQ_STATUS R/W1C[0]=out_event [1]=in_change
   ============================================================ */

#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

#define GPIO_BASE       0x40000000UL

#define GPIO_DIR        (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_DATA_OUT   (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_DATA_IN    (*(volatile uint32_t *)(GPIO_BASE + 0x08))
#define GPIO_CTRL       (*(volatile uint32_t *)(GPIO_BASE + 0x0C))
#define GPIO_IRQ_STATUS (*(volatile uint32_t *)(GPIO_BASE + 0x10))

/* Set all 4 LEDs as outputs and drive them */
static inline void gpio_set_leds(uint8_t pattern)
{
    GPIO_DIR      = 0xF;
    GPIO_DATA_OUT = pattern & 0xF;
}

/* Read buttons [3:0] */
static inline uint8_t gpio_read_btns(void)
{
    return (uint8_t)(GPIO_DATA_IN & 0xF);
}

/* Read switches [3:0] (upper nibble of DATA_IN) */
static inline uint8_t gpio_read_sw(void)
{
    return (uint8_t)((GPIO_DATA_IN >> 4) & 0xF);
}

#endif /* GPIO_H */
