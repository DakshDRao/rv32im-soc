// ============================================================
//  tb_mul_div.sv  -  Unit Testbench for mul_div  (RV32M)
//  Project : Single-Cycle RISC-V Core
//
//  Fix: check task directly reads 'result' signal after #2
//  settling delay, rather than capturing it by value at call
//  time (which was reading stale combinational output).
// ============================================================

`timescale 1ns/1ps

module tb_mul_div;

    logic [31:0] a, b, result;
    logic [2:0]  funct3;

    mul_div dut (.a(a), .b(b), .funct3(funct3), .result(result));

    // ── Helpers ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // result read directly (not passed by value) after settling
    task automatic check(input string name, input [31:0] exp);
        #2;
        if (result !== exp) begin
            $display("  FAIL  %-50s | got=%08h  exp=%08h", name, result, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-50s | %08h", name, result);
            pass_count++;
        end
    endtask

    // funct3 codes
    localparam [2:0]
        MUL    = 3'b000,
        MULH   = 3'b001,
        MULHSU = 3'b010,
        MULHU  = 3'b011,
        DIV    = 3'b100,
        DIVU   = 3'b101,
        REM    = 3'b110,
        REMU   = 3'b111;

    // Useful constants
    localparam [31:0]
        INT_MIN  = 32'h8000_0000,
        INT_MAX  = 32'h7FFF_FFFF,
        ALL_ONES = 32'hFFFF_FFFF;

    initial begin
        $display("\n========================================");
        $display("  RV32M mul_div Unit Testbench");
        $display("========================================\n");

        // ══════════════════════════════════════════════════
        //  MUL
        // ══════════════════════════════════════════════════
        $display("--- MUL ---");
        funct3 = MUL;

        a = 32'd3;    b = 32'd7;
        check("MUL  3 x 7 = 21",                  32'd21);

        a = 32'd100;  b = 32'd200;
        check("MUL  100 x 200 = 20000",            32'd20000);

        a = ALL_ONES; b = ALL_ONES;
        check("MUL  (-1) x (-1) = 1",              32'd1);

        a = ALL_ONES; b = 32'd1;
        check("MUL  (-1) x 1 = 0xFFFFFFFF",        ALL_ONES);

        a = INT_MIN;  b = 32'd2;
        check("MUL  INT_MIN x 2 = 0 (lower 32)",   32'd0);

        // ══════════════════════════════════════════════════
        //  MULH
        // ══════════════════════════════════════════════════
        $display("\n--- MULH ---");
        funct3 = MULH;

        a = 32'd3;    b = 32'd7;
        check("MULH  3 x 7  upper=0",              32'd0);

        a = ALL_ONES; b = ALL_ONES;
        check("MULH  (-1)x(-1) upper=0",           32'd0);

        a = ALL_ONES; b = 32'd1;
        check("MULH  (-1)x1 upper=0xFFFFFFFF",     ALL_ONES);

        a = INT_MIN;  b = INT_MIN;
        check("MULH  INT_MIN x INT_MIN upper=0x40000000", 32'h4000_0000);

        a = INT_MIN;  b = ALL_ONES;
        check("MULH  INT_MIN x (-1) upper=0",      32'h0000_0000);

        // ══════════════════════════════════════════════════
        //  MULHSU
        // ══════════════════════════════════════════════════
        $display("\n--- MULHSU ---");
        funct3 = MULHSU;

        a = 32'd3;    b = 32'd7;
        check("MULHSU  3x7 upper=0",               32'd0);

        a = ALL_ONES; b = ALL_ONES;
        check("MULHSU  (-1)x0xFFFFFFFF upper=0xFFFFFFFF", 32'hFFFF_FFFF);

        // ══════════════════════════════════════════════════
        //  MULHU
        // ══════════════════════════════════════════════════
        $display("\n--- MULHU ---");
        funct3 = MULHU;

        a = 32'd3;    b = 32'd7;
        check("MULHU  3x7 upper=0",                32'd0);

        a = ALL_ONES; b = ALL_ONES;
        check("MULHU  0xFFFFFFFF^2 upper=0xFFFFFFFE", 32'hFFFF_FFFE);

        a = INT_MIN;  b = 32'd2;
        check("MULHU  0x80000000x2 upper=1",       32'd1);

        // ══════════════════════════════════════════════════
        //  DIV
        // ══════════════════════════════════════════════════
        $display("\n--- DIV ---");
        funct3 = DIV;

        a = 32'd20;        b = 32'd4;
        check("DIV   20  /  4  =  5",              32'd5);

        a = 32'd7;         b = 32'd2;
        check("DIV    7  /  2  =  3 (trunc)",      32'd3);

        a = ALL_ONES;      b = 32'd1;
        check("DIV   -1  /  1  = -1",              ALL_ONES);

        a = 32'hFFFF_FFEC; b = ALL_ONES;
        check("DIV  -20  / -1  = 20",              32'd20);

        a = 32'hFFFF_FFEC; b = 32'd4;
        check("DIV  -20  /  4  = -5",              32'hFFFF_FFFB);

        a = 32'd42;        b = 32'd0;
        check("DIV   42  /  0  = 0xFFFFFFFF",      ALL_ONES);

        a = INT_MIN;       b = ALL_ONES;
        check("DIV  INT_MIN / -1 = INT_MIN",        INT_MIN);

        // ══════════════════════════════════════════════════
        //  DIVU
        // ══════════════════════════════════════════════════
        $display("\n--- DIVU ---");
        funct3 = DIVU;

        a = 32'd20;   b = 32'd4;
        check("DIVU  20 / 4 = 5",                  32'd5);

        a = ALL_ONES; b = 32'd1;
        check("DIVU  0xFFFFFFFF / 1 = 0xFFFFFFFF", ALL_ONES);

        a = ALL_ONES; b = ALL_ONES;
        check("DIVU  0xFFFFFFFF / 0xFFFFFFFF = 1", 32'd1);

        a = 32'd100;  b = 32'd0;
        check("DIVU  100 / 0 = 0xFFFFFFFF",        ALL_ONES);

        // ══════════════════════════════════════════════════
        //  REM
        // ══════════════════════════════════════════════════
        $display("\n--- REM ---");
        funct3 = REM;

        a = 32'd20;        b = 32'd6;
        check("REM   20 %  6  =  2",               32'd2);

        a = 32'd7;         b = 32'd2;
        check("REM    7 %  2  =  1",               32'd1);

        a = 32'hFFFF_FFEC; b = 32'd6;
        check("REM  -20 %  6  = -2",               32'hFFFF_FFFE);

        a = 32'd20;        b = ALL_ONES;
        check("REM   20 % -1  =  0",               32'd0);

        a = 32'd13;        b = 32'd0;
        check("REM   13 %  0  = 13 (dividend)",    32'd13);

        a = INT_MIN;       b = ALL_ONES;
        check("REM  INT_MIN % -1 = 0",             32'd0);

        // ══════════════════════════════════════════════════
        //  REMU
        // ══════════════════════════════════════════════════
        $display("\n--- REMU ---");
        funct3 = REMU;

        a = 32'd20;   b = 32'd6;
        check("REMU  20 % 6 = 2",                  32'd2);

        a = ALL_ONES; b = 32'd16;
        check("REMU  0xFFFFFFFF % 16 = 15",        32'd15);

        a = 32'd99;   b = 32'd0;
        check("REMU  99 % 0 = 99 (dividend)",      32'd99);

        a = 32'd42;   b = 32'd42;
        check("REMU  42 % 42 = 0",                 32'd0);

        // ─────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    initial begin #10000; $display("TIMEOUT"); $finish; end

endmodule