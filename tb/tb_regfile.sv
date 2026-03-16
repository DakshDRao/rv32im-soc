// ============================================================
//  tb_regfile.sv  -  Self-Checking Testbench for regfile.sv
//
//  Test groups:
//    A. x0 hardwire       - writes ignored, reads always 0
//    B. Basic read/write  - write then read every register
//    C. Write-before-read - forwarding on rs1, rs2, both
//    D. Write enable gate - we=0 must not alter registers
//    E. Two-port independence - rs1 ≠ rs2 simultaneously
//    F. Overwrite         - second write wins
//    G. ABI name spot-check (sp=x2, ra=x1, a0=x10, t0=x5)
// ============================================================

`timescale 1ns/1ps

module tb_regfile;

    // ── DUT Ports ────────────────────────────────────────────
    logic        clk, we;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] wd, rd1, rd2;

    // ── DUT ──────────────────────────────────────────────────
    regfile dut (.*);

    // ── Clock - 10 ns period ─────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Counters ─────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ─────────────────────────────────────────────────────────
    //  Tasks
    // ─────────────────────────────────────────────────────────

    // Write a register (one clock cycle)
    task automatic write_reg(input [4:0] addr, input [31:0] data);
        @(negedge clk);          // set up before next posedge
        rd = addr; wd = data; we = 1'b1;
        rs1 = 5'd0; rs2 = 5'd0; // keep read ports quiet
        @(posedge clk);          // latch
        #1;                      // small delta after posedge
        we = 1'b0;
    endtask

    // Check a read port
    task automatic check(
        input string   test_name,
        input [31:0]   got,
        input [31:0]   exp
    );
        if (got !== exp) begin
            $display("  FAIL  %-40s | got=%08h  exp=%08h", test_name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-40s | %08h", test_name, got);
            pass_count++;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        // Default safe state
        we = 0; rd = 0; wd = 0; rs1 = 0; rs2 = 0;
        @(negedge clk);

        // ── A. x0 Hardwire ───────────────────────────────────
        $display("\n--- A: x0 hardwired to 0 ---");

        // Try to write x0
        write_reg(5'd0, 32'hDEAD_BEEF);
        rs1 = 5'd0; rs2 = 5'd0; #1;
        check("x0 read after attempted write (rs1)", rd1, 32'd0);
        check("x0 read after attempted write (rs2)", rd2, 32'd0);

        write_reg(5'd0, 32'hFFFFFFFF);
        rs1 = 5'd0; #1;
        check("x0 write 0xFFFF still 0",            rd1, 32'd0);

        // ── B. Basic Write / Read all 31 registers ───────────
        $display("\n--- B: Write then read x1-x31 ---");

        for (int i = 1; i < 32; i++) begin
            automatic logic [31:0] val = 32'hA0000000 | i;
            write_reg(i[4:0], val);
            rs1 = i[4:0]; #1;
            check($sformatf("x%0d write/read", i), rd1, val);
        end

        // ── C. Write-before-Read Forwarding ──────────────────
        $display("\n--- C: Write-before-read forwarding ---");

        // Pre-load x5 = 0xAAAAAAAA
        write_reg(5'd5, 32'hAAAAAAAA);

        // Now write x5 = 0xBBBBBBBB while reading x5 on rs1
        @(negedge clk);
        rd  = 5'd5;
        wd  = 32'hBBBBBBBB;
        we  = 1'b1;
        rs1 = 5'd5;    // same as rd - should forward wd
        rs2 = 5'd0;
        #1;
        check("Fwd: rs1==rd sees new wd immediately", rd1, 32'hBBBBBBBB);
        @(posedge clk); #1;
        we = 0;

        // Pre-load x6 = 0xCCCCCCCC
        write_reg(5'd6, 32'hCCCCCCCC);

        // Write x6 = 0xDDDDDDDD while reading x6 on rs2
        @(negedge clk);
        rd  = 5'd6;
        wd  = 32'hDDDDDDDD;
        we  = 1'b1;
        rs1 = 5'd0;
        rs2 = 5'd6;    // same as rd - should forward wd
        #1;
        check("Fwd: rs2==rd sees new wd immediately", rd2, 32'hDDDDDDDD);
        @(posedge clk); #1;
        we = 0;

        // Both rs1 and rs2 == rd simultaneously
        write_reg(5'd7, 32'h11111111);
        @(negedge clk);
        rd  = 5'd7;
        wd  = 32'h22222222;
        we  = 1'b1;
        rs1 = 5'd7;
        rs2 = 5'd7;
        #1;
        check("Fwd: rs1==rs2==rd both forward",       rd1, 32'h22222222);
        check("Fwd: rs1==rs2==rd both forward (rs2)", rd2, 32'h22222222);
        @(posedge clk); #1;
        we = 0;

        // No forwarding when we=0 (stale value should appear)
        write_reg(5'd8, 32'hFACEFACE);
        @(negedge clk);
        rd  = 5'd8;
        wd  = 32'hDEADDEAD;
        we  = 1'b0;          // write disabled
        rs1 = 5'd8;
        #1;
        check("No fwd when we=0 (stale value)",       rd1, 32'hFACEFACE);
        we = 0;

        // ── D. Write Enable Gate ─────────────────────────────
        $display("\n--- D: we=0 must not alter registers ---");

        write_reg(5'd9, 32'h12345678);

        @(negedge clk);
        rd = 5'd9; wd = 32'hDEADBEEF; we = 1'b0;  // blocked write
        @(posedge clk); #1;
        we = 0;

        rs1 = 5'd9; #1;
        check("x9 unchanged after we=0 write", rd1, 32'h12345678);

        // ── E. Two-Port Independence ──────────────────────────
        $display("\n--- E: Simultaneous independent reads ---");

        write_reg(5'd10, 32'hAAAA_0000);
        write_reg(5'd11, 32'h0000_BBBB);

        rs1 = 5'd10; rs2 = 5'd11; #1;
        check("Dual read: rs1=x10",    rd1, 32'hAAAA_0000);
        check("Dual read: rs2=x11",    rd2, 32'h0000_BBBB);

        rs1 = 5'd11; rs2 = 5'd10; #1;
        check("Dual read swapped: rs1=x11", rd1, 32'h0000_BBBB);
        check("Dual read swapped: rs2=x10", rd2, 32'hAAAA_0000);

        // ── F. Overwrite (second write wins) ─────────────────
        $display("\n--- F: Overwrite ---");

        write_reg(5'd15, 32'h00000001);
        write_reg(5'd15, 32'h00000002);
        write_reg(5'd15, 32'hCAFEBABE);
        rs1 = 5'd15; #1;
        check("x15 after 3 overwrites = last", rd1, 32'hCAFEBABE);

        // ── G. ABI Register Name Spot-Check ──────────────────
        $display("\n--- G: ABI register aliases ---");

        write_reg(5'd1,  32'hAA000001);  // ra  (return address)
        write_reg(5'd2,  32'hBB000002);  // sp  (stack pointer)
        write_reg(5'd5,  32'hCC000005);  // t0  (temp)
        write_reg(5'd10, 32'hDD00000A);  // a0  (arg/return)

        rs1 = 5'd1;  #1; check("ra = x1",  rd1, 32'hAA000001);
        rs1 = 5'd2;  #1; check("sp = x2",  rd1, 32'hBB000002);
        rs1 = 5'd5;  #1; check("t0 = x5",  rd1, 32'hCC000005);
        rs1 = 5'd10; #1; check("a0 = x10", rd1, 32'hDD00000A);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - RegFile is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    // Watchdog
    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule