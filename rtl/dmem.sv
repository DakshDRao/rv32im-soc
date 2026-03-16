// ============================================================
//  dmem.sv  -  Data Memory  (Sync write, Async read, RV32I)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  Single-cycle loads must complete combinationally so the
//  result is available for writeback in the same cycle.
//
//  Write port : synchronous (posedge clk), byte-enable gated
//  Read port  : combinational - load result available same cycle
//
//  Byte enables (funct3[1:0] + addr[1:0]):
//    SB → 1 of 4 byte lanes
//    SH → 2 consecutive lanes (halfword-aligned)
//    SW → all 4 lanes
//
//  Load extension applied combinationally after raw read:
//    LB  → sign-extend selected byte
//    LH  → sign-extend selected halfword
//    LW  → full word passthrough
//    LBU → zero-extend selected byte
//    LHU → zero-extend selected halfword
// ============================================================

module dmem #(
    parameter int DEPTH     = 1024,
    parameter int ADDR_BITS = 10
)(
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic [2:0]  funct3,
    output logic [31:0] rdata
);

localparam [2:0]
    F3_LB=3'b000, F3_LH=3'b001, F3_LW=3'b010,
    F3_LBU=3'b100, F3_LHU=3'b101;

// ── 4 byte-wide banks ─────────────────────────────────────────
logic [7:0] bank0 [0:DEPTH-1];
logic [7:0] bank1 [0:DEPTH-1];
logic [7:0] bank2 [0:DEPTH-1];
logic [7:0] bank3 [0:DEPTH-1];

logic [ADDR_BITS-1:0] word_idx;
logic [1:0]           byte_off;
assign word_idx = addr[ADDR_BITS+1:2];
assign byte_off = addr[1:0];

// ── Byte enable decode ────────────────────────────────────────
logic [3:0] byte_en;
always_comb begin : byte_enable_decode
    case (funct3[1:0])
        2'b00: begin   // SB
            case (byte_off)
                2'b00: byte_en = 4'b0001;
                2'b01: byte_en = 4'b0010;
                2'b10: byte_en = 4'b0100;
                2'b11: byte_en = 4'b1000;
            endcase
        end
        2'b01: begin   // SH
            case (byte_off)
                2'b00:   byte_en = 4'b0011;
                2'b10:   byte_en = 4'b1100;
                default: byte_en = 4'b0000;
            endcase
        end
        2'b10:   byte_en = 4'b1111;   // SW
        default: byte_en = 4'b0000;
    endcase
end

// ── Synchronous write ─────────────────────────────────────────
always_ff @(posedge clk) begin : write_port
    if (we) begin
        if (byte_en[0]) bank0[word_idx] <= wdata[7:0];
        if (byte_en[1]) bank1[word_idx] <= (funct3[0] | funct3[1]) ? wdata[15:8]  : wdata[7:0];
        if (byte_en[2]) bank2[word_idx] <= funct3[1] ? wdata[23:16] : wdata[7:0];
        if (byte_en[3]) bank3[word_idx] <= funct3[1] ? wdata[31:24] : (funct3[0] ? wdata[15:8] : wdata[7:0]);
    end
end

// ── Combinational (async) read + load extension ───────────────
logic [31:0] raw;
assign raw = {bank3[word_idx], bank2[word_idx],
              bank1[word_idx], bank0[word_idx]};

always_comb begin : load_extend
    case (funct3)
        F3_LB:  case (byte_off)
                    2'b00: rdata = {{24{raw[7]}},  raw[7:0]};
                    2'b01: rdata = {{24{raw[15]}}, raw[15:8]};
                    2'b10: rdata = {{24{raw[23]}}, raw[23:16]};
                    2'b11: rdata = {{24{raw[31]}}, raw[31:24]};
                endcase
        F3_LH:  case (byte_off)
                    2'b00:   rdata = {{16{raw[15]}}, raw[15:0]};
                    2'b10:   rdata = {{16{raw[31]}}, raw[31:16]};
                    default: rdata = 32'b0;
                endcase
        F3_LW:  rdata = raw;
        F3_LBU: case (byte_off)
                    2'b00: rdata = {24'b0, raw[7:0]};
                    2'b01: rdata = {24'b0, raw[15:8]};
                    2'b10: rdata = {24'b0, raw[23:16]};
                    2'b11: rdata = {24'b0, raw[31:24]};
                endcase
        F3_LHU: case (byte_off)
                    2'b00:   rdata = {16'b0, raw[15:0]};
                    2'b10:   rdata = {16'b0, raw[31:16]};
                    default: rdata = 32'b0;
                endcase
        default: rdata = raw;
    endcase
end

// synthesis translate_off
initial begin
    for (int i = 0; i < DEPTH; i++)
        {bank3[i], bank2[i], bank1[i], bank0[i]} = 32'h0;
end
// synthesis translate_on

endmodule