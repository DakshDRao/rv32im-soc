// ============================================================
//  timer.sv  -  RISC-V Machine Timer (mtime / mtimecmp)
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//  Step    : 17 — Timer + MTIME
//
//  Spec compliance:
//    Implements the RISC-V privileged spec §3.1.10 Machine Timer
//    Registers.  mtime increments every PRESCALER+1 clocks.
//    Timer interrupt fires (level) when mtime >= mtimecmp
//    and irq_en=1.  Firmware clears it by writing a new
//    mtimecmp value in the future.
//
//  Register Map  (base = 0x4000_2000)
//  ─────────────────────────────────────────────────────────
//  Offset  Name          Access  Description
//  0x00    MTIME_LO      R/W     mtime[31:0]   — writable for init
//  0x04    MTIME_HI      R/W     mtime[63:32]
//  0x08    MTIMECMP_LO   R/W     mtimecmp[31:0]
//  0x0C    MTIMECMP_HI   R/W     mtimecmp[63:32]
//  0x10    CTRL          R/W     [0]=enable  [1]=irq_en
//  0x14    PRESCALER     R/W     tick every PRESCALER+1 clocks
//                                (default=0 → every clock, good for sim)
//                                (set to 99 for 1 µs tick at 100 MHz)
//
//  IRQ (level, active-high):
//    irq = irq_en & enable & (mtime >= mtimecmp)
//
//  64-bit write ordering note:
//    To avoid a spurious interrupt when updating a 64-bit value,
//    firmware should:
//      1. Write MTIMECMP_HI = 0xFFFF_FFFF  (prevents match during update)
//      2. Write MTIMECMP_LO = new_lo
//      3. Write MTIMECMP_HI = new_hi
//    Same convention used by Linux/FreeRTOS RISC-V timer drivers.
// ============================================================

module timer (
    input  logic        clk,
    input  logic        rst,

    // ── Bus interface (from bus_fabric) ──────────────────────
    input  logic [11:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic [2:0]  funct3,   // unused — word accesses only
    output logic [31:0] rdata,

    // ── Interrupt (level, active-high) ───────────────────────
    output logic        irq
);

// ─────────────────────────────────────────────────────────────
//  Register Addresses
// ─────────────────────────────────────────────────────────────
localparam logic [11:0]
    ADDR_MTIME_LO    = 12'h000,
    ADDR_MTIME_HI    = 12'h004,
    ADDR_MTIMECMP_LO = 12'h008,
    ADDR_MTIMECMP_HI = 12'h00C,
    ADDR_CTRL        = 12'h010,
    ADDR_PRESCALER   = 12'h014;

// ─────────────────────────────────────────────────────────────
//  Registers
// ─────────────────────────────────────────────────────────────
logic [63:0] mtime;
logic [63:0] mtimecmp;
logic        enable;
logic        irq_en;
logic [31:0] prescaler;     // tick every prescaler+1 clocks
logic [31:0] prescaler_cnt;

// ─────────────────────────────────────────────────────────────
//  Prescaler + mtime Increment
// ─────────────────────────────────────────────────────────────
wire tick = (prescaler_cnt == prescaler);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        mtime         <= 64'h0;
        mtimecmp      <= 64'hFFFF_FFFF_FFFF_FFFF;  // no match at reset
        enable        <= 1'b0;
        irq_en        <= 1'b0;
        prescaler     <= 32'h0;   // tick every clock (sim default)
        prescaler_cnt <= 32'h0;
    end else begin

        // ── Prescaler counter ──────────────────────────────
        if (tick)
            prescaler_cnt <= 32'h0;
        else
            prescaler_cnt <= prescaler_cnt + 1'b1;

        // ── mtime increment ────────────────────────────────
        if (enable && tick)
            mtime <= mtime + 1'b1;

        // ── Register writes (take priority over increment) ─
        if (we) begin
            unique case (addr)
                ADDR_MTIME_LO:    mtime[31:0]     <= wdata;
                ADDR_MTIME_HI:    mtime[63:32]    <= wdata;
                ADDR_MTIMECMP_LO: mtimecmp[31:0]  <= wdata;
                ADDR_MTIMECMP_HI: mtimecmp[63:32] <= wdata;
                ADDR_CTRL:        {irq_en, enable} <= wdata[1:0];
                ADDR_PRESCALER:   begin
                    prescaler     <= wdata;
                    prescaler_cnt <= 32'h0;   // reset counter on prescaler change
                end
                default: ;
            endcase
        end

    end
end

// ─────────────────────────────────────────────────────────────
//  Interrupt
//  Fires when mtime >= mtimecmp, irq_en and enable are both set.
//  Unsigned comparison — both operands are 64-bit.
// ─────────────────────────────────────────────────────────────
assign irq = enable & irq_en & (mtime >= mtimecmp);

// ─────────────────────────────────────────────────────────────
//  Read Mux
// ─────────────────────────────────────────────────────────────
always_comb begin : read_mux
    unique case (addr)
        ADDR_MTIME_LO:    rdata = mtime[31:0];
        ADDR_MTIME_HI:    rdata = mtime[63:32];
        ADDR_MTIMECMP_LO: rdata = mtimecmp[31:0];
        ADDR_MTIMECMP_HI: rdata = mtimecmp[63:32];
        ADDR_CTRL:        rdata = {30'h0, irq_en, enable};
        ADDR_PRESCALER:   rdata = prescaler;
        default:          rdata = 32'h0;
    endcase
end

endmodule
