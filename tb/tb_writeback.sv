// ============================================================
//  tb_writeback.sv  -  Self-Checking Testbench for writeback.sv
//
//  Test groups:
//    A. WB_ALU  - wd = alu_result
//    B. WB_MEM  - wd = mem_rdata
//    C. WB_PC4  - wd = pc_plus4
//    D. WB_IMM  - wd = imm
//    E. Input isolation - changing inactive inputs doesn't affect output
//    F. All-same inputs - correct input is still selected
// ============================================================

`timescale 1ns/1ps

module tb_writeback;

    logic [1:0]  wb_sel;
    logic [31:0] alu_result, mem_rdata, pc_plus4, imm;
    logic [31:0] wd;

    writeback dut (.*);

    int pass_count = 0;
    int fail_count = 0;

    localparam [1:0] WB_ALU=2'b00, WB_MEM=2'b01, WB_PC4=2'b10, WB_IMM=2'b11;

    task automatic check(input string name, input [31:0] got, exp);
        if (got !== exp) begin
            $display("  FAIL  %-45s | got=%08h  exp=%08h", name, got, exp);
            fail_count++;
        end else begin
            $display("  PASS  %-45s | %08h", name, got);
            pass_count++;
        end
    endtask

    initial begin
        $display("\n========================================");
        $display("  Writeback Mux Testbench - RV32I");
        $display("========================================\n");

        // Distinct sentinel values for each input
        alu_result = 32'hAA_00_00_00;
        mem_rdata  = 32'h00_BB_00_00;
        pc_plus4   = 32'h00_00_CC_00;
        imm        = 32'h00_00_00_DD;

        // ── A. WB_ALU ─────────────────────────────────────────
        $display("--- A: WB_ALU ---");
        wb_sel = WB_ALU; #1;
        check("WB_ALU selects alu_result", wd, alu_result);

        alu_result = 32'hDEADBEEF; #1;
        check("WB_ALU tracks alu_result change", wd, 32'hDEADBEEF);

        alu_result = 32'h00000000; #1;
        check("WB_ALU: zero passthrough", wd, 32'h00000000);

        alu_result = 32'hFFFFFFFF; #1;
        check("WB_ALU: all-ones passthrough", wd, 32'hFFFFFFFF);

        // ── B. WB_MEM ─────────────────────────────────────────
        $display("\n--- B: WB_MEM ---");
        alu_result = 32'hAA000000; mem_rdata = 32'h00BB0000;
        wb_sel = WB_MEM; #1;
        check("WB_MEM selects mem_rdata", wd, 32'h00BB0000);

        mem_rdata = 32'hFFFFFFAA; #1;  // sign-extended LB result
        check("WB_MEM: sign-extended byte", wd, 32'hFFFFFFAA);

        mem_rdata = 32'h0000007F; #1;
        check("WB_MEM: positive byte", wd, 32'h0000007F);

        // ── C. WB_PC4 ─────────────────────────────────────────
        $display("\n--- C: WB_PC4 ---");
        pc_plus4 = 32'h00000008;
        wb_sel = WB_PC4; #1;
        check("WB_PC4 selects pc_plus4", wd, 32'h00000008);

        pc_plus4 = 32'h000100AC; #1;
        check("WB_PC4 tracks pc_plus4", wd, 32'h000100AC);

        // ── D. WB_IMM ─────────────────────────────────────────
        $display("\n--- D: WB_IMM ---");
        imm = 32'hABCDE000;   // LUI result: upper 20 bits set
        wb_sel = WB_IMM; #1;
        check("WB_IMM selects imm (LUI)", wd, 32'hABCDE000);

        imm = 32'hFFFFF000; #1;
        check("WB_IMM: max negative LUI",  wd, 32'hFFFFF000);

        imm = 32'h00001000; #1;
        check("WB_IMM: small positive LUI",wd, 32'h00001000);

        // ── E. Input isolation ────────────────────────────────
        $display("\n--- E: Input isolation ---");

        // WB_ALU selected - changing other inputs must not affect wd
        alu_result=32'h12345678; mem_rdata=32'hAA; pc_plus4=32'hBB; imm=32'hCC;
        wb_sel = WB_ALU; #1;
        check("WB_ALU: wd immune to mem/pc4/imm changes", wd, 32'h12345678);
        mem_rdata=32'hDEADBEEF; pc_plus4=32'hCAFEBABE; imm=32'hFFFFFFFF; #1;
        check("WB_ALU: still unchanged after other inputs change", wd, 32'h12345678);

        // WB_MEM selected - changing alu/pc4/imm must not affect wd
        mem_rdata=32'hBEEFCAFE;
        wb_sel = WB_MEM; #1;
        alu_result=32'h11111111; pc_plus4=32'h22222222; imm=32'h33333333; #1;
        check("WB_MEM: wd immune to alu/pc4/imm changes", wd, 32'hBEEFCAFE);

        // ── F. All-same inputs ────────────────────────────────
        $display("\n--- F: All inputs same value ---");
        alu_result=32'hCAFEBABE; mem_rdata=32'hCAFEBABE;
        pc_plus4=32'hCAFEBABE;  imm=32'hCAFEBABE;

        wb_sel = WB_ALU; #1; check("All-same WB_ALU", wd, 32'hCAFEBABE);
        wb_sel = WB_MEM; #1; check("All-same WB_MEM", wd, 32'hCAFEBABE);
        wb_sel = WB_PC4; #1; check("All-same WB_PC4", wd, 32'hCAFEBABE);
        wb_sel = WB_IMM; #1; check("All-same WB_IMM", wd, 32'hCAFEBABE);

        // ─────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED - Writeback Mux is correct ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_count);
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule