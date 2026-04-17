`include "ctrl_signal_def.v"
`include "instruction_def.v"
// 纯组合：ALUOp 译码 + 加减/逻辑/移位（5bit 移位量）；单周期内可综合、便于 200MHz 时序收敛。
module ALU(A, B, ALUOp, zero, ALU_result);
    input signed [31:0] A;
    input signed [31:0] B;
    input [3:0] ALUOp;
    output zero;
    output reg signed [31:0] ALU_result;

    wire [4:0] shamt;
    wire [31:0] a_unsigned;

    assign shamt      = B[4:0];
    assign a_unsigned = $unsigned(A);

    always @(*) begin
        case (ALUOp)
            `ALUOp_ADD:  ALU_result = A + B;
            `ALUOp_SUB:  ALU_result = A - B;
            `ALUOp_AND:  ALU_result = A & B;
            `ALUOp_OR:   ALU_result = A | B;
            `ALUOp_XOR:  ALU_result = A ^ B;
            `ALUOp_SLL:  ALU_result = A <<< shamt;
            `ALUOp_SRL:  ALU_result = $signed(a_unsigned >> shamt);
            `ALUOp_SRA:  ALU_result = A >>> shamt;
            default:     ALU_result = A + B;
        endcase
    end

    assign zero = (ALU_result == 32'sd0);

endmodule
