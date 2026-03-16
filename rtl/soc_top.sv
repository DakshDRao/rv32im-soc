// ============================================================
//  soc_top.sv  -  RV32IM SoC Top Level
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7  XC7A35T)
//  Step    : 18 - CSRs + Trap Handling (final Phase 2 top)
//
//  Hierarchy
//  ─────────────────────────────────────────────────────────
//  soc_top
//    ├─ riscv_core  (Steps 10/12/14/18 - core + CSR + dbus)
//    ├─ bus_fabric  (Step 14 - address decode + rdata mux)
//    ├─ dmem        (Step  8 - data BRAM, 0x2000_0000)
//    ├─ gpio        (Step 16 - 0x4000_0000)
//    ├─ uart        (Step 15 - 0x4000_1000)
//    └─ timer       (Step 17 - 0x4000_2000)
//
//  IRQ routing:
//    timer.irq → core.timer_irq → csr_regs (mip.MTIP)
//    uart.irq  → core.uart_irq  → csr_regs (mip.MEIP)
//    gpio.irq  → core.gpio_irq  → csr_regs (mip.MEIP)
//
//  Note: CSR slot at 0x4000_3000 returns 0 (CSRs are accessed
//  via CSRRW/CSRRS/etc instructions, not memory-mapped reads).
// ============================================================

module soc_top #(
    parameter int          IMEM_DEPTH = 16384,
    parameter int          DMEM_DEPTH = 16384,
    parameter logic [31:0] BOOT_ADDR  = 32'h0000_0000,
    parameter string       IMEM_FILE  = "",
    parameter int          CLK_FREQ   = 100_000_000,  // override for sim
    parameter int          BAUD_RATE  = 115_200        // override for sim
)(
    input  logic        clk,
    input  logic        rst_n,         // active-low reset (board button)

    // ── UART ──────────────────────────────────────────────────
    output logic        uart_tx,
    input  logic        uart_rx,

    // ── GPIO ──────────────────────────────────────────────────
    output logic [3:0]  gpio_led,
    input  logic [3:0]  gpio_btn,
    input  logic [3:0]  gpio_sw
);

// ─────────────────────────────────────────────────────────────
//  Reset Synchroniser  (active-low → active-high, 2-FF)
// ─────────────────────────────────────────────────────────────
logic rst_sync_r, rst;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) {rst, rst_sync_r} <= 2'b11;
    else        {rst, rst_sync_r} <= {rst_sync_r, 1'b0};
end

// ─────────────────────────────────────────────────────────────
//  Core Data Bus Wires
// ─────────────────────────────────────────────────────────────
logic [31:0] dbus_addr, dbus_wdata, dbus_rdata;
logic        dbus_we;
logic [2:0]  dbus_funct3;

// ─────────────────────────────────────────────────────────────
//  IMEM Data Bus Wires (for .rodata reads via data bus)
// ─────────────────────────────────────────────────────────────
logic [31:0] imem_daddr_w;
logic [2:0]  imem_dfunct3_w;
logic [31:0] imem_ddata_w;

// ─────────────────────────────────────────────────────────────
//  IRQ Wires
// ─────────────────────────────────────────────────────────────
logic timer_irq_w, uart_irq_w, gpio_irq_w;

// ─────────────────────────────────────────────────────────────
//  RISC-V Core
// ─────────────────────────────────────────────────────────────
riscv_core #(
    .IMEM_DEPTH(IMEM_DEPTH),
    .BOOT_ADDR (BOOT_ADDR),
    .IMEM_FILE (IMEM_FILE)
) u_core (
    .clk        (clk),
    .rst        (rst),
    .dbus_addr  (dbus_addr),
    .dbus_wdata (dbus_wdata),
    .dbus_we    (dbus_we),
    .dbus_funct3(dbus_funct3),
    .dbus_rdata (dbus_rdata),
    .timer_irq   (timer_irq_w),
    .uart_irq    (uart_irq_w),
    .gpio_irq    (gpio_irq_w),
    .imem_daddr  (imem_daddr_w),
    .imem_dfunct3(imem_dfunct3_w),
    .imem_ddata  (imem_ddata_w)
);

// ─────────────────────────────────────────────────────────────
//  Bus-Fabric Peripheral Wires
// ─────────────────────────────────────────────────────────────
logic [31:0] dmem_addr,  dmem_wdata,  dmem_rdata;
logic        dmem_we;
logic [2:0]  dmem_funct3;

logic [11:0] gpio_paddr,  uart_paddr,  timer_paddr,  csr_paddr;
logic [31:0] gpio_pwdata, uart_pwdata, timer_pwdata, csr_pwdata;
logic        gpio_pwe,    uart_pwe,    timer_pwe,    csr_pwe;
logic [2:0]  gpio_pfunct3, uart_pfunct3, timer_pfunct3, csr_pfunct3;
logic [31:0] gpio_prdata, uart_prdata, timer_prdata, csr_prdata;

// ─────────────────────────────────────────────────────────────
//  Bus Fabric
// ─────────────────────────────────────────────────────────────
bus_fabric u_fabric (
    .addr          (dbus_addr),
    .wdata         (dbus_wdata),
    .we            (dbus_we),
    .funct3        (dbus_funct3),
    .rdata         (dbus_rdata),
    .imem_daddr    (imem_daddr_w),
    .imem_dfunct3  (imem_dfunct3_w),
    .imem_ddata    (imem_ddata_w),
    .dmem_addr   (dmem_addr),
    .dmem_wdata  (dmem_wdata),
    .dmem_we     (dmem_we),
    .dmem_funct3 (dmem_funct3),
    .dmem_rdata  (dmem_rdata),
    .gpio_addr   (gpio_paddr),
    .gpio_wdata  (gpio_pwdata),
    .gpio_we     (gpio_pwe),
    .gpio_funct3 (gpio_pfunct3),
    .gpio_rdata  (gpio_prdata),
    .uart_addr   (uart_paddr),
    .uart_wdata  (uart_pwdata),
    .uart_we     (uart_pwe),
    .uart_funct3 (uart_pfunct3),
    .uart_rdata  (uart_prdata),
    .timer_addr  (timer_paddr),
    .timer_wdata (timer_pwdata),
    .timer_we    (timer_pwe),
    .timer_funct3(timer_pfunct3),
    .timer_rdata (timer_prdata),
    .csr_addr    (csr_paddr),
    .csr_wdata   (csr_pwdata),
    .csr_we      (csr_pwe),
    .csr_funct3  (csr_pfunct3),
    .csr_rdata   (csr_prdata)
);

// ─────────────────────────────────────────────────────────────
//  Data Memory  (0x2000_0000)
// ─────────────────────────────────────────────────────────────
dmem #(
    .DEPTH    (DMEM_DEPTH),
    .ADDR_BITS($clog2(DMEM_DEPTH))
) u_dmem (
    .clk   (clk),
    .addr  (dmem_addr),
    .wdata (dmem_wdata),
    .we    (dmem_we),
    .funct3(dmem_funct3),
    .rdata (dmem_rdata)
);

// ─────────────────────────────────────────────────────────────
//  GPIO  (0x4000_0000)
// ─────────────────────────────────────────────────────────────
gpio #(.N_OUT(4), .N_IN(8)) u_gpio (
    .clk      (clk),
    .rst      (rst),
    .addr     (gpio_paddr),
    .wdata    (gpio_pwdata),
    .we       (gpio_pwe),
    .funct3   (gpio_pfunct3),
    .rdata    (gpio_prdata),
    .gpio_led (gpio_led),
    .gpio_btn (gpio_btn),
    .gpio_sw  (gpio_sw),
    .irq      (gpio_irq_w)
);

// ─────────────────────────────────────────────────────────────
//  UART  (0x4000_1000)
// ─────────────────────────────────────────────────────────────
uart #(
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_uart (
    .clk    (clk),
    .rst    (rst),
    .addr   (uart_paddr),
    .wdata  (uart_pwdata),
    .we     (uart_pwe),
    .funct3 (uart_pfunct3),
    .rdata  (uart_prdata),
    .tx     (uart_tx),
    .rx     (uart_rx),
    .irq    (uart_irq_w)
);

// ─────────────────────────────────────────────────────────────
//  TIMER  (0x4000_2000)
// ─────────────────────────────────────────────────────────────
timer u_timer (
    .clk    (clk),
    .rst    (rst),
    .addr   (timer_paddr),
    .wdata  (timer_pwdata),
    .we     (timer_pwe),
    .funct3 (timer_pfunct3),
    .rdata  (timer_prdata),
    .irq    (timer_irq_w)
);

// ─────────────────────────────────────────────────────────────
//  CSR bus slot  (0x4000_3000)
//  CSRs are accessed via CSRRW/etc instructions, not memory-
//  mapped.  This slot returns 0 for all reads; writes ignored.
// ─────────────────────────────────────────────────────────────
assign csr_prdata = 32'h0;
// Suppress unused warnings
logic _csr_unused;
assign _csr_unused = csr_pwe | (|csr_paddr) | (|csr_pwdata) | (|csr_pfunct3);

endmodule