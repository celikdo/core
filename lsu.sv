`timescale 1ns / 1ps
// Execution unit C: load/store unit
module lsu
  import riscv_pkg::*;
#(
    parameter DMemInitFile = "dmem.mem"
) (
    input  logic clk_i,
    input  logic rstn_i,
    input  logic flush_i,
    input  logic dispatch_valid_i,
    input  iq_entry_t dispatch_data_i,
    input  logic [XLEN-1:0] addr_i,

    output lsu_cdb_t  cdb_o,
    output execute_t  execute_o,
    output logic [XLEN-1:0] data_o
);

  logic [XLEN-1:0] data_mem[0:2047];
  initial begin
    $readmemh(DMemInitFile, data_mem, 0, 2047);
  end

  // clk t: dispatch, compute address, latch for clk t+1
  typedef struct packed {
    logic                 valid;
    logic [ROB_IDX_W-1:0] rob_tag;
    logic                 is_store;
    logic [XLEN-1:0]      addr;
    logic [XLEN-1:0]      store_data;
    operation_e          op;
    logic [31:0]         id;
  } lsu_latch_t;

  logic [XLEN-1:0] addr;
  assign addr = dispatch_data_i.src1.val + dispatch_data_i.dinstr.imm;

  lsu_latch_t latch_q;


  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      latch_q <= '0;
    end else begin
      latch_q.valid      <= dispatch_valid_i && !flush_i;
      latch_q.rob_tag    <= dispatch_data_i.rob_tag;
      latch_q.is_store   <= dispatch_data_i.dinstr.is_store;
      latch_q.addr       <= addr;
      latch_q.store_data<= dispatch_data_i.src2.val;
      latch_q.op        <= dispatch_data_i.dinstr.op;
      latch_q.id        <= dispatch_data_i.dinstr.id;
    end
  end


  // clk t+1: memory access from latch
  logic [XLEN-1:0] raw_word;
  assign raw_word = data_mem[latch_q.addr[12:2]];

  logic [XLEN-1:0] load_data;
  always_comb begin
    load_data = raw_word;
    case (latch_q.op)
      LH:  load_data = latch_q.addr[1] ? {{16{raw_word[31]}}, raw_word[31:16]} : {{16{raw_word[15]}}, raw_word[15:0]};
      LHU: load_data = latch_q.addr[1] ? {16'b0, raw_word[31:16]}: {16'b0, raw_word[15:0]};
      LB: begin
        case (latch_q.addr[1:0])
          2'b00: load_data = {{24{raw_word[7]}},  raw_word[7:0]};
          2'b01: load_data = {{24{raw_word[15]}}, raw_word[15:8]};
          2'b10: load_data = {{24{raw_word[23]}}, raw_word[23:16]};
          2'b11: load_data = {{24{raw_word[31]}}, raw_word[31:24]};
        endcase
      end
      LBU: begin
        case (latch_q.addr[1:0])
          2'b00: load_data = {24'b0, raw_word[7:0]};
          2'b01: load_data = {24'b0, raw_word[15:8]};
          2'b10: load_data = {24'b0, raw_word[23:16]};
          2'b11: load_data = {24'b0, raw_word[31:24]};
        endcase
      end
      default: load_data = raw_word;  // LW
    endcase
  end


  assign cdb_o.cdb.valid       = latch_q.valid;
  assign cdb_o.cdb.tag         = latch_q.rob_tag;
  assign cdb_o.cdb.value     = load_data;
  assign cdb_o.cdb.redirect    = 1'b0;
  assign cdb_o.cdb.redirect_pc = '0;
  assign cdb_o.mem_addr        = latch_q.addr;
  assign cdb_o.mem_data       = latch_q.is_store ? latch_q.store_data : load_data;

  assign execute_o.valid = latch_q.valid;
  assign execute_o.id = latch_q.id;

  // store write
  always_ff @(posedge clk_i) begin
    if (latch_q.valid && latch_q.is_store) begin
      case (latch_q.op)
        SW: data_mem[latch_q.addr[12:2]] <= latch_q.store_data;
        SH: begin
          if (latch_q.addr[1]) data_mem[latch_q.addr[12:2]][31:16] <= latch_q.store_data[15:0];
          else                 data_mem[latch_q.addr[12:2]][15:0]  <= latch_q.store_data[15:0];
        end
        SB: begin
          case (latch_q.addr[1:0])
            2'b00: data_mem[latch_q.addr[12:2]][7:0]    <= latch_q.store_data[7:0];
            2'b01: data_mem[latch_q.addr[12:2]][15:8]  <= latch_q.store_data[7:0];
            2'b10: data_mem[latch_q.addr[12:2]][23:16] <= latch_q.store_data[7:0];
            2'b11: data_mem[latch_q.addr[12:2]][31:24] <= latch_q.store_data[7:0];
          endcase
        end
      endcase
    end
  end
  assign data_o = data_mem[addr_i[12:2]];


endmodule
