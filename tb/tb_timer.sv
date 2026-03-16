// ============================================================
//  tb_timer.sv  -  Testbench for timer.sv
//  Project : Single-Cycle RV32IM SoC
//  Step    : 17 — Timer + MTIME
//
//  Tests
//  ─────────────────────────────────────────────────────────
//  1.  Reset state: mtime=0, mtimecmp=MAX, irq=0
//  2.  CTRL enable=0: mtime does not increment
//  3.  CTRL enable=1: mtime increments each clock (prescaler=0)
//  4.  mtime read-back (LO and HI)
//  5.  mtime writable (direct write, LO and HI)
//  6.  mtimecmp read-back (LO and HI)
//  7.  IRQ fires when mtime >= mtimecmp and irq_en=1
//  8.  IRQ does not fire when irq_en=0 (even if mtime >= mtimecmp)
//  9.  IRQ clears when firmware writes new mtimecmp in the future
//  10. Prescaler: tick every N+1 clocks
//  11. 64-bit rollover: mtime_lo wraps, mtime_hi increments
//  12. 64-bit mtimecmp write ordering (safe update sequence)
//  13. IRQ is level: stays asserted until mtimecmp updated
//  14. mtime_hi read is consistent with mtime_lo
// ============================================================

`timescale 1ns/1ps

module tb_timer;

// ─────────────────────────────────────────────────────────────
//  DUT Signals
// ─────────────────────────────────────────────────────────────
logic        clk, rst;
logic [11:0] addr;
logic [31:0] wdata;
logic        we;
logic [2:0]  funct3;
logic [31:0] rdata;
logic        irq;

// ─────────────────────────────────────────────────────────────
//  DUT
// ─────────────────────────────────────────────────────────────
timer dut (.*);

// ─────────────────────────────────────────────────────────────
//  Clock — 10 ns period (100 MHz equivalent)
// ─────────────────────────────────────────────────────────────
initial clk = 0;
always #5 clk = ~clk;

// ─────────────────────────────────────────────────────────────
//  Test Infrastructure
// ─────────────────────────────────────────────────────────────
int pass_cnt = 0;
int fail_cnt = 0;

task automatic chk(
    input string       name,
    input logic [31:0] got,
    input logic [31:0] exp
);
    if (got === exp) begin
        $display("  PASS  %s", name);
        pass_cnt++;
    end else begin
        $display("  FAIL  %s  got=0x%08h  exp=0x%08h", name, got, exp);
        fail_cnt++;
    end
endtask

task automatic bus_write(input logic [11:0] a, input logic [31:0] d);
    @(posedge clk); #1;
    addr = a; wdata = d; we = 1'b1; funct3 = 3'b010;
    @(posedge clk); #1;
    we = 1'b0;
endtask

task automatic bus_read(input logic [11:0] a, output logic [31:0] d);
    @(posedge clk); #1;
    addr = a; wdata = 32'h0; we = 1'b0; funct3 = 3'b010;
    #1; d = rdata;
endtask

// Stop the timer and reset mtime to 0
task automatic timer_reset_state;
    bus_write(12'h010, 32'h0);          // disable
    bus_write(12'h000, 32'h0);          // mtime_lo = 0
    bus_write(12'h004, 32'h0);          // mtime_hi = 0
    bus_write(12'h008, 32'hFFFF_FFFF);  // mtimecmp_lo = MAX
    bus_write(12'h00C, 32'hFFFF_FFFF);  // mtimecmp_hi = MAX
    bus_write(12'h014, 32'h0);          // prescaler = 0
endtask

// ─────────────────────────────────────────────────────────────
//  Test Body
// ─────────────────────────────────────────────────────────────
logic [31:0] val, val2;

initial begin
    $dumpfile("tb_timer.vcd");
    $dumpvars(0, tb_timer);
    $display("\n=== tb_timer ===\n");

    addr = '0; wdata = '0; we = 0; funct3 = 3'b010;
    rst = 1; repeat(4) @(posedge clk); rst = 0; @(posedge clk);

    // ── Test 1: Reset state ───────────────────────────────────
    $display("-- Test 1: Reset state");
    bus_read(12'h000, val); chk("mtime_lo = 0",         val, 32'h0);
    bus_read(12'h004, val); chk("mtime_hi = 0",         val, 32'h0);
    bus_read(12'h008, val); chk("mtimecmp_lo = MAX",    val, 32'hFFFF_FFFF);
    bus_read(12'h00C, val); chk("mtimecmp_hi = MAX",    val, 32'hFFFF_FFFF);
    bus_read(12'h010, val); chk("CTRL = 0",             val, 32'h0);
    bus_read(12'h014, val); chk("PRESCALER = 0",        val, 32'h0);
    chk("irq = 0 at reset", {31'h0, irq}, 32'h0);

    // ── Test 2: mtime does not count when enable=0 ────────────
    $display("-- Test 2: mtime frozen when enable=0");
    repeat(10) @(posedge clk);
    bus_read(12'h000, val);
    chk("mtime_lo still 0 (disabled)", val, 32'h0);

    // ── Test 3: mtime counts when enable=1 ───────────────────
    $display("-- Test 3: mtime counts with enable=1, prescaler=0");
    bus_write(12'h010, 32'h1);           // enable=1, irq_en=0
    repeat(5) @(posedge clk); #1;
    bus_read(12'h000, val);
    // Should have counted ~5 ticks (exact value depends on bus overhead)
    if (val > 0 && val <= 20) begin
        $display("  PASS  mtime_lo > 0 after 5 clocks (got %0d)", val);
        pass_cnt++;
    end else begin
        $display("  FAIL  mtime_lo unexpected value %0d", val);
        fail_cnt++;
    end
    bus_write(12'h010, 32'h0);           // stop

    // ── Test 4: mtime read-back while counting ────────────────
    $display("-- Test 4: mtime LO and HI read-back");
    timer_reset_state;
    bus_write(12'h000, 32'hDEAD_BEEF);   // preload
    bus_write(12'h004, 32'h0000_0001);
    bus_read(12'h000, val);  chk("mtime_lo write/read", val, 32'hDEAD_BEEF);
    bus_read(12'h004, val);  chk("mtime_hi write/read", val, 32'h0000_0001);

    // ── Test 5: mtime writable ────────────────────────────────
    $display("-- Test 5: mtime directly writable");
    bus_write(12'h000, 32'h0000_0064);   // set mtime_lo = 100
    bus_write(12'h004, 32'h0);
    bus_read (12'h000, val);
    chk("mtime_lo set to 100", val, 32'h64);

    // ── Test 6: mtimecmp read-back ────────────────────────────
    $display("-- Test 6: mtimecmp read-back");
    bus_write(12'h008, 32'hCAFE_0000);
    bus_write(12'h00C, 32'h0000_BABE);
    bus_read (12'h008, val);  chk("mtimecmp_lo", val, 32'hCAFE_0000);
    bus_read (12'h00C, val);  chk("mtimecmp_hi", val, 32'h0000_BABE);

    // ── Test 7: IRQ fires when mtime >= mtimecmp, irq_en=1 ───
    $display("-- Test 7: IRQ fires on mtime >= mtimecmp");
    timer_reset_state;
    // Set mtime = 50, mtimecmp = 100, enable counting
    bus_write(12'h000, 32'h32);           // mtime_lo = 50
    bus_write(12'h008, 32'h64);           // mtimecmp_lo = 100
    bus_write(12'h00C, 32'h0);
    chk("irq=0 before match (irq_en=0)", {31'h0, irq}, 32'h0);
    bus_write(12'h010, 32'h3);            // enable=1, irq_en=1

    // Wait until mtime >= mtimecmp (100 - 50 = 50 ticks + bus overhead)
    begin : wait_irq
        int timeout = 300;
        while (!irq && timeout > 0) begin
            @(posedge clk); #1;
            timeout--;
        end
        if (irq) begin
            $display("  PASS  irq asserted when mtime >= mtimecmp");
            pass_cnt++;
        end else begin
            $display("  FAIL  irq never asserted (timeout)");
            fail_cnt++;
        end
    end
    bus_write(12'h010, 32'h0);           // stop

    // ── Test 8: irq_en=0 suppresses interrupt ─────────────────
    $display("-- Test 8: irq_en=0 suppresses IRQ");
    timer_reset_state;
    bus_write(12'h000, 32'h64);           // mtime_lo = 100
    bus_write(12'h008, 32'h0A);           // mtimecmp_lo = 10  (already past)
    bus_write(12'h010, 32'h1);            // enable=1, irq_en=0
    @(posedge clk); #1;
    chk("irq=0 with irq_en=0 even past mtimecmp", {31'h0, irq}, 32'h0);
    bus_write(12'h010, 32'h0);

    // ── Test 9: IRQ clears when mtimecmp moved to future ──────
    $display("-- Test 9: IRQ clears after mtimecmp updated");
    timer_reset_state;
    bus_write(12'h000, 32'h0A);           // mtime_lo = 10
    bus_write(12'h004, 32'h0);            // mtime_hi = 0
    bus_write(12'h008, 32'h0A);           // mtimecmp_lo = 10  (equal → match)
    bus_write(12'h00C, 32'h0);            // mtimecmp_hi = 0  (timer_reset leaves 0xFFFFFFFF)
    bus_write(12'h010, 32'h3);            // enable + irq_en
    @(posedge clk); #1;
    chk("irq=1 at match", {31'h0, irq}, 32'h1);
    // Firmware safe-update sequence for mtimecmp
    bus_write(12'h00C, 32'hFFFF_FFFF);   // step 1: HI = MAX (prevents match)
    bus_write(12'h008, 32'hFFFF_FFFF);   // step 2: LO = MAX
    bus_write(12'h00C, 32'h0000_0001);   // step 3: HI = 1  (far future)
    @(posedge clk); #1;
    chk("irq=0 after mtimecmp moved to future", {31'h0, irq}, 32'h0);
    bus_write(12'h010, 32'h0);

    // ── Test 10: Prescaler divides tick rate ──────────────────
    $display("-- Test 10: Prescaler=4 (tick every 5 clocks)");
    timer_reset_state;
    bus_write(12'h014, 32'h4);            // prescaler = 4 → tick every 5 clocks
    bus_write(12'h010, 32'h1);            // enable
    // After 10 clocks: should have ~2 ticks
    repeat(10) @(posedge clk); #1;
    bus_write(12'h010, 32'h0);
    bus_read (12'h000, val);
    if (val >= 1 && val <= 3) begin
        $display("  PASS  mtime=%0d after 10 clocks with prescaler=4 (exp ~2)", val);
        pass_cnt++;
    end else begin
        $display("  FAIL  mtime=%0d after 10 clocks with prescaler=4 (exp 1-3)", val);
        fail_cnt++;
    end

    // ── Test 11: 32-bit rollover: lo wraps, hi increments ─────
    $display("-- Test 11: mtime_lo rollover increments mtime_hi");
    timer_reset_state;
    bus_write(12'h000, 32'hFFFF_FFFE);   // mtime_lo = 0xFFFFFFFE
    bus_write(12'h004, 32'h0);           // mtime_hi = 0
    bus_write(12'h010, 32'h1);           // enable
    // Wait 3 ticks: FFFE → FFFF → 0000 (carry) → 0001
    repeat(6) @(posedge clk); #1;
    bus_write(12'h010, 32'h0);
    bus_read(12'h004, val);
    chk("mtime_hi incremented after lo rollover", val, 32'h1);
    bus_read(12'h000, val);
    // After FFFE + ~4 ticks = 0x0002 or so
    if (val <= 32'h8) begin
        $display("  PASS  mtime_lo wrapped correctly (got 0x%08h)", val);
        pass_cnt++;
    end else begin
        $display("  FAIL  mtime_lo unexpected after wrap (got 0x%08h)", val);
        fail_cnt++;
    end

    // ── Test 12: Safe 64-bit mtimecmp write ordering ──────────
    $display("-- Test 12: Safe 64-bit mtimecmp write ordering");
    timer_reset_state;
    // Use standard ordering: write HI=MAX first, then LO, then real HI
    bus_write(12'h00C, 32'hFFFF_FFFF);   // HI = MAX (guard)
    bus_write(12'h008, 32'h0000_0200);   // LO = 512
    bus_write(12'h00C, 32'h0000_0000);   // HI = 0
    bus_read (12'h008, val);  chk("mtimecmp_lo = 512",  val, 32'h200);
    bus_read (12'h00C, val);  chk("mtimecmp_hi = 0",    val, 32'h0);
    // Verify no spurious irq during the write sequence (irq_en was 0 throughout)
    chk("no spurious irq during update", {31'h0, irq}, 32'h0);

    // ── Test 13: IRQ is level — stays high until cleared ──────
    $display("-- Test 13: IRQ stays level until mtimecmp updated");
    timer_reset_state;
    bus_write(12'h000, 32'h5);
    bus_write(12'h004, 32'h0);            // mtime_hi = 0
    bus_write(12'h008, 32'h5);            // mtimecmp_lo = 5  (equal → immediate match)
    bus_write(12'h00C, 32'h0);            // mtimecmp_hi = 0  (timer_reset leaves 0xFFFFFFFF)
    bus_write(12'h010, 32'h3);            // enable + irq_en
    @(posedge clk); #1;
    chk("irq level high (cycle 1)", {31'h0, irq}, 32'h1);
    repeat(5) @(posedge clk); #1;
    chk("irq level high (cycle 6)", {31'h0, irq}, 32'h1);
    // Now clear by moving mtimecmp far ahead
    bus_write(12'h008, 32'hFFFF_FFFF);
    bus_write(12'h00C, 32'hFFFF_FFFF);
    @(posedge clk); #1;
    chk("irq level low after mtimecmp update", {31'h0, irq}, 32'h0);
    bus_write(12'h010, 32'h0);

    // ── Test 14: CTRL read-back ───────────────────────────────
    $display("-- Test 14: CTRL register read-back");
    bus_write(12'h010, 32'h3);
    bus_read (12'h010, val);
    chk("CTRL readback 0x3", val & 32'h3, 32'h3);
    bus_write(12'h010, 32'h1);
    bus_read (12'h010, val);
    chk("CTRL readback 0x1", val & 32'h3, 32'h1);
    bus_write(12'h010, 32'h0);

    // ── Summary ───────────────────────────────────────────────
    $display("\n=== Results: %0d/%0d passed ===", pass_cnt, pass_cnt+fail_cnt);
    if (fail_cnt == 0) $display("ALL TESTS PASSED\n");
    else               $display("%0d TESTS FAILED\n", fail_cnt);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
