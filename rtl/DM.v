`include "ctrl_signal_def.v"
// 同步读写（SRAM 宏替换准备）：读写都在时钟沿，写时读出旧值
module DM( Addr, WD, clk, DMCtrl, RD);
    input  [11:2] Addr;
    input  [31:0] WD;
    input  clk;
    input DMCtrl;
    output reg [31:0] RD;

    reg [31:0] memory[0:1023];

    // 同步读写
    always @(posedge clk) begin
        if (DMCtrl)
            memory[Addr] <= WD;
        RD <= memory[Addr];  // 读操作：写时读出旧值
    end

endmodule
