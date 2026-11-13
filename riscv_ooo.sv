`timescale 1 ns / 1 ps
module riscv_ooo
    import riscv_pkg::*;
#(
    parameter DMemInitFile = "dmem.mem",
    parameter IMemInitFile = "imem.mem"
) (
    input  logic clk_i,
    input  logic rstn_i,
    input  logic  [XLEN-1:0] addr_i,
    output logic  [XLEN-1:0] data_o,
    output dinstr_t        decode_o   [2],
    output execute_t       execute_o  [3],
    output commit_t        commit_o   [2]
);


  // Fetch
  logic [XLEN-1:0] pc0, instr0, pc1, instr1;
  logic rd_stall;

  // CDBs (Common Data Buses)
  cdb_t cdb_a, cdb_b;
  lsu_cdb_t cdb_c;


  // ROB
  logic                 rob_alloc0_valid, rob_alloc1_valid;
  rob_entry_t           rob_alloc0_data, rob_alloc1_data;
  logic [ROB_IDX_W-1:0] rob_alloc0_tag, rob_alloc1_tag, rob_head;
  logic [          3:0] rob_free_count;

  logic [ROB_IDX_W-1:0] rob_rd_tag[4];
  logic                 rob_rd_done[4];
  logic [   XLEN-1:0]   rob_rd_value[4];

  logic       rob_commit0_valid, rob_commit1_valid;
  rob_entry_t rob_commit0_data, rob_commit1_data;

  logic            rob_flush;
  logic [XLEN-1:0] rob_redirect_pc;



  // Issue-queue allocation/dispatch (0=A 1=B 2=C)
  logic [$clog2(IQ_DEPTH+1)-1:0] iq_free_count[3];
  logic                          iq_alloc0_valid[3];
  iq_entry_t                     iq_alloc0_data[3];
  logic                          iq_alloc1_valid[3];
  iq_entry_t                     iq_alloc1_data[3];

  logic      iq_a_dispatch_valid, iq_b_dispatch_valid, iq_c_dispatch_valid;
  iq_entry_t iq_a_dispatch_data, iq_b_dispatch_data, iq_c_dispatch_data;

  // Fetch
  fetch #(
      .IMemInitFile(IMemInitFile)

  ) fetch_i (
      .clk_i        (clk_i),
      .rstn_i       (rstn_i),
      .stall_i      (rd_stall),
      .flush_i      (rob_flush),
      .redirect_pc_i(rob_redirect_pc),
      .pc0_o        (pc0),
      .instr0_o     (instr0),
      .pc1_o        (pc1),
      .instr1_o     (instr1)
  );


  // Decode + rename + dispatch
  rename_dispatch rename_dispatch_i (
      .clk_i  (clk_i),
      .rstn_i (rstn_i),
      .flush_i(rob_flush),

      .pc0_i   (pc0),
      .instr0_i(instr0),
      .pc1_i   (pc1),
      .instr1_i(instr1),
      .stall_o (rd_stall),
      .decode_o(decode_o),

      .rob_alloc0_tag_i  (rob_alloc0_tag),
      .rob_alloc1_tag_i  (rob_alloc1_tag),
      .rob_head_i        (rob_head),
      .rob_free_count_i  (rob_free_count),
      .rob_alloc0_valid_o(rob_alloc0_valid),
      .rob_alloc0_data_o (rob_alloc0_data),
      .rob_alloc1_valid_o(rob_alloc1_valid),
      .rob_alloc1_data_o (rob_alloc1_data),

      .rob_rd_tag_o  (rob_rd_tag),
      .rob_rd_done_i (rob_rd_done),
      .rob_rd_value_i(rob_rd_value),

      .iq_free_count_i  (iq_free_count),
      .iq_alloc0_valid_o(iq_alloc0_valid),
      .iq_alloc0_data_o (iq_alloc0_data),
      .iq_alloc1_valid_o(iq_alloc1_valid),
      .iq_alloc1_data_o (iq_alloc1_data),


      .commit0_valid_i(rob_commit0_valid),
      .commit0_data_i (rob_commit0_data),
      .commit1_valid_i(rob_commit1_valid),
      .commit1_data_i (rob_commit1_data)
  );

  // Reorder buffer
  rob rob_i (
      .clk_i (clk_i),
      .rstn_i(rstn_i),

      .alloc0_valid_i(rob_alloc0_valid),
      .alloc0_data_i (rob_alloc0_data),
      .alloc1_valid_i(rob_alloc1_valid),
      .alloc1_data_i (rob_alloc1_data),
      .alloc0_tag_o  (rob_alloc0_tag),
      .alloc1_tag_o  (rob_alloc1_tag),
      .free_count_o  (rob_free_count),

      .cdb_a_i(cdb_a),
      .cdb_b_i(cdb_b),
      .cdb_c_i(cdb_c),
      .rd_tag_i  (rob_rd_tag),
      .rd_done_o (rob_rd_done),
      .rd_value_o(rob_rd_value),
      .commit0_valid_o(rob_commit0_valid),
      .commit0_data_o (rob_commit0_data),
      .commit1_valid_o(rob_commit1_valid),
      .commit1_data_o (rob_commit1_data),
      .flush_o      (rob_flush),
      .redirect_pc_o(rob_redirect_pc),

      .head_o(rob_head)
  );



  // Issue queues
  issue_queue #(
      .DEPTH  (IQ_DEPTH),
      .IS_IQ_C(1'b0)

  ) iq_a_i (
      .clk_i  (clk_i),
      .rstn_i (rstn_i),
      .flush_i(rob_flush),

      .alloc0_valid_i(iq_alloc0_valid[0]),
      .alloc0_data_i (iq_alloc0_data[0]),
      .alloc1_valid_i(iq_alloc1_valid[0]),
      .alloc1_data_i (iq_alloc1_data[0]),

      .cdb_a_i(cdb_a),
      .cdb_b_i(cdb_b),
      .cdb_c_i(cdb_c.cdb),
      .rob_head_i(rob_head),
      .dispatch_ack_i  (1'b1),
      .dispatch_valid_o(iq_a_dispatch_valid),
      .dispatch_data_o (iq_a_dispatch_data),

      .free_count_o(iq_free_count[0])
  );

  issue_queue #(
      .DEPTH  (IQ_DEPTH),
      .IS_IQ_C(1'b0)

  ) iq_b_i (
      .clk_i  (clk_i),
      .rstn_i (rstn_i),
      .flush_i(rob_flush),

      .alloc0_valid_i(iq_alloc0_valid[1]),
      .alloc0_data_i (iq_alloc0_data[1]),
      .alloc1_valid_i(iq_alloc1_valid[1]),
      .alloc1_data_i (iq_alloc1_data[1]),
      .cdb_a_i(cdb_a),
      .cdb_b_i(cdb_b),
      .cdb_c_i(cdb_c.cdb),

      .rob_head_i(rob_head),

      .dispatch_ack_i  (1'b1),
      .dispatch_valid_o(iq_b_dispatch_valid),
      .dispatch_data_o (iq_b_dispatch_data),

      .free_count_o(iq_free_count[1])
  );


  issue_queue #(
      .DEPTH  (IQ_DEPTH),
      .IS_IQ_C(1'b1)

  ) iq_c_i (
      .clk_i  (clk_i),
      .rstn_i (rstn_i),
      .flush_i(rob_flush),

      .alloc0_valid_i(iq_alloc0_valid[2]),
      .alloc0_data_i (iq_alloc0_data[2]),
      .alloc1_valid_i(iq_alloc1_valid[2]),
      .alloc1_data_i (iq_alloc1_data[2]),

      .cdb_a_i(cdb_a),
      .cdb_b_i(cdb_b),
      .cdb_c_i(cdb_c.cdb),

      .rob_head_i(rob_head),

      .dispatch_ack_i  (1'b1),
      .dispatch_valid_o(iq_c_dispatch_valid),
      .dispatch_data_o (iq_c_dispatch_data),

      .free_count_o(iq_free_count[2])
  );

  // Execution units
  alu_branch_unit alu_branch_unit_i (
      .dispatch_valid_i(iq_a_dispatch_valid),
      .dispatch_data_i (iq_a_dispatch_data),
      .cdb_o           (cdb_a),
      .execute_o       (execute_o[0])
  );


  alu_unit alu_unit_i (
      .dispatch_valid_i(iq_b_dispatch_valid),
      .dispatch_data_i (iq_b_dispatch_data),
      .cdb_o           (cdb_b),
      .execute_o       (execute_o[1])
  );


  lsu #(
      .DMemInitFile(DMemInitFile)
  ) lsu_i (
      .clk_i  (clk_i),
      .rstn_i (rstn_i),
      .flush_i(rob_flush),
      .dispatch_valid_i(iq_c_dispatch_valid),
      .dispatch_data_i (iq_c_dispatch_data),
      .cdb_o    (cdb_c),
      .execute_o(execute_o[2]),
      .addr_i(addr_i),
      .data_o(data_o)
  );

  // Commit (in-order, 2-wide)

  localparam logic [XLEN-1:0] CommitPcLo = 32'h8000_0000;
  localparam logic [XLEN-1:0] CommitPcHi = 32'h8000_2000;

  always_comb begin
    commit_o[0].valid    = rob_commit0_valid &&
                            (rob_commit0_data.dinstr.pc >= CommitPcLo) &&
                            (rob_commit0_data.dinstr.pc <  CommitPcHi);
    commit_o[0].pc       = rob_commit0_data.dinstr.pc;
    commit_o[0].instr    = rob_commit0_data.instr;
    commit_o[0].reg_addr = rob_commit0_data.dinstr.rd_used ? rob_commit0_data.dinstr.rd_idx : 5'b0;
    commit_o[0].reg_data = rob_commit0_data.dinstr.rd_used ? rob_commit0_data.value : '0;
    commit_o[0].mem_addr = rob_commit0_data.mem_addr;
    commit_o[0].mem_data = rob_commit0_data.mem_data;
    commit_o[0].mem_wrt  = rob_commit0_data.dinstr.is_store;
    commit_o[0].id       = rob_commit0_data.dinstr.id;

    commit_o[1].valid    = rob_commit1_valid &&
                            (rob_commit1_data.dinstr.pc >= CommitPcLo) &&
                            (rob_commit1_data.dinstr.pc <  CommitPcHi);
    commit_o[1].pc       = rob_commit1_data.dinstr.pc;
    commit_o[1].instr    = rob_commit1_data.instr;
    commit_o[1].reg_addr = rob_commit1_data.dinstr.rd_used ? rob_commit1_data.dinstr.rd_idx : 5'b0;
    commit_o[1].reg_data = rob_commit1_data.dinstr.rd_used ? rob_commit1_data.value : '0;
    commit_o[1].mem_addr = rob_commit1_data.mem_addr;
    commit_o[1].mem_data = rob_commit1_data.mem_data;
    commit_o[1].mem_wrt  = rob_commit1_data.dinstr.is_store;
    commit_o[1].id       = rob_commit1_data.dinstr.id;
  end



endmodule
