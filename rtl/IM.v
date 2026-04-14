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
module IM(InsMemRW, addr, clk, Ins);
    input               InsMemRW;       //指令存储单元信号
    input       [11:2]  addr;           //指令存储器地址
    input               clk;            //时钟信号（SRAM宏替换准备）
    output reg [31:0] Ins;             //取得的指令
    reg [31:0] memory[0:1023];

    // 修改为同步读（SRAM宏替换准备）
    always @(posedge clk) begin
        if (InsMemRW) begin
            Ins <= memory[addr];        //同步读指令
        end
        else begin
            Ins <= 32'h0;               //InsMemRW=0时输出0
        end
    end

endmodule