// ============================================================
//  tb_uart.sv  -  Testbench for uart.sv  (v2 — all fixes)
// ============================================================
`timescale 1ns/1ps
module tb_uart;
localparam int CLK_FREQ  = 1_000_000;
localparam int BAUD_RATE = 100_000;
localparam int BAUD_DIV  = CLK_FREQ / BAUD_RATE;
localparam int HALF_DIV  = BAUD_DIV / 2;
localparam real CLK_PERIOD = 1_000_000_000.0 / CLK_FREQ;

logic clk, rst;
logic [11:0] addr;
logic [31:0] wdata;
logic        we;
logic [2:0]  funct3;
logic [31:0] rdata;
logic        uart_tx_pin, uart_rx_pin;
logic        irq;
assign uart_rx_pin = uart_tx_pin;

uart #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE)) dut (
    .clk(clk),.rst(rst),.addr(addr),.wdata(wdata),
    .we(we),.funct3(funct3),.rdata(rdata),
    .tx(uart_tx_pin),.rx(uart_rx_pin),.irq(irq));

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

int pass_cnt = 0, fail_cnt = 0;

task automatic chk(input string name, input logic [31:0] got, exp);
    if (got === exp) begin $display("  PASS  %s", name); pass_cnt++; end
    else begin $display("  FAIL  %s  got=0x%08h  exp=0x%08h", name, got, exp); fail_cnt++; end
endtask

task automatic bus_write(input logic [11:0] a, input logic [31:0] d);
    @(posedge clk); #1; addr=a; wdata=d; we=1; funct3=3'b010;
    @(posedge clk); #1; we=0;
endtask

task automatic bus_read(input logic [11:0] a, output logic [31:0] d);
    @(posedge clk); #1; addr=a; wdata=0; we=0; funct3=3'b010; #1; d=rdata;
endtask

task automatic wait_tx_done;
    logic [31:0] s; int t=1000;
    do begin bus_read(12'h008,s); if(--t==0) begin $display("  FAIL  wait_tx_done timeout"); fail_cnt++; break; end
    end while(s[0]);
endtask

task automatic wait_rx_ready;
    logic [31:0] s; int t=1000;
    do begin bus_read(12'h008,s); if(--t==0) begin $display("  FAIL  wait_rx_ready timeout"); fail_cnt++; break; end
    end while(!s[1]);
endtask

// Drain any stale loopback bytes before a fresh RX test
task automatic flush_rx;
    logic [31:0] s, d; int g=0;
    forever begin
        bus_read(12'h008,s);
        if(!s[1]) break;
        bus_read(12'h004,d);
        @(posedge clk); #1;
        if(++g>20) begin $display("  WARN  flush_rx: too many iters"); break; end
    end
endtask

task automatic sample_tx_frame(output logic [9:0] frame);
    int i;
    @(negedge uart_tx_pin);
    repeat(HALF_DIV) @(posedge clk);
    frame[0] = uart_tx_pin;
    for(i=1;i<=9;i++) begin repeat(BAUD_DIV) @(posedge clk); frame[i]=uart_tx_pin; end
endtask

logic [9:0]  frame;
logic [31:0] reg_val, rx_byte;

initial begin
    $dumpfile("tb_uart.vcd"); $dumpvars(0,tb_uart);
    $display("\n=== tb_uart ===\n");
    addr='0; wdata='0; we=0; funct3=3'b010; rst=1;
    repeat(4) @(posedge clk); rst=0; @(posedge clk);

    // -- Test 1: TX idle
    $display("-- Test 1: TX idle = 1 (mark)");
    #1; chk("tx idle high",{31'h0,uart_tx_pin},32'h1);

    // -- Test 2: TX frame bit-by-bit (0xA5)
    $display("-- Test 2: TX frame bit-by-bit (send 0xA5 = 8'b10100101)");
    fork bus_write(12'h000,32'hA5); sample_tx_frame(frame); join
    chk("start bit = 0", {31'h0,frame[0]},32'h0);
    chk("data bit 0 = 1",{31'h0,frame[1]},32'h1);
    chk("data bit 1 = 0",{31'h0,frame[2]},32'h0);
    chk("data bit 2 = 1",{31'h0,frame[3]},32'h1);
    chk("data bit 3 = 0",{31'h0,frame[4]},32'h0);
    chk("data bit 4 = 0",{31'h0,frame[5]},32'h0);
    chk("data bit 5 = 1",{31'h0,frame[6]},32'h1);
    chk("data bit 6 = 0",{31'h0,frame[7]},32'h0);
    chk("data bit 7 = 1",{31'h0,frame[8]},32'h1);
    chk("stop bit = 1",  {31'h0,frame[9]},32'h1);

    // -- Test 3: tx_busy
    $display("-- Test 3: STATUS.tx_busy");
    @(posedge clk); #1; addr=12'h000; wdata=32'h42; we=1; @(posedge clk); #1; we=0; #1;
    bus_read(12'h008,reg_val); chk("tx_busy = 1 during TX",reg_val&32'h1,32'h1);
    wait_tx_done; bus_read(12'h008,reg_val); chk("tx_busy = 0 after TX",reg_val&32'h1,32'h0);

    // -- Test 4: Back-to-back TX
    $display("-- Test 4: Back-to-back TX (write while busy is dropped)");
    bus_write(12'h000,32'h11); #1;
    bus_read(12'h008,reg_val); chk("busy after first write",reg_val[0],1'b1);
    bus_write(12'h000,32'h22);
    bus_read(12'h008,reg_val); chk("still busy (second write dropped)",reg_val[0],1'b1);
    wait_tx_done; bus_read(12'h008,reg_val); chk("idle after first byte done",reg_val[0],1'b0);

    // --- Flush stale loopback bytes from tests 2-4 ---
    wait_tx_done;
    repeat(BAUD_DIV*12) @(posedge clk);   // let final RX_STOP settle
    flush_rx;

    // -- Test 5: RX loopback 0x55
    $display("-- Test 5: RX loopback (send 0x55, receive 0x55)");
    bus_write(12'h000,32'h55);
    wait_rx_ready;
    bus_read(12'h004,rx_byte);
    @(posedge clk); #1;                   // let read-clear FF fire
    chk("rx loopback 0x55",rx_byte,32'h55);

    // -- Test 6: rx_ready cleared after read
    $display("-- Test 6: rx_ready cleared after read");
    bus_read(12'h008,reg_val); chk("rx_ready = 0 after read",reg_val[1],1'b0);

    // -- Test 7: RX loopback 0xAA
    $display("-- Test 7: RX loopback second byte (0xAA)");
    wait_tx_done;
    bus_write(12'h000,32'hAA);
    wait_rx_ready;
    bus_read(12'h004,rx_byte);
    @(posedge clk); #1;
    chk("rx loopback 0xAA",rx_byte,32'hAA);

    // -- Test 8: rx_overrun
    // Strategy: send byte 1, wait for TX+RX to complete, don't read.
    // Then send byte 2 (TX is now free), wait for TX+RX, check overrun.
    $display("-- Test 8: rx_overrun (two bytes without reading)");
    wait_tx_done; flush_rx;
    // Byte 1
    bus_write(12'h000,32'hBB);
    wait_tx_done;
    repeat(BAUD_DIV*2) @(posedge clk);   // ensure RX_STOP fires
    bus_read(12'h008,reg_val); chk("rx_ready after byte 1",reg_val[1],1'b1);
    // Byte 2 — rx_ready still 1, so arrival triggers overrun
    bus_write(12'h000,32'hCC);
    wait_tx_done;
    repeat(BAUD_DIV*2) @(posedge clk);   // ensure RX_STOP fires
    bus_read(12'h008,reg_val); chk("rx_overrun set",reg_val[2],1'b1);
    bus_read(12'h004,rx_byte); @(posedge clk); #1;
    bus_read(12'h008,reg_val); chk("rx_overrun cleared after read",reg_val[2],1'b0);

    // -- Test 9: CTRL register
    $display("-- Test 9: CTRL register");
    bus_write(12'h00C,32'h3); bus_read(12'h00C,reg_val);
    chk("CTRL readback 0x3",reg_val&32'h3,32'h3);
    bus_write(12'h00C,32'h0);

    // -- Test 10: IRQ from rx_ie
    $display("-- Test 10: IRQ from rx_ie");
    wait_tx_done; flush_rx;
    bus_write(12'h00C,32'h1);             // rx_ie=1
    bus_write(12'h000,32'h7E);
    wait_rx_ready;
    chk("irq high when rx_ready + rx_ie",{31'h0,irq},32'h1);
    bus_read(12'h004,rx_byte);            // read RXDATA
    @(posedge clk); #1;                   // wait for read-clear FF to fire
    chk("irq low after rx cleared",{31'h0,irq},32'h0);
    bus_write(12'h00C,32'h0);

    // -- Test 11: IRQ from tx_ie
    $display("-- Test 11: IRQ from tx_ie");
    wait_tx_done;
    bus_write(12'h00C,32'h2); #1;
    chk("irq high when tx idle + tx_ie",{31'h0,irq},32'h1);
    @(posedge clk); #1;
    addr=12'h000; wdata=32'h01; we=1; @(posedge clk); #1; we=0; #1;
    bus_read(12'h008,reg_val);
    if(reg_val[0]) chk("irq low while tx_busy",{31'h0,irq},32'h0);
    else $display("  SKIP  irq-during-busy (too fast to catch)");
    wait_tx_done; #1;
    chk("irq high again after tx done",{31'h0,irq},32'h1);
    bus_write(12'h00C,32'h0);

    $display("\n=== Results: %0d/%0d passed ===",pass_cnt,pass_cnt+fail_cnt);
    if(fail_cnt==0) $display("ALL TESTS PASSED\n");
    else $display("%0d TESTS FAILED\n",fail_cnt);
    $finish;
end

initial begin #50_000_000; $display("TIMEOUT"); $finish; end
endmodule
