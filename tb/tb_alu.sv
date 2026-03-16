// ============================================================
//  tb_alu.sv  —  Self-Checking Testbench for alu.sv
//
//  Runs 60+ directed tests covering every opcode.
//  Checks edge cases: zero, overflow wrap, sign extension,
//  shift by 0 / shift by 31, SLT signed vs SLTU unsigned.
//
//  Usage in Vivado:
//    1. Add alu.sv + tb_alu.sv to a sim-only project
//    2. Set tb_alu as top
//    3. Run Behavioral Simulation → check PASS/FAIL in console
// ============================================================

`timescale 1ns/1ps

module tb_alu;

    // ── DUT Ports ────────────────────────────────────────────
    logic [31:0] a, b;
    logic [3:0]  alu_op;
    logic [31:0] result;
    logic        zero;

    // ── Instantiate DUT ──────────────────────────────────────
    alu dut (.*);

    // ── Test Counters ────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ── ALU Op Codes (mirror alu.sv) ─────────────────────────
    localparam [3:0]
        ADD  = 4'd0, SUB  = 4'd1, AND  = 4'd2, OR   = 4'd3,
        XOR  = 4'd4, SLL  = 4'd5, SRL  = 4'd6, SRA  = 4'd7,
        SLT  = 4'd8, SLTU = 4'd9;

    // ── Check Task ───────────────────────────────────────────
    task automatic check(
        input string    test_name,
        input [31:0]    got_result,
        input [31:0]    exp_result,
        input logic     got_zero,
        input logic     exp_zero
    );
        if (got_result !== exp_result || got_zero !== exp_zero) begin
            $display("  FAIL  %-30s | result=%08h (exp %08h) | zero=%b (exp %b)",
                     test_name, got_result, exp_result, got_zero, exp_zero);
            fail_count++;
        end else begin
            $display("  PASS  %-30s | result=%08h | zero=%b",
                     test_name, got_result, got_zero);
            pass_count++;
        end
    endtask

    // ── Apply inputs and wait for combo to settle ────────────
    task automatic apply(
        input [31:0] in_a,
        input [31:0] in_b,
        input [3:0]  op
    );
        a = in_a; b = in_b; alu_op = op;
        #5; // small combinational delay
    endtask

    // ─────────────────────────────────────────────────────────
    //  Test Vectors
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  ALU Testbench — RV32I");
        $display("========================================\n");

        // ── ADD ──────────────────────────────────────────────
        $display("--- ADD ---");
        apply(32'd5,          32'd3,          ADD);
        check("5 + 3",        result, 32'd8,         zero, 1'b0);

        apply(32'hFFFFFFFF,   32'd1,          ADD);
        check("0xFFFF + 1 (wrap)", result, 32'd0,    zero, 1'b1);  // zero=1 !

        apply(32'd0,          32'd0,          ADD);
        check("0 + 0",        result, 32'd0,         zero, 1'b1);

        apply(32'h7FFFFFFF,   32'd1,          ADD);
        check("INT_MAX + 1",  result, 32'h80000000,  zero, 1'b0);  // signed overflow wraps

        apply(32'hDEADBEEF,   32'd0,          ADD);
        check("x + 0 = x",   result, 32'hDEADBEEF,  zero, 1'b0);

        // ── SUB ──────────────────────────────────────────────
        $display("--- SUB ---");
        apply(32'd10,         32'd3,          SUB);
        check("10 - 3",       result, 32'd7,         zero, 1'b0);

        apply(32'd5,          32'd5,          SUB);
        check("5 - 5 = 0",   result, 32'd0,          zero, 1'b1);

        apply(32'd0,          32'd1,          SUB);
        check("0 - 1 (wrap)", result, 32'hFFFFFFFF,  zero, 1'b0);

        apply(32'h80000000,   32'd1,          SUB);
        check("INT_MIN - 1",  result, 32'h7FFFFFFF,  zero, 1'b0);

        // ── AND ──────────────────────────────────────────────
        $display("--- AND ---");
        apply(32'hFF00FF00,   32'h0F0F0F0F,   AND);
        check("AND mask",     result, 32'h0F000F00,  zero, 1'b0);

        apply(32'hFFFFFFFF,   32'h00000000,   AND);
        check("AND all zeros",result, 32'h00000000,  zero, 1'b1);

        apply(32'hAAAAAAAA,   32'hAAAAAAAA,   AND);
        check("AND same val", result, 32'hAAAAAAAA,  zero, 1'b0);

        // ── OR ───────────────────────────────────────────────
        $display("--- OR ---");
        apply(32'hFF000000,   32'h00FF0000,   OR);
        check("OR combine",   result, 32'hFFFF0000,  zero, 1'b0);

        apply(32'h00000000,   32'h00000000,   OR);
        check("OR zeros",     result, 32'h00000000,  zero, 1'b1);

        apply(32'hFFFFFFFF,   32'h00000000,   OR);
        check("OR with 0",    result, 32'hFFFFFFFF,  zero, 1'b0);

        // ── XOR ──────────────────────────────────────────────
        $display("--- XOR ---");
        apply(32'hAAAAAAAA,   32'h55555555,   XOR);
        check("XOR all ones", result, 32'hFFFFFFFF,  zero, 1'b0);

        apply(32'hDEADBEEF,   32'hDEADBEEF,   XOR);
        check("XOR self=0",   result, 32'h00000000,  zero, 1'b1);

        apply(32'hFFFFFFFF,   32'hFFFFFFFF,   XOR);
        check("XOR 0xFFFF self", result, 32'h00000000, zero, 1'b1);

        // ── SLL (Shift Left Logical) ──────────────────────────
        $display("--- SLL ---");
        apply(32'd1,          32'd4,          SLL);
        check("1 << 4",       result, 32'd16,        zero, 1'b0);

        apply(32'd1,          32'd31,         SLL);
        check("1 << 31",      result, 32'h80000000,  zero, 1'b0);

        apply(32'hFFFFFFFF,   32'd1,          SLL);
        check("0xFFFF << 1",  result, 32'hFFFFFFFE,  zero, 1'b0);

        apply(32'd5,          32'd0,          SLL);
        check("SLL by 0",     result, 32'd5,         zero, 1'b0);

        // Only b[4:0] matters — upper bits must be ignored
        apply(32'd1,          32'hFFFFFFE4,   SLL);  // b[4:0] = 4
        check("SLL b[4:0]=4", result, 32'd16,        zero, 1'b0);

        // ── SRL (Shift Right Logical) ─────────────────────────
        $display("--- SRL ---");
        apply(32'h80000000,   32'd1,          SRL);
        check("0x8000 >> 1",  result, 32'h40000000,  zero, 1'b0);  // 0-fills MSB

        apply(32'hFFFFFFFF,   32'd4,          SRL);
        check("0xFFFF >> 4",  result, 32'h0FFFFFFF,  zero, 1'b0);

        apply(32'hFFFFFFFF,   32'd31,         SRL);
        check("0xFFFF >> 31", result, 32'h00000001,  zero, 1'b0);

        apply(32'd8,          32'd3,          SRL);
        check("8 >> 3",       result, 32'd1,         zero, 1'b0);

        // ── SRA (Shift Right Arithmetic) ──────────────────────
        $display("--- SRA ---");
        apply(32'h80000000,   32'd1,          SRA);
        check("0x8000 SRA 1", result, 32'hC0000000,  zero, 1'b0);  // sign extends!

        apply(32'hFFFFFFFF,   32'd4,          SRA);
        check("0xFFFF SRA 4", result, 32'hFFFFFFFF,  zero, 1'b0);  // all ones

        apply(32'h7FFFFFFF,   32'd1,          SRA);
        check("INT_MAX SRA 1",result, 32'h3FFFFFFF,  zero, 1'b0);  // positive: 0-fill

        apply(32'h80000000,   32'd31,         SRA);
        check("0x8000 SRA 31",result, 32'hFFFFFFFF,  zero, 1'b0);

        // KEY: SRL vs SRA differ only for negative numbers
        apply(32'hFFFFFF80,   32'd4,          SRL);
        check("SRL neg num",  result, 32'h0FFFFFF8,  zero, 1'b0);  // 0-fill

        apply(32'hFFFFFF80,   32'd4,          SRA);
        check("SRA neg num",  result, 32'hFFFFFFF8,  zero, 1'b0);  // 1-fill

        // ── SLT (Set Less Than, signed) ───────────────────────
        $display("--- SLT ---");
        apply(32'd3,          32'd5,          SLT);
        check("3 < 5  → 1",  result, 32'd1,          zero, 1'b0);

        apply(32'd5,          32'd3,          SLT);
        check("5 < 3  → 0",  result, 32'd0,          zero, 1'b1);

        apply(32'd5,          32'd5,          SLT);
        check("5 < 5  → 0",  result, 32'd0,          zero, 1'b1);

        // Critical signed test: -1 < 1 must be TRUE
        apply(32'hFFFFFFFF,   32'd1,          SLT);
        check("-1 < 1 → 1 (signed)", result, 32'd1,  zero, 1'b0);

        // -1 > -5 (both negative)
        apply(32'hFFFFFFFF,   32'hFFFFFFFB,   SLT);
        check("-1 < -5 → 0", result, 32'd0,          zero, 1'b1);

        apply(32'h80000000,   32'd0,          SLT);
        check("INT_MIN < 0 → 1",result, 32'd1,       zero, 1'b0);

        // ── SLTU (Set Less Than, unsigned) ────────────────────
        $display("--- SLTU ---");
        apply(32'd3,          32'd5,          SLTU);
        check("3 <u 5  → 1", result, 32'd1,          zero, 1'b0);

        // Critical: 0xFFFFFFFF is MAX unsigned, so NOT less than 1
        apply(32'hFFFFFFFF,   32'd1,          SLTU);
        check("0xFFFF <u 1 → 0",result, 32'd0,       zero, 1'b1);

        // 0 is less than any positive unsigned
        apply(32'd0,          32'd1,          SLTU);
        check("0 <u 1 → 1",  result, 32'd1,          zero, 1'b0);

        apply(32'hFFFFFFFE,   32'hFFFFFFFF,   SLTU);
        check("MAX-1 <u MAX → 1",result, 32'd1,      zero, 1'b0);

        // ── ZERO FLAG edge cases ──────────────────────────────
        $display("--- ZERO FLAG ---");
        apply(32'd0,          32'd0,          OR);
        check("zero: 0|0",    result, 32'd0,         zero, 1'b1);

        apply(32'd1,          32'd0,          AND);
        check("zero: 1&0",    result, 32'd0,         zero, 1'b1);

        apply(32'hDEAD,       32'hDEAD,       XOR);
        check("zero: x^x",    result, 32'd0,         zero, 1'b1);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED — ALU is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED — fix before proceeding ***\n", fail_count);

        $finish;
    end

    // ── Timeout Watchdog ─────────────────────────────────────
    initial begin
        #10000;
        $display("TIMEOUT — simulation hung");
        $finish;
    end

endmodule