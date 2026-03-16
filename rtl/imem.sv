// ============================================================
//  imem.sv  -  Instruction Memory  (Async read, RV32I)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  TWO read ports:
//    Port 1 (instr): instruction fetch from PC — word-aligned
//    Port 2 (ddata): data read from bus fabric — supports byte/
//                    halfword/word via funct3 (same as dmem)
//
//  Port 2 allows firmware to read .rodata strings that the
//  compiler places in the code segment (0x0000_xxxx range).
// ============================================================

module imem #(
    parameter int    DEPTH     = 1024,
    parameter int    ADDR_BITS = 10,
    parameter string MEM_FILE  = ""
)(
    input  logic        clk,
    // ── Port 1: instruction fetch ─────────────────────────────
    input  logic [31:0] addr,
    output logic [31:0] instr,
    // ── Port 2: data read (for .rodata access) ────────────────
    input  logic [31:0] daddr,
    input  logic [2:0]  dfunct3,
    output logic [31:0] ddata
);

logic [31:0] mem [0:DEPTH-1];

initial begin
    for (int i = 0; i < DEPTH; i++)
        mem[i] = 32'h0000_0013;
    if (MEM_FILE != "")
        $readmemh(MEM_FILE, mem);
end

// ── Port 1: instruction fetch (word-aligned) ─────────────────
assign instr = mem[addr[ADDR_BITS+1:2]];

// ── Port 2: data read with byte/halfword/word support ─────────
logic [31:0] raw_word;
logic [1:0]  byte_off;

assign raw_word = mem[daddr[ADDR_BITS+1:2]];
assign byte_off = daddr[1:0];

always_comb begin : ddata_mux
    unique casez (dfunct3)
        3'b000: begin // LB  — sign-extended byte
            logic [7:0] b;
            b = raw_word >> (byte_off * 8);
            ddata = {{24{b[7]}}, b};
        end
        3'b001: begin // LH  — sign-extended halfword
            logic [15:0] h;
            h = raw_word >> (byte_off[1] * 16);
            ddata = {{16{h[15]}}, h};
        end
        3'b010: begin // LW  — full word
            ddata = raw_word;
        end
        3'b100: begin // LBU — zero-extended byte
            ddata = {24'h0, raw_word >> (byte_off * 8)};
        end
        3'b101: begin // LHU — zero-extended halfword
            ddata = {16'h0, raw_word >> (byte_off[1] * 16)};
        end
        default: ddata = raw_word;
    endcase
end

endmodule
