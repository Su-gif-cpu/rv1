`include "ctrl_signal_def.v"
module EXT(imm_in, ExtSel, imm_out);
    input [11:0]     imm_in;    //输入的12位数据
    input            ExtSel;    //控制信号
    output reg[31:0] imm_out;   //扩展后的32位数据

    always@(imm_in or ExtSel) begin
    case(ExtSel)
        `ExtSel_ZERO :imm_out = {20'b0,imm_in[11:0]};                         //无符号扩展
        `ExtSel_SIGNED:imm_out = {imm_in[11] ? 20'hfffff : 20'h00000 ,imm_in[11:0]}; //有符号扩展
        default      :imm_out = 32'b0;
    endcase
    end
endmodule