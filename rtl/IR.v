// 用于临时存储指令的二进制形式
`include "ctrl_signal_def.v"
module IR(in_ins, clk, IRWrite, out_ins);
    input           clk, IRWrite;    //IR寄存器写使能信号（保留接口兼容性）
    input [31:0]    in_ins;          //指令输入
    output [31:0]   out_ins;         //指令输出

    // 改为组合逻辑直通（配合 IM 同步读，保持流水线性能）
    assign out_ins = in_ins;

endmodule
