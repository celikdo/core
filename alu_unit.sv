`timescale 1ns / 1ps
// Execution unit B: ALU only
module alu_unit
  import riscv_pkg::*;
(
    input  logic       dispatch_valid_i,
    input  iq_entry_t  dispatch_data_i,
    output cdb_t       cdb_o,
    output execute_t   execute_o
);

  dinstr_t dinstr;
  assign dinstr = dispatch_data_i.dinstr;

  logic [XLEN-1:0] op_a, op_b, alu_result;


  assign op_a = (dinstr.op == AUIPC) ? dinstr.pc : dispatch_data_i.src1.val;
  assign op_b = dinstr.imm_used ? dinstr.imm : dispatch_data_i.src2.val;


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

  assign cdb_o.valid      = dispatch_valid_i;
  assign cdb_o.tag        = dispatch_data_i.rob_tag;
  assign cdb_o.value    =   alu_result;
  assign cdb_o.redirect   = 1'b0;
  assign cdb_o.redirect_pc = '0;
  assign execute_o.valid = dispatch_valid_i;
  assign execute_o.id    = dinstr.id;

endmodule
