// ============================================================
//  tb_riscv_core.sv  -  Integration Testbench for riscv_core
//
//  Strategy: load small hand-assembled programs, run them,
//  then peek inside the register file via hierarchical paths
//  to verify the correct values were computed.
//
//  Test programs:
//    P1. ALU basics    - ADDI, ADD, SUB, AND, OR, XOR
//    P2. Loads/Stores  - SW, LW, SB, LB, SH, LH, LBU, LHU
//    P3. Branches      - BEQ, BNE, BLT, BGE (taken + not taken)
//    P4. JAL / JALR    - jump and link, return address
//    P5. LUI / AUIPC   - upper immediate and PC-relative
//    P6. Shifts        - SLLI, SRLI, SRAI, SLL, SRL, SRA
// ============================================================

`timescale 1ns/1ps

module tb_riscv_core;

    // ── DUT Ports ─────────────────────────────────────────────
    logic clk, rst;

    // ── DUT - 256-word IMEM/DMEM ──────────────────────────────
    riscv_core #(
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .BOOT_ADDR (32'h0),
        .IMEM_FILE ("C:/Users/Daksh/RISCV/riscv_core/sw/test.mem")
    ) dut (.*);

    // ── Clock ─────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Counters ──────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    // ─────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────
    task automatic check(input string name, input [31:0] got, exp);
        if (got !== exp) begin
            $display("  FAIL  %-45s | got=%08h  exp=%08h", name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-45s | %08h", name, got);
            pass_count++;
        end
    endtask

    // Read a register from the live register file
    function automatic [31:0] xreg(input int n);
        if (n == 0) return 32'h0;
        return dut.u_regfile.regs[n];
    endfunction

    // Load a program into IMEM and reset the core
    task automatic load_and_reset(input [31:0] prog[]);
        // Reset core
        rst = 1;
        @(posedge clk); @(posedge clk); #1;
        // Load program words into IMEM array
        for (int i = 0; i < prog.size(); i++)
            dut.u_imem.mem[i] = prog[i];
        // Pad remaining with NOP
        for (int i = prog.size(); i < 256; i++)
            dut.u_imem.mem[i] = 32'h00000013;
        // Release reset
        @(negedge clk); rst = 0;
        #1;
    endtask

    // Run N instructions (1 clock each - async memory, single-cycle core)
    task automatic run(input int n_instr);
        repeat(n_instr) @(posedge clk);
        #1;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Instruction Encoders (same as tb_imm_gen)
    // ─────────────────────────────────────────────────────────
    function automatic [31:0] NOP();
        return 32'h00000013;  // ADDI x0, x0, 0
    endfunction

    function automatic [31:0] ADDI(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic [31:0] ADD(input [4:0] rd, rs1, rs2);
        return {7'b0, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function automatic [31:0] SUB(input [4:0] rd, rs1, rs2);
        return {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function automatic [31:0] AND_(input [4:0] rd, rs1, rs2);
        return {7'b0, rs2, rs1, 3'b111, rd, 7'b0110011};
    endfunction

    function automatic [31:0] OR_(input [4:0] rd, rs1, rs2);
        return {7'b0, rs2, rs1, 3'b110, rd, 7'b0110011};
    endfunction

    function automatic [31:0] XOR_(input [4:0] rd, rs1, rs2);
        return {7'b0, rs2, rs1, 3'b100, rd, 7'b0110011};
    endfunction

    function automatic [31:0] SW(input [4:0] rs1, rs2, input [11:0] imm12);
        return {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] LW(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function automatic [31:0] SB(input [4:0] rs1, rs2, input [11:0] imm12);
        return {imm12[11:5], rs2, rs1, 3'b000, imm12[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] LB(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b000, rd, 7'b0000011};
    endfunction

    function automatic [31:0] LBU(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b100, rd, 7'b0000011};
    endfunction

    function automatic [31:0] SH(input [4:0] rs1, rs2, input [11:0] imm12);
        return {imm12[11:5], rs2, rs1, 3'b001, imm12[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] LH(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b001, rd, 7'b0000011};
    endfunction

    function automatic [31:0] LHU(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b101, rd, 7'b0000011};
    endfunction

    function automatic [31:0] BEQ(input [4:0] rs1, rs2, input [12:0] off);
        return {off[12],off[10:5],rs2,rs1,3'b000,off[4:1],off[11],7'b1100011};
    endfunction

    function automatic [31:0] BNE(input [4:0] rs1, rs2, input [12:0] off);
        return {off[12],off[10:5],rs2,rs1,3'b001,off[4:1],off[11],7'b1100011};
    endfunction

    function automatic [31:0] BLT(input [4:0] rs1, rs2, input [12:0] off);
        return {off[12],off[10:5],rs2,rs1,3'b100,off[4:1],off[11],7'b1100011};
    endfunction

    function automatic [31:0] BGE(input [4:0] rs1, rs2, input [12:0] off);
        return {off[12],off[10:5],rs2,rs1,3'b101,off[4:1],off[11],7'b1100011};
    endfunction

    function automatic [31:0] JAL_(input [4:0] rd, input [20:0] off);
        return {off[20],off[10:1],off[11],off[19:12],rd,7'b1101111};
    endfunction

    function automatic [31:0] JALR_(input [4:0] rd, rs1, input [11:0] imm12);
        return {imm12, rs1, 3'b000, rd, 7'b1100111};
    endfunction

    function automatic [31:0] LUI_(input [4:0] rd, input [19:0] imm20);
        return {imm20, rd, 7'b0110111};
    endfunction

    function automatic [31:0] AUIPC_(input [4:0] rd, input [19:0] imm20);
        return {imm20, rd, 7'b0010111};
    endfunction

    function automatic [31:0] SLLI(input [4:0] rd, rs1, shamt);
        return {7'b0, shamt, rs1, 3'b001, rd, 7'b0010011};
    endfunction

    function automatic [31:0] SRLI(input [4:0] rd, rs1, shamt);
        return {7'b0, shamt, rs1, 3'b101, rd, 7'b0010011};
    endfunction

    function automatic [31:0] SRAI(input [4:0] rd, rs1, shamt);
        return {7'b0100000, shamt, rs1, 3'b101, rd, 7'b0010011};
    endfunction

    function automatic [31:0] SLL_(input [4:0] rd, rs1, rs2);
        return {7'b0, rs2, rs1, 3'b001, rd, 7'b0110011};
    endfunction

    function automatic [31:0] SRL_(input [4:0] rd, rs1, rs2);
        return {7'b0, rs2, rs1, 3'b101, rd, 7'b0110011};
    endfunction

    function automatic [31:0] SRA_(input [4:0] rd, rs1, rs2);
        return {7'b0100000, rs2, rs1, 3'b101, rd, 7'b0110011};
    endfunction
    
    function automatic [31:0] MUL_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b000, rd, 7'b011_0011};
    endfunction
    
    function automatic [31:0] MULH_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b001, rd, 7'b011_0011};
    endfunction
    
    function automatic [31:0] MULHU_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b011, rd, 7'b011_0011};
    endfunction
    
    function automatic [31:0] DIV_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b100, rd, 7'b011_0011};
    endfunction
    
    function automatic [31:0] DIVU_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b101, rd, 7'b011_0011};
    endfunction
    
    function automatic [31:0] REM_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b110, rd, 7'b011_0011};
    endfunction
    
    function automatic [31:0] REMU_(input [4:0] rd, rs1, rs2);
        return {7'b000_0001, rs2, rs1, 3'b111, rd, 7'b011_0011};
    endfunction


    // ─────────────────────────────────────────────────────────
    //  Main Test Sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        $display("\n========================================");
        $display("  RV32I Core Integration Testbench");
        $display("========================================\n");

        rst = 1; #10;

        // ══════════════════════════════════════════════════════
        //  P1. ALU Basics
        //  x1=10, x2=3
        //  x3=x1+x2=13, x4=x1-x2=7, x5=x1&x2=2
        //  x6=x1|x2=11, x7=x1^x2=9, x8=x1+100=110
        // ══════════════════════════════════════════════════════
        $display("--- P1: ALU Basics ---");
        begin
            logic [31:0] prog[];
            prog = new[9];
            prog[0] = ADDI(1, 0, 12'd10);    // x1 = 10
            prog[1] = ADDI(2, 0, 12'd3);     // x2 = 3
            prog[2] = ADD(3, 1, 2);           // x3 = 13
            prog[3] = SUB(4, 1, 2);           // x4 = 7
            prog[4] = AND_(5, 1, 2);          // x5 = 2
            prog[5] = OR_ (6, 1, 2);          // x6 = 11
            prog[6] = XOR_(7, 1, 2);          // x7 = 9
            prog[7] = ADDI(8, 1, 12'd100);    // x8 = 110
            prog[8] = NOP();
            load_and_reset(prog);
            run(9);
            check("P1: x1=10",  xreg(1), 32'd10);
            check("P1: x2=3",   xreg(2), 32'd3);
            check("P1: x3=13",  xreg(3), 32'd13);
            check("P1: x4=7",   xreg(4), 32'd7);
            check("P1: x5=2",   xreg(5), 32'd2);
            check("P1: x6=11",  xreg(6), 32'd11);
            check("P1: x7=9",   xreg(7), 32'd9);
            check("P1: x8=110", xreg(8), 32'd110);
        end

        // ══════════════════════════════════════════════════════
        //  P2. Loads / Stores
        //  Store 0xDEADBEEF, load it back as word, byte, halfword
        // ══════════════════════════════════════════════════════
        $display("\n--- P2: Loads / Stores ---");
        begin
            logic [31:0] prog[];
            prog = new[14];
            // x1 = 0xBEEF via LUI+ADDI trick (lower 12 bits)
            prog[0]  = LUI_(1, 20'hDEADC);      // x1 = 0xDEADC000
            prog[1]  = ADDI(1, 1, 12'hEEF);     // x1 = 0xDEADBEEF (DEADC000-1111+EEF)
            // Actually: LUI loads upper 20, then ADDI adds signed imm
            // 0xDEADC000 + 0xFFFFFEEF = 0xDEADBEEF ✓  (0xEEF is positive)
            // Let's use simpler known value: store 0x12345678
            prog[0]  = ADDI(1, 0, 12'd0);       // x1 = base addr = 0
            prog[1]  = LUI_(2, 20'h12345);       // x2 = 0x12345000
            prog[2]  = ADDI(2, 2, 12'h678);      // x2 = 0x12345678
            prog[3]  = SW(1, 2, 12'd0);          // mem[0] = 0x12345678
            prog[4]  = LW(3, 1, 12'd0);          // x3 = mem[0] = 0x12345678
            prog[5]  = LB(4, 1, 12'd0);          // x4 = sign_ext(0x78) = 0x78
            prog[6]  = LB(5, 1, 12'd1);          // x5 = sign_ext(0x56) = 0x56
            prog[7]  = LBU(6, 1, 12'd0);         // x6 = 0x78 (unsigned)
            prog[8]  = SB(1, 2, 12'd4);          // mem[4][7:0] = 0x78
            prog[9]  = LBU(7, 1, 12'd4);         // x7 = 0x78
            prog[10] = SH(1, 2, 12'd8);          // mem[8][15:0] = 0x5678
            prog[11] = LH(8, 1, 12'd8);          // x8 = sign_ext(0x5678)=0x5678
            prog[12] = LHU(9, 1, 12'd8);         // x9 = 0x5678 (unsigned)
            prog[13] = NOP();
            load_and_reset(prog);
            run(14);
            check("P2: LW  0x12345678",   xreg(3), 32'h12345678);
            check("P2: LB  byte0=0x78",   xreg(4), 32'h00000078);
            check("P2: LB  byte1=0x56",   xreg(5), 32'h00000056);
            check("P2: LBU byte0=0x78",   xreg(6), 32'h00000078);
            check("P2: SB/LBU 0x78",      xreg(7), 32'h00000078);
            check("P2: LH  0x5678",       xreg(8), 32'h00005678);
            check("P2: LHU 0x5678",       xreg(9), 32'h00005678);
        end

        // ══════════════════════════════════════════════════════
        //  P3. Branches
        //  BEQ taken skips ADDI; BNE taken skips; BLT/BGE
        // ══════════════════════════════════════════════════════
        $display("\n--- P3: Branches ---");
        begin
            logic [31:0] prog[];
            prog = new[12];
            prog[0]  = ADDI(1, 0, 12'd5);        // x1 = 5
            prog[1]  = ADDI(2, 0, 12'd5);        // x2 = 5
            prog[2]  = ADDI(3, 0, 12'd10);       // x3 = 10
            // BEQ x1,x2,+8: taken → skip prog[4], land on prog[5]
            prog[3]  = BEQ(1, 2, 13'd8);
            prog[4]  = ADDI(4, 0, 12'd99);       // x4=99 (should be SKIPPED)
            prog[5]  = ADDI(4, 0, 12'd1);        // x4=1  (should execute)
            // BNE x1,x3,+8: taken (5≠10) → skip prog[7], land on prog[8]
            prog[6]  = BNE(1, 3, 13'd8);
            prog[7]  = ADDI(5, 0, 12'd99);       // x5=99 (should be SKIPPED)
            prog[8]  = ADDI(5, 0, 12'd2);        // x5=2  (should execute)
            // BLT x1,x3,+8: taken (5<10) → skip prog[10], land on prog[11]
            prog[9]  = BLT(1, 3, 13'd8);
            prog[10] = ADDI(6, 0, 12'd99);       // x6=99 (should be SKIPPED)
            prog[11] = ADDI(6, 0, 12'd3);        // x6=3  (should execute)
            load_and_reset(prog);
            run(14);   // extra cycles to let branches settle
            check("P3: BEQ taken - x4=1  (not 99)", xreg(4), 32'd1);
            check("P3: BNE taken - x5=2  (not 99)", xreg(5), 32'd2);
            check("P3: BLT taken - x6=3  (not 99)", xreg(6), 32'd3);
        end

        // ══════════════════════════════════════════════════════
        //  P4. JAL / JALR
        //  JAL saves PC+4 in x1, jumps forward
        //  JALR uses x1 to jump back to return address
        // ══════════════════════════════════════════════════════
        $display("\n--- P4: JAL / JALR ---");
        begin
            logic [31:0] prog[];
            prog = new[8];
            // prog[0] at PC=0x00: JAL x1, +12 → jumps to prog[3] (PC=0x0C)
            //   x1 = return address = 0x04
            prog[0] = JAL_(1, 21'd12);
            prog[1] = ADDI(2, 0, 12'd99);    // SKIPPED
            prog[2] = ADDI(2, 0, 12'd99);    // SKIPPED
            // prog[3] at PC=0x0C: x3=42, then JALR x0, x1, 0 → jumps to PC=0x04
            prog[3] = ADDI(3, 0, 12'd42);
            prog[4] = JALR_(0, 1, 12'd0);    // jump to x1=0x04
            // prog[5] would be at 0x14 - never reached
            prog[5] = ADDI(4, 0, 12'd99);    // SKIPPED
            // prog[1] at PC=0x04 gets executed after JALR return:
            // We reuse prog[1] - let's replace with something we can check
            // Since prog[1]=0x04 is executed after the return, make it useful:
            prog[1] = ADDI(5, 0, 12'd7);     // x5=7 (executed after JALR return)
            prog[2] = NOP();                  // clear - was ADDI x2,99, still in array
            prog[6] = NOP();
            prog[7] = NOP();
            load_and_reset(prog);
            run(12);
            check("P4: JAL  x1=0x04 (ret addr)", xreg(1), 32'h00000004);
            check("P4: JAL  x3=42",              xreg(3), 32'd42);
            check("P4: JALR x5=7 (after return)",xreg(5), 32'd7);
        end

        // ══════════════════════════════════════════════════════
        //  P5. LUI / AUIPC
        // ══════════════════════════════════════════════════════
        $display("\n--- P5: LUI / AUIPC ---");
        begin
            logic [31:0] prog[];
            prog = new[4];
            // PC=0x00: LUI x1, 0xABCDE → x1 = 0xABCDE000
            prog[0] = LUI_(1, 20'hABCDE);
            // PC=0x04: AUIPC x2, 1 → x2 = PC + 0x1000 = 0x04 + 0x1000 = 0x1004
            // BUT: due to BRAM 1-cycle latency, actual PC seen by AUIPC is 0x04
            prog[1] = AUIPC_(2, 20'd1);
            prog[2] = NOP();
            prog[3] = NOP();
            load_and_reset(prog);
            run(4);
            check("P5: LUI   x1=0xABCDE000", xreg(1), 32'hABCDE000);
            check("P5: AUIPC x2=PC+0x1000",  xreg(2), 32'h00001004);
        end

        // ══════════════════════════════════════════════════════
        //  P6. Shifts
        // ══════════════════════════════════════════════════════
        $display("\n--- P6: Shifts ---");
        begin
            logic [31:0] prog[];
            prog = new[10];
            prog[0] = ADDI(1, 0, 12'd1);         // x1 = 1
            prog[1] = ADDI(2, 0, 12'd4);         // x2 = 4  (shift amount)
            prog[2] = SLLI(3, 1, 5'd4);          // x3 = 1<<4 = 16
            prog[3] = SRLI(4, 3, 5'd2);          // x4 = 16>>2 = 4
            prog[4] = LUI_(5, 20'h80000);        // x5 = 0x80000000 (negative)
            prog[5] = SRAI(6, 5, 5'd4);          // x6 = 0x80000000>>>4 = 0xF8000000
            prog[6] = SLL_(7, 1, 2);             // x7 = 1<<4 = 16
            prog[7] = SRL_(8, 3, 2);             // x8 = 16>>4 = 1
            prog[8] = SRA_(9, 5, 2);             // x9 = 0x80000000>>>4 = 0xF8000000
            prog[9] = NOP();
            load_and_reset(prog);
            run(10);
            check("P6: SLLI 1<<4=16",       xreg(3), 32'd16);
            check("P6: SRLI 16>>2=4",       xreg(4), 32'd4);
            check("P6: SRAI 0x80000000>>4", xreg(6), 32'hF8000000);
            check("P6: SLL  1<<4=16",       xreg(7), 32'd16);
            check("P6: SRL  16>>4=1",       xreg(8), 32'd1);
            check("P6: SRA  0x80000000>>4", xreg(9), 32'hF8000000);
        end
        // ══════════════════════════════════════════════════════
        //  P7. M-Extension (MUL / DIV / REM)
        //
        //  x1 = 20, x2 = 6, x3 = -20 (0xFFFFFFEC), x4 = -1
        //  x5  = MUL   x1, x2  = 120
        //  x6  = DIV   x1, x2  = 3
        //  x7  = REM   x1, x2  = 2
        //  x8  = DIV   x3, x2  = -3  (signed, truncate toward 0)
        //  x9  = REM   x3, x2  = -2  (sign follows dividend)
        //  x10 = DIVU  x1, x2  = 3
        //  x11 = REMU  x1, x2  = 2
        //  x12 = MULHU x4, x4  = 0xFFFFFFFE (upper 32 of 0xFFFFFFFF²)
        //  x13 = DIV   x1, x0  = 0xFFFFFFFF (div-by-zero)
        //  x14 = REM   x1, x0  = 20          (div-by-zero rem=dividend)
        // ══════════════════════════════════════════════════════
        $display("\n--- P7: M-Extension ---");
        begin
            logic [31:0] prog[];
            prog = new[16];
            prog[0]  = ADDI(1,  0, 12'd20);          // x1  = 20
            prog[1]  = ADDI(2,  0, 12'd6);           // x2  = 6
            prog[2]  = ADDI(3,  0, 12'hFEC);         // x3  = -20  (0xFFFFFFEC)
            prog[3]  = ADDI(4,  0, 12'hFFF);         // x4  = -1   (0xFFFFFFFF)
            prog[4]  = MUL_ (5,  1, 2);              // x5  = 120
            prog[5]  = DIV_ (6,  1, 2);              // x6  = 3
            prog[6]  = REM_ (7,  1, 2);              // x7  = 2
            prog[7]  = DIV_ (8,  3, 2);              // x8  = -3
            prog[8]  = REM_ (9,  3, 2);              // x9  = -2
            prog[9]  = DIVU_(10, 1, 2);              // x10 = 3
            prog[10] = REMU_(11, 1, 2);              // x11 = 2
            prog[11] = MULHU_(12, 4, 4);             // x12 = 0xFFFFFFFE
            prog[12] = DIV_ (13, 1, 0);              // x13 = 0xFFFFFFFF (dbz)
            prog[13] = REM_ (14, 1, 0);              // x14 = 20         (dbz)
            prog[14] = NOP();
            prog[15] = NOP();
            load_and_reset(prog);
            run(16);
            check("P7: MUL   20×6=120",              xreg(5),  32'd120);
            check("P7: DIV   20/6=3",                xreg(6),  32'd3);
            check("P7: REM   20%6=2",                xreg(7),  32'd2);
            check("P7: DIV  -20/6=-3",               xreg(8),  32'hFFFF_FFFD);
            check("P7: REM  -20%6=-2",               xreg(9),  32'hFFFF_FFFE);
            check("P7: DIVU  20/6=3",                xreg(10), 32'd3);
            check("P7: REMU  20%6=2",                xreg(11), 32'd2);
            check("P7: MULHU (-1)²=0xFFFFFFFE",      xreg(12), 32'hFFFF_FFFE);
            check("P7: DIV   dbz=0xFFFFFFFF",        xreg(13), 32'hFFFF_FFFF);
            check("P7: REM   dbz=dividend(20)",      xreg(14), 32'd20);
        end
        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - Core integration correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);
        $finish;
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule