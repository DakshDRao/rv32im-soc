// ============================================================
//  tb_branch_unit.sv  -  Self-Checking Testbench
//                        for branch_unit.sv
//
//  Test groups:
//    A. BEQ  - equal / not equal
//    B. BNE  - not equal / equal
//    C. BLT  - signed less-than, including negative numbers
//    D. BGE  - signed greater-or-equal, boundary cases
//    E. BLTU - unsigned less-than (0xFFFFFFFF is MAX, not -1)
//    F. BGEU - unsigned greater-or-equal
//    G. branch=0 gate - condition true but branch=0 → never taken
//    H. Signed vs Unsigned contrast - the critical difference
//    I. Boundary: rs1==rs2 for all six conditions
// ============================================================

`timescale 1ns/1ps

module tb_branch_unit;

    // ── DUT Ports ─────────────────────────────────────────────
    logic [31:0] rs1, rs2;
    logic [2:0]  funct3;
    logic        branch;
    logic        branch_taken;

    // ── DUT ───────────────────────────────────────────────────
    branch_unit dut (.*);

    // ── Counters ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ── funct3 codes ──────────────────────────────────────────
    localparam [2:0]
        BEQ=3'b000, BNE=3'b001,
        BLT=3'b100, BGE=3'b101,
        BLTU=3'b110, BGEU=3'b111;

    // ─────────────────────────────────────────────────────────
    //  Tasks
    // ─────────────────────────────────────────────────────────
    task automatic check(
        input string test_name,
        input logic  got,
        input logic  exp
    );
        if (got !== exp) begin
            $display("  FAIL  %-50s | got=%b  exp=%b", test_name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-50s | taken=%b", test_name, got);
            pass_count++;
        end
    endtask

    task automatic apply(
        input [31:0] a, b,
        input [2:0]  f3,
        input        br
    );
        rs1 = a; rs2 = b; funct3 = f3; branch = br;
        #2;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  Branch Unit Testbench - RV32I");
        $display("========================================\n");

        // ══════════════════════════════════════════════════════
        //  A. BEQ  (branch_taken = 1 when rs1 == rs2)
        // ══════════════════════════════════════════════════════
        $display("--- A: BEQ ---");

        apply(32'd5,         32'd5,         BEQ, 1);
        check("BEQ: 5 == 5              → taken",    branch_taken, 1'b1);

        apply(32'd5,         32'd6,         BEQ, 1);
        check("BEQ: 5 == 6              → not taken",branch_taken, 1'b0);

        apply(32'hFFFFFFFF,  32'hFFFFFFFF,  BEQ, 1);
        check("BEQ: 0xFFFF == 0xFFFF    → taken",    branch_taken, 1'b1);

        apply(32'd0,         32'd0,         BEQ, 1);
        check("BEQ: 0 == 0              → taken",    branch_taken, 1'b1);

        apply(32'd0,         32'd1,         BEQ, 1);
        check("BEQ: 0 == 1              → not taken",branch_taken, 1'b0);

        // ══════════════════════════════════════════════════════
        //  B. BNE  (branch_taken = 1 when rs1 != rs2)
        // ══════════════════════════════════════════════════════
        $display("\n--- B: BNE ---");

        apply(32'd5,         32'd6,         BNE, 1);
        check("BNE: 5 != 6              → taken",    branch_taken, 1'b1);

        apply(32'd5,         32'd5,         BNE, 1);
        check("BNE: 5 != 5              → not taken",branch_taken, 1'b0);

        apply(32'd0,         32'd1,         BNE, 1);
        check("BNE: 0 != 1              → taken",    branch_taken, 1'b1);

        apply(32'hDEADBEEF,  32'hDEADBEEF, BNE, 1);
        check("BNE: 0xDEAD != 0xDEAD   → not taken",branch_taken, 1'b0);

        // ══════════════════════════════════════════════════════
        //  C. BLT  - signed less-than
        //  KEY: negative numbers (MSB=1) are less than positives
        // ══════════════════════════════════════════════════════
        $display("\n--- C: BLT (signed) ---");

        apply(32'd3,         32'd5,         BLT, 1);
        check("BLT:  3 <  5             → taken",    branch_taken, 1'b1);

        apply(32'd5,         32'd3,         BLT, 1);
        check("BLT:  5 <  3             → not taken",branch_taken, 1'b0);

        apply(32'd5,         32'd5,         BLT, 1);
        check("BLT:  5 <  5             → not taken",branch_taken, 1'b0);

        // -1 < 1 must be TRUE (signed)
        apply(32'hFFFFFFFF,  32'd1,         BLT, 1);
        check("BLT: -1 <  1             → taken",    branch_taken, 1'b1);

        // -5 < -1 must be TRUE
        apply(32'hFFFFFFFB,  32'hFFFFFFFF,  BLT, 1);
        check("BLT: -5 <  -1            → taken",    branch_taken, 1'b1);

        // -1 < -5 must be FALSE
        apply(32'hFFFFFFFF,  32'hFFFFFFFB,  BLT, 1);
        check("BLT: -1 <  -5            → not taken",branch_taken, 1'b0);

        // INT_MIN < 0 must be TRUE
        apply(32'h80000000,  32'd0,         BLT, 1);
        check("BLT: INT_MIN < 0         → taken",    branch_taken, 1'b1);

        // ══════════════════════════════════════════════════════
        //  D. BGE  - signed greater-or-equal
        //  BGE is exactly NOT(BLT) - tests the ~ inversion
        // ══════════════════════════════════════════════════════
        $display("\n--- D: BGE (signed) ---");

        apply(32'd5,         32'd3,         BGE, 1);
        check("BGE:  5 >= 3             → taken",    branch_taken, 1'b1);

        apply(32'd5,         32'd5,         BGE, 1);
        check("BGE:  5 >= 5             → taken",    branch_taken, 1'b1);

        apply(32'd3,         32'd5,         BGE, 1);
        check("BGE:  3 >= 5             → not taken",branch_taken, 1'b0);

        // 1 >= -1 must be TRUE (signed)
        apply(32'd1,         32'hFFFFFFFF,  BGE, 1);
        check("BGE:  1 >= -1            → taken",    branch_taken, 1'b1);

        // -1 >= -1 must be TRUE
        apply(32'hFFFFFFFF,  32'hFFFFFFFF,  BGE, 1);
        check("BGE: -1 >= -1            → taken",    branch_taken, 1'b1);

        // -1 >= 0 must be FALSE
        apply(32'hFFFFFFFF,  32'd0,         BGE, 1);
        check("BGE: -1 >= 0             → not taken",branch_taken, 1'b0);

        // ══════════════════════════════════════════════════════
        //  E. BLTU  - unsigned less-than
        //  0xFFFFFFFF is MAX unsigned, NOT negative
        // ══════════════════════════════════════════════════════
        $display("\n--- E: BLTU (unsigned) ---");

        apply(32'd3,         32'd5,         BLTU, 1);
        check("BLTU: 3 <u 5             → taken",    branch_taken, 1'b1);

        apply(32'd5,         32'd3,         BLTU, 1);
        check("BLTU: 5 <u 3             → not taken",branch_taken, 1'b0);

        // 0xFFFFFFFF is UINT_MAX - NOT less than 1
        apply(32'hFFFFFFFF,  32'd1,         BLTU, 1);
        check("BLTU: UINT_MAX <u 1      → not taken",branch_taken, 1'b0);

        // 1 <u 0xFFFFFFFF must be TRUE
        apply(32'd1,         32'hFFFFFFFF,  BLTU, 1);
        check("BLTU: 1 <u UINT_MAX      → taken",    branch_taken, 1'b1);

        apply(32'd0,         32'hFFFFFFFF,  BLTU, 1);
        check("BLTU: 0 <u UINT_MAX      → taken",    branch_taken, 1'b1);

        // ══════════════════════════════════════════════════════
        //  F. BGEU  - unsigned greater-or-equal
        // ══════════════════════════════════════════════════════
        $display("\n--- F: BGEU (unsigned) ---");

        apply(32'd5,         32'd3,         BGEU, 1);
        check("BGEU: 5 >=u 3            → taken",    branch_taken, 1'b1);

        apply(32'd5,         32'd5,         BGEU, 1);
        check("BGEU: 5 >=u 5            → taken",    branch_taken, 1'b1);

        apply(32'd3,         32'd5,         BGEU, 1);
        check("BGEU: 3 >=u 5            → not taken",branch_taken, 1'b0);

        // 0xFFFFFFFF >=u 1 must be TRUE (it's UINT_MAX)
        apply(32'hFFFFFFFF,  32'd1,         BGEU, 1);
        check("BGEU: UINT_MAX >=u 1     → taken",    branch_taken, 1'b1);

        apply(32'd0,         32'd0,         BGEU, 1);
        check("BGEU: 0 >=u 0            → taken",    branch_taken, 1'b1);

        // ══════════════════════════════════════════════════════
        //  G. branch=0 gate
        //  Condition may be true, but branch=0 must force
        //  branch_taken=0. This is the control signal gate.
        // ══════════════════════════════════════════════════════
        $display("\n--- G: branch=0 gate (never taken) ---");

        apply(32'd5,         32'd5,         BEQ, 0);
        check("BEQ true  but branch=0   → not taken",branch_taken, 1'b0);

        apply(32'd3,         32'd5,         BLT, 0);
        check("BLT true  but branch=0   → not taken",branch_taken, 1'b0);

        apply(32'hFFFFFFFF,  32'd1,         BLT, 0);
        check("BLT(-1<1) but branch=0   → not taken",branch_taken, 1'b0);

        apply(32'd1,         32'hFFFFFFFF,  BLTU,0);
        check("BLTU true but branch=0   → not taken",branch_taken, 1'b0);

        // ══════════════════════════════════════════════════════
        //  H. Signed vs Unsigned contrast
        //  SAME operands, DIFFERENT result depending on BLT/BLTU
        //  This is the most important correctness check.
        // ══════════════════════════════════════════════════════
        $display("\n--- H: Signed vs Unsigned contrast ---");

        // rs1=0xFFFFFFFF, rs2=0x00000001
        //   Signed:   rs1 = -1  → -1 < 1   → BLT  taken
        //   Unsigned: rs1 = UINT_MAX → not < 1 → BLTU NOT taken
        apply(32'hFFFFFFFF,  32'd1,         BLT,  1);
        check("BLT : 0xFFFF vs 1 (signed -1 < 1)  → taken",    branch_taken, 1'b1);

        apply(32'hFFFFFFFF,  32'd1,         BLTU, 1);
        check("BLTU: 0xFFFF vs 1 (UINT_MAX < 1)   → not taken",branch_taken, 1'b0);

        // rs1=0x80000000, rs2=0x7FFFFFFF
        //   Signed:   rs1 = INT_MIN < INT_MAX → BLT  taken
        //   Unsigned: rs1 = 2147483648 > 2147483647 → BLTU NOT taken
        apply(32'h80000000,  32'h7FFFFFFF,  BLT,  1);
        check("BLT : INT_MIN < INT_MAX (signed)    → taken",    branch_taken, 1'b1);

        apply(32'h80000000,  32'h7FFFFFFF,  BLTU, 1);
        check("BLTU: 0x8000 <u 0x7FFF (unsigned)  → not taken",branch_taken, 1'b0);

        // ══════════════════════════════════════════════════════
        //  I. Boundary: rs1 == rs2 for all six conditions
        // ══════════════════════════════════════════════════════
        $display("\n--- I: rs1 == rs2 boundary ---");

        apply(32'd42, 32'd42, BEQ,  1); check("BEQ  equal boundary → taken",    branch_taken, 1'b1);
        apply(32'd42, 32'd42, BNE,  1); check("BNE  equal boundary → not taken",branch_taken, 1'b0);
        apply(32'd42, 32'd42, BLT,  1); check("BLT  equal boundary → not taken",branch_taken, 1'b0);
        apply(32'd42, 32'd42, BGE,  1); check("BGE  equal boundary → taken",    branch_taken, 1'b1);
        apply(32'd42, 32'd42, BLTU, 1); check("BLTU equal boundary → not taken",branch_taken, 1'b0);
        apply(32'd42, 32'd42, BGEU, 1); check("BGEU equal boundary → taken",    branch_taken, 1'b1);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - Branch Unit is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule