// ============================================================
//  writeback.sv  -  Writeback Mux  (RV32I)
//  Project : Single-Cycle RISC-V Core
//  Board   : Arty A7 (Artix-7)
//
//  Selects what gets written back to the register file (rd).
//  Purely combinational - one 4-way mux.
//
//  wb_sel encoding (must match control.sv WB_* constants):
//    2'b00  WB_ALU : rd ← alu_result   R-type, I-ALU, AUIPC, JALR
//    2'b01  WB_MEM : rd ← mem_rdata    LB, LH, LW, LBU, LHU
//    2'b10  WB_PC4 : rd ← pc_plus4     JAL, JALR (return address)
//    2'b11  WB_IMM : rd ← imm          LUI (upper immediate)
// ============================================================

module writeback (
    input  logic [1:0]  wb_sel,
    input  logic [31:0] alu_result,
    input  logic [31:0] mem_rdata,
    input  logic [31:0] pc_plus4,
    input  logic [31:0] imm,
    output logic [31:0] wd            // write data → regfile.wd
);

localparam [1:0]
    WB_ALU = 2'b00,
    WB_MEM = 2'b01,
    WB_PC4 = 2'b10,
    WB_IMM = 2'b11;

always_comb begin : wb_mux
    unique case (wb_sel)
        WB_ALU: wd = alu_result;
        WB_MEM: wd = mem_rdata;
        WB_PC4: wd = pc_plus4;
        WB_IMM: wd = imm;
    endcase
end

endmodule