// ============================================================
//  pc_logic.sv  -  Program Counter + Next-PC Mux
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//
//  Step 18 changes:
//    • trap_taken, trap_pc, mret_taken, mepc inputs added
//    • Next-PC priority updated (highest → lowest):
//        1. trap_taken → trap_pc  (interrupt or exception)
//        2. mret_taken → mepc     (MRET)
//        3. jalr       → pc_jalr
//        4. jump       → pc_jal
//        5. branch_taken → pc_branch
//        6. default    → PC+4
// ============================================================

module pc_logic #(
    parameter logic [31:0] BOOT_ADDR = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst,

    // ── Control signals ──────────────────────────────────────
    input  logic        jump,
    input  logic        jalr,
    input  logic        branch_taken,

    // ── Step 18: trap / MRET ─────────────────────────────────
    input  logic        trap_taken,   // any trap this cycle
    input  logic [31:0] trap_pc,      // mtvec-derived target
    input  logic        mret_taken,   // MRET this cycle
    input  logic [31:0] mepc,         // saved exception PC

    // ── Data inputs ──────────────────────────────────────────
    input  logic [31:0] rs1,
    input  logic [31:0] imm,

    // ── Outputs ──────────────────────────────────────────────
    output logic [31:0] pc,
    output logic [31:0] pc_plus4
);

logic [31:0] pc_seq, pc_branch, pc_jal, pc_jalr;
assign pc_seq    = pc + 32'd4;
assign pc_branch = pc + imm;
assign pc_jal    = pc + imm;
assign pc_jalr   = (rs1 + imm) & ~32'h1;

logic [31:0] next_pc;

always_comb begin : next_pc_mux
    priority if (trap_taken)    next_pc = trap_pc;
    else if (mret_taken)        next_pc = mepc;
    else if (jalr)              next_pc = pc_jalr;
    else if (jump)              next_pc = pc_jal;
    else if (branch_taken)      next_pc = pc_branch;
    else                        next_pc = pc_seq;
end

always_ff @(posedge clk) begin : pc_reg
    if (rst) pc <= BOOT_ADDR;
    else     pc <= next_pc;
end

assign pc_plus4 = pc + 32'd4;

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && pc[1:0] !== 2'b00)
        $display("[PC WARNING] misaligned PC = %08h at time %0t", pc, $time);
    if (jump && jalr)
        $display("[PC WARNING] jump & jalr both asserted at time %0t", $time);
end
// synthesis translate_on

endmodule
