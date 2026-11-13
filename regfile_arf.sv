`timescale 1ns / 1ps
module regfile_arf
  import riscv_pkg::*;
(
    input  logic clk_i,
    input  logic rstn_i,

    // combinational read ports
    input  logic [4:0]      rs1_idx0_i,
    input  logic [4:0]      rs2_idx0_i,
    input  logic [4:0]      rs1_idx1_i,
    input  logic [4:0]      rs2_idx1_i,
    output logic [XLEN-1:0] rs1_data0_o,
    output logic [XLEN-1:0] rs2_data0_o,
    output logic [XLEN-1:0] rs1_data1_o,
    output logic [XLEN-1:0] rs2_data1_o,

    // commit writeback
    input  logic           we0_i,
    input  logic [4:0]       waddr0_i,
    input  logic [XLEN-1:0]  wdata0_i,
    input  logic           we1_i,
    input  logic [4:0]       waddr1_i,
    input  logic [XLEN-1:0]  wdata1_i
);

  logic [XLEN-1:0] regs_q[32];


  assign rs1_data0_o = (rs1_idx0_i == 5'd0) ? '0 : regs_q[rs1_idx0_i];
  assign rs2_data0_o = (rs2_idx0_i == 5'd0) ? '0 : regs_q[rs2_idx0_i];
  assign rs1_data1_o = (rs1_idx1_i == 5'd0) ? '0 : regs_q[rs1_idx1_i];
  assign rs2_data1_o = (rs2_idx1_i == 5'd0) ? '0 : regs_q[rs2_idx1_i];

  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      for (int i = 0; i < 32; i++) regs_q[i] <= '0;
    end else begin
      
      // we1 last -> priority  on the same adres
      if (we0_i && waddr0_i != 5'd0) regs_q[waddr0_i] <= wdata0_i;
      if (we1_i && waddr1_i != 5'd0) regs_q[waddr1_i] <= wdata1_i;
    end
  end

endmodule
