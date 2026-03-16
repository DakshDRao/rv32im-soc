// ============================================================
//  mul_div.sv  -  M-Extension MUL / DIV Unit  (RV32M)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  Implements all 8 RV32M instructions, purely combinational.
//  Vivado infers DSP48E1 slices for the multipliers on Artix-7.
//
//  funct3 encoding (matches RISC-V ISA Vol.1 §7.1):
//    000  MUL     lower 32 bits of signed(rs1) × signed(rs2)
//    001  MULH    upper 32 bits of signed(rs1) × signed(rs2)
//    010  MULHSU  upper 32 bits of signed(rs1) × unsigned(rs2)
//    011  MULHU   upper 32 bits of unsigned(rs1) × unsigned(rs2)
//    100  DIV     signed(rs1)   /  signed(rs2)
//    101  DIVU    unsigned(rs1) /  unsigned(rs2)
//    110  REM     signed(rs1)   %  signed(rs2)
//    111  REMU    unsigned(rs1) %  unsigned(rs2)
//
//  Divide-by-zero (spec §7.2 Table 7.1):
//    DIV  / DIVU  → 0xFFFF_FFFF  (-1 / all-ones)
//    REM  / REMU  → dividend (rs1) unchanged
//
//  Signed overflow (INT_MIN / -1):
//    DIV          → INT_MIN  (0x8000_0000)
//    REM          → 0
// ============================================================

module mul_div (
    input  logic [31:0] a,        // rs1
    input  logic [31:0] b,        // rs2
    input  logic [2:0]  funct3,   // operation select
    output logic [31:0] result
);

// ─────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────
localparam [31:0] ALL_ONES = 32'hFFFF_FFFF;
localparam [31:0] INT_MIN  = 32'h8000_0000;

// ─────────────────────────────────────────────────────────────
//  Operand Extension
//  Sign-extend / zero-extend a and b to 64 bits once.
//  mul_su uses a_s (signed) × b_u treated as positive signed
//  (b_u[63] is always 0, so $signed(b_u) is always ≥ 0).
// ─────────────────────────────────────────────────────────────
logic signed [63:0] a_s;    // sign-extended a
logic        [63:0] a_u;    // zero-extended a
logic signed [63:0] b_s;    // sign-extended b
logic        [63:0] b_u;    // zero-extended b

assign a_s = {{32{a[31]}}, a};
assign b_s = {{32{b[31]}}, b};
assign a_u = {32'b0, a};
assign b_u = {32'b0, b};

// ─────────────────────────────────────────────────────────────
//  Multipliers
//  Three separate expressions so Vivado can map each to its
//  own DSP48E1 slice. Inference works best with signed 64-bit.
// ─────────────────────────────────────────────────────────────
logic signed [63:0] prod_ss;   // signed   × signed
logic signed [63:0] prod_su;   // signed   × unsigned
logic        [63:0] prod_uu;   // unsigned × unsigned

assign prod_ss = a_s * b_s;
assign prod_su = a_s * $signed(b_u);  // b_u MSB=0 → always positive signed
assign prod_uu = a_u * b_u;

// ─────────────────────────────────────────────────────────────
//  Dividers & Remainder
//  All four variants with spec-compliant corner case handling.
// ─────────────────────────────────────────────────────────────
logic [31:0] div_s, div_u, rem_s, rem_u;

always_comb begin : division

    // ── Signed DIV ──────────────────────────────────────────
    if (b == 32'h0)
        div_s = ALL_ONES;                        // div-by-zero
    else if (a == INT_MIN && b == ALL_ONES)
        div_s = INT_MIN;                         // overflow: INT_MIN / -1
    else
        div_s = 32'($signed(a) / $signed(b));

    // ── Unsigned DIV ────────────────────────────────────────
    div_u = (b == 32'h0) ? ALL_ONES : (a / b);

    // ── Signed REM ──────────────────────────────────────────
    if (b == 32'h0)
        rem_s = a;                               // div-by-zero: remainder = dividend
    else if (a == INT_MIN && b == ALL_ONES)
        rem_s = 32'h0;                           // overflow: remainder = 0
    else
        rem_s = 32'($signed(a) % $signed(b));

    // ── Unsigned REM ────────────────────────────────────────
    rem_u = (b == 32'h0) ? a : (a % b);

end : division

// ─────────────────────────────────────────────────────────────
//  Output Mux
// ─────────────────────────────────────────────────────────────
always_comb begin : output_mux
    unique case (funct3)
        3'b000: result = prod_ss[31:0];     // MUL
        3'b001: result = prod_ss[63:32];    // MULH
        3'b010: result = prod_su[63:32];    // MULHSU
        3'b011: result = prod_uu[63:32];    // MULHU
        3'b100: result = div_s;             // DIV
        3'b101: result = div_u;             // DIVU
        3'b110: result = rem_s;             // REM
        3'b111: result = rem_u;             // REMU
    endcase
end : output_mux

endmodule