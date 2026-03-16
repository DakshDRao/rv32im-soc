// ============================================================
//  tb_gpio.sv  -  Testbench for gpio.sv
//  Project : Single-Cycle RV32IM SoC
//  Step    : 16 — GPIO
//
//  Tests
//  ─────────────────────────────────────────────────────────
//  1.  Reset state: all registers zero, gpio_led = 0
//  2.  DIR register: read-back, led masked when DIR=0
//  3.  DATA_OUT: write → LED driven only where DIR=1
//  4.  DATA_OUT read-back
//  5.  DIR=0 masks output (led=0 even if data_out set)
//  6.  DATA_IN: btn pins reflected with 2-FF sync delay
//  7.  DATA_IN: sw pins reflected in upper nibble
//  8.  DATA_IN: combined btn+sw read
//  9.  CTRL register read-back
//  10. IRQ: out_event set on DATA_OUT write, cleared W1C
//  11. IRQ: in_change set on input toggle, cleared W1C
//  12. IRQ: out_ie gates irq signal
//  13. IRQ: in_ie gates irq signal
//  14. IRQ: both events independently maskable
//  15. IRQ deasserts after W1C clear
// ============================================================

`timescale 1ns/1ps

module tb_gpio;

// ─────────────────────────────────────────────────────────────
//  DUT Signals
// ─────────────────────────────────────────────────────────────
logic        clk, rst;
logic [11:0] addr;
logic [31:0] wdata;
logic        we;
logic [2:0]  funct3;
logic [31:0] rdata;
logic [3:0]  gpio_led;
logic [3:0]  gpio_btn;
logic [3:0]  gpio_sw;
logic        irq;

// ─────────────────────────────────────────────────────────────
//  DUT
// ─────────────────────────────────────────────────────────────
gpio #(.N_OUT(4), .N_IN(8)) dut (
    .clk      (clk),
    .rst      (rst),
    .addr     (addr),
    .wdata    (wdata),
    .we       (we),
    .funct3   (funct3),
    .rdata    (rdata),
    .gpio_led (gpio_led),
    .gpio_btn (gpio_btn),
    .gpio_sw  (gpio_sw),
    .irq      (irq)
);

// ─────────────────────────────────────────────────────────────
//  Clock
// ─────────────────────────────────────────────────────────────
initial clk = 0;
always #5 clk = ~clk;  // 100 MHz

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
    #1;
    d = rdata;
endtask

// Wait N clocks for synchroniser pipeline
task automatic sync_wait(input int n);
    repeat(n) @(posedge clk);
    #1;
endtask

// ─────────────────────────────────────────────────────────────
//  Test Body
// ─────────────────────────────────────────────────────────────
logic [31:0] val;

initial begin
    $dumpfile("tb_gpio.vcd");
    $dumpvars(0, tb_gpio);
    $display("\n=== tb_gpio ===\n");

    // Initialise inputs
    gpio_btn = 4'h0;
    gpio_sw  = 4'h0;
    addr     = '0; wdata = '0; we = 0; funct3 = 3'b010;

    // ── Reset ─────────────────────────────────────────────────
    rst = 1; repeat(4) @(posedge clk); rst = 0; @(posedge clk);

    // ── Test 1: Reset state ───────────────────────────────────
    $display("-- Test 1: Reset state");
    bus_read(12'h000, val); chk("DIR = 0",        val, 32'h0);
    bus_read(12'h004, val); chk("DATA_OUT = 0",   val, 32'h0);
    bus_read(12'h00C, val); chk("CTRL = 0",       val, 32'h0);
    bus_read(12'h010, val); chk("IRQ_STATUS = 0", val, 32'h0);
    chk("gpio_led = 0", {28'h0, gpio_led}, 32'h0);

    // ── Test 2: DIR register ──────────────────────────────────
    $display("-- Test 2: DIR register");
    bus_write(12'h000, 32'hF);       // all 4 pins as outputs
    bus_read (12'h000, val);
    chk("DIR readback 0xF", val, 32'hF);

    // ── Test 3: DATA_OUT drives LEDs when DIR=1 ───────────────
    $display("-- Test 3: DATA_OUT → gpio_led (DIR=0xF)");
    bus_write(12'h004, 32'hA);       // 0b1010
    @(posedge clk); #1;
    chk("gpio_led = 0xA", {28'h0, gpio_led}, 32'hA);

    bus_write(12'h004, 32'h5);       // 0b0101
    @(posedge clk); #1;
    chk("gpio_led = 0x5", {28'h0, gpio_led}, 32'h5);

    // ── Test 4: DATA_OUT read-back ────────────────────────────
    $display("-- Test 4: DATA_OUT read-back");
    bus_read(12'h004, val);
    chk("DATA_OUT readback 0x5", val, 32'h5);

    // ── Test 5: DIR mask — output suppressed when DIR=0 ───────
    $display("-- Test 5: DIR=0 masks gpio_led output");
    bus_write(12'h000, 32'h0);       // all inputs
    @(posedge clk); #1;
    chk("gpio_led = 0 when DIR=0", {28'h0, gpio_led}, 32'h0);
    // DATA_OUT register still holds value
    bus_read(12'h004, val);
    chk("DATA_OUT reg preserved", val, 32'h5);
    // Restore DIR
    bus_write(12'h000, 32'hF);

    // ── Test 6: DATA_IN — buttons ────────────────────────────
    $display("-- Test 6: DATA_IN — button pins");
    gpio_btn = 4'hB;                 // BTN[3:0] = 0b1011
    sync_wait(3);                    // 2-FF sync + 1 margin
    bus_read(12'h008, val);
    chk("DATA_IN btn = 0xB", val & 32'hF, 32'hB);

    // ── Test 7: DATA_IN — switches ───────────────────────────
    $display("-- Test 7: DATA_IN — switch pins (upper nibble)");
    gpio_sw = 4'hC;                  // SW[3:0] = 0b1100
    sync_wait(3);
    bus_read(12'h008, val);
    chk("DATA_IN sw = 0xC (bits[7:4])", (val >> 4) & 32'hF, 32'hC);

    // ── Test 8: DATA_IN — combined ───────────────────────────
    $display("-- Test 8: DATA_IN combined {sw=0xC, btn=0xB} = 0xCB");
    bus_read(12'h008, val);
    chk("DATA_IN combined 0xCB", val & 32'hFF, 32'hCB);

    // Reset inputs
    gpio_btn = 4'h0; gpio_sw = 4'h0;
    sync_wait(3);

    // ── Test 9: CTRL register read-back ─────────────────────
    $display("-- Test 9: CTRL register");
    bus_write(12'h00C, 32'h3);
    bus_read (12'h00C, val);
    chk("CTRL readback 0x3", val & 32'h3, 32'h3);
    bus_write(12'h00C, 32'h0);      // clear interrupts for now

    // ── Test 10: out_event set on DATA_OUT write ──────────────
    $display("-- Test 10: IRQ_STATUS[0] out_event on DATA_OUT write");
    bus_read(12'h010, val);
    // Clear any previous events from Test 3 writes
    bus_write(12'h010, 32'h3);
    bus_write(12'h004, 32'hF);      // write DATA_OUT → sets out_event
    @(posedge clk); #1;
    bus_read(12'h010, val);
    chk("out_event set after DATA_OUT write", val & 32'h1, 32'h1);

    // W1C clear
    bus_write(12'h010, 32'h1);      // write 1 to clear bit[0]
    bus_read (12'h010, val);
    chk("out_event cleared by W1C", val & 32'h1, 32'h0);

    // ── Test 11: in_change set on input toggle ────────────────
    $display("-- Test 11: IRQ_STATUS[1] in_change on input toggle");
    bus_write(12'h010, 32'h3);      // clear all events
    gpio_btn = 4'h1;                 // toggle a button
    sync_wait(3);
    bus_read(12'h010, val);
    chk("in_change set after btn toggle", val & 32'h2, 32'h2);

    // W1C clear
    bus_write(12'h010, 32'h2);
    bus_read (12'h010, val);
    chk("in_change cleared by W1C", val & 32'h2, 32'h0);

    // Reset inputs
    gpio_btn = 4'h0; sync_wait(3);
    bus_write(12'h010, 32'h3);      // clear pending change from reset

    // ── Test 12: out_ie gates irq ─────────────────────────────
    $display("-- Test 12: out_ie gates irq");
    bus_write(12'h010, 32'h3);      // clear events
    bus_write(12'h00C, 32'h1);      // out_ie = 1, in_ie = 0
    bus_write(12'h004, 32'h1);      // write DATA_OUT → out_event
    @(posedge clk); #1;
    chk("irq asserted with out_ie=1", {31'h0, irq}, 32'h1);
    bus_write(12'h010, 32'h1);      // clear event
    #1;
    chk("irq deasserted after W1C", {31'h0, irq}, 32'h0);

    // ── Test 13: in_ie gates irq ──────────────────────────────
    $display("-- Test 13: in_ie gates irq");
    bus_write(12'h00C, 32'h2);      // in_ie = 1, out_ie = 0
    bus_write(12'h010, 32'h3);      // clear events
    gpio_sw = 4'h5;
    sync_wait(3);
    chk("irq asserted with in_ie=1 + in_change", {31'h0, irq}, 32'h1);
    bus_write(12'h010, 32'h2);      // clear in_change
    #1;
    chk("irq deasserted after in_change clear", {31'h0, irq}, 32'h0);

    // ── Test 14: out_ie does NOT trigger from in_change ───────
    $display("-- Test 14: out_ie does not fire from in_change");
    bus_write(12'h00C, 32'h1);      // out_ie=1 only
    bus_write(12'h010, 32'h3);
    gpio_sw = 4'h0;                  // toggle switch back
    sync_wait(3);
    // in_change is set but out_ie is 0 for it → no irq
    chk("irq = 0 (out_ie but only in_change event)", {31'h0, irq}, 32'h0);

    // ── Test 15: Full IRQ deassert after both W1C ─────────────
    $display("-- Test 15: Both events, both cleared");
    bus_write(12'h00C, 32'h3);      // both interrupts enabled
    bus_write(12'h010, 32'h3);      // clear first
    bus_write(12'h004, 32'hF);      // trigger out_event
    gpio_btn = 4'hF;                 // trigger in_change
    sync_wait(3);
    bus_read(12'h010, val);
    chk("both events set", val & 32'h3, 32'h3);
    chk("irq high with both", {31'h0, irq}, 32'h1);
    bus_write(12'h010, 32'h3);      // clear both
    #1;
    chk("irq low after clearing both", {31'h0, irq}, 32'h0);

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
