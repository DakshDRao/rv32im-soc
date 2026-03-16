// ============================================================
//  bus_fabric.sv  -  SoC Data-Bus Address Decoder + Mux
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//
//  Memory Map
//  ──────────────────────────────────────────────────────────
//  Region   Base         Size   Notes
//  IMEM     0x0000_0000  64 KB  Instruction fetch + DATA READ
//  DMEM     0x2000_0000  64 KB  Data BRAM (read/write)
//  GPIO     0x4000_0000   4 KB  Step 16
//  UART     0x4000_1000   4 KB  Step 15
//  TIMER    0x4000_2000   4 KB  Step 17
//  CSR/TRAP 0x4000_3000   4 KB  Step 18
//  ──────────────────────────────────────────────────────────
//  IMEM is now accessible via the data bus (read-only) so that
//  firmware can read .rodata strings placed in the code segment.
// ============================================================

module bus_fabric (
    // ── Core-side (from riscv_core dbus_*) ──────────────────
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic [2:0]  funct3,
    output logic [31:0] rdata,

    // ── IMEM data-read port (read-only, .rodata access) ──────
    output logic [31:0] imem_daddr,
    output logic [2:0]  imem_dfunct3,
    input  logic [31:0] imem_ddata,

    // ── DMEM port ────────────────────────────────────────────
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic        dmem_we,
    output logic [2:0]  dmem_funct3,
    input  logic [31:0] dmem_rdata,

    // ── GPIO port ────────────────────────────────────────────
    output logic [11:0] gpio_addr,
    output logic [31:0] gpio_wdata,
    output logic        gpio_we,
    output logic [2:0]  gpio_funct3,
    input  logic [31:0] gpio_rdata,

    // ── UART port ────────────────────────────────────────────
    output logic [11:0] uart_addr,
    output logic [31:0] uart_wdata,
    output logic        uart_we,
    output logic [2:0]  uart_funct3,
    input  logic [31:0] uart_rdata,

    // ── TIMER port ───────────────────────────────────────────
    output logic [11:0] timer_addr,
    output logic [31:0] timer_wdata,
    output logic        timer_we,
    output logic [2:0]  timer_funct3,
    input  logic [31:0] timer_rdata,

    // ── CSR/Trap port ────────────────────────────────────────
    output logic [11:0] csr_addr,
    output logic [31:0] csr_wdata,
    output logic        csr_we,
    output logic [2:0]  csr_funct3,
    input  logic [31:0] csr_rdata
);

// ─────────────────────────────────────────────────────────────
//  Address Region Decode
// ─────────────────────────────────────────────────────────────
typedef enum logic [2:0] {
    SEL_IMEM  = 3'd5,
    SEL_DMEM  = 3'd0,
    SEL_GPIO  = 3'd1,
    SEL_UART  = 3'd2,
    SEL_TIMER = 3'd3,
    SEL_CSR   = 3'd4,
    SEL_NONE  = 3'd7
} sel_e;

sel_e sel;

always_comb begin : addr_decode
    unique casez (addr)
        // IMEM  - 0x0000_0000 .. 0x0000_FFFF (data reads only)
        32'h0000_????:  sel = SEL_IMEM;
        // DMEM  - 0x2000_0000 .. 0x2000_FFFF
        32'h2000_????:  sel = SEL_DMEM;
        // Peripheral block
        32'h4000_0???:  sel = SEL_GPIO;
        32'h4000_1???:  sel = SEL_UART;
        32'h4000_2???:  sel = SEL_TIMER;
        32'h4000_3???:  sel = SEL_CSR;
        default:        sel = SEL_NONE;
    endcase
end

// ─────────────────────────────────────────────────────────────
//  IMEM data port passthrough
// ─────────────────────────────────────────────────────────────
assign imem_daddr   = addr;
assign imem_dfunct3 = funct3;

// ─────────────────────────────────────────────────────────────
//  Write-Data / funct3 broadcast
// ─────────────────────────────────────────────────────────────
assign dmem_wdata   = wdata;
assign gpio_wdata   = wdata;
assign uart_wdata   = wdata;
assign timer_wdata  = wdata;
assign csr_wdata    = wdata;

assign dmem_funct3  = funct3;
assign gpio_funct3  = funct3;
assign uart_funct3  = funct3;
assign timer_funct3 = funct3;
assign csr_funct3   = funct3;

// ─────────────────────────────────────────────────────────────
//  Address Routing
// ─────────────────────────────────────────────────────────────
assign dmem_addr  = addr;
assign gpio_addr  = addr[11:0];
assign uart_addr  = addr[11:0];
assign timer_addr = addr[11:0];
assign csr_addr   = addr[11:0];

// ─────────────────────────────────────────────────────────────
//  Write-Enable Gating  (IMEM is read-only on data bus)
// ─────────────────────────────────────────────────────────────
assign dmem_we  = we & (sel == SEL_DMEM);
assign gpio_we  = we & (sel == SEL_GPIO);
assign uart_we  = we & (sel == SEL_UART);
assign timer_we = we & (sel == SEL_TIMER);
assign csr_we   = we & (sel == SEL_CSR);

// ─────────────────────────────────────────────────────────────
//  Read-Data Mux
// ─────────────────────────────────────────────────────────────
always_comb begin : rdata_mux
    unique case (sel)
        SEL_IMEM:  rdata = imem_ddata;
        SEL_DMEM:  rdata = dmem_rdata;
        SEL_GPIO:  rdata = gpio_rdata;
        SEL_UART:  rdata = uart_rdata;
        SEL_TIMER: rdata = timer_rdata;
        SEL_CSR:   rdata = csr_rdata;
        default:   rdata = 32'hDEAD_BEEF;
    endcase
end

endmodule
