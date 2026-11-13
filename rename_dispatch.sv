`timescale 1ns / 1ps
module rename_dispatch
  import riscv_pkg::*;
(
    input  logic clk_i,
    input  logic rstn_i,
    input  logic flush_i,

    // fetch
    input  logic [XLEN-1:0] pc0_i,
    input  logic [XLEN-1:0] instr0_i,
    input  logic [XLEN-1:0] pc1_i,
    input  logic [XLEN-1:0] instr1_i,

    output logic stall_o, 
    output dinstr_t decode_o[2],

    // ROB allocation
    input  logic [ROB_IDX_W-1:0] rob_alloc0_tag_i,
    input  logic [ROB_IDX_W-1:0] rob_alloc1_tag_i,
    input  logic [ROB_IDX_W-1:0] rob_head_i,
    input  logic [3:0]       rob_free_count_i,
    output logic             rob_alloc0_valid_o,
    output rob_entry_t      rob_alloc0_data_o,
    output logic              rob_alloc1_valid_o,
    output rob_entry_t         rob_alloc1_data_o,

    // ROB-as-PRF read ports
    output logic [ROB_IDX_W-1:0] rob_rd_tag_o  [4],
    input  logic              rob_rd_done_i [4] ,
    input  logic [XLEN-1:0]    rob_rd_value_i[4],

    // issue-queue allocation
    input  logic [$clog2(IQ_DEPTH+1)-1:0] iq_free_count_i [3],
    output logic                          iq_alloc0_valid_o[3],
    output iq_entry_t                    iq_alloc0_data_o [3],
    output logic                          iq_alloc1_valid_o[3],
    output iq_entry_t                    iq_alloc1_data_o [3],

    // commit
    input  logic       commit0_valid_i,
    input  rob_entry_t commit0_data_i,
    input  logic       commit1_valid_i,
    input  rob_entry_t commit1_data_i
);


  // decode
  dinstr_t dinstr0_raw, dinstr1_raw;

  decoder decoder0_i (
      .instr_i (instr0_i),
      .pc_i (pc0_i),
      .id_i (32'd0),
      .valid_i (1'b1),
      .dinstr_o(dinstr0_raw)
  );

  decoder decoder1_i (
      .instr_i (instr1_i),
      .pc_i (pc1_i),
      .id_i (32'd0),
      .valid_i (1'b1),
      .dinstr_o(dinstr1_raw)
  );

  // Rename table and ARF
  rnt_entry_t rnt_rs1_0, rnt_rs2_0, rnt_rs1_1, rnt_rs2_1;
  logic [XLEN-1:0] arf_rs1_0, arf_rs2_0, arf_rs1_1, arf_rs2_1;

  logic wr0_en, wr1_en;

  rename_table rename_table_i (
      .clk_i  (clk_i),
      .rstn_i (rstn_i),
      .flush_i(flush_i),

      .rs1_idx0_i(dinstr0_raw.rs1_idx),
      .rs2_idx0_i(dinstr0_raw.rs2_idx),
      .rs1_idx1_i(dinstr1_raw.rs1_idx),
      .rs2_idx1_i(dinstr1_raw.rs2_idx),
      .rs1_0_o   (rnt_rs1_0),
      .rs2_0_o   (rnt_rs2_0),
      .rs1_1_o   (rnt_rs1_1),
      .rs2_1_o   (rnt_rs2_1),
      

      .commit0_valid_i  (commit0_valid_i),
      .commit0_rd_used_i(commit0_data_i.dinstr.rd_used),
      .commit0_rd_idx_i (commit0_data_i.dinstr.rd_idx),
      .commit0_tag_i    (rob_head_i),
      .commit1_valid_i  (commit1_valid_i),
      .commit1_rd_used_i(commit1_data_i.dinstr.rd_used),
      .commit1_rd_idx_i (commit1_data_i.dinstr.rd_idx),
      .commit1_tag_i    (rob_head_i + 3'd1),
      .wr0_en_i    (wr0_en),
      .wr0_rd_idx_i(dinstr0_raw.rd_idx),
      .wr0_tag_i   (rob_alloc0_tag_i),
      .wr1_en_i    (wr1_en),
      .wr1_rd_idx_i(dinstr1_raw.rd_idx),
      .wr1_tag_i   (rob_alloc1_tag_i)

  );

  regfile_arf regfile_arf_i (
      .clk_i (clk_i),
      .rstn_i(rstn_i),

      .rs1_idx0_i (dinstr0_raw.rs1_idx),
      .rs2_idx0_i (dinstr0_raw.rs2_idx),
      .rs1_idx1_i (dinstr1_raw.rs1_idx),
      .rs2_idx1_i (dinstr1_raw.rs2_idx),
      .rs1_data0_o(arf_rs1_0),
      .rs2_data0_o(arf_rs2_0),
      .rs1_data1_o(arf_rs1_1),
      .rs2_data1_o(arf_rs2_1),
      .we0_i  (commit0_valid_i && commit0_data_i.dinstr.rd_used),
      .waddr0_i(commit0_data_i.dinstr.rd_idx),
      .wdata0_i(commit0_data_i.value),
      .we1_i  (commit1_valid_i && commit1_data_i.dinstr.rd_used),
      .waddr1_i(commit1_data_i.dinstr.rd_idx),
      .wdata1_i(commit1_data_i.value));

  // Issue-queue route
  typedef enum logic [1:0] {
    ROUTE_A,
    ROUTE_B,
    ROUTE_C
  } route_e;

  // function of route: koads/store: C, branches/jumps: A everything els: B if it has room, if no: A
  function automatic route_e route_slot(dinstr_t d,logic [$clog2(IQ_DEPTH+1)-1:0] b_free_remaining);
    if (d.is_mem) return ROUTE_C;
    if (d.is_branch || d.is_jump) return ROUTE_A;
    if (b_free_remaining > 0) return ROUTE_B;
    return ROUTE_A;
  endfunction

  route_e route0, route1;

  assign route0 = route_slot(dinstr0_raw, iq_free_count_i[1]);
  assign route1 = route_slot(
      dinstr1_raw,
      iq_free_count_i[1] - ((dinstr0_raw.valid && route0 == ROUTE_B) ? 3'd1 : 3'd0)
  );

  // Resource check
  logic [1:0] rob_need, a_need, b_need, c_need;

  assign rob_need = {1'b0, dinstr0_raw.valid} + {1'b0, dinstr1_raw.valid};

  always_comb begin
    a_need = 2'd0;
    b_need = 2'd0;
    c_need = 2'd0;

    if (dinstr0_raw.valid) begin
      case (route0)
        ROUTE_A: a_need = a_need + 2'd1;
        ROUTE_B: b_need = b_need + 2'd1;
        ROUTE_C: c_need = c_need + 2'd1;
        default: ;
      endcase
    end

    if (dinstr1_raw.valid) begin

      case (route1)
        ROUTE_A: a_need = a_need + 2'd1;
        ROUTE_B: b_need = b_need + 2'd1;
        ROUTE_C: c_need = c_need + 2'd1;
        default: ;
      endcase
    end
  end

  logic resources_ok;
  assign resources_ok = (rob_free_count_i  >= {2'b0, rob_need}) &&
                         (iq_free_count_i[0] >= {1'b0, a_need}) &&
                         (iq_free_count_i[1] >= {1'b0, b_need}) &&
                         (iq_free_count_i[2] >= {1'b0, c_need});

  logic alloc0_en, alloc1_en;
  logic alloc0_en_f, alloc1_en_f;

  assign alloc0_en  = dinstr0_raw.valid && resources_ok;
  assign alloc1_en  = dinstr1_raw.valid && resources_ok;
  assign alloc0_en_f = alloc0_en && !flush_i;
  assign alloc1_en_f = alloc1_en && !flush_i;

  assign stall_o = (dinstr0_raw.valid || dinstr1_raw.valid) && !resources_ok;

  // id counter: only increment when something actually allocates.

  logic [31:0] id_ctr_q;

  always_ff @(posedge clk_i) begin
    if (!rstn_i) id_ctr_q <= 32'd1;
    else id_ctr_q <= id_ctr_q + 32'(alloc0_en_f) + 32'(alloc1_en_f);
  end

  dinstr_t dinstr0, dinstr1;
  always_comb begin
    dinstr0     = dinstr0_raw;
    dinstr0.id  = id_ctr_q;
    dinstr1     = dinstr1_raw;
    dinstr1.id  = id_ctr_q + 32'(alloc0_en_f);
  end


  // function of source operand resolving
  function automatic src_operand_t resolve_src(logic [4:0] reg_idx, logic used,
                                                 rnt_entry_t rnt, logic rob_done,
                                                 logic [XLEN-1:0] rob_val,
                                                 logic [XLEN-1:0] arf_val, logic fwd_valid,
                                                 logic [ROB_IDX_W-1:0] fwd_tag);
    src_operand_t r;
    if (!used || reg_idx == 5'd0) begin
      r = '{ready: 1'b1, val: (reg_idx == 5'd0) ? '0 : arf_val, tag: '0};
    end else if (fwd_valid) begin
      r = '{ready: 1'b0, val: '0, tag: fwd_tag};
    end else if (!rnt.pending) begin
      r = '{ready: 1'b1, val: arf_val, tag: '0};
    end else if (rob_done) begin
      r = '{ready: 1'b1, val: rob_val, tag: '0};
    end else begin
      r = '{ready: 1'b0, val: '0, tag: rnt.tag};
    end
    return r;
  endfunction

  logic fwd1_rs1, fwd1_rs2;
  assign fwd1_rs1 = alloc0_en_f && dinstr0_raw.rd_used && (dinstr1_raw.rs1_idx == dinstr0_raw.rd_idx);
  assign fwd1_rs2 = alloc0_en_f && dinstr0_raw.rd_used && (dinstr1_raw.rs2_idx == dinstr0_raw.rd_idx);

  assign rob_rd_tag_o[0] = rnt_rs1_0.tag;
  assign rob_rd_tag_o[1] = rnt_rs2_0.tag;
  assign rob_rd_tag_o[2] = rnt_rs1_1.tag;
  assign rob_rd_tag_o[3] = rnt_rs2_1.tag;

  src_operand_t src1_0, src2_0, src1_1, src2_1;

  assign src1_0 = resolve_src(dinstr0_raw.rs1_idx, dinstr0_raw.rs1_used, rnt_rs1_0,
                               rob_rd_done_i[0], rob_rd_value_i[0], arf_rs1_0, 1'b0, '0);
  assign src2_0 = resolve_src(dinstr0_raw.rs2_idx, dinstr0_raw.rs2_used, rnt_rs2_0,
                               rob_rd_done_i[1], rob_rd_value_i[1], arf_rs2_0, 1'b0, '0);
  assign src1_1 = resolve_src(dinstr1_raw.rs1_idx, dinstr1_raw.rs1_used, rnt_rs1_1,
                               rob_rd_done_i[2], rob_rd_value_i[2], arf_rs1_1, fwd1_rs1,
                               rob_alloc0_tag_i);
  assign src2_1 = resolve_src(dinstr1_raw.rs2_idx, dinstr1_raw.rs2_used, rnt_rs2_1,
                               rob_rd_done_i[3], rob_rd_value_i[3], arf_rs2_1, fwd1_rs2,
                               rob_alloc0_tag_i);

  // ROB allocation data
  rob_entry_t rob_alloc0_data, rob_alloc1_data;

  always_comb begin
    rob_alloc0_data         = '0;
    rob_alloc0_data.busy    = 1'b1;
    rob_alloc0_data.done    = 1'b0;
    rob_alloc0_data.dinstr  = dinstr0;
    rob_alloc0_data.instr   =  instr0_i;

    rob_alloc1_data         = '0;
    rob_alloc1_data.busy    = 1'b1;
    rob_alloc1_data.done   = 1'b0;
    rob_alloc1_data.dinstr  = dinstr1;
    rob_alloc1_data.instr   = instr1_i;
  end

  assign rob_alloc0_valid_o = alloc0_en_f;
  assign rob_alloc0_data_o  = rob_alloc0_data;
  assign rob_alloc1_valid_o =  alloc1_en_f;
  assign rob_alloc1_data_o  = rob_alloc1_data;

  // Issue-queue allocation data
  iq_entry_t iq_data0, iq_data1;

  always_comb begin
    iq_data0        = '0;
    iq_data0.busy   = 1'b1;
    iq_data0.rob_tag  = rob_alloc0_tag_i;
    iq_data0.dinstr   = dinstr0;
    iq_data0.src1     = src1_0;
    iq_data0.src2     = src2_0;

    iq_data1         = '0;
    iq_data1.busy    = 1'b1;
    iq_data1.rob_tag  = rob_alloc1_tag_i;
    iq_data1.dinstr   = dinstr1;
    iq_data1.src1     = src1_1;
    iq_data1.src2     = src2_1;
  end

  always_comb begin
    for (int x = 0; x < 3; x++) begin
      iq_alloc0_valid_o[x] = alloc0_en_f && (route0 == route_e'(x));
      iq_alloc0_data_o[x]  = iq_data0;
      iq_alloc1_valid_o[x] = alloc1_en_f && (route1 == route_e'(x));
      iq_alloc1_data_o[x]  = iq_data1;
    end
  end


  // Rename-table writes
  assign wr0_en = alloc0_en_f && dinstr0.rd_used && (dinstr0.rd_idx != 5'd0);
  assign wr1_en = alloc1_en_f && dinstr1.rd_used && (dinstr1.rd_idx != 5'd0);

  // decode_o, force valid=0 on flush, since the decoders are
  // combinational on the fetch PCs.
  always_comb begin
    decode_o[0]    = dinstr0;
    decode_o[0].valid = alloc0_en_f;
    decode_o[1]    = dinstr1;
    decode_o[1].valid = alloc1_en_f;
  end


endmodule
