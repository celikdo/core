`timescale 1ns / 1ps
// Reorder buffer, also acts like physical register file
module rob
  import riscv_pkg::*;
(
    input  logic clk_i,
    input  logic rstn_i,

    // allocation (0 on a flush cycle)
    input  logic                  alloc0_valid_i,
    input  rob_entry_t            alloc0_data_i,
    input  logic                  alloc1_valid_i,
    input  rob_entry_t            alloc1_data_i,
    output logic [ROB_IDX_W-1:0]  alloc0_tag_o,
    output logic [ROB_IDX_W-1:0]  alloc1_tag_o,
    output logic [3:0]            free_count_o,

    // CDB writeback
    input  cdb_t     cdb_a_i,
    input  cdb_t     cdb_b_i,
    input  lsu_cdb_t cdb_c_i,

    // ROB - PRF read ports (rename time): slot0/slot1 x rs1/rs2
    input  logic [ROB_IDX_W-1:0] rd_tag_i  [4],
    output logic                 rd_done_o [4],
    output logic [XLEN-1:0]      rd_value_o[4],

    // in-order commit, up to 2/cycle
    output logic       commit0_valid_o,
    output rob_entry_t commit0_data_o,
    output logic       commit1_valid_o,
    output rob_entry_t commit1_data_o,

    // redirect fetch, invalidate everything younger
    output logic            flush_o,
    output logic [XLEN-1:0] redirect_pc_o,

    output logic [ROB_IDX_W-1:0] head_o
);

  rob_entry_t entries_q[ROB_DEPTH];
  rob_entry_t entries_next[ROB_DEPTH];

  logic [ROB_IDX_W-1:0] head_q, head_next;
  logic [ROB_IDX_W-1:0] tail_q, tail_next;
  logic [3:0]           count_q, count_next;

  assign head_o       = head_q;
  assign alloc0_tag_o = tail_q;
  assign alloc1_tag_o = tail_q + 3'd1;
  assign free_count_o = 4'(ROB_DEPTH) - count_q;


  // ROB - PRF read ports
  always_comb begin
    for (int i = 0; i < 4; i++) begin
      rd_done_o[i]  = entries_q[rd_tag_i[i]].done;
      rd_value_o[i] = entries_q[rd_tag_i[i]].value;

      if (cdb_a_i.valid && cdb_a_i.tag == rd_tag_i[i]) begin
        rd_done_o[i]  = 1'b1;
        rd_value_o[i] = cdb_a_i.value;
      end else if (cdb_b_i.valid && cdb_b_i.tag == rd_tag_i[i]) begin
        rd_done_o[i]  = 1'b1;
        rd_value_o[i] = cdb_b_i.value;
      end else if (cdb_c_i.cdb.valid && cdb_c_i.cdb.tag == rd_tag_i[i]) begin
        rd_done_o[i]  = 1'b1;
        rd_value_o[i] = cdb_c_i.cdb.value;
      end
    end
  end

  // Commit eligibility/redirect logic
  logic redirect0, redirect1;

  assign commit0_data_o   = entries_q[head_q];
  assign commit1_data_o   = entries_q[head_q+3'd1];

  assign commit0_valid_o  = (count_q > 4'd0) && entries_q[head_q].done;
  assign redirect0        = commit0_valid_o && entries_q[head_q].redirect;

  assign commit1_valid_o  = commit0_valid_o && !redirect0 &&
                             (count_q > 4'd1) && entries_q[head_q+3'd1].done;
  assign redirect1      = commit1_valid_o && entries_q[head_q+3'd1].redirect;

  assign flush_o          = redirect0 || redirect1;
  assign redirect_pc_o    = redirect0 ? entries_q[head_q].redirect_pc
                                       : entries_q[head_q+3'd1].redirect_pc;


  // entries_next: CDB writeback, then allocation

  always_comb begin
    entries_next = entries_q;

    if (cdb_a_i.valid) begin
      entries_next[cdb_a_i.tag].done     = 1'b1;
      entries_next[cdb_a_i.tag].value       = cdb_a_i.value;
      entries_next[cdb_a_i.tag].redirect    = cdb_a_i.redirect;
      entries_next[cdb_a_i.tag].redirect_pc = cdb_a_i.redirect_pc;
    end
    if (cdb_b_i.valid) begin
      entries_next[cdb_b_i.tag].done     = 1'b1;
      entries_next[cdb_b_i.tag].value       = cdb_b_i.value;
      entries_next[cdb_b_i.tag].redirect    = cdb_b_i.redirect;
      entries_next[cdb_b_i.tag].redirect_pc = cdb_b_i.redirect_pc;
    end
    if (cdb_c_i.cdb.valid) begin
      entries_next[cdb_c_i.cdb.tag].done     = 1'b1;
      entries_next[cdb_c_i.cdb.tag].value       = cdb_c_i.cdb.value;
      entries_next[cdb_c_i.cdb.tag].redirect    = cdb_c_i.cdb.redirect;
      entries_next[cdb_c_i.cdb.tag].redirect_pc = cdb_c_i.cdb.redirect_pc;
      entries_next[cdb_c_i.cdb.tag].mem_addr    = cdb_c_i.mem_addr;
      entries_next[cdb_c_i.cdb.tag].mem_data    = cdb_c_i.mem_data;
    end

    if (alloc0_valid_i) entries_next[tail_q]         = alloc0_data_i;
    if (alloc1_valid_i) entries_next[tail_q+3'd1]      = alloc1_data_i;
  end

  // head/tail/count update
  logic [3:0] n_commit, n_alloc;
  assign n_commit = {3'b0, commit0_valid_o} + {3'b0, commit1_valid_o};
  assign n_alloc  = {3'b0, alloc0_valid_i}  + {3'b0, alloc1_valid_i};

  always_comb begin
    if (flush_o) begin
      
      // retire the redirecting instruction, discard everything else in flight.
      head_next  = redirect0 ? (head_q + 3'd1) : (head_q + 3'd2);
      tail_next  = head_next;
      count_next = 4'd0;
    end else begin
      head_next  = head_q + n_commit[ROB_IDX_W-1:0];
      tail_next  = tail_q + n_alloc[ROB_IDX_W-1:0];
      count_next = count_q -  n_commit + n_alloc ;
    end
  end


  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      for (int i = 0; i < ROB_DEPTH; i++) entries_q[i] <= '0;
      head_q  <= '0;
      tail_q  <= '0;
      count_q <= '0;
    end else begin
      entries_q <= entries_next;
      head_q    <= head_next;
      tail_q   <= tail_next;
      count_q   <= count_next;
    end
  end

endmodule
