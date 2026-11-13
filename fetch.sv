`timescale 1ns / 1ps
// 2-wide fetch: PC register + instruction memory
module fetch
  import riscv_pkg::*;
#(
    parameter IMemInitFile = "imem.mem"
) (input  logic clk_i,
    input  logic rstn_i,

    input  logic            stall_i,
    input  logic            flush_i,
    input  logic [XLEN-1:0] redirect_pc_i,
    output logic [XLEN-1:0] pc0_o,
    output logic [XLEN-1:0] instr0_o,
    output logic [XLEN-1:0] pc1_o,
    output logic [XLEN-1:0] instr1_o
);

  logic [XLEN-1:0] instr_mem[0:2047];
  initial begin
    $readmemh(IMemInitFile, instr_mem, 0, 2047);
  end

  logic [XLEN-1:0] pc_q;

  assign pc0_o = pc_q;
  assign pc1_o = pc_q + 32'd4;
  assign instr0_o = instr_mem[pc0_o[12:2]];
  assign instr1_o = instr_mem[pc1_o[12:2]];


  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      pc_q <= 32'h8000_0000;
    end else if (flush_i) begin
      pc_q <= redirect_pc_i;
    end else if (stall_i) begin
      pc_q <= pc_q;
    end else begin
      pc_q <= pc_q + 32'd8;
    end
  end

endmodule
