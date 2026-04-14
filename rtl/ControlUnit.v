`timescale 1ns / 1ps


`include "ctrl_signal_def.v"
`include "instruction_def.v"
module ControlUnit(
    input rst,                      //
    input clk,                      //
    input zero,                     //
    input [6:0] opcode,             //
    input [6:0] Funct7,             //
    input [2:0] Funct3,             //
    output reg PCWrite,             //
    output reg InsMemRW,            //
    output reg IRWrite,             //
    output reg RFWrite,             //
    output reg DMCtrl,              //
    output reg ExtSel,              //
    output reg ALUSrcA,             //
    output reg [1:0] ALUSrcB,       //
    output reg [1:0] RegSel,        //
    output reg [1:0] NPCOp,         //
    output reg [1:0] WDSel,         //
    output reg [3:0] ALUOp          //
);

    // 状态定义
    localparam S_IF  = 3'd0;  // Instruction Fetch
    localparam S_ID  = 3'd1;  // Instruction Decode
    localparam S_EX  = 3'd2;  // Execute
    localparam S_MEM = 3'd3;  // Memory Access
    localparam S_WB  = 3'd4;  // Write Back

    reg [2:0] state, next_state;

    // 状态转移（时序逻辑）
    always @(posedge clk or posedge rst) begin
        if (rst)
            state <= S_IF;
        else
            state <= next_state;
    end

    // 次态逻辑
    always @(*) begin
        case (state)
            S_IF:  next_state = S_ID;
            S_ID:  next_state = S_EX;
            S_EX:  begin
                case (opcode)
                    `INSTR_LW_OP: next_state = S_MEM;
                    `INSTR_SW_OP: next_state = S_MEM;
                    default:      next_state = S_IF;  // R/I/B/J 指令直接回 IF
                endcase
            end
            S_MEM: next_state = (opcode == `INSTR_LW_OP) ? S_WB : S_IF;
            S_WB:  next_state = S_IF;
            default: next_state = S_IF;
        endcase
    end

    // 控制信号生成（组合逻辑）
    always @(*) begin
        // 默认值（所有信号关闭）
        PCWrite  = 0;
        InsMemRW = 0;
        IRWrite  = 0;
        RFWrite  = 0;
        DMCtrl   = 0;
        ExtSel   = `ExtSel_SIGNED;
        ALUSrcA  = `ALUSrcA_A;
        ALUSrcB  = `ALUSrcB_B;
        RegSel   = `RegSel_rd;
        NPCOp    = `NPC_PC;
        WDSel    = `WDSel_FromALU;
        ALUOp    = `ALUOp_ADD;

        case (state)
            S_IF: begin
                // 取指：IM 读指令，IR 锁存，PC 更新
                InsMemRW = 1;
                IRWrite  = 1;
                PCWrite  = 1;
                NPCOp    = `NPC_PC;  // PC+4
            end

            S_ID: begin
                // 译码：读寄存器，准备操作数（RF 异步读，无需控制信号）
                // 对于 JAL，可以在此阶段直接跳转
                if (opcode == `INSTR_JAL_OP) begin
                    PCWrite  = 1;
                    NPCOp    = `NPC_Offset20;
                    RFWrite  = 1;
                    RegSel   = `RegSel_31;  // rd = x31
                    WDSel    = `WDSel_FromPC;
                end
            end

            S_EX: begin
                case (opcode)
                    `INSTR_RTYPE_OP: begin
                        // R-type 指令
                        ALUSrcA = `ALUSrcA_A;
                        ALUSrcB = `ALUSrcB_B;
                        case ({Funct7, Funct3})
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
                        RFWrite = 1;
                        RegSel  = `RegSel_rd;
                        WDSel   = `WDSel_FromALU;
                        PCWrite = 1;
                        NPCOp   = `NPC_PC;
                    end

                    `INSTR_ITYPE_OP: begin
                        // I-type 指令 (addi, ori)
                        ALUSrcA = `ALUSrcA_A;
                        ALUSrcB = `ALUSrcB_Imm;
                        case (Funct3)
                            `INSTR_ADDI_FUNCT: begin
                                ALUOp  = `ALUOp_ADD;
                                ExtSel = `ExtSel_SIGNED;
                            end
                            `INSTR_ORI_FUNCT: begin
                                ALUOp  = `ALUOp_OR;
                                ExtSel = `ExtSel_ZERO;
                            end
                            default: ALUOp = `ALUOp_ADD;
                        endcase
                        RFWrite = 1;
                        RegSel  = `RegSel_rd;
                        WDSel   = `WDSel_FromALU;
                        PCWrite = 1;
                        NPCOp   = `NPC_PC;
                    end

                    `INSTR_LW_OP: begin
                        // LW: 计算地址
                        ALUSrcA = `ALUSrcA_A;
                        ALUSrcB = `ALUSrcB_Imm;
                        ALUOp   = `ALUOp_ADD;
                        ExtSel  = `ExtSel_SIGNED;
                    end

                    `INSTR_SW_OP: begin
                        // SW: 计算地址
                        ALUSrcA = `ALUSrcA_A;
                        ALUSrcB = `ALUSrcB_Offset;
                        ALUOp   = `ALUOp_ADD;
                    end

                    `INSTR_BTYPE_OP: begin
                        // BEQ/BNE: 分支判断
                        ALUSrcA = `ALUSrcA_A;
                        ALUSrcB = `ALUSrcB_B;
                        ALUOp   = `ALUOp_SUB;
                        case (Funct3)
                            `INSTR_BEQ_FUNCT: begin
                                if (zero) begin
                                    PCWrite = 1;
                                    NPCOp   = `NPC_Offset12;
                                end else begin
                                    PCWrite = 1;
                                    NPCOp   = `NPC_PC;
                                end
                            end
                            `INSTR_BNE_FUNCT: begin
                                if (!zero) begin
                                    PCWrite = 1;
                                    NPCOp   = `NPC_Offset12;
                                end else begin
                                    PCWrite = 1;
                                    NPCOp   = `NPC_PC;
                                end
                            end
                            default: begin
                                PCWrite = 1;
                                NPCOp   = `NPC_PC;
                            end
                        endcase
                    end

                    `INSTR_JALR_OP: begin
                        // JALR: 计算跳转地址
                        ALUSrcA = `ALUSrcA_A;
                        ALUSrcB = `ALUSrcB_Imm;
                        ALUOp   = `ALUOp_ADD;
                        ExtSel  = `ExtSel_SIGNED;
                        PCWrite = 1;
                        NPCOp   = `NPC_rs;  // NPC 从 ALU 结果获取（需要在 riscv.v 连线）
                        RFWrite = 1;
                        RegSel  = `RegSel_rd;
                        WDSel   = `WDSel_FromPC;
                    end

                    default: begin
                        PCWrite = 1;
                        NPCOp   = `NPC_PC;
                    end
                endcase
            end

            S_MEM: begin
                if (opcode == `INSTR_LW_OP) begin
                    // LW: 读存储器
                    DMCtrl = 0;  // 读
                end else if (opcode == `INSTR_SW_OP) begin
                    // SW: 写存储器
                    DMCtrl  = 1;  // 写
                    PCWrite = 1;
                    NPCOp   = `NPC_PC;
                end
            end

            S_WB: begin
                // LW 写回
                RFWrite = 1;
                RegSel  = `RegSel_rd;
                WDSel   = `WDSel_FromMEM;
                PCWrite = 1;
                NPCOp   = `NPC_PC;
            end

            default: begin
                // 默认状态
            end
        endcase
    end

endmodule