// ============================================================
//  tb_dmem.sv  -  Self-Checking Testbench for dmem.sv
//
//  Test groups:
//    A. SW / LW    - full word store and load
//    B. SH / LH    - halfword store, signed load, both offsets
//    C. SB / LB    - byte store, signed load, all 4 byte offsets
//    D. LBU        - byte load unsigned (no sign extension)
//    E. LHU        - halfword load unsigned
//    F. Sign extension contrast  - LB vs LBU, LH vs LHU
//    G. Multiple addresses       - verify address independence
//    H. Byte-enable isolation    - SB only writes target byte
//    I. SH isolation             - SH only writes target halfword
//    J. Overwrite                - second write wins
// ============================================================

`timescale 1ns/1ps

module tb_dmem;

    // ── DUT Ports ─────────────────────────────────────────────
    logic        clk;
    logic [31:0] addr, wdata;
    logic        we;
    logic [2:0]  funct3;
    logic [31:0] rdata;

    // ── DUT ───────────────────────────────────────────────────
    dmem #(.DEPTH(256), .ADDR_BITS(8)) dut (.*);

    // ── Clock ─────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Counters ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ── funct3 codes ──────────────────────────────────────────
    localparam [2:0]
        F3_SB=3'b000, F3_SH=3'b001, F3_SW=3'b010,
        F3_LB=3'b000, F3_LH=3'b001, F3_LW=3'b010,
        F3_LBU=3'b100, F3_LHU=3'b101;

    // ─────────────────────────────────────────────────────────
    //  Tasks
    // ─────────────────────────────────────────────────────────
    task automatic check(
        input string  test_name,
        input [31:0]  got,
        input [31:0]  exp
    );
        if (got !== exp) begin
            $display("  FAIL  %-52s | got=%08h  exp=%08h", test_name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-52s | %08h", test_name, got);
            pass_count++;
        end
    endtask

    // Store: one clock cycle write
    task automatic store(
        input [31:0] a,
        input [31:0] d,
        input [2:0]  f3
    );
        addr=a; wdata=d; we=1'b1; funct3=f3;
        @(posedge clk); #1;
        we = 1'b0;
    endtask

    // Load: present address and funct3, clock once, read rdata
    // rdata is combinational - same cycle as addr (async read)
    task automatic load(
        input [31:0] a,
        input [2:0]  f3
    );
        addr=a; funct3=f3; we=1'b0;
        @(posedge clk); #1;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  DMEM Testbench - RV32I");
        $display("========================================\n");

        we=0; addr=0; wdata=0; funct3=F3_LW;
        @(negedge clk);

        // ══════════════════════════════════════════════════════
        //  A. SW / LW - full 32-bit word
        // ══════════════════════════════════════════════════════
        $display("--- A: SW / LW ---");

        store(32'h00, 32'hDEADBEEF, F3_SW);
        load (32'h00, F3_LW);
        check("SW/LW 0xDEADBEEF at addr=0x00", rdata, 32'hDEADBEEF);

        store(32'h04, 32'h12345678, F3_SW);
        load (32'h04, F3_LW);
        check("SW/LW 0x12345678 at addr=0x04", rdata, 32'h12345678);

        store(32'h08, 32'h00000000, F3_SW);
        load (32'h08, F3_LW);
        check("SW/LW 0x00000000 at addr=0x08", rdata, 32'h00000000);

        store(32'hFC, 32'hCAFEBABE, F3_SW);
        load (32'hFC, F3_LW);
        check("SW/LW 0xCAFEBABE at addr=0xFC", rdata, 32'hCAFEBABE);

        // ══════════════════════════════════════════════════════
        //  B. SH / LH - halfword, both offsets (0 and +2)
        //  Store 0xABCD at offset 0, 0x1234 at offset 2
        //  LH sign-extends: 0xABCD → 0xFFFFABCD (bit15=1)
        //                   0x1234 → 0x00001234 (bit15=0)
        // ══════════════════════════════════════════════════════
        $display("\n--- B: SH / LH ---");

        store(32'h10, 32'h0000ABCD, F3_SH);   // store at byte_off=0
        load (32'h10, F3_LH);
        check("SH/LH 0xABCD off=0 sign-ext",  rdata, 32'hFFFFABCD);

        store(32'h12, 32'h00001234, F3_SH);   // store at byte_off=2
        load (32'h12, F3_LH);
        check("SH/LH 0x1234 off=2 sign-ext",  rdata, 32'h00001234);

        // Verify both halves coexist in same word
        load (32'h10, F3_LW);
        check("SH both halves: word = 0x1234ABCD", rdata, 32'h1234ABCD);

        store(32'h20, 32'h00007FFF, F3_SH);   // 0x7FFF: positive, bit15=0
        load (32'h20, F3_LH);
        check("SH/LH 0x7FFF sign=0 → 0x00007FFF", rdata, 32'h00007FFF);

        store(32'h20, 32'h00008000, F3_SH);   // 0x8000: negative, bit15=1
        load (32'h20, F3_LH);
        check("SH/LH 0x8000 sign=1 → 0xFFFF8000", rdata, 32'hFFFF8000);

        // ══════════════════════════════════════════════════════
        //  C. SB / LB - byte, all 4 offsets
        //  LB sign-extends: 0xFF → 0xFFFFFFFF, 0x7F → 0x0000007F
        // ══════════════════════════════════════════════════════
        $display("\n--- C: SB / LB ---");

        // Write four distinct bytes at the four byte lanes of word 0x30
        store(32'h30, 32'h000000AA, F3_SB);  // byte_off=0 → bank0
        store(32'h31, 32'h000000BB, F3_SB);  // byte_off=1 → bank1
        store(32'h32, 32'h000000CC, F3_SB);  // byte_off=2 → bank2
        store(32'h33, 32'h000000DD, F3_SB);  // byte_off=3 → bank3

        // Verify full word
        load (32'h30, F3_LW);
        check("SB x4: word = 0xDDCCBBAA", rdata, 32'hDDCCBBAA);

        // LB from each offset - all have MSB set → sign-extend to 0xFF...
        load (32'h30, F3_LB); check("LB off=0: 0xAA → 0xFFFFFFAA", rdata, 32'hFFFFFFAA);
        load (32'h31, F3_LB); check("LB off=1: 0xBB → 0xFFFFFFBB", rdata, 32'hFFFFFFBB);
        load (32'h32, F3_LB); check("LB off=2: 0xCC → 0xFFFFFFCC", rdata, 32'hFFFFFFCC);
        load (32'h33, F3_LB); check("LB off=3: 0xDD → 0xFFFFFFDD", rdata, 32'hFFFFFFDD);

        // Positive byte (bit7=0) → zero-fill upper bits
        store(32'h40, 32'h0000007F, F3_SB);
        load (32'h40, F3_LB);
        check("LB 0x7F sign=0 → 0x0000007F", rdata, 32'h0000007F);

        // ══════════════════════════════════════════════════════
        //  D. LBU - unsigned byte load (always zero-extend)
        // ══════════════════════════════════════════════════════
        $display("\n--- D: LBU ---");

        store(32'h50, 32'h000000FF, F3_SB);
        load (32'h50, F3_LBU);
        check("LBU 0xFF → 0x000000FF (zero-ext)", rdata, 32'h000000FF);

        store(32'h51, 32'h00000080, F3_SB);
        load (32'h51, F3_LBU);
        check("LBU 0x80 → 0x00000080 (zero-ext)", rdata, 32'h00000080);

        store(32'h52, 32'h0000007F, F3_SB);
        load (32'h52, F3_LBU);
        check("LBU 0x7F → 0x0000007F",            rdata, 32'h0000007F);

        // ══════════════════════════════════════════════════════
        //  E. LHU - unsigned halfword load (always zero-extend)
        // ══════════════════════════════════════════════════════
        $display("\n--- E: LHU ---");

        store(32'h60, 32'h0000FFFF, F3_SH);
        load (32'h60, F3_LHU);
        check("LHU 0xFFFF → 0x0000FFFF (zero-ext)", rdata, 32'h0000FFFF);

        store(32'h60, 32'h00008000, F3_SH);
        load (32'h60, F3_LHU);
        check("LHU 0x8000 → 0x00008000 (zero-ext)", rdata, 32'h00008000);

        // ══════════════════════════════════════════════════════
        //  F. Sign extension contrast  LB vs LBU, LH vs LHU
        //  Same data, same address - only funct3 differs
        // ══════════════════════════════════════════════════════
        $display("\n--- F: Sign vs unsigned contrast ---");

        store(32'h70, 32'h000000FF, F3_SB);
        load (32'h70, F3_LB);  check("LB  0xFF → 0xFFFFFFFF (signed)",   rdata, 32'hFFFFFFFF);
        load (32'h70, F3_LBU); check("LBU 0xFF → 0x000000FF (unsigned)", rdata, 32'h000000FF);

        store(32'h74, 32'h0000ABCD, F3_SH);
        load (32'h74, F3_LH);  check("LH  0xABCD → 0xFFFFABCD (signed)",   rdata, 32'hFFFFABCD);
        load (32'h74, F3_LHU); check("LHU 0xABCD → 0x0000ABCD (unsigned)", rdata, 32'h0000ABCD);

        // ══════════════════════════════════════════════════════
        //  G. Multiple addresses - no aliasing
        // ══════════════════════════════════════════════════════
        $display("\n--- G: Address independence ---");

        store(32'h80, 32'h11111111, F3_SW);
        store(32'h84, 32'h22222222, F3_SW);
        store(32'h88, 32'h33333333, F3_SW);
        store(32'h8C, 32'h44444444, F3_SW);

        load(32'h80, F3_LW); check("addr=0x80 isolated", rdata, 32'h11111111);
        load(32'h84, F3_LW); check("addr=0x84 isolated", rdata, 32'h22222222);
        load(32'h88, F3_LW); check("addr=0x88 isolated", rdata, 32'h33333333);
        load(32'h8C, F3_LW); check("addr=0x8C isolated", rdata, 32'h44444444);

        // ══════════════════════════════════════════════════════
        //  H. Byte-enable isolation - SB only writes ONE byte
        //  Fill word with 0xFFFFFFFF, then SB 0x00 to one lane
        //  All other bytes must remain 0xFF
        // ══════════════════════════════════════════════════════
        $display("\n--- H: SB byte-enable isolation ---");

        store(32'hA0, 32'hFFFFFFFF, F3_SW);

        store(32'hA0, 32'h00000000, F3_SB);  // zero byte_off=0 only
        load (32'hA0, F3_LW);
        check("SB off=0: word=0xFFFFFF00", rdata, 32'hFFFFFF00);

        store(32'hA0, 32'hFFFFFFFF, F3_SW);  // restore
        store(32'hA1, 32'h00000000, F3_SB);  // zero byte_off=1 only
        load (32'hA0, F3_LW);
        check("SB off=1: word=0xFFFF00FF", rdata, 32'hFFFF00FF);

        store(32'hA0, 32'hFFFFFFFF, F3_SW);  // restore
        store(32'hA2, 32'h00000000, F3_SB);  // zero byte_off=2 only
        load (32'hA0, F3_LW);
        check("SB off=2: word=0xFF00FFFF", rdata, 32'hFF00FFFF);

        store(32'hA0, 32'hFFFFFFFF, F3_SW);  // restore
        store(32'hA3, 32'h00000000, F3_SB);  // zero byte_off=3 only
        load (32'hA0, F3_LW);
        check("SB off=3: word=0x00FFFFFF", rdata, 32'h00FFFFFF);

        // ══════════════════════════════════════════════════════
        //  I. SH halfword isolation
        //  Fill word with 0x00000000, write 0xBEEF to upper half
        //  Lower half must remain 0x0000
        // ══════════════════════════════════════════════════════
        $display("\n--- I: SH halfword isolation ---");

        store(32'hB0, 32'h00000000, F3_SW);
        store(32'hB2, 32'h0000BEEF, F3_SH);  // byte_off=2 → upper half
        load (32'hB0, F3_LW);
        check("SH off=2 upper only: 0xBEEF0000", rdata, 32'hBEEF0000);

        store(32'hC0, 32'hFFFFFFFF, F3_SW);
        store(32'hC0, 32'h00001234, F3_SH);  // byte_off=0 → lower half
        load (32'hC0, F3_LW);
        check("SH off=0 lower only: 0xFFFF1234", rdata, 32'hFFFF1234);

        // ══════════════════════════════════════════════════════
        //  J. Overwrite - last write wins
        // ══════════════════════════════════════════════════════
        $display("\n--- J: Overwrite ---");

        store(32'hD0, 32'h11111111, F3_SW);
        store(32'hD0, 32'h22222222, F3_SW);
        store(32'hD0, 32'hDEADBEEF, F3_SW);
        load (32'hD0, F3_LW);
        check("Overwrite: last SW wins", rdata, 32'hDEADBEEF);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - DMEM is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule