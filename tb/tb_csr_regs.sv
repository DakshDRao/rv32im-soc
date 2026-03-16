// ============================================================
//  tb_csr_regs.sv  -  Unit testbench for csr_regs.sv
//  Project : Single-Cycle RV32IM SoC
//  Step    : 18 — CSRs + Trap Handling
//
//  Tests
//  ─────────────────────────────────────────────────────────
//   1. Reset state
//   2. CSRRW: rd ← old; CSR ← rs1
//   3. CSRRS: OR bits; skip write if rs1=x0
//   4. CSRRC: clear bits; skip write if rs1=x0
//   5. Immediate variants: CSRRWI / CSRRSI / CSRRCI
//   6. mstatus MIE/MPIE/MPP fields
//   7. mtvec write/read
//   8. mepc bit[1:0] forced 0
//   9. mip read-only reflects timer_irq
//  10. cycle counter increments
//  11. ECALL: trap_taken, mcause, mepc, MIE cleared
//  12. EBREAK: trap_taken, mcause=3
//  13. Timer interrupt: MIE=1 + MTIE=1 + timer_irq → trap
//  14. Interrupt suppressed when MIE=0
//  15. Interrupt suppressed when MTIE=0
//  16. Vectored mtvec: trap_pc = BASE + 4*cause for irq
//  17. MRET: MIE←MPIE, MPIE←1, mepc_out correct
//  18. CSR write suppressed when trap fires same cycle
//  19. mie mask (only [11][7][3] writable)
//  20. mhartid = 0
// ============================================================

`timescale 1ns/1ps

module tb_csr_regs;

// ─────────────────────────────────────────────────────────────
//  DUT Signals
// ─────────────────────────────────────────────────────────────
logic        clk, rst;
logic [11:0] csr_addr;
logic [31:0] rs1_data;
logic [4:0]  rs1_addr;
logic [4:0]  zimm;
logic [2:0]  csr_op;
logic        is_csr, is_ecall, is_ebreak, is_mret;
logic [31:0] pc;
logic        timer_irq, uart_irq, gpio_irq;

logic [31:0] mepc_out, trap_pc;
logic        trap_taken, mret_taken;
logic [31:0] csr_rdata;

csr_regs dut (.*);

// ─────────────────────────────────────────────────────────────
//  Clock
// ─────────────────────────────────────────────────────────────
initial clk = 0;
always #5 clk = ~clk;

// ─────────────────────────────────────────────────────────────
//  Test Infrastructure
// ─────────────────────────────────────────────────────────────
int pass_cnt = 0;
int fail_cnt = 0;

task automatic chk(input string name, input logic [31:0] got, input logic [31:0] exp);
    if (got === exp) begin
        $display("  PASS  %s", name);
        pass_cnt++;
    end else begin
        $display("  FAIL  %s  got=0x%08h  exp=0x%08h", name, got, exp);
        fail_cnt++;
    end
endtask

task automatic chk1(input string name, input logic got, input logic exp);
    chk(name, {31'h0, got}, {31'h0, exp});
endtask

// Drive a single CSR instruction for one cycle
task automatic do_csr(
    input  logic [11:0] a,
    input  logic [2:0]  op,
    input  logic [31:0] rdata_in,
    input  logic [4:0]  rs1_a,
    input  logic [4:0]  zi,
    input  logic [31:0] pc_in,
    output logic [31:0] old_val
);
    @(posedge clk); #1;
    csr_addr=a; csr_op=op; rs1_data=rdata_in; rs1_addr=rs1_a;
    zimm=zi; pc=pc_in;
    is_csr=1; is_ecall=0; is_ebreak=0; is_mret=0;
    timer_irq=0; uart_irq=0; gpio_irq=0;
    #1; old_val = csr_rdata;
    @(posedge clk); #1; is_csr=0;
endtask

task automatic csr_write(input logic [11:0] a, input logic [31:0] val);
    logic [31:0] dummy;
    do_csr(a, 3'b001, val, 5'h1, 5'h0, 32'h0, dummy);
endtask

task automatic csr_read(input logic [11:0] a, output logic [31:0] val);
    do_csr(a, 3'b010, 32'h0, 5'h0, 5'h0, 32'h0, val);
endtask

task automatic all_idle;
    @(posedge clk); #1;
    is_csr=0; is_ecall=0; is_ebreak=0; is_mret=0;
    timer_irq=0; uart_irq=0; gpio_irq=0;
endtask

// ─────────────────────────────────────────────────────────────
//  Test Body
// ─────────────────────────────────────────────────────────────
logic [31:0] val, old, c1;
logic        mpie_saved;

initial begin
    $dumpfile("tb_csr_regs.vcd");
    $dumpvars(0, tb_csr_regs);
    $display("\n=== tb_csr_regs ===\n");

    csr_addr=0; rs1_data=0; rs1_addr=0; zimm=0; csr_op=0;
    is_csr=0; is_ecall=0; is_ebreak=0; is_mret=0;
    pc=0; timer_irq=0; uart_irq=0; gpio_irq=0;
    rst=1; repeat(4) @(posedge clk); rst=0; @(posedge clk);

    // ── Test 1: Reset state ───────────────────────────────────
    $display("-- Test 1: Reset state");
    csr_read(12'h300, val); chk("mstatus=0x1800", val, 32'h0000_1800);
    csr_read(12'h304, val); chk("mie=0",          val, 32'h0);
    csr_read(12'h305, val); chk("mtvec=0",        val, 32'h0);
    csr_read(12'h341, val); chk("mepc=0",         val, 32'h0);
    csr_read(12'h342, val); chk("mcause=0",       val, 32'h0);
    chk1("trap_taken=0", trap_taken, 1'b0);

    // ── Test 2: CSRRW ─────────────────────────────────────────
    $display("-- Test 2: CSRRW");
    csr_write(12'h340, 32'hDEAD_BEEF);
    do_csr(12'h340, 3'b001, 32'hCAFE_BABE, 5'h1, 5'h0, 32'h0, old);
    chk("CSRRW old value", old, 32'hDEAD_BEEF);
    csr_read(12'h340, val); chk("CSRRW new value", val, 32'hCAFE_BABE);

    // ── Test 3: CSRRS + x0 skip ──────────────────────────────
    $display("-- Test 3: CSRRS");
    csr_write(12'h340, 32'hF0F0_F0F0);
    do_csr(12'h340, 3'b010, 32'h0F0F_0F0F, 5'h1, 5'h0, 32'h0, old);
    chk("CSRRS old", old, 32'hF0F0_F0F0);
    csr_read(12'h340, val); chk("CSRRS result", val, 32'hFFFF_FFFF);
    // x0 → no write
    csr_write(12'h340, 32'hAAAA_AAAA);
    do_csr(12'h340, 3'b010, 32'hFFFF_FFFF, 5'h0, 5'h0, 32'h0, old);
    csr_read(12'h340, val); chk("CSRRS x0 no-write", val, 32'hAAAA_AAAA);

    // ── Test 4: CSRRC ─────────────────────────────────────────
    $display("-- Test 4: CSRRC");
    csr_write(12'h340, 32'hFFFF_FFFF);
    do_csr(12'h340, 3'b011, 32'h0F0F_0F0F, 5'h2, 5'h0, 32'h0, old);
    chk("CSRRC old", old, 32'hFFFF_FFFF);
    csr_read(12'h340, val); chk("CSRRC result", val, 32'hF0F0_F0F0);

    // ── Test 5: Immediate variants ───────────────────────────
    $display("-- Test 5: CSRRWI/CSRRSI/CSRRCI");
    do_csr(12'h340, 3'b101, 32'h0, 5'h0, 5'h1F, 32'h0, old);
    csr_read(12'h340, val); chk("CSRRWI=0x1F",   val, 32'h1F);
    do_csr(12'h340, 3'b110, 32'h0, 5'h0, 5'h1,  32'h0, old);
    csr_read(12'h340, val); chk("CSRRSI or-1",   val, 32'h1F);
    do_csr(12'h340, 3'b111, 32'h0, 5'h0, 5'h1,  32'h0, old);
    csr_read(12'h340, val); chk("CSRRCI clr-1",  val, 32'h1E);
    // zimm=0 → no write
    csr_write(12'h340, 32'hBBBB_BBBB);
    do_csr(12'h340, 3'b110, 32'h0, 5'h0, 5'h0,  32'h0, old);
    csr_read(12'h340, val); chk("CSRRSI zimm=0 no-write", val, 32'hBBBB_BBBB);

    // ── Test 6: mstatus fields ───────────────────────────────
    $display("-- Test 6: mstatus MIE/MPP");
    do_csr(12'h300, 3'b010, 32'h8, 5'h1, 5'h0, 32'h0, old); // set MIE
    csr_read(12'h300, val);
    chk("mstatus MIE=1",   val & 32'h8,    32'h8);
    chk("mstatus MPP=11",  val & 32'h1800, 32'h1800);
    do_csr(12'h300, 3'b011, 32'h8, 5'h1, 5'h0, 32'h0, old); // clear MIE
    csr_read(12'h300, val);
    chk("mstatus MIE=0",   val & 32'h8, 32'h0);

    // ── Test 7: mtvec ────────────────────────────────────────
    $display("-- Test 7: mtvec");
    csr_write(12'h305, 32'h0000_4000);
    csr_read (12'h305, val); chk("mtvec=0x4000", val, 32'h4000);

    // ── Test 8: mepc alignment ───────────────────────────────
    $display("-- Test 8: mepc bit[1:0] forced 0");
    csr_write(12'h341, 32'h0000_1003);
    csr_read (12'h341, val);
    chk("mepc aligned", val, 32'h0000_1000);

    // ── Test 9: mip read-only ────────────────────────────────
    $display("-- Test 9: mip reflects timer_irq");
    @(posedge clk); #1;
    timer_irq=1; is_csr=0;
    // Sample mip combinationally while timer_irq is still high
    csr_addr=12'h344; csr_op=3'b010; rs1_data=32'h0; rs1_addr=5'h0;
    is_csr=0;  // read-only, no write needed
    #1;
    chk("mip.MTIP=1", csr_rdata & 32'h80, 32'h80);
    timer_irq=0;
    csr_write(12'h344, 32'hFFFF_FFFF); // should be ignored
    csr_read (12'h344, val); chk("mip write ignored", val & 32'h80, 32'h0);

    // ── Test 10: cycle counter ───────────────────────────────
    $display("-- Test 10: cycle counter");
    csr_read(12'hC00, val); c1 = val;
    repeat(5) all_idle;
    csr_read(12'hC00, val);
    if (val > c1) begin
        $display("  PASS  cycle increments (delta=%0d)", val-c1); pass_cnt++;
    end else begin
        $display("  FAIL  cycle stuck"); fail_cnt++;
    end

    // ── Test 11: ECALL trap ───────────────────────────────────
    $display("-- Test 11: ECALL");
    csr_write(12'h305, 32'h0000_8000);  // mtvec direct
    @(posedge clk); #1;
    is_ecall=1; pc=32'h0000_0100; timer_irq=0; is_csr=0;
    #1;
    chk1("trap_taken=1",  trap_taken, 1'b1);
    chk("trap_pc=mtvec",  trap_pc,    32'h0000_8000);
    @(posedge clk); #1; is_ecall=0;
    csr_read(12'h341, val); chk("mepc=0x100",        val, 32'h0000_0100);
    csr_read(12'h342, val); chk("mcause=0xB (ECALL)", val, 32'h0000_000B);
    csr_read(12'h300, val); chk("MIE cleared",        val & 32'h8, 32'h0);

    // ── Test 12: EBREAK trap ─────────────────────────────────
    $display("-- Test 12: EBREAK");
    @(posedge clk); #1;
    is_ebreak=1; pc=32'h0000_0200; is_csr=0;
    #1; chk1("trap_taken=1", trap_taken, 1'b1);
    @(posedge clk); #1; is_ebreak=0;
    csr_read(12'h342, val); chk("mcause=3 (EBREAK)", val, 32'h0000_0003);
    csr_read(12'h341, val); chk("mepc=0x200",        val, 32'h0000_0200);

    // ── Test 13: Timer interrupt ──────────────────────────────
    $display("-- Test 13: Timer interrupt");
    do_csr(12'h300, 3'b010, 32'h8, 5'h1, 5'h0, 32'h0, old); // MIE=1
    csr_write(12'h304, 32'h80);         // MTIE=1
    csr_write(12'h305, 32'h0000_C000);  // mtvec=0xC000
    @(posedge clk); #1;
    timer_irq=1; is_csr=0; pc=32'h0000_0300;
    #1;
    chk1("trap_taken=1 timer",     trap_taken, 1'b1);
    chk("trap_pc=0xC000",          trap_pc,    32'h0000_C000);
    @(posedge clk); #1; timer_irq=0;
    csr_read(12'h342, val); chk("mcause=0x80000007",   val, 32'h8000_0007);
    csr_read(12'h341, val); chk("mepc=0x300",          val, 32'h0000_0300);
    csr_read(12'h300, val); chk("MIE cleared on irq",  val & 32'h8, 32'h0);
    mpie_saved = val[7];             // save MPIE for test 17

    // ── Test 14: MIE=0 blocks interrupt ──────────────────────
    $display("-- Test 14: Interrupt blocked when MIE=0");
    csr_write(12'h304, 32'h80);
    @(posedge clk); #1;
    timer_irq=1; is_csr=0;
    #1; chk1("trap_taken=0 (MIE=0)", trap_taken, 1'b0);
    timer_irq=0;

    // ── Test 15: MTIE=0 blocks interrupt ─────────────────────
    $display("-- Test 15: Interrupt blocked when MTIE=0");
    do_csr(12'h300, 3'b010, 32'h8, 5'h1, 5'h0, 32'h0, old); // MIE=1
    csr_write(12'h304, 32'h0);           // MTIE=0
    @(posedge clk); #1;
    timer_irq=1; is_csr=0;
    #1; chk1("trap_taken=0 (MTIE=0)", trap_taken, 1'b0);
    timer_irq=0;

    // ── Test 16: Vectored trap PC ─────────────────────────────
    $display("-- Test 16: Vectored mtvec for timer IRQ");
    // BASE=0x1000 | MODE=1 → timer trap → 0x1000 + 4*7 = 0x101C
    csr_write(12'h305, 32'h0000_1001);
    csr_write(12'h304, 32'h80);
    do_csr(12'h300, 3'b010, 32'h8, 5'h1, 5'h0, 32'h0, old); // MIE=1
    @(posedge clk); #1;
    timer_irq=1; is_csr=0;
    #1; chk("trap_pc vectored 0x101C", trap_pc, 32'h0000_101C);
    @(posedge clk); #1; timer_irq=0;

    // ── Test 17: MRET ────────────────────────────────────────
    $display("-- Test 17: MRET");
    csr_write(12'h341, 32'h0000_0400);   // set mepc
    @(posedge clk); #1;
    is_mret=1; timer_irq=0; is_csr=0;
    #1;
    chk1("mret_taken=1",         mret_taken, 1'b1);
    chk1("trap_taken=0 on mret", trap_taken, 1'b0);
    chk("mepc_out=0x400",        mepc_out,   32'h0000_0400);
    @(posedge clk); #1; is_mret=0;
    csr_read(12'h300, val);
    chk("MPIE←1 after MRET",       val & 32'h80, 32'h80);
    chk("MIE←MPIE after MRET",     val & 32'h8, {31'h0, mpie_saved} << 3);

    // ── Test 18: CSR write suppressed on same-cycle trap ──────
    $display("-- Test 18: CSR write suppressed when trap fires");
    csr_write(12'h340, 32'hAAAA_AAAA);
    do_csr(12'h300, 3'b010, 32'h8, 5'h1, 5'h0, 32'h0, old); // MIE=1
    csr_write(12'h304, 32'h80);
    @(posedge clk); #1;
    // Both CSR write to mscratch AND timer_irq fire simultaneously
    csr_addr=12'h340; rs1_data=32'hDEAD_BEEF; rs1_addr=5'h1;
    csr_op=3'b001; is_csr=1; timer_irq=1; pc=32'h0;
    @(posedge clk); #1; is_csr=0; timer_irq=0;
    csr_read(12'h340, val);
    chk("mscratch unchanged (write suppressed)", val, 32'hAAAA_AAAA);

    // ── Test 19: mie mask ────────────────────────────────────
    $display("-- Test 19: mie mask [11][7][3] only");
    csr_write(12'h304, 32'hFFFF_FFFF);
    csr_read (12'h304, val); chk("mie mask=0x888", val, 32'h0000_0888);

    // ── Test 20: mhartid = 0 ────────────────────────────────
    $display("-- Test 20: mhartid=0");
    csr_read(12'hF14, val); chk("mhartid=0", val, 32'h0);

    // ── Summary ──────────────────────────────────────────────
    $display("\n=== Results: %0d/%0d passed ===", pass_cnt, pass_cnt+fail_cnt);
    if (fail_cnt == 0) $display("ALL TESTS PASSED\n");
    else               $display("%0d TESTS FAILED\n", fail_cnt);

    $finish;
end

initial begin #2_000_000; $display("TIMEOUT"); $finish; end

endmodule
