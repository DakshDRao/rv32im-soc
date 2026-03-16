// ============================================================
//  imm_gen.sv  -  Immediate Generator  (RV32I)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  RISC-V scatters immediate bits across the instruction word
//  specifically to keep rs1/rs2/rd at FIXED bit positions in
//  all formats. This module reassembles and sign-extends all
//  five immediate encodings.
//
//  Reference: RISC-V ISA Vol.1 §2.3, Figure 2.4
//
//  All logic is purely combinational - no clock needed.
// ============================================================

module imm_gen (
    input  logic [31:0] instr,      // Full 32-bit instruction word
    input  logic [2:0]  imm_sel,    // Format select (from control.sv)
    output logic [31:0] imm         // Sign-extended immediate
);

// ─────────────────────────────────────────────────────────────
//  Immediate Format Select Encoding
//  Must stay in sync with control.sv
// ─────────────────────────────────────────────────────────────
localparam [2:0]
    IMM_I = 3'd0,   // I-type : ADDI, LOAD, JALR
    IMM_S = 3'd1,   // S-type : STORE
    IMM_B = 3'd2,   // B-type : BRANCH
    IMM_U = 3'd3,   // U-type : LUI, AUIPC
    IMM_J = 3'd4;   // J-type : JAL

// ─────────────────────────────────────────────────────────────
//  Bit-field Reference  (from RISC-V ISA Figure 2.4)
//
//  inst[31]      = sign bit for ALL formats
//  inst[30:25]   = imm[10:5]  in I/S/B/J
//  inst[24:21]   = imm[4:1]   in I/J
//  inst[20]      = imm[0]     in I  |  imm[11] in J
//  inst[19:12]   = imm[19:12] in U/J
//  inst[11:8]    = imm[4:1]   in S/B
//  inst[7]       = imm[11]    in B  |  imm[0] in S
//
//  B and J always have imm[0]=0  (instructions are 2-byte aligned)
// ─────────────────────────────────────────────────────────────

always_comb begin : immediate_decode
    unique case (imm_sel)

        // ── I-type ───────────────────────────────────────────
        // Used by: ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
        //          LB LH LW LBU LHU   JALR
        //
        //  31       20 19     12 11    7 6      0
        //  [imm11:0]   [rs1  ]   [funct3] [opcode]
        //
        //  imm[31:12] = sign-extend from inst[31]
        //  imm[11:0]  = inst[31:20]
        IMM_I: imm = { {20{instr[31]}}, instr[31:20] };

        // ── S-type ───────────────────────────────────────────
        // Used by: SB SH SW
        //
        //  31     25 24   20 19   15 14  12 11    7 6      0
        //  [imm11:5] [rs2]   [rs1]   [f3]  [imm4:0] [opcode]
        //
        //  imm[31:12] = sign-extend
        //  imm[11:5]  = inst[31:25]
        //  imm[4:0]   = inst[11:7]
        IMM_S: imm = { {20{instr[31]}}, instr[31:25], instr[11:7] };

        // ── B-type ───────────────────────────────────────────
        // Used by: BEQ BNE BLT BGE BLTU BGEU
        //
        //  31    30   25 24  20 19  15 14 12 11   8  7    6    0
        //  [i12] [i10:5] [rs2]  [rs1]  [f3] [i4:1] [i11] [opcode]
        //
        //  imm[31:13] = sign-extend
        //  imm[12]    = inst[31]
        //  imm[11]    = inst[7]       ← NOTE: bit 11 is in inst[7]!
        //  imm[10:5]  = inst[30:25]
        //  imm[4:1]   = inst[11:8]
        //  imm[0]     = 0             ← always even (2-byte aligned)
        IMM_B: imm = { {19{instr[31]}}, instr[31], instr[7],
                        instr[30:25],   instr[11:8], 1'b0 };

        // ── U-type ───────────────────────────────────────────
        // Used by: LUI AUIPC
        //
        //  31           12 11    7 6      0
        //  [imm31:12]      [rd]    [opcode]
        //
        //  imm[31:12] = inst[31:12]   (no sign extension needed -
        //  imm[11:0]  = 0              upper bits already in place)
        IMM_U: imm = { instr[31:12], 12'b0 };

        // ── J-type ───────────────────────────────────────────
        // Used by: JAL
        //
        //  31    30      21  20   19      12 11    7 6      0
        //  [i20] [i10:1]    [i11] [i19:12]   [rd]    [opcode]
        //
        //  imm[31:21] = sign-extend
        //  imm[20]    = inst[31]
        //  imm[19:12] = inst[19:12]   ← NOTE: these are NOT contiguous
        //  imm[11]    = inst[20]       ← bit 11 is in inst[20]!
        //  imm[10:1]  = inst[30:21]
        //  imm[0]     = 0             ← always even
        IMM_J: imm = { {11{instr[31]}}, instr[31], instr[19:12],
                        instr[20],       instr[30:21], 1'b0 };

        default: imm = 32'b0;

    endcase
end : immediate_decode

endmodule