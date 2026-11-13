`timescale 1ns / 1ps
// Execution unit A: ALU + branch/jump + redirect computation
module alu_branch_unit
  import riscv_pkg::*;
(   input  logic       dispatch_valid_i,
    input  iq_entry_t  dispatch_data_i,
    output cdb_t       cdb_o,
    output execute_t   execute_o
);

  dinstr_t dinstr;
  assign dinstr = dispatch_data_i.dinstr;

  logic [XLEN-1:0] op_a, op_b, alu_result;
  assign op_a = (dinstr.op == AUIPC) ? dinstr.pc : dispatch_data_i.src1.val;
  assign op_b = (dinstr.imm_used && !dinstr.is_branch) ? dinstr.imm : dispatch_data_i.src2.val;

  // ALU
  always_comb begin
    alu_result = '0;
    case (dinstr.op)
      ADD, ADDI, LBU, LHU, LB, LH, LW, SB, SH, SW, AUIPC, JALR: alu_result = op_a + op_b;
      SUB: alu_result = op_a - op_b;
      SLL, SLLI: alu_result = op_a << op_b[4:0];
      SRL, SRLI: alu_result = op_a >> op_b[4:0];
      SRA, SRAI: alu_result = $signed(op_a) >>> op_b[4:0];
      XOR, XORI: alu_result = op_a ^ op_b;
      OR, ORI: alu_result = op_a | op_b;
      AND, ANDI: alu_result = op_a & op_b;
      SLT, SLTI: alu_result = {31'b0, ($signed(op_a) < $signed(op_b))};
      SLTU, SLTIU: alu_result = {31'b0, (op_a < op_b)};
      LUI: alu_result = op_b;
      default: alu_result = '0;
    endcase
  end

  // branch comparator
  logic branch_taken;
  always_comb begin
    branch_taken = 1'b0;
    if (dinstr.is_branch) begin
      case (dinstr.op)
        BEQ: branch_taken = (dispatch_data_i.src1.val == dispatch_data_i.src2.val);
        BNE: branch_taken = (dispatch_data_i.src1.val != dispatch_data_i.src2.val);
        BLT: branch_taken = ($signed(dispatch_data_i.src1.val) <  $signed(dispatch_data_i.src2.val));
        BGE: branch_taken = ($signed(dispatch_data_i.src1.val) >= $signed(dispatch_data_i.src2.val));
        BLTU: branch_taken = (dispatch_data_i.src1.val <  dispatch_data_i.src2.val);
        BGEU: branch_taken = (dispatch_data_i.src1.val >= dispatch_data_i.src2.val);
        default: branch_taken = 1'b0;
      endcase
    end
  end
  logic            redirect;
  logic [XLEN-1:0] redirect_pc;
  assign redirect  = dinstr.is_jump || (dinstr.is_branch && branch_taken);
  assign redirect_pc = (dinstr.op == JALR) ? {alu_result[31:1], 1'b0} : (dinstr.pc + dinstr.imm);

  // CDB: JAL/JALR write back the link address (pc+4), not the ALU adder result
  assign cdb_o.valid      = dispatch_valid_i;
  assign cdb_o.tag         = dispatch_data_i.rob_tag;
  assign cdb_o.value     = (dinstr.op == JAL || dinstr.op == JALR) ? (dinstr.pc + 32'd4) : alu_result;
  assign cdb_o.redirect = dispatch_valid_i && redirect;
  assign cdb_o.redirect_pc = redirect_pc;

  assign execute_o.valid = dispatch_valid_i;
  assign execute_o.id    = dinstr.id;


endmodule
