// ============================================================
//  alu.sv  -  Arithmetic Logic Unit  (RV32I + RV32M)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  alu_op encoding (5 bits):
//    alu_op[4] = 0  →  RV32I operation, alu_op[3:0] selects:
//      0  ADD    a + b
//      1  SUB    a - b
//      2  AND    a & b
//      3  OR     a | b
//      4  XOR    a ^ b
//      5  SLL    a << b[4:0]
//      6  SRL    a >> b[4:0]
//      7  SRA    a >>> b[4:0]
//      8  SLT    signed(a) < signed(b)
//      9  SLTU   a < b  (unsigned)
//
//    alu_op[4] = 1  →  RV32M operation, alu_op[2:0] = funct3:
//      000  MUL      lower 32 of signed×signed
//      001  MULH     upper 32 of signed×signed
//      010  MULHSU   upper 32 of signed×unsigned
//      011  MULHU    upper 32 of unsigned×unsigned
//      100  DIV      signed divide
//      101  DIVU     unsigned divide
//      110  REM      signed remainder
//      111  REMU     unsigned remainder
//
//  All logic is purely combinational - no clock needed.
// ============================================================

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [4:0]  alu_op,    // 5 bits: [4]=M-ext flag, [3:0]=op
    output logic [31:0] result,
    output logic        zero
);

// ─────────────────────────────────────────────────────────────
//  RV32I Operation Codes  (alu_op[4]=0)
// ─────────────────────────────────────────────────────────────
localparam [3:0]
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_AND  = 4'd2,
    ALU_OR   = 4'd3,
    ALU_XOR  = 4'd4,
    ALU_SLL  = 4'd5,
    ALU_SRL  = 4'd6,
    ALU_SRA  = 4'd7,
    ALU_SLT  = 4'd8,
    ALU_SLTU = 4'd9;

// ─────────────────────────────────────────────────────────────
//  M-Extension Unit
//  Always computing - result selected only when alu_op[4]=1.
//  Vivado will prune unused logic during synthesis.
// ─────────────────────────────────────────────────────────────
logic [31:0] mext_result;

mul_div u_mul_div (
    .a      (a),
    .b      (b),
    .funct3 (alu_op[2:0]),
    .result (mext_result)
);

// ─────────────────────────────────────────────────────────────
//  Core Combinational Logic
// ─────────────────────────────────────────────────────────────
always_comb begin : alu_core
    result = 32'hDEAD_BEEF;   // default catches illegal ops in sim

    if (alu_op[4]) begin
        // ── M-Extension ─────────────────────────────────────
        result = mext_result;
    end else begin
        // ── RV32I ───────────────────────────────────────────
        unique case (alu_op[3:0])
            ALU_ADD  : result = a + b;
            ALU_SUB  : result = a - b;
            ALU_AND  : result = a & b;
            ALU_OR   : result = a | b;
            ALU_XOR  : result = a ^ b;
            ALU_SLL  : result = a << b[4:0];
            ALU_SRL  : result = a >> b[4:0];
            ALU_SRA  : result = 32'($signed(a) >>> b[4:0]);
            ALU_SLT  : result = {31'b0, $signed(a) < $signed(b)};
            ALU_SLTU : result = {31'b0, a < b};
            default  : result = 32'hDEAD_BEEF;
        endcase
    end
end : alu_core

// ─────────────────────────────────────────────────────────────
//  Zero Flag
// ─────────────────────────────────────────────────────────────
assign zero = (result == 32'b0);

endmodule