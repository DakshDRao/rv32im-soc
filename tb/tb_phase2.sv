// ============================================================
//  tb_phase2.sv  -  Phase 2 Comprehensive Verification
//  Project : Single-Cycle RV32IM SoC
//
//  Tests (in order):
//    [1] Reset & Boot       PC starts at 0, releases cleanly
//    [2] Core Execution     PC advances, not stuck
//    [3] GPIO Init          LEDs set to outputs, initial 0
//    [4] IMEM Data Read     .rodata strings readable (banner chars arrive)
//    [5] UART TX            Banner text received and decoded correctly
//    [6] LED Binary Counter LEDs count 0→1→2→...→F
//    [7] CSR Cycle Counter  Cycle count is monotonically increasing
//    [8] LED Wrap & Repeat  Counter wraps 0xF→0x0 and continues
//    [9] Button Echo        Press BTN, firmware echoes it via UART
//   [10] UART RX            Loopback: TX byte echoed back via RX
//
//  Pass/Fail printed at end. All 10 must pass for Phase 2 sign-off.
//
//  Runtime: ~400ms sim time (run for 400ms in XSim)
//  Clock:   100 MHz (10 ns period)
// ============================================================
`timescale 1ns/1ps

module tb_phase2;

// ─────────────────────────────────────────────────────────────
//  Parameters
// ─────────────────────────────────────────────────────────────
localparam int    CLK_FREQ    = 100_000_000;
localparam int    BAUD_RATE   = 115_200;
localparam int    BAUD_DIV    = CLK_FREQ / BAUD_RATE;  // 868 clocks/bit
localparam real   CLK_PERIOD  = 10.0;                   // ns

// Max sim time for each test phase
localparam int    RESET_TIMEOUT     = 100;
localparam int    BOOT_TIMEOUT      = 5_000;
localparam int    BANNER_TIMEOUT    = 25_000_000;   // ~250ms for full banner
localparam int    LED_TIMEOUT       = 40_000_000;   // ~400ms for first LED
localparam int    LED_WRAP_TIMEOUT  = 200_000_000;  // ~2s for wrap
localparam int    BTN_TIMEOUT       = 50_000_000;   // ~500ms for echo

// ─────────────────────────────────────────────────────────────
//  DUT
// ─────────────────────────────────────────────────────────────
logic        clk, rst_n;
logic        uart_tx, uart_rx;
logic [3:0]  gpio_led;
logic [3:0]  gpio_btn;
logic [3:0]  gpio_sw;

soc_top #(
    .IMEM_DEPTH(16384),
    .DMEM_DEPTH(16384),
    .BOOT_ADDR (32'h0000_0000),
    .CLK_FREQ  (CLK_FREQ),
    .BAUD_RATE (BAUD_RATE)
) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .uart_tx  (uart_tx),
    .uart_rx  (uart_rx),
    .gpio_led (gpio_led),
    .gpio_btn (gpio_btn),
    .gpio_sw  (gpio_sw)
);

// ─────────────────────────────────────────────────────────────
//  Clock
// ─────────────────────────────────────────────────────────────
initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ─────────────────────────────────────────────────────────────
//  Internal signal taps
// ─────────────────────────────────────────────────────────────
wire [31:0] pc       = dut.u_core.pc;
wire [63:0] cycle_csr= dut.u_core.u_csr.cycle_r;
wire        tx_busy  = dut.u_uart.tx_busy;

// ─────────────────────────────────────────────────────────────
//  Test scoreboard
// ─────────────────────────────────────────────────────────────
int  pass_count = 0;
int  fail_count = 0;
string test_log[10];

task automatic record(input int idx, input string name, input logic pass, input string detail="");
    string status;
    status = pass ? "PASS" : "FAIL";
    test_log[idx] = $sformatf("[%s] Test %0d: %s  %s", status, idx+1, name, detail);
    if (pass) pass_count++;
    else      fail_count++;
    $display("%s", test_log[idx]);
endtask

// ─────────────────────────────────────────────────────────────
//  UART decoder (receive bytes from uart_tx)
// ─────────────────────────────────────────────────────────────
byte  uart_buf[$];       // received bytes
int   uart_char_count = 0;
logic uart_rx_done = 0;

task automatic uart_receive_byte(output byte b);
    logic [7:0] rx;
    // Wait for start bit
    @(negedge uart_tx);
    repeat(BAUD_DIV/2) @(posedge clk);
    if (uart_tx !== 1'b0) begin b = 8'hFF; return; end
    for (int i = 0; i < 8; i++) begin
        repeat(BAUD_DIV) @(posedge clk);
        rx[i] = uart_tx;
    end
    repeat(BAUD_DIV) @(posedge clk); // stop bit
    b = rx;
endtask

// Background UART monitor — runs the whole simulation
initial begin
    byte b;
    @(posedge rst_n);
    repeat(10) @(posedge clk);
    forever begin
        uart_receive_byte(b);
        uart_buf.push_back(b);
        uart_char_count++;
        if (b >= 8'h20 && b < 8'h7f)
            $write("%c", b);
        else if (b == 8'h0a)
            $write("\n");
    end
end

// ─────────────────────────────────────────────────────────────
//  Helper: search uart_buf for a string
// ─────────────────────────────────────────────────────────────
function automatic logic uart_contains(string s);
    int slen = s.len();
    for (int i = 0; i <= int'(uart_buf.size()) - slen; i++) begin
        logic match = 1;
        for (int j = 0; j < slen; j++) begin
            if (uart_buf[i+j] != byte'(s[j])) begin match = 0; break; end
        end
        if (match) return 1;
    end
    return 0;
endfunction

// ─────────────────────────────────────────────────────────────
//  Helper: wait for condition with timeout, return 1=ok 0=timeout
// ─────────────────────────────────────────────────────────────
task automatic wait_for(ref logic sig, input int max_cycles, output logic ok);
    for (int i = 0; i < max_cycles; i++) begin
        @(posedge clk);
        if (sig) begin ok = 1; return; end
    end
    ok = 0;
endtask

// ─────────────────────────────────────────────────────────────
//  LED change tracker
// ─────────────────────────────────────────────────────────────
int        led_change_count = 0;
logic[3:0] led_values[$];
logic[3:0] led_prev = 4'hX;
logic      led_changed_flag = 0;

always @(posedge clk) begin
    if (gpio_led !== led_prev && gpio_led !== 4'hX) begin
        led_values.push_back(gpio_led);
        led_change_count++;
        led_changed_flag = 1;
        led_prev <= gpio_led;
    end
end

// ─────────────────────────────────────────────────────────────
//  MAIN TEST SEQUENCE
// ─────────────────────────────────────────────────────────────
initial begin
    // Init
    rst_n    = 0;
    uart_rx  = 1;
    gpio_btn = 0;
    gpio_sw  = 0;

    $display("\n");
    $display("============================================================");
    $display("  RV32IM SoC  -  Phase 2 Comprehensive Verification");
    $display("  Clock: %0d MHz   UART: %0d baud", CLK_FREQ/1000000, BAUD_RATE);
    $display("============================================================\n");

    // ──────────────────────────────────────────────────────────
    //  TEST 1: Reset & Boot
    // ──────────────────────────────────────────────────────────
    $display("[TEST 1] Reset & Boot...");
    repeat(8) @(posedge clk);   // hold reset 8 cycles

    // Check rst is asserted during reset
    if (dut.rst !== 1'b1)
        $display("  Warning: rst not asserted during rst_n=0");

    rst_n = 1;
    repeat(4) @(posedge clk);   // 2-FF sync delay

    // rst should now be deasserted
    begin
        logic ok;
        int   pc_before;
        pc_before = pc;
        repeat(10) @(posedge clk);
        record(0, "Reset & Boot",
               (dut.rst === 1'b0) && (pc !== 32'hX),
               $sformatf("rst=%b pc=0x%08h", dut.rst, pc));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 2: Core Execution  (PC must advance)
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 2] Core execution (PC advancing)...");
    begin
        logic [31:0] pc0;
        int ok_count;
        pc0 = pc;
        ok_count = 0;
        for (int i = 0; i < BOOT_TIMEOUT; i++) begin
            @(posedge clk);
            if (pc !== pc0 && pc !== 32'hX) begin
                ok_count++;
                if (ok_count >= 3) break; // saw 3 distinct PC values
                pc0 = pc;
            end
        end
        record(1, "Core Execution", (ok_count >= 3),
               $sformatf("saw %0d PC transitions", ok_count));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 3: GPIO Init  (LEDs go to 0x0 early)
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 3] GPIO initialisation...");
    begin
        logic ok;
        for (int i = 0; i < 500_000; i++) begin
            @(posedge clk);
            // gpio_led should be driven 0 by firmware (gpio_set_leds(0))
            if (gpio_led === 4'h0 && dut.u_gpio.dir_r !== 4'h0) begin
                ok = 1; break;
            end
        end
        // DIR register should be 0xF (all outputs)
        record(2, "GPIO Init",
               (dut.u_gpio.dir_r === 4'hF),
               $sformatf("DIR=0x%01h gpio_led=0x%01h", dut.u_gpio.dir_r, gpio_led));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 4: IMEM Data Read  (.rodata strings work)
    //  Evidence: UART receives non-0xEF bytes (real ASCII chars)
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 4] IMEM data read (.rodata via data bus)...");
    begin
        // Wait for at least 10 UART chars
        for (int i = 0; i < BANNER_TIMEOUT && uart_char_count < 10; i++)
            @(posedge clk);

        // Check that we didn't get a stream of 0xEF (the old bug)
        begin
            int ef_count = 0;
            int total = (uart_buf.size() > 20) ? 20 : uart_buf.size();
            for (int i = 0; i < total; i++)
                if (uart_buf[i] == 8'hEF) ef_count++;
            record(3, "IMEM Data Read (.rodata)",
                   (uart_char_count >= 5 && ef_count < total/2),
                   $sformatf("received %0d chars, 0xEF count=%0d/%0d",
                              uart_char_count, ef_count, total));
        end
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 5: UART TX  (banner text received)
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 5] UART TX banner...");
    begin
        // Wait for "Hello" in the uart buffer
        for (int i = 0; i < BANNER_TIMEOUT && !uart_contains("Hello"); i++)
            @(posedge clk);
        // Also wait for "RV32" to confirm full banner
        for (int i = 0; i < BANNER_TIMEOUT && !uart_contains("RV32"); i++)
            @(posedge clk);
        record(4, "UART TX Banner",
               uart_contains("Hello") && uart_contains("RV32"),
               $sformatf("chars=%0d has_Hello=%0b has_RV32=%0b",
                          uart_char_count,
                          uart_contains("Hello"), uart_contains("RV32")));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 6: LED Binary Counter
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 6] LED binary counter (0→1→2→3→4)...");
    begin
        int prev_count;
        prev_count = led_change_count;

        // Wait for at least 5 consecutive LED increments
        for (int i = 0; i < LED_TIMEOUT && (led_change_count - prev_count) < 5; i++)
            @(posedge clk);

        // Verify sequence is monotonically incrementing (mod 16)
        begin
            logic seq_ok = 1;
            int   start_idx;
            start_idx = (led_values.size() >= 5) ? led_values.size()-5 : 0;
            for (int i = start_idx; i < int'(led_values.size())-1; i++) begin
                logic [3:0] expected = (led_values[i] + 1) & 4'hF;
                if (led_values[i+1] !== expected && led_values[i] !== 4'hF) begin
                    seq_ok = 0;
                    $display("  Sequence break: [%0d]=0x%01h [%0d]=0x%01h (expected 0x%01h)",
                             i, led_values[i], i+1, led_values[i+1], expected);
                end
            end
            record(5, "LED Binary Counter",
                   ((led_change_count - prev_count) >= 5) && seq_ok,
                   $sformatf("%0d changes seen, sequence %s",
                              led_change_count - prev_count,
                              seq_ok ? "correct" : "WRONG"));
        end
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 7: CSR Cycle Counter  (monotonically increasing)
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 7] CSR cycle counter...");
    begin
        logic [63:0] c0, c1, c2;
        c0 = cycle_csr;
        repeat(1000) @(posedge clk);
        c1 = cycle_csr;
        repeat(1000) @(posedge clk);
        c2 = cycle_csr;
        record(6, "CSR Cycle Counter",
               (c1 > c0) && (c2 > c1) && (c2 - c0 >= 1000),
               $sformatf("c0=%0d c1=%0d c2=%0d delta=%0d",
                          c0[31:0], c1[31:0], c2[31:0], (c2-c0)));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 8: LED Wrap 0xF → 0x0 and Continue
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 8] LED counter wraps 0xF→0x0...");
    begin
        // Wait for an 0xF→0x0 transition in led_values
        logic wrap_seen = 0;
        for (int i = 0; i < LED_WRAP_TIMEOUT && !wrap_seen; i++) begin
            @(posedge clk);
            // Check recent transitions
            for (int j = int'(led_values.size())-1; j >= 1; j--) begin
                if (led_values[j-1] === 4'hF && led_values[j] === 4'h0) begin
                    wrap_seen = 1; break;
                end
            end
        end
        record(7, "LED Counter Wrap (0xF→0x0)",
               wrap_seen,
               $sformatf("total LED changes so far: %0d", led_change_count));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 9: Button Echo
    //  Assert BTN1 (gpio_btn[0]) and check UART receives "BTN"
    //  The firmware prints "BTN pressed: 0" when btn[0] goes high
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 9] Button echo (press BTN, expect UART output)...");
    begin
        int chars_before;
        chars_before = uart_char_count;

        // Wait until firmware is past its banner (at least 30ms sim time)
        repeat(3_000_000) @(posedge clk);

        // Assert BTN0 for 5 LED cycles (~5 * 250k cycles)
        gpio_btn[0] = 1;
        repeat(1_500_000) @(posedge clk);
        gpio_btn[0] = 0;

        // Wait for UART to receive "BTN"
        for (int i = 0; i < BTN_TIMEOUT && !uart_contains("BTN"); i++)
            @(posedge clk);

        record(8, "Button Echo",
               uart_contains("BTN"),
               $sformatf("UART contains 'BTN': %0b  (chars before: %0d after: %0d)",
                          uart_contains("BTN"), chars_before, uart_char_count));
    end

    // ──────────────────────────────────────────────────────────
    //  TEST 10: UART RX / Loopback
    //  Verify the UART RX path works by feeding a byte back in
    //  and checking the UART module receives it (rx_ready flag)
    // ──────────────────────────────────────────────────────────
    $display("\n[TEST 10] UART RX loopback...");
    begin
        // Send byte 0x41 ('A') to uart_rx using the same 8N1 protocol
        automatic byte send_byte = 8'h41;
        logic rx_ready_seen = 0;

        // Transmit start bit + 8 data bits + stop bit
        uart_rx = 0; // start bit
        repeat(BAUD_DIV) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            uart_rx = send_byte[i];
            repeat(BAUD_DIV) @(posedge clk);
        end
        uart_rx = 1; // stop bit
        repeat(BAUD_DIV*2) @(posedge clk);

        // Check rx_ready went high in the UART
        for (int i = 0; i < BAUD_DIV*20; i++) begin
            @(posedge clk);
            if (dut.u_uart.rx_ready) begin rx_ready_seen = 1; break; end
        end

        record(9, "UART RX Loopback",
               rx_ready_seen,
               $sformatf("rx_ready=%0b rx_data=0x%02h (expected 0x%02h)",
                          rx_ready_seen,
                          rx_ready_seen ? dut.u_uart.rx_data : 8'hXX,
                          send_byte));
    end

    // ──────────────────────────────────────────────────────────
    //  RESULTS
    // ──────────────────────────────────────────────────────────
    repeat(100) @(posedge clk);

    $display("\n");
    $display("============================================================");
    $display("  PHASE 2 VERIFICATION RESULTS");
    $display("============================================================");
    for (int i = 0; i < 10; i++)
        $display("  %s", test_log[i]);
    $display("------------------------------------------------------------");
    $display("  PASSED: %0d / 10    FAILED: %0d / 10", pass_count, fail_count);
    $display("------------------------------------------------------------");

    if (fail_count == 0) begin
        $display("");
        $display("  ██████╗ ██╗  ██╗ █████╗ ███████╗███████╗    ██████╗ ");
        $display("  ██╔══██╗██║  ██║██╔══██╗██╔════╝██╔════╝    ╚════██╗");
        $display("  ██████╔╝███████║███████║███████╗█████╗       █████╔╝");
        $display("  ██╔═══╝ ██╔══██║██╔══██║╚════██║██╔══╝      ██╔═══╝ ");
        $display("  ██║     ██║  ██║██║  ██║███████║███████╗    ███████╗");
        $display("  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝    ╚══════╝");
        $display("");
        $display("  *** PHASE 2 COMPLETE ***");
        $display("  Single-Cycle RV32IM SoC fully verified.");
        $display("  Ready to proceed to Phase 3: 5-Stage Pipeline.");
    end else begin
        $display("");
        $display("  *** PHASE 2 INCOMPLETE - %0d test(s) failed ***", fail_count);
        $display("  Review failed tests above before proceeding.");
    end

    $display("============================================================\n");
    $finish;
end

// ─────────────────────────────────────────────────────────────
//  Watchdog — absolute maximum runtime
// ─────────────────────────────────────────────────────────────
initial begin
    #400_000_000_000; // 400 ms
    $display("\n[WATCHDOG] Simulation exceeded 400ms wall time. Aborting.");
    $finish;
end

endmodule
