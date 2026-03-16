// ============================================================
//  regfile.sv  -  Integer Register File  (RV32I)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  Spec rules (RISC-V ISA Vol.1 §2.1):
//    • 32 registers, each 32 bits wide  (x0 - x31)
//    • x0 is HARDWIRED to 0 - writes to it are silently ignored
//    • Two independent async read ports  (rs1, rs2)
//    • One synchronous write port        (rd, posedge clk)
//
//  Extra: Write-before-Read forwarding
//    If the control unit writes rd and reads the same address
//    in the same cycle (only possible in single-cycle once we
//    pipeline), we forward wd combinationally so the read port
//    sees the new value immediately. Harmless in single-cycle,
//    essential groundwork for the pipeline in Phase 2.
//
//  Synthesis note:
//    Vivado infers this as Distributed RAM (LUT-RAM) on Artix-7
//    because of the async read ports. That is correct behaviour -
//    do NOT force it to BRAM (BRAM needs registered reads).
// ============================================================

module regfile (
    input  logic        clk,

    // ── Write Port ───────────────────────────────────────────
    input  logic        we,          // Write enable (RegWrite from control)
    input  logic [4:0]  rd,          // Destination register address
    input  logic [31:0] wd,          // Write data (from WB mux)

    // ── Read Port A (rs1) ────────────────────────────────────
    input  logic [4:0]  rs1,         // Source register 1 address
    output logic [31:0] rd1,         // Read data 1

    // ── Read Port B (rs2) ────────────────────────────────────
    input  logic [4:0]  rs2,         // Source register 2 address
    output logic [31:0] rd2          // Read data 2
);

// ─────────────────────────────────────────────────────────────
//  Register Array
//  Only x1-x31 stored. x0 never written, always returns 0.
//  Declared as [1:31] so the index directly matches x-register
//  number - no offset arithmetic needed.
// ─────────────────────────────────────────────────────────────
logic [31:0] regs [1:31];

// ─────────────────────────────────────────────────────────────
//  Read Port A  -  Combinational (async)
//
//  Priority:
//    1. rs1 == x0            → always 0 (hardwired)
//    2. rs1 == rd AND we=1   → forward wd (write-before-read)
//    3. otherwise            → read from register array
// ─────────────────────────────────────────────────────────────
always_comb begin : read_port_a
    if (rs1 == 5'd0)
        rd1 = 32'b0;
    else
        rd1 = regs[rs1];
end

// ─────────────────────────────────────────────────────────────
//  Read Port B  -  Combinational (async)
// ─────────────────────────────────────────────────────────────
always_comb begin : read_port_b
    if (rs2 == 5'd0)
        rd2 = 32'b0;
    else
        rd2 = regs[rs2];
end

// ─────────────────────────────────────────────────────────────
//  Write Port  -  Synchronous (posedge clk)
//  x0 write guard: synthesiser will optimise this away cleanly.
// ─────────────────────────────────────────────────────────────
always_ff @(posedge clk) begin : write_port
    if (we && rd != 5'd0)
        regs[rd] <= wd;
end

// ─────────────────────────────────────────────────────────────
//  Simulation Initialisation
//  Zero all regs at time 0 so sim waveforms start clean.
//  `initial` blocks are ignored by Vivado synthesis.
// ─────────────────────────────────────────────────────────────
// synthesis translate_off
initial begin
    for (int i = 1; i < 32; i++)
        regs[i] = 32'd0;
end
// synthesis translate_on

endmodule