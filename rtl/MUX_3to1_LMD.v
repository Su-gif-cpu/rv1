`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/11/25 09:52:17
// Design Name: 
// Module Name: MUX_3to1_LMD
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`include "ctrl_signal_def.v"
module MUX_3to1_LMD(X, Y, Z, control, out);
    input [31:0] X;             //临时寄存器ALU0中的内容
    input [31:0] Y;             //临时寄存器LMD中的内容
    input [31:2] Z;             //PC+4
    input [1:0] control;        //选择控制信号
    output reg [31:0] out;      //输出选择结果

    always @ (X or Y or Z or control) begin
        case(control)
            `WDSel_FromALU : out = X;      //选择X
            `WDSel_FromMEM : out = Y;      //选择Y
            // Z 为 PC+4[31:2]，低 2 位恒为 0；禁止将 30 位总线零扩展到 32 位以免抹掉 PC 高位
            `WDSel_FromPC  : out = {Z, 2'b00};
            `WDSel_Else    : out = 0;
        endcase
    end
endmodule
