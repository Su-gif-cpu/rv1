`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/10/26 09:28:20
// Design Name: 
// Module Name: IM
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
module IM(InsMemRW, addr, Ins, clk, rst);
    input               InsMemRW;       //指令存储单元信号
    input       [11:2]  addr;           //指令存储器地址
    input               clk;            //时钟信号（SRAM宏替换）
    input               rst;            //复位信号
    output reg [31:0] Ins;             //取得的指令
    reg [31:0] memory[0:1023];

    // 同步读（SRAM 宏替换准备）
    always @(posedge clk) begin
        if (rst)
            Ins <= 32'h0000_0013;  // Reset 时输出 NOP，避免 X 态
        else if (InsMemRW)
            Ins <= memory[addr];
        else
            Ins <= 32'b0;
    end

endmodule
