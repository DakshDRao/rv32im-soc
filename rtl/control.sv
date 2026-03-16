// ============================================================
//  control.sv  -  Main Control Unit  (RV32I + RV32M + CSR/Trap)
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//
//  Step 18 changes:
//    • instr_20 (bit[20]), instr_28 (bit[28]) inputs added
//    • OP_SYSTEM fully decoded:
//        funct3≠000 → CSR instructions
//        funct3=000, instr_20=0 → ECALL
//        funct3=000, instr_20=1 → EBREAK
//        funct3=000, instr_28=1 → MRET
//    • wb_sel widened 2→3 bits; WB_CSR = 3'b100 added
//    • New outputs: is_csr, is_ecall, is_ebreak, is_mret
// ============================================================

module control (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic       funct7_5,     // inst[30]
    input  logic       funct7_1,     // inst[25]
    input  logic       instr_20,     // inst[20] — ECALL vs EBREAK
    input  logic       instr_28,     // inst[28] — MRET detect

    output logic        reg_write,
    output logic        alu_src,
    output logic [4:0]  alu_op,
    output logic        mem_write,
    output logic [2:0]  mem_funct3,
    output logic [2:0]  wb_sel,      // WIDENED: 2→3 bits
    output logic        branch,
    output logic        jump,
    output logic        jalr,
    output logic [2:0]  imm_sel,
    output logic        auipc_op,
    // ── New Step 18 outputs ──────────────────────────────────
    output logic        is_csr,      // CSR read/write instruction
    output logic        is_ecall,    // ECALL
    output logic        is_ebreak,   // EBREAK
    output logic        is_mret      // MRET
);

// ─────────────────────────────────────────────────────────────
//  Opcode Constants
// ─────────────────────────────────────────────────────────────
localparam [6:0]
    OP_R      = 7'b011_0011,
    OP_I_ALU  = 7'b001_0011,
    OP_LOAD   = 7'b000_0011,
    OP_STORE  = 7'b010_0011,
    OP_BRANCH = 7'b110_0011,
    OP_JAL    = 7'b110_1111,
    OP_JALR   = 7'b110_0111,
    OP_LUI    = 7'b011_0111,
    OP_AUIPC  = 7'b001_0111,
    OP_FENCE  = 7'b000_1111,
    OP_SYSTEM = 7'b111_0011;

// ─────────────────────────────────────────────────────────────
//  ALU Operation Codes
// ─────────────────────────────────────────────────────────────
localparam [4:0]
    ALU_ADD  = 5'd0,
    ALU_SUB  = 5'd1,
    ALU_AND  = 5'd2,
    ALU_OR   = 5'd3,
    ALU_XOR  = 5'd4,
    ALU_SLL  = 5'd5,
    ALU_SRL  = 5'd6,
    ALU_SRA  = 5'd7,
    ALU_SLT  = 5'd8,
    ALU_SLTU = 5'd9;

// ─────────────────────────────────────────────────────────────
//  Immediate Format Codes
// ─────────────────────────────────────────────────────────────
localparam [2:0]
    IMM_I = 3'd0,
    IMM_S = 3'd1,
    IMM_B = 3'd2,
    IMM_U = 3'd3,
    IMM_J = 3'd4;

// ─────────────────────────────────────────────────────────────
//  Writeback Mux Select  (3-bit from Step 18)
// ─────────────────────────────────────────────────────────────
localparam [2:0]
    WB_ALU = 3'b000,
    WB_MEM = 3'b001,
    WB_PC4 = 3'b010,
    WB_IMM = 3'b011,
    WB_CSR = 3'b100;   // NEW: CSR read data

// ─────────────────────────────────────────────────────────────
//  Decode Logic
// ─────────────────────────────────────────────────────────────
always_comb begin : decode

    // ── Safe defaults (NOP) ──────────────────────────────────
    reg_write  = 1'b0;
    alu_src    = 1'b0;
    alu_op     = ALU_ADD;
    mem_write  = 1'b0;
    mem_funct3 = funct3;
    wb_sel     = WB_ALU;
    branch     = 1'b0;
    jump       = 1'b0;
    jalr       = 1'b0;
    imm_sel    = IMM_I;
    auipc_op   = 1'b0;
    is_csr     = 1'b0;
    is_ecall   = 1'b0;
    is_ebreak  = 1'b0;
    is_mret    = 1'b0;

    unique case (opcode)

        // ── R-type (RV32I) + M-Extension ─────────────────────
        OP_R: begin
            reg_write = 1'b1;
            wb_sel    = WB_ALU;
            if (funct7_1) begin
                alu_op = {2'b10, funct3};
            end else begin
                unique case (funct3)
                    3'b000: alu_op = funct7_5 ? ALU_SUB : ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7_5 ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end
        end

        // ── I-type ALU ────────────────────────────────────────
        OP_I_ALU: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            wb_sel    = WB_ALU;
            imm_sel   = IMM_I;
            unique case (funct3)
                3'b000: alu_op = ALU_ADD;
                3'b001: alu_op = ALU_SLL;
                3'b010: alu_op = ALU_SLT;
                3'b011: alu_op = ALU_SLTU;
                3'b100: alu_op = ALU_XOR;
                3'b101: alu_op = funct7_5 ? ALU_SRA : ALU_SRL;
                3'b110: alu_op = ALU_OR;
                3'b111: alu_op = ALU_AND;
                default: alu_op = ALU_ADD;
            endcase
        end

        // ── Loads ─────────────────────────────────────────────
        OP_LOAD: begin
            reg_write  = 1'b1;
            alu_src    = 1'b1;
            alu_op     = ALU_ADD;
            wb_sel     = WB_MEM;
            imm_sel    = IMM_I;
            mem_funct3 = funct3;
        end

        // ── Stores ────────────────────────────────────────────
        OP_STORE: begin
            alu_src    = 1'b1;
            alu_op     = ALU_ADD;
            mem_write  = 1'b1;
            imm_sel    = IMM_S;
            mem_funct3 = funct3;
        end

        // ── Branches ──────────────────────────────────────────
        OP_BRANCH: begin
            branch  = 1'b1;
            imm_sel = IMM_B;
        end

        // ── JAL ───────────────────────────────────────────────
        OP_JAL: begin
            reg_write = 1'b1;
            jump      = 1'b1;
            wb_sel    = WB_PC4;
            imm_sel   = IMM_J;
        end

        // ── JALR ──────────────────────────────────────────────
        OP_JALR: begin
            reg_write = 1'b1;
            jalr      = 1'b1;
            alu_src   = 1'b1;
            alu_op    = ALU_ADD;
            wb_sel    = WB_PC4;
            imm_sel   = IMM_I;
        end

        // ── LUI ───────────────────────────────────────────────
        OP_LUI: begin
            reg_write = 1'b1;
            wb_sel    = WB_IMM;
            imm_sel   = IMM_U;
        end

        // ── AUIPC ─────────────────────────────────────────────
        OP_AUIPC: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            alu_op    = ALU_ADD;
            wb_sel    = WB_ALU;
            imm_sel   = IMM_U;
            auipc_op  = 1'b1;
        end

        // ── FENCE — NOP ───────────────────────────────────────
        OP_FENCE: begin /* defaults = NOP */ end

        // ── SYSTEM: CSR / ECALL / EBREAK / MRET ──────────────
        OP_SYSTEM: begin
            if (funct3 != 3'b000) begin
                // ── CSR instructions ─────────────────────────
                is_csr    = 1'b1;
                reg_write = 1'b1;   // rd ← old CSR value
                wb_sel    = WB_CSR;
            end else begin
                // ── Privileged instructions ───────────────────
                // MRET:   instr[28]=1 (funct7[3]=1, encoding 0011000_00010_00000_000_00000)
                // EBREAK: instr[20]=1, instr[28]=0
                // ECALL:  instr[20]=0, instr[28]=0
                if (instr_28)       is_mret   = 1'b1;
                else if (instr_20)  is_ebreak = 1'b1;
                else                is_ecall  = 1'b1;
            end
        end

        default: begin /* illegal opcode - NOP */ end

    endcase
end : decode

endmodule
