`include "ctrl_signal_def.v"
`include "instruction_def.v"
module NPC(NPCOp, Offset12, Offset20, PC, rs, PCA4, NPC);
    input [1:0] NPCOp;      //控制信号
    input [12:1] Offset12;  //比较指令的跳转偏移量
    input [20:1] Offset20;  //跳转指令的跳转偏移量
    input [31:0] PC;        //本条指令的地址
    input [31:0] rs;        //跳转到子程序的地址
    output reg [31:0] PCA4; //PC+4
    output reg [31:0] NPC;  //下一条指令的地址

    wire signed [31:0] Offset13;
    wire signed [31:0] Offset21;

    // Bug N2 修复：正确的符号扩展到32位
    assign Offset13 = {{19{Offset12[12]}}, Offset12[12:1], 1'b0};
    assign Offset21 = {{11{Offset20[20]}}, Offset20[20:1], 1'b0};

    always@(*) begin
        case(NPCOp)
            `NPC_PC         : NPC = PC + 4;                     //顺序执行,32位CPU,地址每次加4
            `NPC_Offset12   : NPC = PC + Offset13;              //Bug N1 修复：分支指令 PC+offset
            `NPC_rs         : NPC = {rs[31:1], 1'b0};           //Bug N1 修复：JALR 地址最低位清零
            `NPC_Offset20   : NPC = PC + Offset21;              //跳转指令 PC+offset
        endcase
        PCA4 = PC + 4;  // Bug N3 部分修复：保持当前PC的PC+4
    end
endmodule