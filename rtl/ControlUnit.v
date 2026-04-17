`timescale 1ns / 1ps

`include "ctrl_signal_def.v"
`include "instruction_def.v"

// 流水线用纯组合译码：端口与多周期版一致；clk/rst/zero 不参与 FSM（由顶层处理冒险与 PC）。
module ControlUnit(
    input rst,
    input clk,
    input zero,
    input [6:0] opcode,
    input [6:0] Funct7,
    input [2:0] Funct3,
    output reg PCWrite,
    output reg InsMemRW,
    output reg IRWrite,
    output reg RFWrite,
    output reg DMCtrl,
    output reg ExtSel,
    output reg ALUSrcA,
    output reg [1:0] ALUSrcB,
    output reg [1:0] RegSel,
    output reg [1:0] NPCOp,
    output reg [1:0] WDSel,
    output reg [3:0] ALUOp
);

    wire [9:0] funct_r = {Funct7, Funct3};

    always @(*) begin
        PCWrite   = 1'b0;
        InsMemRW  = 1'b1;
        IRWrite   = 1'b1;
        RFWrite   = 1'b0;
        DMCtrl    = `DMCtrl_RD;
        ExtSel    = `ExtSel_SIGNED;
        ALUSrcA   = `ALUSrcA_A;
        ALUSrcB   = `ALUSrcB_B;
        RegSel    = `RegSel_rd;
        NPCOp     = `NPC_PC;
        WDSel     = `WDSel_FromALU;
        ALUOp     = `ALUOp_ADD;

        case (opcode)
            `INSTR_RTYPE_OP: begin
                RFWrite = 1'b1;
                ALUSrcB = `ALUSrcB_B;
                case (funct_r)
                    `INSTR_ADD_FUNCT: ALUOp = `ALUOp_ADD;
                    `INSTR_SUB_FUNCT: ALUOp = `ALUOp_SUB;
                    `INSTR_AND_FUNCT: ALUOp = `ALUOp_AND;
                    `INSTR_OR_FUNCT:  ALUOp = `ALUOp_OR;
                    `INSTR_XOR_FUNCT: ALUOp = `ALUOp_XOR;
                    `INSTR_SLL_FUNCT: ALUOp = `ALUOp_SLL;
                    `INSTR_SRL_FUNCT: ALUOp = `ALUOp_SRL;
                    `INSTR_SRA_FUNCT: ALUOp = `ALUOp_SRA;
                    default:          ALUOp = `ALUOp_ADD;
                endcase
            end
            `INSTR_ITYPE_OP: begin
                RFWrite = 1'b1;
                ALUSrcB = `ALUSrcB_Imm;
                if (Funct3 == `INSTR_ADDI_FUNCT) begin
                    ExtSel = `ExtSel_SIGNED;
                    ALUOp  = `ALUOp_ADD;
                end else if (Funct3 == `INSTR_ORI_FUNCT) begin
                    ExtSel = `ExtSel_ZERO;
                    ALUOp  = `ALUOp_OR;
                end else begin
                    ExtSel = `ExtSel_SIGNED;
                    ALUOp  = `ALUOp_ADD;
                end
            end
            `INSTR_LW_OP: begin
                RFWrite = 1'b1;
                ALUSrcB = `ALUSrcB_Imm;
                ExtSel  = `ExtSel_SIGNED;
                ALUOp   = `ALUOp_ADD;
                WDSel   = `WDSel_FromMEM;
            end
            `INSTR_SW_OP: begin
                RFWrite = 1'b0;
                DMCtrl  = `DMCtrl_WR;
                ALUSrcB = `ALUSrcB_Imm;
                ExtSel  = `ExtSel_SIGNED;
                ALUOp   = `ALUOp_ADD;
            end
            `INSTR_BTYPE_OP: begin
                RFWrite = 1'b0;
                ALUSrcB = `ALUSrcB_B;
                ALUOp   = `ALUOp_SUB;
                NPCOp   = `NPC_Offset12;
            end
            `INSTR_JAL_OP: begin
                RFWrite = 1'b1;
                WDSel   = `WDSel_FromPC;
                NPCOp   = `NPC_Offset20;
            end
            `INSTR_JALR_OP: begin
                RFWrite = 1'b1;
                ALUSrcB = `ALUSrcB_Imm;
                ExtSel  = `ExtSel_SIGNED;
                ALUOp   = `ALUOp_ADD;
                WDSel   = `WDSel_FromPC;
                NPCOp   = `NPC_rs;
            end
            default: ;
        endcase
    end

endmodule
