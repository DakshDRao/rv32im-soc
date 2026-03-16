// ============================================================
//  tb_imem.sv  -  Self-Checking Testbench for imem.sv
//
//  Test groups:
//    A. Init check    - known words at known addresses after load
//    B. Sequential    - walk through addresses 0,4,8,...,0x3C
//    C. Word align    - addr[1:0] ignored (byte addr → word index)
//    D. Latency       - output appears ONE cycle after addr presented
//    E. NOP fill      - uninitialised locations return NOP (0x13)
//    F. Re-read       - same address twice gives same result
// ============================================================

`timescale 1ns/1ps

module tb_imem;

    // ── DUT Ports ─────────────────────────────────────────────
    logic        clk;
    logic [31:0] addr;
    logic [31:0] instr;

    // ── DUT - depth=64 words ────────────────────────────────
    // MEM_FILE left empty; testbench loads via hierarchical $readmemh
    imem #(
        .DEPTH    (64),
        .ADDR_BITS(6),
        .MEM_FILE ("")
    ) dut (.*);

    // ── Clock - 10 ns period ──────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Counters ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ─────────────────────────────────────────────────────────
    //  Expected instruction words (must match test_imem.mem)
    // ─────────────────────────────────────────────────────────
    logic [31:0] expected [0:15];
    initial begin
        expected[0]  = 32'h00000013;  // NOP
        expected[1]  = 32'h00500093;  // ADDI x1,x0,5
        expected[2]  = 32'h00600113;  // ADDI x2,x0,6
        expected[3]  = 32'h00208193;  // ADDI x3,x1,2
        expected[4]  = 32'h002081B3;  // ADD  x3,x1,x2
        expected[5]  = 32'h40208233;  // SUB  x4,x1,x2
        expected[6]  = 32'h0020F2B3;  // AND  x5,x1,x2
        expected[7]  = 32'h0020E333;  // OR   x6,x1,x2
        expected[8]  = 32'h0020C3B3;  // XOR  x7,x1,x2
        expected[9]  = 32'h00109413;  // SLLI x8,x1,1
        expected[10] = 32'h0010D493;  // SRLI x9,x1,1
        expected[11] = 32'h00100513;  // ADDI x10,x0,1
        expected[12] = 32'h00200593;  // ADDI x11,x0,2
        expected[13] = 32'h00300613;  // ADDI x12,x0,3
        expected[14] = 32'hDEADBEEF;  // sentinel
        expected[15] = 32'h00000013;  // NOP padding
    end

    // ─────────────────────────────────────────────────────────
    //  Tasks
    // ─────────────────────────────────────────────────────────
    task automatic check(
        input string  test_name,
        input [31:0]  got,
        input [31:0]  exp
    );
        if (got !== exp) begin
            $display("  FAIL  %-50s | got=%08h  exp=%08h", test_name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-50s | %08h", test_name, got);
            pass_count++;
        end
    endtask

    // Present address, clock once, read result (1-cycle latency)
    task automatic fetch(input [31:0] byte_addr);
        addr = byte_addr;
        @(posedge clk); #1;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  IMEM Testbench - RV32I");
        $display("========================================\n");

        // Load .mem file directly into DUT memory array via hierarchical path.
        // This works regardless of Vivado's simulation working directory.
        $readmemh("test_imem.mem", dut.mem);

        addr = 0;
        @(negedge clk); // start in setup window

        // ══════════════════════════════════════════════════════
        //  A. Init Check - spot-check known locations
        // ══════════════════════════════════════════════════════
        $display("--- A: Init check (known words) ---");

        fetch(32'h00); check("addr=0x00 → NOP",         instr, expected[0]);
        fetch(32'h04); check("addr=0x04 → ADDI x1,x0,5",instr, expected[1]);
        fetch(32'h08); check("addr=0x08 → ADDI x2,x0,6",instr, expected[2]);
        fetch(32'h14); check("addr=0x14 → SUB  x4,x1,x2",instr, expected[5]);
        fetch(32'h38); check("addr=0x38 → sentinel DEADBEEF",instr, expected[14]);

        // ══════════════════════════════════════════════════════
        //  B. Sequential fetch - walk all 16 loaded words
        // ══════════════════════════════════════════════════════
        $display("\n--- B: Sequential fetch 0x00-0x3C ---");

        for (int i = 0; i < 16; i++) begin
            fetch(i * 4);
            check($sformatf("sequential addr=%02h", i*4), instr, expected[i]);
        end

        // ══════════════════════════════════════════════════════
        //  C. Word-alignment - low 2 bits of addr are ignored
        //  Byte addresses 0,1,2,3 all map to word 0
        //  Byte addresses 4,5,6,7 all map to word 1
        // ══════════════════════════════════════════════════════
        $display("\n--- C: Word alignment (addr[1:0] ignored) ---");

        fetch(32'h00); check("0x00 → word[0]", instr, expected[0]);
        fetch(32'h01); check("0x01 → word[0]", instr, expected[0]);
        fetch(32'h02); check("0x02 → word[0]", instr, expected[0]);
        fetch(32'h03); check("0x03 → word[0]", instr, expected[0]);

        fetch(32'h04); check("0x04 → word[1]", instr, expected[1]);
        fetch(32'h05); check("0x05 → word[1]", instr, expected[1]);
        fetch(32'h06); check("0x06 → word[1]", instr, expected[1]);
        fetch(32'h07); check("0x07 → word[1]", instr, expected[1]);

        fetch(32'h08); check("0x08 → word[2]", instr, expected[2]);
        fetch(32'h0B); check("0x0B → word[2]", instr, expected[2]);

        // ══════════════════════════════════════════════════════
        //  D. Latency check - output must appear AFTER posedge
        //  Present address, check output is NOT yet valid before
        //  clocking, then check it IS valid after posedge.
        // ══════════════════════════════════════════════════════
        $display("\n--- D: 1-cycle latency ---");

        // Present addr=0x10 (word[4] = ADD x3,x1,x2 = 0x002081B3)
        // Before clocking, instr still holds previous value (word[2])
        addr = 32'h10; #1;
        check("before posedge: instr = stale word[2]", instr, expected[2]);

        // After posedge, instr should update to word[4]
        @(posedge clk); #1;
        check("after  posedge: instr = word[4]",       instr, expected[4]);

        // ══════════════════════════════════════════════════════
        //  E. NOP fill - uninitialised words beyond loaded program
        //  Locations 16..63 were not in the .mem file, must be NOP
        // ══════════════════════════════════════════════════════
        $display("\n--- E: Uninitialised locations = NOP ---");

        fetch(32'h40); check("addr=0x40 (word[16]) = NOP", instr, 32'h00000013);
        fetch(32'h80); check("addr=0x80 (word[32]) = NOP", instr, 32'h00000013);
        fetch(32'hF8); check("addr=0xF8 (word[62]) = NOP", instr, 32'h00000013);

        // ══════════════════════════════════════════════════════
        //  F. Re-read - same address twice gives same result
        // ══════════════════════════════════════════════════════
        $display("\n--- F: Re-read stability ---");

        fetch(32'h0C); check("re-read 0x0C first",  instr, expected[3]);
        fetch(32'h0C); check("re-read 0x0C second", instr, expected[3]);
        fetch(32'h0C); check("re-read 0x0C third",  instr, expected[3]);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - IMEM is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule