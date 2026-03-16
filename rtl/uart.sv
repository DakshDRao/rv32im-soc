// ============================================================
//  uart.sv  -  8N1 UART Peripheral
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//  Step    : 15 — UART (TX + RX + Interrupt)
//
//  Register Map  (base = 0x4000_1000)
//  ─────────────────────────────────────────────────────────
//  Offset  Name     Access  Description
//  0x00    TXDATA   W       Write byte → start TX (ignored if tx_busy)
//  0x04    RXDATA   R       Read received byte; clears rx_ready + overrun
//  0x08    STATUS   R       [0]=tx_busy [1]=rx_ready [2]=rx_overrun
//  0x0C    CTRL     R/W     [0]=rx_ie   [1]=tx_ie
//
//  IRQ (level):
//    irq = (rx_ie & rx_ready) | (tx_ie & ~tx_busy)
//
//  TX path:
//    Shift register {stop=1, data[7:0], start=0} driven LSB-first.
//    tx line held high (mark) when idle.
//
//  RX path:
//    2-FF synchroniser → falling-edge start-bit detect →
//    sample middle of start bit → sample 8 data bits at
//    BAUD_DIV intervals → check stop bit.
//    rx_overrun set if a second byte arrives before RXDATA is read.
//
//  Parameters:
//    CLK_FREQ  — system clock in Hz  (default 100 MHz)
//    BAUD_RATE — baud rate           (default 115 200)
// ============================================================

module uart #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
)(
    input  logic        clk,
    input  logic        rst,

    // ── Bus interface (from bus_fabric) ──────────────────────
    input  logic [11:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic [2:0]  funct3,   // unused — all accesses are word-width
    output logic [31:0] rdata,

    // ── Serial pins ──────────────────────────────────────────
    output logic        tx,
    input  logic        rx,

    // ── Interrupt (level, active-high) ───────────────────────
    output logic        irq
);

// ─────────────────────────────────────────────────────────────
//  Baud Generator Constants
// ─────────────────────────────────────────────────────────────
localparam int BAUD_DIV     = CLK_FREQ / BAUD_RATE;           // clocks per bit
localparam int BAUD_HALF    = BAUD_DIV / 2;                   // half-period for RX centering
localparam int BAUD_CNT_W   = $clog2(BAUD_DIV + 1);

// ─────────────────────────────────────────────────────────────
//  Register Addresses
// ─────────────────────────────────────────────────────────────
localparam logic [11:0] ADDR_TXDATA = 12'h000;
localparam logic [11:0] ADDR_RXDATA = 12'h004;
localparam logic [11:0] ADDR_STATUS = 12'h008;
localparam logic [11:0] ADDR_CTRL   = 12'h00C;

// ─────────────────────────────────────────────────────────────
//  TX Path
// ─────────────────────────────────────────────────────────────
logic [9:0]               tx_shift;       // {stop, data[7:0], start}
logic [3:0]               tx_bits_rem;    // bits left to send (10 → 0)
logic [BAUD_CNT_W-1:0]    tx_cnt;         // baud counter
logic                     tx_busy;

// TX serial line: drive shift[0] when busy, else idle (mark=1)
assign tx = tx_busy ? tx_shift[0] : 1'b1;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_shift    <= '1;
        tx_bits_rem <= '0;
        tx_cnt      <= '0;
        tx_busy     <= 1'b0;
    end else begin
        if (!tx_busy) begin
            // Accept new byte on write to TXDATA
            if (we && addr == ADDR_TXDATA) begin
                tx_shift    <= {1'b1, wdata[7:0], 1'b0};  // stop | data | start
                tx_bits_rem <= 4'd10;
                tx_cnt      <= '0;
                tx_busy     <= 1'b1;
            end
        end else begin
            // Count one baud period
            if (tx_cnt == BAUD_CNT_W'(BAUD_DIV - 1)) begin
                tx_cnt      <= '0;
                tx_shift    <= {1'b1, tx_shift[9:1]};      // shift right, fill 1
                tx_bits_rem <= tx_bits_rem - 1'b1;
                if (tx_bits_rem == 4'd1)
                    tx_busy <= 1'b0;
            end else begin
                tx_cnt <= tx_cnt + 1'b1;
            end
        end
    end
end

// ─────────────────────────────────────────────────────────────
//  RX Path
// ─────────────────────────────────────────────────────────────

// 2-FF synchroniser
logic rx_s1, rx_s0, rx_prev;
always_ff @(posedge clk or posedge rst) begin
    if (rst) {rx_s1, rx_s0, rx_prev} <= 3'b111;
    else     {rx_s0, rx_s1, rx_prev} <= {rx_s1, rx, rx_s0};
end

wire rx_fall = rx_prev & ~rx_s0;   // falling edge = start bit

// RX state machine
typedef enum logic [1:0] {
    RX_IDLE  = 2'd0,
    RX_START = 2'd1,
    RX_DATA  = 2'd2,
    RX_STOP  = 2'd3
} rx_state_e;

rx_state_e                rx_state;
logic [BAUD_CNT_W-1:0]    rx_cnt;
logic [2:0]               rx_bit_idx;
logic [7:0]               rx_shift;
logic [7:0]               rx_data;
logic                     rx_ready;
logic                     rx_overrun;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_state   <= RX_IDLE;
        rx_cnt     <= '0;
        rx_bit_idx <= '0;
        rx_shift   <= '0;
        rx_data    <= '0;
        rx_ready   <= 1'b0;
        rx_overrun <= 1'b0;
    end else begin

        // ── State machine ──────────────────────────────────
        unique case (rx_state)

            RX_IDLE: begin
                if (rx_fall) begin
                    rx_state <= RX_START;
                    rx_cnt   <= '0;
                end
            end

            // Wait BAUD_HALF to land in the middle of start bit
            RX_START: begin
                if (rx_cnt == BAUD_CNT_W'(BAUD_HALF - 1)) begin
                    rx_cnt <= '0;
                    if (!rx_s0) begin           // confirmed start bit
                        rx_state   <= RX_DATA;
                        rx_bit_idx <= 3'd0;
                    end else begin
                        rx_state <= RX_IDLE;    // glitch — abort
                    end
                end else begin
                    rx_cnt <= rx_cnt + 1'b1;
                end
            end

            // Sample 8 data bits, one BAUD_DIV apart
            RX_DATA: begin
                if (rx_cnt == BAUD_CNT_W'(BAUD_DIV - 1)) begin
                    rx_cnt     <= '0;
                    rx_shift   <= {rx_s0, rx_shift[7:1]};   // LSB first
                    if (rx_bit_idx == 3'd7)
                        rx_state <= RX_STOP;
                    else
                        rx_bit_idx <= rx_bit_idx + 1'b1;
                end else begin
                    rx_cnt <= rx_cnt + 1'b1;
                end
            end

            // Wait one more period then check stop bit
            RX_STOP: begin
                if (rx_cnt == BAUD_CNT_W'(BAUD_DIV - 1)) begin
                    rx_cnt   <= '0;
                    rx_state <= RX_IDLE;
                    if (rx_s0) begin            // valid stop bit (mark)
                        rx_data  <= rx_shift;
                        rx_overrun <= rx_ready; // was previous byte read?
                        rx_ready <= 1'b1;
                    end
                    // framing error: silently discard (could add flag in Step 18)
                end else begin
                    rx_cnt <= rx_cnt + 1'b1;
                end
            end

        endcase

        // ── Register read side-effects ─────────────────────
        // Reading RXDATA clears rx_ready and rx_overrun
        if (!we && addr == ADDR_RXDATA) begin
            rx_ready   <= 1'b0;
            rx_overrun <= 1'b0;
        end

    end
end

// ─────────────────────────────────────────────────────────────
//  Control Register
// ─────────────────────────────────────────────────────────────
logic rx_ie, tx_ie;

always_ff @(posedge clk or posedge rst) begin
    if (rst)                            {tx_ie, rx_ie} <= 2'b00;
    else if (we && addr == ADDR_CTRL)   {tx_ie, rx_ie} <= wdata[1:0];
end

// ─────────────────────────────────────────────────────────────
//  Interrupt
// ─────────────────────────────────────────────────────────────
assign irq = (rx_ie & rx_ready) | (tx_ie & ~tx_busy);

// ─────────────────────────────────────────────────────────────
//  Read Mux
// ─────────────────────────────────────────────────────────────
always_comb begin : read_mux
    unique case (addr)
        ADDR_RXDATA: rdata = {24'h0, rx_data};
        ADDR_STATUS: rdata = {29'h0, rx_overrun, rx_ready, tx_busy};
        ADDR_CTRL:   rdata = {30'h0, tx_ie, rx_ie};
        default:     rdata = 32'h0;
    endcase
end

endmodule
