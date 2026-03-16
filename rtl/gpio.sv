// ============================================================
//  gpio.sv  -  General Purpose I/O Peripheral
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//  Step    : 16 — GPIO (LEDs / Buttons / Switches)
//
//  Register Map  (base = 0x4000_0000)
//  ─────────────────────────────────────────────────────────
//  Offset  Name        Access  Description
//  0x00    DIR         R/W     [3:0]  1=output 0=input (per LED pin)
//  0x04    DATA_OUT    R/W     [3:0]  → gpio_led (only where DIR=1)
//  0x08    DATA_IN     R       [7:0]  ← {sw[3:0], btn[3:0]} (2-FF synced)
//  0x0C    CTRL        R/W     [0]=out_ie  [1]=in_ie
//  0x10    IRQ_STATUS  R/W1C   [0]=out_event [1]=in_change  (write-1-to-clear)
//
//  IRQ (level):
//    irq = |(ctrl & irq_status)
//
//  Output:
//    gpio_led[i] = data_out[i]  when DIR[i]=1, else 1'bz (tri-state)
//    In simulation output is driven 0 when DIR[i]=0 for observability.
//
//  Input synchronisation:
//    btn and sw pass through a 2-FF synchroniser before being
//    latched into data_in.  A change in any synchronised input
//    sets irq_status[1] (in_change) when in_ie=1.
// ============================================================

module gpio #(
    parameter int N_OUT = 4,    // number of output (LED) pins
    parameter int N_IN  = 8     // number of input (BTN+SW) pins
)(
    input  logic            clk,
    input  logic            rst,

    // ── Bus interface (from bus_fabric) ──────────────────────
    input  logic [11:0]     addr,
    input  logic [31:0]     wdata,
    input  logic            we,
    input  logic [2:0]      funct3,   // unused — word accesses only
    output logic [31:0]     rdata,

    // ── Board pins ───────────────────────────────────────────
    output logic [N_OUT-1:0] gpio_led,
    input  logic [N_OUT-1:0] gpio_btn,
    input  logic [N_OUT-1:0] gpio_sw,

    // ── Interrupt ────────────────────────────────────────────
    output logic             irq
);

// ─────────────────────────────────────────────────────────────
//  Register Addresses
// ─────────────────────────────────────────────────────────────
localparam logic [11:0]
    ADDR_DIR        = 12'h000,
    ADDR_DATA_OUT   = 12'h004,
    ADDR_DATA_IN    = 12'h008,
    ADDR_CTRL       = 12'h00C,
    ADDR_IRQ_STATUS = 12'h010;

// ─────────────────────────────────────────────────────────────
//  Registers
// ─────────────────────────────────────────────────────────────
logic [N_OUT-1:0] dir_r;        // direction: 1=output
logic [N_OUT-1:0] data_out_r;   // output data
logic [1:0]       ctrl_r;       // [0]=out_ie [1]=in_ie
logic [1:0]       irq_status_r; // [0]=out_event [1]=in_change

// ─────────────────────────────────────────────────────────────
//  Input Synchroniser  (2-FF)
// ─────────────────────────────────────────────────────────────
logic [N_IN-1:0] in_sync1, in_sync0, in_prev;
logic [N_IN-1:0] data_in_sync;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        in_sync1  <= '0;
        in_sync0  <= '0;
        in_prev   <= '0;
    end else begin
        in_sync1  <= {gpio_sw, gpio_btn};
        in_sync0  <= in_sync1;
        in_prev   <= in_sync0;
    end
end
assign data_in_sync = in_sync0;

wire in_changed = (data_in_sync != in_prev);

// ─────────────────────────────────────────────────────────────
//  Register Write + IRQ Status
// ─────────────────────────────────────────────────────────────
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        dir_r        <= '0;
        data_out_r   <= '0;
        ctrl_r       <= '0;
        irq_status_r <= '0;
    end else begin

        // ── Input-change event ─────────────────────────────
        if (in_changed)
            irq_status_r[1] <= 1'b1;

        // ── Register writes ────────────────────────────────
        if (we) begin
            unique case (addr)
                ADDR_DIR:        dir_r      <= wdata[N_OUT-1:0];
                ADDR_DATA_OUT: begin
                    data_out_r   <= wdata[N_OUT-1:0];
                    irq_status_r[0] <= 1'b1;   // out_event on any write
                end
                ADDR_CTRL:       ctrl_r     <= wdata[1:0];
                ADDR_IRQ_STATUS: irq_status_r <= irq_status_r & ~wdata[1:0]; // W1C
                default: ;
            endcase
        end

    end
end

// ─────────────────────────────────────────────────────────────
//  Output Drive
//  gpio_led[i] follows data_out_r[i] when DIR[i]=1, else 0.
//  (For synthesis on real board, replace with tri-state / IOBUF.)
// ─────────────────────────────────────────────────────────────
assign gpio_led = data_out_r & dir_r;

// ─────────────────────────────────────────────────────────────
//  Interrupt
// ─────────────────────────────────────────────────────────────
assign irq = |(ctrl_r & irq_status_r);

// ─────────────────────────────────────────────────────────────
//  Read Mux
// ─────────────────────────────────────────────────────────────
always_comb begin : read_mux
    unique case (addr)
        ADDR_DIR:        rdata = {{(32-N_OUT){1'b0}}, dir_r};
        ADDR_DATA_OUT:   rdata = {{(32-N_OUT){1'b0}}, data_out_r};
        ADDR_DATA_IN:    rdata = {{(32-N_IN) {1'b0}}, data_in_sync};
        ADDR_CTRL:       rdata = {30'h0, ctrl_r};
        ADDR_IRQ_STATUS: rdata = {30'h0, irq_status_r};
        default:         rdata = 32'h0;
    endcase
end

endmodule
