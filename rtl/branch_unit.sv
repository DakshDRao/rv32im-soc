// ============================================================
//  branch_unit.sv  -  Branch Condition Evaluator  (RV32I)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  Evaluates all six RISC-V branch conditions using dedicated
//  comparators. Deliberately NOT reusing the ALU result -
//  this keeps the ALU free to compute the branch TARGET
//  address (PC + B-imm) at the same time.
//
//  Output:
//    branch_taken = 1  →  pc_logic selects PC + B-imm
//    branch_taken = 0  →  pc_logic selects PC + 4
//
//  Reference: RISC-V ISA Vol.1 §2.5
//
//  funct3 encoding:
//    000  BEQ   rs1 == rs2
//    001  BNE   rs1 != rs2
//    100  BLT   rs1 <  rs2  (signed)
//    101  BGE   rs1 >= rs2  (signed)
//    110  BLTU  rs1 <  rs2  (unsigned)
//    111  BGEU  rs1 >= rs2  (unsigned)
// ============================================================

module branch_unit (
    input  logic [31:0] rs1,           // Register source 1 value
    input  logic [31:0] rs2,           // Register source 2 value
    input  logic [2:0]  funct3,        // Branch type selector
    input  logic        branch,        // 1 = this is a branch instruction
    output logic        branch_taken   // 1 = condition true, take the branch
);

// ─────────────────────────────────────────────────────────────
//  funct3 Branch Codes
// ─────────────────────────────────────────────────────────────
localparam [2:0]
    BEQ  = 3'b000,
    BNE  = 3'b001,
    BLT  = 3'b100,
    BGE  = 3'b101,
    BLTU = 3'b110,
    BGEU = 3'b111;

// ─────────────────────────────────────────────────────────────
//  Dedicated Comparators
//  Computed once, shared across all branch conditions.
//  Synthesiser will share logic automatically.
//
//  eq   : equality (used by BEQ / BNE)
//  lt_s : signed less-than    (used by BLT / BGE)
//  lt_u : unsigned less-than  (used by BLTU / BGEU)
// ─────────────────────────────────────────────────────────────
logic eq, lt_s, lt_u;

assign eq   =  (rs1 == rs2);
assign lt_s =  ($signed(rs1) < $signed(rs2));
assign lt_u =  (rs1 < rs2);

// ─────────────────────────────────────────────────────────────
//  Condition Evaluation
//  branch_taken is 0 when branch=0 (not a branch instruction)
//  so the PC mux never fires on non-branch instructions.
// ─────────────────────────────────────────────────────────────
logic condition;

always_comb begin : eval
    unique case (funct3)
        BEQ  : condition =  eq;
        BNE  : condition = ~eq;
        BLT  : condition =  lt_s;
        BGE  : condition = ~lt_s;
        BLTU : condition =  lt_u;
        BGEU : condition = ~lt_u;
        default: condition = 1'b0;  // funct3=010/011 undefined → never taken
    endcase
end : eval

assign branch_taken = branch & condition;

endmodule