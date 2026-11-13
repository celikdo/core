`timescale 1ns / 1ps
module issue_queue
  import riscv_pkg::*;
#(
    parameter int DEPTH    = IQ_DEPTH,
    parameter bit IS_IQ_C  = 1'b0
) (
    input  logic clk_i,
    input  logic rstn_i,
    input  logic flush_i,

    input  logic       alloc0_valid_i,
    input  iq_entry_t  alloc0_data_i,
    input  logic       alloc1_valid_i,
    input  iq_entry_t  alloc1_data_i,

    input  cdb_t cdb_a_i,
    input  cdb_t cdb_b_i,
    input  cdb_t cdb_c_i,

    input  logic [ROB_IDX_W-1:0] rob_head_i,
    input  logic       dispatch_ack_i,
    output logic        dispatch_valid_o,
    output iq_entry_t  dispatch_data_o,
    output logic [$clog2(DEPTH+1)-1:0] free_count_o
);

  iq_entry_t entries_q[DEPTH];
  iq_entry_t entries_next[DEPTH];

  // d ispatch select (from entries_q)
  logic [$clog2(DEPTH)-1:0] dispatch_idx;


  always_comb begin
    dispatch_valid_o = 1'b0;
    dispatch_idx    = '0;
    dispatch_data_o  = '0;

    if (IS_IQ_C) begin
      for (int i = 0; i < DEPTH; i++) begin
        if (entries_q[i].busy && entries_q[i].rob_tag == rob_head_i &&
            entries_q[i].src1.ready && entries_q[i].src2.ready) begin
          dispatch_valid_o= 1'b1;
          dispatch_idx     = i[$clog2(DEPTH)-1:0];
          dispatch_data_o = entries_q[i];
        end
      end
    end else begin
      for (int i = DEPTH - 1; i >= 0; i--) begin
        if (entries_q[i].busy && entries_q[i].src1.ready && entries_q[i].src2.ready) begin
          dispatch_valid_o = 1'b1;
          dispatch_idx     = i[$clog2(DEPTH)-1:0];
          dispatch_data_o  = entries_q[i];
        end
      end
    end
  end

  // Free-slot mask 
  logic [DEPTH-1:0] free_mask;
  always_comb begin
    for (int i = 0; i < DEPTH; i++) free_mask[i] = !entries_q[i].busy;
  end

  assign free_count_o = $countones(free_mask);


  // Free slot search
  logic [$clog2(DEPTH)-1:0] alloc0_idx, alloc1_idx;
  logic alloc0_found, alloc1_found;

  always_comb begin
    alloc0_found = 1'b0;
    alloc0_idx   = '0;
    for (int i = 0; i < DEPTH; i++) begin
      if (!alloc0_found && free_mask[i]) begin
        alloc0_found = 1'b1;
        alloc0_idx   = i[$clog2(DEPTH)-1:0];
      end
    end

    alloc1_found = 1'b0;
    alloc1_idx   = '0;
    for (int i = 0; i < DEPTH; i++) begin

      if (!alloc1_found &&  free_mask[i] &&
          !(alloc0_valid_i && alloc0_found && i[$clog2(DEPTH)-1:0] == alloc0_idx)) begin
        alloc1_found = 1'b1;
        alloc1_idx   = i[$clog2(DEPTH)-1:0];
      end
    end
  end


  // Next-state computation
  always_comb begin
    entries_next =  entries_q;

    // CDB snoop
    for (int i = 0; i < DEPTH; i++) begin
      if (entries_q[i].busy) begin
        if (!entries_q[i].src1.ready) begin
          if (cdb_a_i.valid && cdb_a_i.tag == entries_q[i].src1.tag) begin
            entries_next[i].src1.ready = 1'b1;
            entries_next[i].src1.val   =  cdb_a_i.value;
          end else if (cdb_b_i.valid && cdb_b_i.tag == entries_q[i].src1.tag) begin
            entries_next[i].src1.ready = 1'b1;
            entries_next[i].src1.val   = cdb_b_i.value;
          end else if (cdb_c_i.valid && cdb_c_i.tag == entries_q[i].src1.tag) begin
            entries_next[i].src1.ready  = 1'b1;
            entries_next[i].src1.val   = cdb_c_i.value;
          end
        end
        if (!entries_q[i].src2.ready) begin
          if (cdb_a_i.valid && cdb_a_i.tag == entries_q[i].src2.tag) begin
            entries_next[i].src2.ready = 1'b1;
            entries_next[i].src2.val  = cdb_a_i.value;
          end else if(cdb_b_i.valid && cdb_b_i.tag == entries_q[i].src2.tag) begin
            entries_next[i].src2.ready = 1'b1;
            entries_next[i].src2.val = cdb_b_i.value;
          end else if (cdb_c_i.valid && cdb_c_i.tag == entries_q[i].src2.tag) begin
            entries_next[i].src2.ready = 1'b1;
            entries_next[i].src2.val   = cdb_c_i.value;
          end
        end
      end
    end

    // dispatch ack
    if (dispatch_valid_o && dispatch_ack_i) begin
      entries_next[dispatch_idx].busy = 1'b0;
    end


    // allocation into free slots
    if (alloc0_valid_i) entries_next[alloc0_idx] = alloc0_data_i;
    if (alloc1_valid_i) entries_next[alloc1_idx] = alloc1_data_i;

    // flush
    if (flush_i) begin
      for (int i = 0; i < DEPTH; i++) entries_next[i].busy = 1'b0;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      for (int i = 0; i < DEPTH; i++) entries_q[i]  <= '0;
    end else begin
      entries_q <= entries_next;
    end
  end

endmodule

