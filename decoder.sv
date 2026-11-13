`timescale 1ns / 1ps
module decoder // same decoder as HWs before
  import riscv_pkg::*;
(
    input  logic [XLEN-1:0]  instr_i,
    input  logic [XLEN-1:0]  pc_i,
    input  logic [XLEN-1:0]  id_i,
    input  logic             valid_i,
    output dinstr_t          dinstr_o
);

    logic [6:0] opcode;
    logic [2:0] func3;
    logic [6:0] func7;

    assign dinstr_o.rd_idx  = instr_i[4:0];
    assign func3            = instr_i[7:5];
    assign dinstr_o.rs1_idx = instr_i[12:8];
    assign opcode           = instr_i[19:13];
    assign dinstr_o.rs2_idx = instr_i[24:20];
    assign func7            = instr_i[31:25];
    assign dinstr_o.pc      = pc_i;
    assign dinstr_o.id      = id_i;

    always_comb begin
        dinstr_o.valid     = 1'b0;
        dinstr_o.is_store  = 1'b0;
        dinstr_o.is_mem    = 1'b0;
        dinstr_o.is_jump   = 1'b0;
        dinstr_o.is_branch = 1'b0;
        dinstr_o.rd_used   = 1'b0;
        dinstr_o.rs1_used  = 1'b0;
        dinstr_o.rs2_used  = 1'b0;
        dinstr_o.imm_used  = 1'b0;
        dinstr_o.imm       = 32'b0;
        dinstr_o.op        = LUI;

        if (valid_i) begin
            case (opcode)
                7'b1110101: begin // LUI
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.op       = LUI;
                    dinstr_o.rd_used  = 1'b1;
                    dinstr_o.imm_used = 1'b1;
                    dinstr_o.imm      = {instr_i[31:20], instr_i[12:5], 12'b0};
                end
                7'b1110100: begin // AUIPC
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.op       = AUIPC;
                    dinstr_o.rd_used  = 1'b1;
                    dinstr_o.imm_used = 1'b1;
                    dinstr_o.imm      = {instr_i[31:20], instr_i[12:5], 12'b0};
                end
                7'b1101111: begin // JAL
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.op       = JAL;
                    dinstr_o.rd_used  = 1'b1;
                    dinstr_o.is_jump  = 1'b1;
                    dinstr_o.imm_used = 1'b1;
                    dinstr_o.imm      = {{12{instr_i[31]}}, instr_i[12:5], instr_i[20], instr_i[30:21], 1'b0};
                end
                7'b1100111: begin // JALR
                    if (func3 == 3'b000) begin
                        dinstr_o.valid    = 1'b1;
                        dinstr_o.op       = JALR;
                        dinstr_o.rd_used  = 1'b1;
                        dinstr_o.rs1_used = 1'b1;
                        dinstr_o.is_jump  = 1'b1;
                        dinstr_o.imm_used = 1'b1;
                        dinstr_o.imm      = {{20{instr_i[31]}}, instr_i[31:20]};
                    end
                end
                7'b1100011: begin // branch
                    dinstr_o.valid     = 1'b1;
                    dinstr_o.is_branch = 1'b1;
                    dinstr_o.rs1_used  = 1'b1;
                    dinstr_o.rs2_used  = 1'b1;
                    dinstr_o.imm_used  = 1'b1;
                    dinstr_o.imm       = {{20{instr_i[31]}}, instr_i[0], instr_i[30:25], instr_i[4:1], 1'b0};
                    case (func3)
                        3'b100:  dinstr_o.op = BEQ;
                        3'b101:  dinstr_o.op = BNE;
                        3'b000:  dinstr_o.op = BGEU;
                        3'b001:  dinstr_o.op = BLTU;
                        3'b010:  dinstr_o.op = BGE;
                        3'b011:  dinstr_o.op = BLT;
                        default: dinstr_o.valid = 1'b0;
                    endcase
                end
                7'b1100000: begin // load
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.is_mem   = 1'b1;
                    dinstr_o.rd_used  = 1'b1;
                    dinstr_o.rs1_used = 1'b1;
                    dinstr_o.imm_used = 1'b1;
                    dinstr_o.imm      = {{20{instr_i[31]}}, instr_i[31:20]};
                    case (func3)
                        3'b000:  dinstr_o.op = LBU;
                        3'b001:  dinstr_o.op = LHU;
                        3'b100:  dinstr_o.op = LB;
                        3'b101:  dinstr_o.op = LH;
                        3'b110:  dinstr_o.op = LW;
                        default: dinstr_o.valid = 1'b0;
                    endcase
                end
                7'b1100001: begin // store
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.is_mem   = 1'b1;
                    dinstr_o.is_store = 1'b1;
                    dinstr_o.rs1_used = 1'b1;
                    dinstr_o.rs2_used = 1'b1;
                    dinstr_o.imm_used = 1'b1;
                    dinstr_o.imm      = {{20{instr_i[31]}}, instr_i[31:25], instr_i[4:0]};
                    case (func3)
                        3'b000:  dinstr_o.op = SB;
                        3'b001:  dinstr_o.op = SH;
                        3'b010:  dinstr_o.op = SW;
                        default: dinstr_o.valid = 1'b0;
                    endcase
                end
                7'b1100100: begin // I type ALU
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.rd_used  = 1'b1;
                    dinstr_o.rs1_used = 1'b1;
                    dinstr_o.imm_used = 1'b1;
                    if (func3 == 3'b001 || func3 == 3'b101) begin
                        dinstr_o.imm = {27'b0, instr_i[24:20]};
                    end else begin
                        dinstr_o.imm = {{20{instr_i[31]}}, instr_i[31:20]};
                    end
                    case (func3)
                        3'b000:  dinstr_o.op = ADDI;
                        3'b010:  dinstr_o.op = SLTI;
                        3'b011:  dinstr_o.op = SLTIU;
                        3'b100:  dinstr_o.op = ORI;
                        3'b110:  dinstr_o.op = XORI;
                        3'b111:  dinstr_o.op = ANDI;
                        3'b001:  if (func7 == 7'b0000000) dinstr_o.op = SLLI;
                        3'b101:  if (func7 == 7'b0000000) dinstr_o.op = SRLI;
                                 else if (func7 == 7'b0000010) dinstr_o.op = SRAI;
                        default: dinstr_o.valid = 1'b0;
                    endcase
                end
                7'b1110001: begin // R type
                    dinstr_o.valid    = 1'b1;
                    dinstr_o.rd_used  = 1'b1;
                    dinstr_o.rs1_used = 1'b1;
                    dinstr_o.rs2_used = 1'b1;
                    case ({func7, func3})
                        {7'b0000000, 3'b000}: dinstr_o.op = ADD;
                        {7'b0000010, 3'b000}: dinstr_o.op = SUB;
                        {7'b0000000, 3'b001}: dinstr_o.op = SLL;
                        {7'b0000000, 3'b010}: dinstr_o.op = SLT;
                        {7'b0000000, 3'b011}: dinstr_o.op = SLTU;
                        {7'b0000000, 3'b100}: dinstr_o.op = XOR;
                        {7'b0000000, 3'b101}: dinstr_o.op = SRL;
                        {7'b0000010, 3'b101}: dinstr_o.op = SRA;
                        {7'b0000000, 3'b110}: dinstr_o.op = OR;
                        {7'b0000000, 3'b111}: dinstr_o.op = AND;
                        default:              dinstr_o.valid = 1'b0;
                    endcase
                end
                default: ; // unknown, valid = 0
            endcase
        end
    end

endmodule
