`timescale 1ns / 1ps
// Rename table: mapping architectural registers to ROB tags.
// pending=0 -> ARF value is current.
module rename_table
  import riscv_pkg::*;
(
    input  logic clk_i,
    input  logic rstn_i,
    input  logic flush_i,

    // combinational read ports
    input logic [4:0] rs1_idx0_i,
    input logic [4:0] rs2_idx0_i,
    input logic [4:0] rs1_idx1_i,
    input logic [4:0] rs2_idx1_i,
    output rnt_entry_t rs1_0_o,
    output rnt_entry_t rs2_0_o,
    output rnt_entry_t rs1_1_o,
    output rnt_entry_t rs2_1_o,


    // commit-clear
    input  logic commit0_valid_i,
    input  logic commit0_rd_used_i,
    input  logic [4:0]           commit0_rd_idx_i,
    input  logic [ROB_IDX_W-1:0] commit0_tag_i,
    input  logic commit1_valid_i ,
    input  logic commit1_rd_used_i,
    input  logic [4:0]           commit1_rd_idx_i ,
    input  logic [ROB_IDX_W-1:0] commit1_tag_i,

    // rename-write
    input  logic wr0_en_i,
    input  logic [4:0] wr0_rd_idx_i,
    input  logic [ROB_IDX_W-1:0] wr0_tag_i,
    input  logic wr1_en_i,
    input  logic [4:0] wr1_rd_idx_i,
    input  logic [ROB_IDX_W-1:0] wr1_tag_i
);

  rnt_entry_t table_q[32];
  rnt_entry_t table_next[32];

  assign rs1_0_o = table_q[rs1_idx0_i];
  assign rs2_0_o = table_q[rs2_idx0_i];
  assign rs1_1_o = table_q[rs1_idx1_i];
  assign rs2_1_o = table_q[rs2_idx1_i];

  always_comb begin
    table_next = table_q;

    if (flush_i) begin
      // redirect at commit invalidates every in-flight rename

      for (int i = 0; i < 32; i++) table_next[i].pending = 1'b0;
    end else begin

      // commit-clear
      if (commit0_valid_i && commit0_rd_used_i &&
          table_q[commit0_rd_idx_i].tag == commit0_tag_i ) begin
        table_next[commit0_rd_idx_i].pending = 1'b0;
      end
      if (commit1_valid_i && commit1_rd_used_i &&
          table_q[commit1_rd_idx_i].tag == commit1_tag_i) begin
        table_next[commit1_rd_idx_i].pending = 1'b0;
      end

      // rename-write
      if (wr0_en_i) table_next[wr0_rd_idx_i] = '{pending: 1'b1, tag: wr0_tag_i};
      if (wr1_en_i) table_next[wr1_rd_idx_i] = '{pending: 1'b1, tag: wr1_tag_i};
    end
  end

  always_ff @( posedge clk_i) begin
    if (!rstn_i) begin
      for (int i = 0; i < 32; i++) table_q[i] <= '0;
    end else begin
      table_q <= table_next;
    end
  end


endmodule
