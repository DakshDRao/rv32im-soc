// ============================================================
//  riscv_core.sv  -  Single-Cycle RV32IM Core (SoC version)
//  Project : Single-Cycle RV32IM SoC
//  Board   : Arty A7 (Artix-7)
//
//  Step 14 change: dmem removed, external dbus_* ports added
//  Step 18 changes:
//    • csr_regs instantiated
//    • control gets instr[20] and instr[28]
//    • wb_sel widened to 3 bits
//    • writeback gets csr_rdata
//    • pc_logic gets trap_taken/trap_pc/mret_taken/mepc
//    • trap_taken gates reg_write, mem_write, csr_we
//    • Interrupt lines (timer/uart/gpio) added as inputs
// ============================================================

module riscv_core #(
    parameter int          IMEM_DEPTH = 1024,
    parameter logic [31:0] BOOT_ADDR  = 32'h0000_0000,
    parameter string       IMEM_FILE  = ""
)(
    input  logic        clk,
    input  logic        rst,

    // ── External Data Bus ────────────────────────────────────
    output logic [31:0] dbus_addr,
    output logic [31:0] dbus_wdata,
    output logic        dbus_we,
    output logic [2:0]  dbus_funct3,
    input  logic [31:0] dbus_rdata,

    // ── Interrupt lines (from peripherals) ───────────────────
    input  logic        timer_irq,
    input  logic        uart_irq,
    input  logic        gpio_irq,

    // ── IMEM data port (for bus_fabric to read .rodata) ──────
    input  logic [31:0] imem_daddr,
    input  logic [2:0]  imem_dfunct3,
    output logic [31:0] imem_ddata
);

// ─────────────────────────────────────────────────────────────
//  PC / Instruction
// ─────────────────────────────────────────────────────────────
logic [31:0] pc, pc_plus4, instr;

// Instruction fields
logic [6:0]  opcode;
logic [4:0]  rs1_addr, rs2_addr, rd_addr;
logic [2:0]  funct3;
logic        funct7_5, funct7_1;
logic        instr_20, instr_28;

assign opcode   = instr[6:0];
assign rd_addr  = instr[11:7];
assign funct3   = instr[14:12];
assign rs1_addr = instr[19:15];
assign rs2_addr = instr[24:20];
assign funct7_1 = instr[25];
assign funct7_5 = instr[30];
assign instr_20 = instr[20];
assign instr_28 = instr[28];

// ─────────────────────────────────────────────────────────────
//  Control Signals
// ─────────────────────────────────────────────────────────────
logic        reg_write_raw;   // from control (before trap gating)
logic        alu_src;
logic [4:0]  alu_op;
logic        mem_write_raw;   // from control (before trap gating)
logic [2:0]  mem_funct3;
logic [2:0]  wb_sel;
logic        branch, jump, jalr;
logic [2:0]  imm_sel;
logic        auipc_op;
logic        is_csr, is_ecall, is_ebreak, is_mret;

// ─────────────────────────────────────────────────────────────
//  Trap / CSR signals
// ─────────────────────────────────────────────────────────────
logic        trap_taken, mret_taken;
logic [31:0] trap_pc, mepc;
logic [31:0] csr_rdata;

// Gate writes on trap: when a trap fires, the current
// instruction's side effects are suppressed.
wire reg_write = reg_write_raw & ~trap_taken;
wire mem_write = mem_write_raw & ~trap_taken;

// ─────────────────────────────────────────────────────────────
//  Immediate / Regfile / ALU
// ─────────────────────────────────────────────────────────────
logic [31:0] imm;
logic [31:0] rs1_data, rs2_data, wd;
logic [31:0] alu_a, alu_b, alu_result;
logic        alu_zero;
logic        branch_taken;
logic [31:0] mem_rdata;

// ─────────────────────────────────────────────────────────────
//  Data Bus
// ─────────────────────────────────────────────────────────────
assign dbus_addr   = alu_result;
assign dbus_wdata  = rs2_data;
assign dbus_we     = mem_write;
assign dbus_funct3 = mem_funct3;
assign mem_rdata   = dbus_rdata;

// ─────────────────────────────────────────────────────────────
//  PC Logic
// ─────────────────────────────────────────────────────────────
pc_logic #(.BOOT_ADDR(BOOT_ADDR)) u_pc (
    .clk         (clk),
    .rst         (rst),
    .jump        (jump),
    .jalr        (jalr),
    .branch_taken(branch_taken),
    .trap_taken  (trap_taken),
    .trap_pc     (trap_pc),
    .mret_taken  (mret_taken),
    .mepc        (mepc),
    .rs1         (rs1_data),
    .imm         (imm),
    .pc          (pc),
    .pc_plus4    (pc_plus4)
);

// ─────────────────────────────────────────────────────────────
//  Instruction Memory
//  Port 2 (daddr/ddata) is wired to the data bus via soc_top
//  so firmware can read .rodata strings from IMEM address space.
// ─────────────────────────────────────────────────────────────
imem #(
    .DEPTH    (IMEM_DEPTH),
    .ADDR_BITS($clog2(IMEM_DEPTH)),
    .MEM_FILE (IMEM_FILE)
) u_imem (
    .clk     (clk),
    .addr    (pc),
    .instr   (instr),
    .daddr   (imem_daddr),
    .dfunct3 (imem_dfunct3),
    .ddata   (imem_ddata)
);

// ─────────────────────────────────────────────────────────────
//  Control Unit
// ─────────────────────────────────────────────────────────────
control u_ctrl (
    .opcode    (opcode),
    .funct3    (funct3),
    .funct7_5  (funct7_5),
    .funct7_1  (funct7_1),
    .instr_20  (instr_20),
    .instr_28  (instr_28),
    .reg_write (reg_write_raw),
    .alu_src   (alu_src),
    .alu_op    (alu_op),
    .mem_write (mem_write_raw),
    .mem_funct3(mem_funct3),
    .wb_sel    (wb_sel),
    .branch    (branch),
    .jump      (jump),
    .jalr      (jalr),
    .imm_sel   (imm_sel),
    .auipc_op  (auipc_op),
    .is_csr    (is_csr),
    .is_ecall  (is_ecall),
    .is_ebreak (is_ebreak),
    .is_mret   (is_mret)
);

// ─────────────────────────────────────────────────────────────
//  Immediate Generator
// ─────────────────────────────────────────────────────────────
imm_gen u_immgen (
    .instr  (instr),
    .imm_sel(imm_sel),
    .imm    (imm)
);

// ─────────────────────────────────────────────────────────────
//  Register File
// ─────────────────────────────────────────────────────────────
regfile u_regfile (
    .clk (clk),
    .we  (reg_write),
    .rs1 (rs1_addr),
    .rs2 (rs2_addr),
    .rd  (rd_addr),
    .wd  (wd),
    .rd1 (rs1_data),
    .rd2 (rs2_data)
);

// ─────────────────────────────────────────────────────────────
//  ALU
// ─────────────────────────────────────────────────────────────
assign alu_a = auipc_op ? pc : rs1_data;
assign alu_b = alu_src  ? imm : rs2_data;

alu u_alu (
    .a      (alu_a),
    .b      (alu_b),
    .alu_op (alu_op),
    .result (alu_result),
    .zero   (alu_zero)
);

// ─────────────────────────────────────────────────────────────
//  Branch Unit
// ─────────────────────────────────────────────────────────────
branch_unit u_branch (
    .rs1         (rs1_data),
    .rs2         (rs2_data),
    .funct3      (funct3),
    .branch      (branch),
    .branch_taken(branch_taken)
);

// ─────────────────────────────────────────────────────────────
//  CSR Registers + Trap Handler
// ─────────────────────────────────────────────────────────────
csr_regs u_csr (
    .clk        (clk),
    .rst        (rst),
    .csr_addr   (instr[31:20]),
    .rs1_data   (rs1_data),
    .rs1_addr   (rs1_addr),
    .zimm       (rs1_addr),       // zimm uses same field as rs1 (instr[19:15])
    .csr_op     (funct3),
    .is_csr     (is_csr),
    .is_ecall   (is_ecall),
    .is_ebreak  (is_ebreak),
    .is_mret    (is_mret),
    .pc         (pc),
    .timer_irq  (timer_irq),
    .uart_irq   (uart_irq),
    .gpio_irq   (gpio_irq),
    .mepc_out   (mepc),
    .trap_pc    (trap_pc),
    .trap_taken (trap_taken),
    .mret_taken (mret_taken),
    .csr_rdata  (csr_rdata)
);

// ─────────────────────────────────────────────────────────────
//  Writeback Mux
// ─────────────────────────────────────────────────────────────
writeback u_wb (
    .wb_sel    (wb_sel),
    .alu_result(alu_result),
    .mem_rdata (mem_rdata),
    .pc_plus4  (pc_plus4),
    .imm       (imm),
    .csr_rdata (csr_rdata),
    .wd        (wd)
);

endmodule