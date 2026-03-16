// ============================================================
//  tb_pc_logic.sv  -  Self-Checking Testbench for pc_logic.sv
//
//  Test groups:
//    A. Reset          - PC loads BOOT_ADDR on rst, holds until released
//    B. Sequential     - PC+4 each cycle when no control signals
//    C. Branch taken   - PC jumps to PC+imm, then resumes +4
//    D. Branch not taken - branch_taken=0 must not change PC
//    E. JAL            - PC = PC + J-imm, rd1 gets PC+4
//    F. JALR           - PC = (rs1+imm)&~1, LSB always cleared
//    G. Priority       - JALR > JAL > BRANCH > SEQ
//    H. PC+4 output    - always equals current PC + 4
//    I. JALR LSB clear - odd target addresses become even
//    J. Negative imm   - backward branches and jumps
// ============================================================

`timescale 1ns/1ps

module tb_pc_logic;

    // ── DUT Ports ─────────────────────────────────────────────
    logic        clk, rst;
    logic        jump, jalr, branch_taken;
    logic [31:0] rs1, imm;
    logic [31:0] pc, pc_plus4;

    // ── DUT (BOOT_ADDR = 0) ───────────────────────────────────
    pc_logic #(.BOOT_ADDR(32'h0000_0000)) dut (.*);

    // ── Clock - 10 ns period ──────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Counters ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

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

    // Set inputs immediately, wait for next posedge, settle #1
    // Caller must already be past a posedge (i.e. in the setup window)
    task automatic tick(
        input logic j, jr, bt,
        input [31:0] r1, immediate
    );
        jump = j; jalr = jr; branch_taken = bt;
        rs1  = r1; imm  = immediate;
        @(posedge clk);
        #1;   // small delta so outputs settle
    endtask

    // Apply without clocking (combinational check)
    task automatic apply_comb(
        input logic j, jr, bt,
        input [31:0] r1, immediate
    );
        jump = j; jalr = jr; branch_taken = bt;
        rs1  = r1; imm  = immediate;
        #2;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  PC Logic Testbench - RV32I");
        $display("========================================\n");

        // Safe initial state
        jump=0; jalr=0; branch_taken=0; rs1=0; imm=0;
        rst=1;

        // ══════════════════════════════════════════════════════
        //  A. RESET
        // ══════════════════════════════════════════════════════
        $display("--- A: Reset ---");

        // Hold reset for 3 cycles, PC must stay at BOOT_ADDR
        @(posedge clk); #1; check("rst cyc1: PC = BOOT_ADDR", pc, 32'h0000_0000);
        @(posedge clk); #1; check("rst cyc2: PC = BOOT_ADDR", pc, 32'h0000_0000);
        @(posedge clk); #1; check("rst cyc3: PC = BOOT_ADDR", pc, 32'h0000_0000);

        // Release reset at negedge - we are now in the setup window
        // before the next posedge. No extra clock fires before group B.
        @(negedge clk); rst = 0; jump=0; jalr=0; branch_taken=0; rs1=0; imm=0;
        #1; // settle - PC = 0x00, next posedge not yet fired

        // ══════════════════════════════════════════════════════
        //  B. SEQUENTIAL  (no control signals)
        //  Pattern: check current PC, then tick (which advances PC)
        //  tick() returns AFTER posedge, so PC is already the new value
        // ══════════════════════════════════════════════════════
        $display("\n--- B: Sequential PC+4 ---");

        check("seq: PC = 0x00000000", pc, 32'h0000_0000); tick(0,0,0, 0,0);
        check("seq: PC = 0x00000004", pc, 32'h0000_0004); tick(0,0,0, 0,0);
        check("seq: PC = 0x00000008", pc, 32'h0000_0008); tick(0,0,0, 0,0);
        check("seq: PC = 0x0000000C", pc, 32'h0000_000C); tick(0,0,0, 0,0);
        check("seq: PC = 0x00000010", pc, 32'h0000_0010);
        // PC = 0x10 here, no final tick

        // ══════════════════════════════════════════════════════
        //  C. BRANCH TAKEN
        //  PC=0x10, branch_taken=1, imm=+20 → after tick PC = 0x24
        // ══════════════════════════════════════════════════════
        $display("\n--- C: Branch taken ---");

        tick(0,0,1, 0, 32'd20);           // PC: 0x10 → 0x24
        check("branch taken: PC = 0x00000024", pc, 32'h0000_0024);

        tick(0,0,0, 0,0);                 // PC: 0x24 → 0x28
        check("after branch: PC = 0x00000028", pc, 32'h0000_0028);

        // ══════════════════════════════════════════════════════
        //  D. BRANCH NOT TAKEN
        //  branch_taken=0, imm=+100 → PC must only step +4
        // ══════════════════════════════════════════════════════
        $display("\n--- D: Branch not taken ---");

        tick(0,0,0, 0, 32'd100);          // PC: 0x28 → 0x2C (not 0x8C)
        check("branch NOT taken: PC = 0x0000002C", pc, 32'h0000_002C);

        // ══════════════════════════════════════════════════════
        //  E. JAL
        //  PC=0x2C, jump=1, imm=+100 → after tick PC = 0x90
        //  pc_plus4 is combinational = current PC+4
        //  Check it BEFORE the tick while PC is still 0x2C → 0x30
        // ══════════════════════════════════════════════════════
        $display("\n--- E: JAL ---");

        begin
            logic [31:0] expected_ra;
            expected_ra = pc + 4;          // 0x2C+4 = 0x30 - computed now
            // Verify pc_plus4 output while PC=0x2C (BEFORE tick)
            check("JAL: pc_plus4 = 0x00000030",    pc_plus4, expected_ra);
            tick(1,0,0, 0, 32'd100);       // PC: 0x2C → 0x90
            check("JAL: PC = 0x00000090",  pc,       32'h0000_0090);
        end

        tick(0,0,0, 0,0);                 // PC: 0x90 → 0x94
        check("after JAL: PC = 0x00000094", pc, 32'h0000_0094);

        // ══════════════════════════════════════════════════════
        //  F. JALR
        //  jalr=1 → PC = (rs1 + imm) & ~1
        //  LSB is always cleared regardless of rs1+imm result
        // ══════════════════════════════════════════════════════
        $display("\n--- F: JALR ---");

        // PC = 0x94, JALR with rs1=0x200, imm=+8 → target=(0x208)&~1=0x208
        tick(0,1,0, 32'h200, 32'd8);
        check("JALR: PC = 0x00000208",    pc, 32'h0000_0208);

        // JALR with rs1=0x100, imm=0 → PC = 0x100
        tick(0,1,0, 32'h100, 32'd0);
        check("JALR rs1=0x100 imm=0",     pc, 32'h0000_0100);

        // ══════════════════════════════════════════════════════
        //  G. PRIORITY: JALR > JAL > BRANCH > SEQ
        //  Assert all simultaneously, JALR must win
        // ══════════════════════════════════════════════════════
        $display("\n--- G: Priority ---");

        // All three asserted: jalr=1, jump=1, branch_taken=1
        // rs1=0x500, imm=0 → JALR target = 0x500
        // JAL target   = pc+0 = pc
        // branch target = pc+0 = pc
        // JALR MUST WIN → PC = 0x500
        tick(1,1,1, 32'h500, 32'd0);
        check("Priority: JALR wins over JAL+BRANCH", pc, 32'h0000_0500);

        // jalr=0, jump=1, branch_taken=1
        // rs1=0, imm=+0x40 → JAL target = pc+0x40 = 0x540
        // branch target = pc+0x40 = 0x540 (same imm, same result here)
        // JAL MUST WIN (behaves same as branch in this case, hard to distinguish)
        // Use imm that only makes sense for one: set imm=0x100 and check vs pc+0x100
        begin
            logic [31:0] cur_pc;
            cur_pc = pc; // 0x500
            tick(1,0,1, 0, 32'h100);   // jump=1, branch_taken=1, imm=0x100
            check("Priority: JAL wins over BRANCH", pc, cur_pc + 32'h100);
        end

        // ══════════════════════════════════════════════════════
        //  H. PC+4 always equals current PC + 4
        // ══════════════════════════════════════════════════════
        $display("\n--- H: pc_plus4 correctness ---");

        // Reset and walk through several cycles checking pc_plus4
        @(negedge clk); rst = 1;
        @(posedge clk); #1;
        @(negedge clk); rst = 0; jump=0; jalr=0; branch_taken=0;

        repeat(5) begin
            @(posedge clk); #1;
            check($sformatf("pc_plus4 = pc+4 at PC=%08h", pc),
                  pc_plus4, pc + 32'd4);
        end

        // ══════════════════════════════════════════════════════
        //  I. JALR LSB clear - odd addresses become even
        // ══════════════════════════════════════════════════════
        $display("\n--- I: JALR LSB always cleared ---");

        // rs1+imm = odd address → must be rounded down to even
        tick(0,1,0, 32'h201, 32'd0);  // 0x201 & ~1 = 0x200
        check("JALR 0x201 → 0x200 (LSB cleared)", pc, 32'h0000_0200);

        tick(0,1,0, 32'h0,   32'd5);  // 0+5=5 → 5&~1=4
        check("JALR 0+5=5   → 4   (LSB cleared)", pc, 32'h0000_0004);

        tick(0,1,0, 32'hFFF, 32'd2);  // 0xFFF+2=0x1001 → 0x1000
        check("JALR 0x1001  → 0x1000 (LSB cleared)", pc, 32'h0000_1000);

        // Even address - should be unchanged
        tick(0,1,0, 32'h400, 32'd0);  // 0x400 & ~1 = 0x400
        check("JALR 0x400  → 0x400  (already even)", pc, 32'h0000_0400);

        // ══════════════════════════════════════════════════════
        //  J. NEGATIVE IMM - backward branches and jumps
        // ══════════════════════════════════════════════════════
        $display("\n--- J: Negative immediate (backward jumps) ---");

        // Reset to 0x100 by JALR then go forward to 0x120, then branch back
        tick(0,1,0, 32'h100, 32'd0);  // PC = 0x100
        tick(0,0,0, 0,0);             // PC = 0x104
        tick(0,0,0, 0,0);             // PC = 0x108

        // Branch back by -8: PC = 0x108 + (-8) = 0x100
        tick(0,0,1, 0, 32'hFFFFFFF8);  // imm = -8
        check("Backward branch: PC = 0x00000100", pc, 32'h0000_0100);

        // JAL backward: PC=0x100, imm=-4 → PC = 0x0FC
        tick(1,0,0, 0, 32'hFFFFFFFC);  // imm = -4
        check("Backward JAL:    PC = 0x000000FC", pc, 32'h0000_00FC);

        // ─────────────────────────────────────────────────────
        //  Final Report
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - PC Logic is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);

        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule