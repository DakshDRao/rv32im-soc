// ============================================================
//  tb_imm_gen.sv  -  Self-Checking Testbench for imm_gen.sv
//
//  Strategy: build REAL hand-encoded RISC-V instructions,
//  feed them in, and verify the extracted immediate matches
//  what an assembler would produce.
//
//  Test groups:
//    A. I-type  - positive, negative, zero, max, min
//    B. S-type  - verify split-field reassembly
//    C. B-type  - verify scattered bits incl. bit11 in inst[7]
//    D. U-type  - upper 20 bits, lower 12 zeroed
//    E. J-type  - verify scattered bits incl. bit11 in inst[20]
//    F. Sign extension - all formats sign-extend from inst[31]
//    G. imm[0]=0 enforced - B and J always even
// ============================================================

`timescale 1ns/1ps

module tb_imm_gen;

    // ── DUT Ports ─────────────────────────────────────────────
    logic [31:0] instr;
    logic [2:0]  imm_sel;
    logic [31:0] imm;

    // ── DUT ───────────────────────────────────────────────────
    imm_gen dut (.*);

    // ── Counters ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ── Format Select Codes ───────────────────────────────────
    localparam IMM_I=3'd0, IMM_S=3'd1, IMM_B=3'd2,
               IMM_U=3'd3, IMM_J=3'd4;

    // ─────────────────────────────────────────────────────────
    //  Check Task
    // ─────────────────────────────────────────────────────────
    task automatic check(
        input string   test_name,
        input [31:0]   got,
        input [31:0]   exp
    );
        if (got !== exp) begin
            $display("  FAIL  %-42s | got=%08h  exp=%08h", test_name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-42s | %08h", test_name, got);
            pass_count++;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    //  Instruction Encoders
    //  Build real machine-code words so we can cross-check
    //  against a known-good assembler encoding.
    // ─────────────────────────────────────────────────────────

    // I-type: ADDI rd, rs1, imm12
    function automatic [31:0] enc_I(
        input [11:0] imm12,
        input [4:0]  rs1,
        input [2:0]  funct3,
        input [4:0]  rd,
        input [6:0]  opcode
    );
        enc_I = { imm12, rs1, funct3, rd, opcode };
    endfunction

    // S-type: SW rs2, imm12(rs1)
    function automatic [31:0] enc_S(
        input [11:0] imm12,
        input [4:0]  rs2,
        input [4:0]  rs1,
        input [2:0]  funct3,
        input [6:0]  opcode
    );
        enc_S = { imm12[11:5], rs2, rs1, funct3, imm12[4:0], opcode };
    endfunction

    // B-type: BEQ rs1, rs2, imm13  (imm13[0] must be 0)
    function automatic [31:0] enc_B(
        input [12:0] imm13,   // pass full 13-bit offset, bit0 ignored
        input [4:0]  rs1,
        input [4:0]  rs2,
        input [2:0]  funct3,
        input [6:0]  opcode
    );
        enc_B = { imm13[12], imm13[10:5],
                  rs2, rs1, funct3,
                  imm13[4:1], imm13[11],
                  opcode };
    endfunction

    // U-type: LUI rd, imm20
    function automatic [31:0] enc_U(
        input [19:0] imm20,
        input [4:0]  rd,
        input [6:0]  opcode
    );
        enc_U = { imm20, rd, opcode };
    endfunction

    // J-type: JAL rd, imm21  (imm21[0] must be 0)
    function automatic [31:0] enc_J(
        input [20:0] imm21,
        input [4:0]  rd,
        input [6:0]  opcode
    );
        enc_J = { imm21[20], imm21[10:1], imm21[11],
                  imm21[19:12], rd, opcode };
    endfunction

    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  ImmGen Testbench - RV32I");
        $display("========================================\n");

        // ══════════════════════════════════════════════════════
        //  A. I-TYPE
        //     ADDI x1, x0, <imm>  opcode=0010011 funct3=000
        // ══════════════════════════════════════════════════════
        $display("--- A: I-type ---");

        // ADDI x1, x0, 1   → imm = 1
        instr = enc_I(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: imm = +1",          imm, 32'd1);

        // ADDI x1, x0, 2047  → imm = 2047 (max positive 12-bit)
        instr = enc_I(12'd2047, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: imm = +2047 (max)", imm, 32'd2047);

        // ADDI x1, x0, 0   → imm = 0
        instr = enc_I(12'd0, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: imm = 0",           imm, 32'd0);

        // ADDI x1, x0, -1  (12'hFFF) → sign-extended → 0xFFFFFFFF
        instr = enc_I(12'hFFF, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: imm = -1 (0xFFF)",  imm, 32'hFFFFFFFF);

        // ADDI x1, x0, -2048  (12'h800) → sign-extended → 0xFFFFF800
        instr = enc_I(12'h800, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: imm = -2048 (min)", imm, 32'hFFFFF800);

        // ADDI x1, x0, 100
        instr = enc_I(12'd100, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: imm = +100",        imm, 32'd100);

        // ══════════════════════════════════════════════════════
        //  B. S-TYPE
        //     SW x2, <imm>(x1)  opcode=0100011 funct3=010
        //     Immediate is SPLIT: inst[31:25]=imm[11:5]
        //                          inst[11:7] =imm[4:0]
        // ══════════════════════════════════════════════════════
        $display("--- B: S-type ---");

        // SW x2, 4(x1)  → imm = 4
        instr = enc_S(12'd4, 5'd2, 5'd1, 3'b010, 7'b0100011);
        imm_sel = IMM_S; #1;
        check("S: imm = +4",          imm, 32'd4);

        // SW x2, 2047(x1) → imm = 2047
        instr = enc_S(12'd2047, 5'd2, 5'd1, 3'b010, 7'b0100011);
        imm_sel = IMM_S; #1;
        check("S: imm = +2047 (max)", imm, 32'd2047);

        // SW x2, -1(x1)  → imm = 0xFFFFFFFF
        instr = enc_S(12'hFFF, 5'd2, 5'd1, 3'b010, 7'b0100011);
        imm_sel = IMM_S; #1;
        check("S: imm = -1",          imm, 32'hFFFFFFFF);

        // SW x2, -4(x1) → 12'hFFC → 0xFFFFFFFC
        instr = enc_S(12'hFFC, 5'd2, 5'd1, 3'b010, 7'b0100011);
        imm_sel = IMM_S; #1;
        check("S: imm = -4",          imm, 32'hFFFFFFFC);

        // Verify split: imm=0b1000_0001_0001 = 12'h811
        // upper[11:5]=6'b100000, lower[4:0]=5'b10001
        instr = enc_S(12'h811, 5'd2, 5'd1, 3'b010, 7'b0100011);
        imm_sel = IMM_S; #1;
        check("S: imm split field 0x811", imm, 32'hFFFFF811); // sign-ext negative

        // ══════════════════════════════════════════════════════
        //  C. B-TYPE
        //     BEQ x1, x2, <offset>  opcode=1100011 funct3=000
        //     Most scrambled format - bit11 lives in inst[7]!
        // ══════════════════════════════════════════════════════
        $display("--- C: B-type ---");

        // BEQ +8  (offset = 8 = 13'b0_000_0000_1000)
        instr = enc_B(13'd8, 5'd1, 5'd2, 3'b000, 7'b1100011);
        imm_sel = IMM_B; #1;
        check("B: offset = +8",       imm, 32'd8);

        // BEQ +4094 (max positive even offset for 13-bit)
        instr = enc_B(13'd4094, 5'd1, 5'd2, 3'b000, 7'b1100011);
        imm_sel = IMM_B; #1;
        check("B: offset = +4094",    imm, 32'd4094);

        // BEQ -2  (13'h1FFE) → sign-ext → 0xFFFFFFFE
        instr = enc_B(13'h1FFE, 5'd1, 5'd2, 3'b000, 7'b1100011);
        imm_sel = IMM_B; #1;
        check("B: offset = -2",       imm, 32'hFFFFFFFE);

        // Test that bit11 is correctly pulled from inst[7]
        // offset = 13'b0_1000_0000_0000 = 12'h800 = 2048
        // This puts a 1 in imm[11], which lives in inst[7]
        instr = enc_B(13'h0800, 5'd1, 5'd2, 3'b000, 7'b1100011);
        imm_sel = IMM_B; #1;
        check("B: bit11 in inst[7] = 2048", imm, 32'd2048);

        // Verify imm[0] is always 0 (instructions 2-byte aligned)
        instr = enc_B(13'd10, 5'd1, 5'd2, 3'b000, 7'b1100011);
        imm_sel = IMM_B; #1;
        check("B: imm[0] always 0",   imm[0], 1'b0);

        // ══════════════════════════════════════════════════════
        //  D. U-TYPE
        //     LUI x1, <imm20>  opcode=0110111
        //     Upper 20 bits placed, lower 12 zeroed
        // ══════════════════════════════════════════════════════
        $display("--- D: U-type ---");

        // LUI x1, 1 → imm = 0x00001000
        instr = enc_U(20'd1, 5'd1, 7'b0110111);
        imm_sel = IMM_U; #1;
        check("U: imm20=1 → 0x00001000", imm, 32'h00001000);

        // LUI x1, 0xABCDE → imm = 0xABCDE000
        instr = enc_U(20'hABCDE, 5'd1, 7'b0110111);
        imm_sel = IMM_U; #1;
        check("U: imm20=0xABCDE",     imm, 32'hABCDE000);

        // LUI x1, 0xFFFFF → imm = 0xFFFFF000
        instr = enc_U(20'hFFFFF, 5'd1, 7'b0110111);
        imm_sel = IMM_U; #1;
        check("U: max imm20",         imm, 32'hFFFFF000);

        // LUI x1, 0 → imm = 0
        instr = enc_U(20'd0, 5'd1, 7'b0110111);
        imm_sel = IMM_U; #1;
        check("U: imm20=0",           imm, 32'h00000000);

        // Verify lower 12 bits are always 0
        instr = enc_U(20'hABCDE, 5'd1, 7'b0110111);
        imm_sel = IMM_U; #1;
        check("U: lower 12 bits = 0", imm[11:0], 12'h000);

        // ══════════════════════════════════════════════════════
        //  E. J-TYPE
        //     JAL x1, <offset>  opcode=1101111
        //     Second most scrambled - bit11 lives in inst[20]!
        // ══════════════════════════════════════════════════════
        $display("--- E: J-type ---");

        // JAL x1, 4  → imm = 4
        instr = enc_J(21'd4, 5'd1, 7'b1101111);
        imm_sel = IMM_J; #1;
        check("J: offset = +4",       imm, 32'd4);

        // JAL x1, +1048574 (max positive 21-bit even)
        instr = enc_J(21'd1048574, 5'd1, 7'b1101111);
        imm_sel = IMM_J; #1;
        check("J: offset = +1048574", imm, 32'd1048574);

        // JAL x1, -2  → 21'h1FFFFE → sign-ext → 0xFFFFFFFE
        instr = enc_J(21'h1FFFFE, 5'd1, 7'b1101111);
        imm_sel = IMM_J; #1;
        check("J: offset = -2",       imm, 32'hFFFFFFFE);

        // Test bit11 in inst[20]  - offset = 21'h000800 = 2048
        instr = enc_J(21'h000800, 5'd1, 7'b1101111);
        imm_sel = IMM_J; #1;
        check("J: bit11 in inst[20] = 2048", imm, 32'd2048);

        // Verify imm[0] is always 0
        instr = enc_J(21'd20, 5'd1, 7'b1101111);
        imm_sel = IMM_J; #1;
        check("J: imm[0] always 0",   imm[0], 1'b0);

        // ══════════════════════════════════════════════════════
        //  F. SIGN EXTENSION - all formats
        // ══════════════════════════════════════════════════════
        $display("--- F: Sign extension (inst[31] propagates) ---");

        // I: inst[31]=1 → upper 20 bits all 1
        instr = enc_I(12'h800, 5'd0, 3'b000, 5'd1, 7'b0010011);
        imm_sel = IMM_I; #1;
        check("I: sign bit propagates", imm[31:12], 20'hFFFFF);

        // S: inst[31]=1 → upper 20 bits all 1
        instr = enc_S(12'h800, 5'd2, 5'd1, 3'b010, 7'b0100011);
        imm_sel = IMM_S; #1;
        check("S: sign bit propagates", imm[31:12], 20'hFFFFF);

        // B: inst[31]=1 → upper 19 bits all 1
        instr = enc_B(13'h1000, 5'd1, 5'd2, 3'b000, 7'b1100011);
        imm_sel = IMM_B; #1;
        check("B: sign bit propagates", imm[31:13], 19'h7FFFF);

        // J: inst[31]=1 → upper 11 bits all 1
        instr = enc_J(21'h100000, 5'd1, 7'b1101111);
        imm_sel = IMM_J; #1;
        check("J: sign bit propagates", imm[31:21], 11'h7FF);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - ImmGen is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule