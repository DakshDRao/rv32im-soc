// ============================================================
//  csr_regs.sv  -  Machine-Mode CSR File + Trap Handler
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//  Step    : 18 — CSRs + Trap Handling
//
//  Implemented CSRs
//  ─────────────────────────────────────────────────────────
//  0x300  mstatus   [3]=MIE [7]=MPIE [12:11]=MPP(=11 always)
//  0x304  mie       [3]=MSIE [7]=MTIE [11]=MEIE
//  0x305  mtvec     [31:2]=BASE [1:0]=MODE (0=direct,1=vectored)
//  0x340  mscratch  scratch register for trap handler
//  0x341  mepc      exception program counter (bit[1:0] forced 0)
//  0x342  mcause    [31]=interrupt [30:0]=cause code
//  0x343  mtval     trap value (0 for ECALL/EBREAK/timer irq)
//  0x344  mip       [7]=MTIP(ro) [11]=MEIP(ro) — live interrupt pending
//  0xF14  mhartid   read-zero
//  0xC00  cycle     lower 32 of cycle counter (read-only)
//  0xC80  cycleh    upper 32 of cycle counter (read-only)
//
//  Trap Priority (highest → lowest)
//  ─────────────────────────────────────────────────────────
//  1. Machine External Interrupt (MEI)  mcause = 0x8000_000B
//  2. Machine Timer Interrupt   (MTI)   mcause = 0x8000_0007
//  3. EBREAK                            mcause = 0x0000_0003
//  4. ECALL from M-mode                 mcause = 0x0000_000B
//
//  CSR Instruction Semantics (funct3 = csr_op)
//  ─────────────────────────────────────────────────────────
//  001 CSRRW : rd←old; CSR←rs1
//  010 CSRRS : rd←old; CSR←CSR|rs1   (skip write if rs1=x0)
//  011 CSRRC : rd←old; CSR←CSR&~rs1  (skip write if rs1=x0)
//  101 CSRRWI: rd←old; CSR←zimm
//  110 CSRRSI: rd←old; CSR←CSR|zimm  (skip write if zimm=0)
//  111 CSRRCI: rd←old; CSR←CSR&~zimm (skip write if zimm=0)
//
//  Trap entry (trap_taken=1):
//    mepc   ← PC
//    mcause ← cause
//    mstatus.MPIE ← mstatus.MIE ; mstatus.MIE ← 0
//    PC     ← trap_pc (mtvec-derived)
//
//  MRET (mret_taken=1):
//    mstatus.MIE  ← mstatus.MPIE ; mstatus.MPIE ← 1
//    PC ← mepc
// ============================================================

module csr_regs (
    input  logic        clk,
    input  logic        rst,

    // ── CSR instruction interface ─────────────────────────────
    input  logic [11:0] csr_addr,      // instr[31:20]
    input  logic [31:0] rs1_data,      // register source
    input  logic [4:0]  rs1_addr,      // rs1 index (zero-check for RS/RC)
    input  logic [4:0]  zimm,          // instr[19:15] (immediate CSR ops)
    input  logic [2:0]  csr_op,        // funct3
    input  logic        is_csr,        // CSR instruction this cycle
    input  logic        is_ecall,      // ECALL
    input  logic        is_ebreak,     // EBREAK
    input  logic        is_mret,       // MRET
    input  logic [31:0] pc,            // current PC → mepc on trap

    // ── Peripheral interrupt lines ────────────────────────────
    input  logic        timer_irq,
    input  logic        uart_irq,
    input  logic        gpio_irq,

    // ── To pc_logic ───────────────────────────────────────────
    output logic [31:0] mepc_out,      // MRET return address
    output logic [31:0] trap_pc,       // trap target (from mtvec)
    output logic        trap_taken,    // trap fires this cycle
    output logic        mret_taken,    // MRET fires this cycle

    // ── To writeback mux ──────────────────────────────────────
    output logic [31:0] csr_rdata      // old CSR value → rd
);

// ─────────────────────────────────────────────────────────────
//  CSR Storage
// ─────────────────────────────────────────────────────────────
logic [31:0] mstatus_r;
logic [31:0] mie_r;
logic [31:0] mtvec_r;
logic [31:0] mscratch_r;
logic [31:0] mepc_r;
logic [31:0] mcause_r;
logic [31:0] mtval_r;
logic [63:0] cycle_r;

// ─────────────────────────────────────────────────────────────
//  mip — read-only reflection of live interrupt lines
// ─────────────────────────────────────────────────────────────
wire [31:0] mip_r = {20'h0,
                     (uart_irq | gpio_irq), // bit[11] MEIP
                     3'h0,
                     timer_irq,             // bit[7]  MTIP
                     7'h0};

// ─────────────────────────────────────────────────────────────
//  Interrupt Detection
// ─────────────────────────────────────────────────────────────
wire mie_bit  = mstatus_r[3];
wire timer_int = mie_bit & mie_r[7]  & timer_irq;
wire ext_int   = mie_bit & mie_r[11] & (uart_irq | gpio_irq);

wire interrupt_taken = timer_int | ext_int;

assign trap_taken = interrupt_taken | is_ebreak | is_ecall;
assign mret_taken = is_mret & ~trap_taken;

// ─────────────────────────────────────────────────────────────
//  mcause for this trap
// ─────────────────────────────────────────────────────────────
logic [31:0] mcause_new;
always_comb begin
    priority if (ext_int)     mcause_new = 32'h8000_000B;
    else if (timer_int)       mcause_new = 32'h8000_0007;
    else if (is_ebreak)       mcause_new = 32'h0000_0003;
    else                      mcause_new = 32'h0000_000B;
end

// ─────────────────────────────────────────────────────────────
//  Trap PC (mtvec decoding)
//  Direct   (MODE=0): all traps → BASE
//  Vectored (MODE=1): interrupts → BASE + 4×cause; exceptions → BASE
// ─────────────────────────────────────────────────────────────
always_comb begin
    logic [31:0] base;
    base = {mtvec_r[31:2], 2'b00};
    if (mtvec_r[0] && mcause_new[31])   // vectored + interrupt
        trap_pc = base + (mcause_new[29:0] << 2);
    else
        trap_pc = base;
end

// ─────────────────────────────────────────────────────────────
//  CSR Write Operand + Enable
// ─────────────────────────────────────────────────────────────
wire        is_imm_op = csr_op[2];
wire [31:0] csr_wop   = is_imm_op ? {27'h0, zimm} : rs1_data;

wire rs_zero = is_imm_op ? (zimm == 5'h0) : (rs1_addr == 5'h0);
wire csr_we  = is_csr & ~trap_taken
             & ((csr_op[1:0] == 2'b01)
             |  (csr_op[1:0] == 2'b10 & ~rs_zero)
             |  (csr_op[1:0] == 2'b11 & ~rs_zero));

// (apply_op function removed — see precomputed nv_* wires below)

// ─────────────────────────────────────────────────────────────
//  CSR Read (combinational — always returns current value)
// ─────────────────────────────────────────────────────────────
always_comb begin : csr_read
    unique casez (csr_addr)
        12'h300: csr_rdata = mstatus_r;
        12'h304: csr_rdata = mie_r;
        12'h305: csr_rdata = mtvec_r;
        12'h340: csr_rdata = mscratch_r;
        12'h341: csr_rdata = mepc_r;
        12'h342: csr_rdata = mcause_r;
        12'h343: csr_rdata = mtval_r;
        12'h344: csr_rdata = mip_r;
        12'hF14: csr_rdata = 32'h0;        // mhartid
        12'hC00: csr_rdata = cycle_r[31:0];
        12'hC80: csr_rdata = cycle_r[63:32];
        default: csr_rdata = 32'h0;
    endcase
end

// ─────────────────────────────────────────────────────────────
//  Precomputed CSR write values (combinational)
//  Vivado does not support function calls inside always_ff or
//  part-selects on function return values — compute everything
//  as plain wires and use those in the sequential block.
// ─────────────────────────────────────────────────────────────
logic [31:0] nv_mstatus, nv_mie, nv_mtvec, nv_mscratch;
logic [31:0] nv_mepc,    nv_mcause, nv_mtval;

always_comb begin
    // apply_op inline: RW=wop, RS=old|wop, RC=old&~wop
    case (csr_op[1:0])
        2'b01:   begin
            nv_mstatus  = csr_wop;
            nv_mie      = csr_wop;
            nv_mtvec    = csr_wop;
            nv_mscratch = csr_wop;
            nv_mepc     = csr_wop;
            nv_mcause   = csr_wop;
            nv_mtval    = csr_wop;
        end
        2'b10:   begin
            nv_mstatus  = mstatus_r  | csr_wop;
            nv_mie      = mie_r      | csr_wop;
            nv_mtvec    = mtvec_r    | csr_wop;
            nv_mscratch = mscratch_r | csr_wop;
            nv_mepc     = mepc_r     | csr_wop;
            nv_mcause   = mcause_r   | csr_wop;
            nv_mtval    = mtval_r    | csr_wop;
        end
        2'b11:   begin
            nv_mstatus  = mstatus_r  & ~csr_wop;
            nv_mie      = mie_r      & ~csr_wop;
            nv_mtvec    = mtvec_r    & ~csr_wop;
            nv_mscratch = mscratch_r & ~csr_wop;
            nv_mepc     = mepc_r     & ~csr_wop;
            nv_mcause   = mcause_r   & ~csr_wop;
            nv_mtval    = mtval_r    & ~csr_wop;
        end
        default: begin
            nv_mstatus  = mstatus_r;
            nv_mie      = mie_r;
            nv_mtvec    = mtvec_r;
            nv_mscratch = mscratch_r;
            nv_mepc     = mepc_r;
            nv_mcause   = mcause_r;
            nv_mtval    = mtval_r;
        end
    endcase
end

// ─────────────────────────────────────────────────────────────
//  Sequential: CSR writes + trap/mret updates
// ─────────────────────────────────────────────────────────────
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        mstatus_r  <= 32'h0000_1800;  // MPP=11, MIE=0, MPIE=0
        mie_r      <= 32'h0;
        mtvec_r    <= 32'h0;
        mscratch_r <= 32'h0;
        mepc_r     <= 32'h0;
        mcause_r   <= 32'h0;
        mtval_r    <= 32'h0;
        cycle_r    <= 64'h0;
    end else begin

        cycle_r <= cycle_r + 1'b1;

        if (trap_taken) begin
            mepc_r    <= {pc[31:2], 2'b00};
            mcause_r  <= mcause_new;
            mtval_r   <= 32'h0;
            mstatus_r <= {mstatus_r[31:13], 2'b11,
                          mstatus_r[10:8],
                          mstatus_r[3],   // MPIE ← MIE
                          mstatus_r[6:4],
                          1'b0,            // MIE ← 0
                          mstatus_r[2:0]};

        end else if (mret_taken) begin
            mstatus_r <= {mstatus_r[31:13], 2'b11,
                          mstatus_r[10:8],
                          1'b1,            // MPIE ← 1
                          mstatus_r[6:4],
                          mstatus_r[7],    // MIE ← MPIE
                          mstatus_r[2:0]};

        end else if (csr_we) begin
            unique casez (csr_addr)
                12'h300: mstatus_r  <= {nv_mstatus[31:13], 2'b11,
                                        nv_mstatus[10:8], nv_mstatus[7:3],
                                        nv_mstatus[2:0]};
                12'h304: mie_r      <= nv_mie & 32'h0000_0888;
                12'h305: mtvec_r    <= nv_mtvec;
                12'h340: mscratch_r <= nv_mscratch;
                12'h341: mepc_r     <= {nv_mepc[31:2], 2'b00};
                12'h342: mcause_r   <= nv_mcause;
                12'h343: mtval_r    <= nv_mtval;
                default: ;
            endcase
        end

    end
end

assign mepc_out = mepc_r;

endmodule
