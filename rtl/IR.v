// 用于临时存储指令的二进制形式
`include "ctrl_signal_def.v"
module IR(in_ins, clk, rst, IRWrite, out_ins);
    input           clk, rst, IRWrite;    //时钟、复位、写使能
    input [31:0]    in_ins;               //指令输入
    output reg [31:0] out_ins;            //指令输出

    // 时序逻辑：IR 作为缓冲寄存器，停顿时锁定当前指令
    // 关键：配合同步 IM，IR 必须保持为时序逻辑
    // - IM 同步读延迟一拍，需要 IR 缓冲指令
    // - 停顿时（IRWrite=0），IR 锁定，保证 ID 级指令稳定
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out_ins <= 32'h0000_0013;  // 复位为 NOP
        end else if (IRWrite) begin
            out_ins <= in_ins;         // 只在写使能时更新
        end
        // 否则保持不变（停顿时锁定）
    end

endmodule
