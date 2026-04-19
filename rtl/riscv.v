`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
`include "instruction_def.v"
`include "ctrl_signal_def.v"

// 五级流水线 IF-ID-EX-MEM-WB：load-use 停顿；EX 级 jal/jalr/后备分支；beq/bne 在 ID 提前判定减惩罚。子模块端口与实例数不变。
module riscv(clk, rst);
    input clk, rst;

    wire cu_RFWrite;
    wire cu_DMCtrl_nc;
    wire cu_PCWrite_nc;
    wire cu_IRWrite_nc;
    wire cu_InsMemRW_nc;
    wire cu_ExtSel;
    wire cu_ALUSrcA;
    wire [1:0] cu_ALUSrcB;
    wire [1:0] cu_NPCOp_nc;
    wire [1:0] cu_WDSel;
    wire [1:0] cu_RegSel;
    wire [3:0] cu_ALUOp;

    wire [31:0] PC;
    wire [31:0] in_ins;
    wire [31:0] out_ins;
    wire [31:0] RD;

    reg [31:0] if_id_pc4;

    wire [31:0] RD1, RD2;
    wire [31:0] RD1_r, RD2_r;
    wire [31:0] RD1_flop_in, RD2_flop_in;

    wire [11:0] Imm12;
    wire [4:0] WR;
    wire [31:0] WD;
    wire [31:0] A, B, ALU_result;
    wire zero;
    wire [31:0] alu_reg_out;

    assign Imm12 = out_ins[31:20];

    wire [6:0] if_id_opcode  = out_ins[6:0];
    wire [2:0] if_id_funct3 = out_ins[14:12];
    wire [6:0] if_id_funct7 = out_ins[31:25];
    wire [4:0] if_id_rs1     = out_ins[19:15];
    wire [4:0] if_id_rs2     = out_ins[24:20];

    ControlUnit U_ControlUnit(
        .clk(clk), .rst(rst), .zero(zero),
        .opcode(if_id_opcode), .Funct7(if_id_funct7), .Funct3(if_id_funct3),
        .RFWrite(cu_RFWrite), .DMCtrl(cu_DMCtrl_nc),
        .PCWrite(cu_PCWrite_nc), .IRWrite(cu_IRWrite_nc),
        .InsMemRW(cu_InsMemRW_nc),
        .ExtSel(cu_ExtSel), .ALUOp(cu_ALUOp), .NPCOp(cu_NPCOp_nc),
        .ALUSrcA(cu_ALUSrcA),
        .WDSel(cu_WDSel), .ALUSrcB(cu_ALUSrcB), .RegSel(cu_RegSel)
    );

    wire stall_ld;
    wire branch_taken;
    wire jmp_ex;
    wire jmp_ex_take;
    wire stall_take;
    wire [31:0] npc_ex;
    wire flush_ifid;
    wire        branch_taken_id;
    wire signed [31:0] npc_b_tgt;
    // 避免 jmp_ex/stall_ld 含 X 时 ?: 把 X 传到 PC（你波形里 pc_next 末位 X）
    assign jmp_ex_take = (jmp_ex === 1'b1);
    assign stall_take  = (stall_ld === 1'b1);
    assign flush_ifid  = jmp_ex_take | branch_taken_id;

    wire ir_we  = (~stall_take) | flush_ifid;
    wire [31:0] ir_din = flush_ifid ? 32'h0000_0013 : in_ins;
    wire pc_wen = (~stall_take) | jmp_ex_take | branch_taken_id;

    wire [31:0] pc_plus4 = PC + 32'd4;
    // EX 级跳转/分支优先于 ID 分支（流水 older 指令）；否则 ID 提前 taken 减少 1 拍分支惩罚。
    wire [31:0] pc_next =
        jmp_ex_take ? npc_ex :
        branch_taken_id ? npc_b_tgt :
        (stall_take ? PC : pc_plus4);

    PC U_PC (
        .clk(clk), .rst(rst), .PCWrite(pc_wen), .NPC(pc_next), .PC(PC)
    );

    IM U_IM (
        .addr(PC[11:2]), .Ins(in_ins), .InsMemRW(1'b1), .clk(clk), .rst(rst)
    );

    IR U_IR (
        .clk(clk), .IRWrite(ir_we), .in_ins(ir_din), .out_ins(out_ins)
    );

    wire if_id_uses_rs2 =
        (if_id_opcode === `INSTR_RTYPE_OP) ||
        (if_id_opcode === `INSTR_SW_OP) ||
        (if_id_opcode === `INSTR_BTYPE_OP);

    reg [31:0] id_ex_instr;
    reg [31:0] id_ex_pc4;
    reg [31:0] id_ex_imm32;
    reg        id_ex_regwrite;
    reg        id_ex_memread;
    reg        id_ex_memwrite;
    reg [1:0]  id_ex_wdsel;
    reg [1:0]  id_ex_alusrcb;
    reg [3:0]  id_ex_aluop;
    reg        id_ex_alusrca;
    reg [1:0]  id_ex_regsel;
    reg        id_ex_is_branch;
    reg        id_ex_is_jal;
    reg        id_ex_is_jalr;

    reg [31:0] ex_mem_alu;
    reg [31:0] ex_mem_rs2;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_regwrite;
    reg        ex_mem_memread;
    reg        ex_mem_memwrite;
    reg [1:0]  ex_mem_wdsel;
    reg [1:0]  ex_mem_regsel;
    reg [31:0] ex_mem_pc4;

    reg [31:0] mem_wb_alu;
    reg [31:0] mem_wb_rdata;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_regwrite;
    reg [1:0]  mem_wb_wdsel;
    reg [1:0]  mem_wb_regsel;
    reg [31:0] mem_wb_pc4;

    wire [6:0] id_ex_opcode = id_ex_instr[6:0];
    wire [2:0] id_ex_funct3 = id_ex_instr[14:12];
    wire [4:0] id_ex_rs1    = id_ex_instr[19:15];
    wire [4:0] id_ex_rs2    = id_ex_instr[24:20];
    wire [4:0] id_ex_rd_w   = id_ex_instr[11:7];
    // DM 同步读后，EX 级和 MEM 级的 lw 都需要停顿
    wire stall_ex_hzd = id_ex_memread && !(id_ex_rd_w === 5'd0) && (
        (id_ex_rd_w === if_id_rs1) ||
        (if_id_uses_rs2 && (id_ex_rd_w === if_id_rs2))
    );
    wire stall_mem_hzd = ex_mem_memread && !(ex_mem_rd === 5'd0) && (
        (ex_mem_rd === if_id_rs1) ||
        (if_id_uses_rs2 && (ex_mem_rd === if_id_rs2))
    );
    assign stall_ld = stall_ex_hzd || stall_mem_hzd;

    // B 型目标（与 NPC 一致）；branch_taken_id 在 rs1/rs2 旁路之后赋值。
    wire [12:1] b12_if      = {out_ins[31], out_ins[7], out_ins[30:25], out_ins[11:8]};
    wire [31:0] pc_reloc_if = if_id_pc4 - 32'd4;
    assign npc_b_tgt =
        $signed({1'b0, pc_reloc_if}) + $signed({b12_if, 1'b0});

    RF U_RF (
        .RR1(if_id_rs1), .RR2(if_id_rs2), .WR(WR), .WD(WD), .clk(clk),
        .RFWrite(mem_wb_regwrite), .RD1(RD1), .RD2(RD2)
    );

    wire [31:0] wb_value_mux;
    assign wb_value_mux =
        (mem_wb_wdsel === `WDSel_FromMEM) ? RD :
        (mem_wb_wdsel === `WDSel_FromPC)   ? mem_wb_pc4 :
        mem_wb_alu;

    // 旁路目标为 ID 级正在读寄存器堆的 rs1/rs2（if_id_*），与 RF 读口一致
    wire [31:0] rs1_fwd;
    wire [31:0] rs2_fwd;
    // EX 级结果当拍可用（ALU_result）；仅 MEM/WB 的 ex_mem_alu 会晚一拍，缺少本条会断 addi→or 等背对背相关。
    wire [31:0] id_ex_bypass_val;
    assign id_ex_bypass_val =
        (id_ex_is_jal || id_ex_is_jalr) ? id_ex_pc4 : ALU_result;

    assign rs1_fwd =
        (if_id_rs1 === 5'd0) ? 32'd0 :
        (id_ex_regwrite && !id_ex_memread && (if_id_rs1 === id_ex_rd_w) &&
            !(id_ex_rd_w === 5'd0)) ? id_ex_bypass_val :
        (ex_mem_regwrite && (if_id_rs1 === ex_mem_rd) && !(ex_mem_rd === 5'd0) &&
         ~ex_mem_memread) ? ex_mem_alu :
        (mem_wb_regwrite && (if_id_rs1 === mem_wb_rd) && !(mem_wb_rd === 5'd0)) ?
            wb_value_mux : RD1;

    assign rs2_fwd =
        (if_id_rs2 === 5'd0) ? 32'd0 :
        (id_ex_regwrite && !id_ex_memread && (if_id_rs2 === id_ex_rd_w) &&
            !(id_ex_rd_w === 5'd0)) ? id_ex_bypass_val :
        (ex_mem_regwrite && (if_id_rs2 === ex_mem_rd) && !(ex_mem_rd === 5'd0) &&
         ~ex_mem_memread) ? ex_mem_alu :
        (mem_wb_regwrite && (if_id_rs2 === mem_wb_rd) && !(mem_wb_rd === 5'd0)) ?
            wb_value_mux : RD2;

    wire cmp_eq_id  = (rs1_fwd == rs2_fwd);
    wire br_beq_if  = (if_id_funct3 === 3'b000);
    wire br_bne_if  = (if_id_funct3 === 3'b001);
    wire if_is_br   = (if_id_opcode === `INSTR_BTYPE_OP);
    assign branch_taken_id =
        !stall_take && if_is_br &&
        ((br_beq_if && cmp_eq_id) || (br_bne_if && !cmp_eq_id));

    assign RD1_flop_in = stall_take ? RD1_r : rs1_fwd;
    assign RD2_flop_in = stall_take ? RD2_r : rs2_fwd;

    Flopr U_A (
        .clk(clk), .rst(rst), .in_data(RD1_flop_in), .out_data(RD1_r)
    );

    Flopr U_B (
        .clk(clk), .rst(rst), .in_data(RD2_flop_in), .out_data(RD2_r)
    );

    wire [11:0] ext_imm_in;
    assign ext_imm_in = (if_id_opcode === `INSTR_SW_OP) ?
        {out_ins[31:25], out_ins[11:7]} : Imm12;

    wire [31:0] cu_imm32;
    EXT U_EXT (
        .imm_in(ext_imm_in), .ExtSel(cu_ExtSel), .imm_out(cu_imm32)
    );

    MUX_2to1_A U_MUX_2to1_A (
        .X(RD1_r), .Y(5'd0), .control(id_ex_alusrca), .out(A)
    );

    wire [11:0] b_ofs;
    assign b_ofs =
        (id_ex_opcode === `INSTR_BTYPE_OP) ?
            {id_ex_instr[31], id_ex_instr[7], id_ex_instr[30:25], id_ex_instr[11:8]} :
        (id_ex_opcode === `INSTR_SW_OP) ?
            {id_ex_instr[31:25], id_ex_instr[11:7]} :
        id_ex_imm32[11:0];

    MUX_3to1_B U_MUX_3to1_B (
        .X(RD2_r), .Y(id_ex_imm32), .Z(b_ofs), .control(id_ex_alusrcb), .out(B)
    );

    ALU U_ALU (
        .A(A), .B(B), .ALUOp(id_ex_aluop), .ALU_result(ALU_result), .zero(zero)
    );

    Flopr U_ALUOut (
        .clk(clk), .rst(rst), .in_data(ALU_result), .out_data(alu_reg_out)
    );

    wire [12:1] npc_b12;
    wire [20:1] npc_j20;
    assign npc_b12 = {id_ex_instr[31], id_ex_instr[7], id_ex_instr[30:25], id_ex_instr[11:8]};
    assign npc_j20 = {id_ex_instr[31], id_ex_instr[19:12], id_ex_instr[20], id_ex_instr[30:21]};

    wire [1:0] npc_sel_ex;
    assign npc_sel_ex =
        id_ex_is_jal  ? `NPC_Offset20 :
        id_ex_is_jalr ? `NPC_rs :
        branch_taken  ? `NPC_Offset12 : `NPC_PC;

    wire [31:0] jalr_targ;
    assign jalr_targ = ALU_result & 32'hFFFFFFFE;

    wire [31:0] pca4_nc;
    NPC U_NPC (
        .PC(id_ex_pc4),
        .NPCOp(npc_sel_ex),
        .Offset12(npc_b12),
        .Offset20(npc_j20),
        .rs(jalr_targ),
        .PCA4(pca4_nc),
        .NPC(npc_ex)
    );

    // zero 为 X 时不用逻辑非扩展为 X；仅在为 1/0 时判 taken
    wire br_beq = (id_ex_funct3 === 3'b000);
    wire br_bne = (id_ex_funct3 === 3'b001);
    assign branch_taken = id_ex_is_branch &&
        ((br_beq && (zero === 1'b1)) || (br_bne && (zero === 1'b0)));

    assign jmp_ex    = id_ex_is_jal | id_ex_is_jalr | branch_taken;

    wire [11:2] dm_addr;
    assign dm_addr = (ex_mem_memread | ex_mem_memwrite) ? ex_mem_alu[11:2] : 10'd0;

    DM U_DM (
        .Addr(dm_addr),
        .WD(ex_mem_rs2),
        .DMCtrl(ex_mem_memwrite),
        .clk(clk),
        .RD(RD)
    );

    wire [31:0] DR_out;
    assign DR_out = RD;

    MUX_3to1 U_MUX_3to1 (
        .X(mem_wb_rd), .Y(5'd0), .Z(5'd31),
        .control(mem_wb_regsel), .out(WR)
    );

    MUX_3to1_LMD U_MUX_3to1_LMD (
        .X(mem_wb_alu), .Y(RD), .Z(mem_wb_pc4[31:2]),
        .control(mem_wb_wdsel), .out(WD)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_pc4 <= 32'd0;
            id_ex_instr <= 32'h0000_0013;
            id_ex_pc4 <= 32'd0;
            id_ex_imm32 <= 32'd0;
            id_ex_regwrite <= 1'b0;
            id_ex_memread <= 1'b0;
            id_ex_memwrite <= 1'b0;
            id_ex_wdsel <= `WDSel_FromALU;
            id_ex_alusrcb <= `ALUSrcB_B;
            id_ex_aluop <= `ALUOp_ADD;
            id_ex_alusrca <= `ALUSrcA_A;
            id_ex_regsel <= `RegSel_rd;
            id_ex_is_branch <= 1'b0;
            id_ex_is_jal <= 1'b0;
            id_ex_is_jalr <= 1'b0;
            ex_mem_alu <= 32'd0;
            ex_mem_rs2 <= 32'd0;
            ex_mem_rd <= 5'd0;
            ex_mem_regwrite <= 1'b0;
            ex_mem_memread <= 1'b0;
            ex_mem_memwrite <= 1'b0;
            ex_mem_wdsel <= `WDSel_FromALU;
            ex_mem_regsel <= `RegSel_rd;
            ex_mem_pc4 <= 32'd0;
            mem_wb_alu <= 32'd0;
            mem_wb_rdata <= 32'd0;
            mem_wb_rd <= 5'd0;
            mem_wb_regwrite <= 1'b0;
            mem_wb_wdsel <= `WDSel_FromALU;
            mem_wb_regsel <= `RegSel_rd;
            mem_wb_pc4 <= 32'd0;
        end else begin
            if (!(stall_ld === 1'b1)) begin
                if (jmp_ex_take)
                    if_id_pc4 <= npc_ex + 32'd4;
                else if (branch_taken_id)
                    if_id_pc4 <= npc_b_tgt + 32'd4;
                else
                    if_id_pc4 <= pc_plus4;
            end

            if (stall_ld === 1'b1) begin
                id_ex_instr <= 32'h0000_0013;
                id_ex_pc4 <= 32'd0;
                id_ex_imm32 <= 32'd0;
                id_ex_regwrite <= 1'b0;
                id_ex_memread <= 1'b0;
                id_ex_memwrite <= 1'b0;
                id_ex_wdsel <= `WDSel_FromALU;
                id_ex_alusrcb <= `ALUSrcB_B;
                id_ex_aluop <= `ALUOp_ADD;
                id_ex_alusrca <= `ALUSrcA_A;
                id_ex_regsel <= `RegSel_rd;
                id_ex_is_branch <= 1'b0;
                id_ex_is_jal <= 1'b0;
                id_ex_is_jalr <= 1'b0;
            end else if (jmp_ex === 1'b1 || branch_taken_id) begin
                id_ex_instr <= 32'h0000_0013;
                id_ex_pc4 <= 32'd0;
                id_ex_imm32 <= 32'd0;
                id_ex_regwrite <= 1'b0;
                id_ex_memread <= 1'b0;
                id_ex_memwrite <= 1'b0;
                id_ex_wdsel <= `WDSel_FromALU;
                id_ex_alusrcb <= `ALUSrcB_B;
                id_ex_aluop <= `ALUOp_ADD;
                id_ex_alusrca <= `ALUSrcA_A;
                id_ex_regsel <= `RegSel_rd;
                id_ex_is_branch <= 1'b0;
                id_ex_is_jal <= 1'b0;
                id_ex_is_jalr <= 1'b0;
            end else begin
                id_ex_instr <= out_ins;
                id_ex_pc4 <= if_id_pc4;
                id_ex_imm32 <= cu_imm32;
                id_ex_regwrite <= cu_RFWrite;
                id_ex_memread <= (if_id_opcode === `INSTR_LW_OP);
                id_ex_memwrite <= (if_id_opcode === `INSTR_SW_OP);
                id_ex_wdsel <= cu_WDSel;
                id_ex_alusrcb <= cu_ALUSrcB;
                id_ex_aluop <= cu_ALUOp;
                id_ex_alusrca <= cu_ALUSrcA;
                id_ex_regsel <= cu_RegSel;
                id_ex_is_branch <= (if_id_opcode === `INSTR_BTYPE_OP);
                id_ex_is_jal <= (if_id_opcode === `INSTR_JAL_OP);
                id_ex_is_jalr <= (if_id_opcode === `INSTR_JALR_OP);
            end

            ex_mem_alu <= ALU_result;
            ex_mem_rs2 <= RD2_r;
            ex_mem_rd <= id_ex_instr[11:7];
            ex_mem_regwrite <= id_ex_regwrite;
            ex_mem_memread <= id_ex_memread;
            ex_mem_memwrite <= id_ex_memwrite;
            ex_mem_wdsel <= id_ex_wdsel;
            ex_mem_regsel <= id_ex_regsel;
            ex_mem_pc4 <= id_ex_pc4;

            mem_wb_alu <= ex_mem_alu;
            mem_wb_rdata <= RD;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_regwrite <= ex_mem_regwrite & !(ex_mem_rd === 5'd0);
            mem_wb_wdsel <= ex_mem_wdsel;
            mem_wb_regsel <= ex_mem_regsel;
            mem_wb_pc4 <= ex_mem_pc4;
        end
    end

`ifdef TRACE_EXEC
    // Simulation-only trace: helps locate where control-flow diverges.
    always @(posedge clk) begin
        if (!rst) begin
            $display("[TRACE] t=%0t PC=%08X IR=%08X | jmp=%b br=%b jal=%b jalr=%b zero=%b npc_ex=%08X | x2=%08X x3=%08X",
                $time, PC, out_ins, jmp_ex, branch_taken, id_ex_is_jal, id_ex_is_jalr, zero, npc_ex,
                U_RF.register[2], U_RF.register[3]);

            if (ex_mem_memwrite) begin
                $display("[TRACE][SW] addr_word=%0d addr_byte=0x%03X data=%08X",
                    ex_mem_alu[11:2], {ex_mem_alu[11:2], 2'b00}, ex_mem_rs2);
            end
        end
    end
`endif

endmodule
