# Load-Branch 冒险死锁排查指南

## 问题现象
- 仿真在 time 450 ps 时卡死
- 寄存器从未被更新
- VCS 编译正常，但仿真无输出

## 测试用例 B 逻辑流程

```assembly
ori x1, x0, 2000      # Cyc 0-4: x1 = 2000
sw  x1, 0(x1)         # Cyc 1-5: [2000] = 2000
lw  x5, 0(x1)         # Cyc 2-6: x5 = [2000] = 2000
bne x5, x0, 12        # Cyc 3-?: if x5!=0, PC+12 (跳过两个nop)
nop                   # (被跳过)
nop                   # (被跳过)
ori x2, x0, 99        # Target: x2 = 99
```

## 流水线执行时间线

关键点是 **Load-Branch 冒险**：
- Cyc 2: lw 进入 EX，计算地址发送到 DM
- Cyc 3: lw 进入 MEM，DM 输出前一周期的旧值；bne 进入 ID，需要 x5
  - **冒险检测触发**：stall_ld = 1
  - EX 被清空为 NOP，PC 停止
  - bne 停留在 ID
  
- Cyc 4: lw 进入 WB，DM 输出新值 (2000)；bne 仍停留在 ID
  - ex_mem_alu = 2000 (来自 EX ALU)
  - mem_wb_alu = 2000 (来自 ex_mem_alu)

- Cyc 5: bne 可通过旁路获得 x5=2000
  - branch_taken_id = 1
  - PC = PC_b_tgt (PC + 12)

## 可能的死锁原因

### 原因 1：停顿逻辑问题
当 `stall_ld = 1` 时：
```verilog
wire ir_we = (~stall_take) | flush_ifid;  // 0 | 0 = 0
```
IR 不更新，分支指令停留在 IR(ID)，无法推进。

**验证方法**：
- 检查 out_ins (ID 级指令) 是否等于分支指令的编码
- 检查 id_ex_instr (EX 级) 是否为 NOP (0x00000013)
- 检查 stall_ld 是否为 1

### 原因 2：Load 数据路径问题
DM 是同步读，数据延迟一周期：
```verilog
always @(posedge clk) begin
    RD <= memory[Addr];  // 读出旧值
end
```

在 MEM 级时，RD 输出的是前一周期的值。需要在下一周期才能用作旁路。

**验证方法**：
- 检查 DM.Addr 是否为 500 (地址 2000 / 4)
- 检查 DM.RD 在 Cyc 4 和 Cyc 5 的值
- 检查 ex_mem_alu 何时为 2000

### 原因 3：旁路逻辑问题
分支需要通过以下方式获得 x5=2000：
```
rs2_fwd = (mem_wb_regwrite && (if_id_rs2==mem_wb_rd)) ? wb_value_mux : RD2
```

**验证方法**：
- 检查 cmp_eq_id (比较结果) 是否在正确的周期变为 1
- 检查 branch_taken_id 是否在 Load 完成后变为 1
- 检查 PC 是否随之更新

### 原因 4：时钟/复位时序问题
新改进的测试台与 hazard_A 保持一致：
- clk 初始为 1
- rst 高电平持续 20ps
- 第一个时钟上升沿发生在 t=50ps

**验证方法**：
- 检查 rst 释放后 PC 的首次变化
- 检查指令是否正确进入各个流水线阶段

## 调试步骤

### Step 1: 运行改进的测试
```bash
cd p:/IC/rv2/sim
make -f Makefile.hazard b_debug
```

### Step 2: 查看控制台输出
寻找以下信息：
- `[T=...] Cyc=0...` 的打印
- `[WARNING] PC stuck at ...` 的死锁警告
- `[FINAL RESULT]` 的最终寄存器值

### Step 3: 使用波形查看
打开 tb.fsdb 波形文件：
```bash
verdi -f simv.f -ssf tb.fsdb
```

关键观察点（从 t=100ps 开始，复位释放后）：
1. **PC 变化**：应该看到 PC 逐步推进 (0 -> 4 -> 8 -> ... -> 12 -> 16)
2. **指令流**：
   - in_ins: ori -> sw -> lw -> bne -> ...
   - out_ins: ori -> sw -> lw -> bne -> ...
   - id_ex_instr: (NOP) -> ori -> sw -> lw -> bne
3. **寄存器写入**：
   - x1 应该在 Cyc 4 左右变为 2000
   - x5 应该在 Cyc 6-7 变为 2000
   - x2 应该在最后变为 99

4. **冒险信号**：
   - stall_ld: 应该在 Cyc 3-5 期间为 1
   - ex_mem_memread: 应该在 MEM 阶段显示 Load 信号

### Step 4: 对比 hazard_A
运行 hazard_A 并对比：
```bash
make -f Makefile.hazard a
```

如果 A 正常而 B 卡死，问题可能是：
- Branch 相关的信号处理
- Load-Branch 冒险特定的逻辑

## 修复建议

根据波形分析，可能的修复包括：

1. **确保 stall_ld 在 Load 完成后释放**
   - 检查冒险检测条件是否正确

2. **确保分支条件正确判定**
   - 检查 cmp_eq_id 的计算
   - 检查 branch_taken_id 的时序

3. **检查旁路优先级**
   - EX 级旁路优先于 MEM 级
   - Load 指令无法通过 EX 级旁路（有 memread 条件检查）

4. **考虑增加额外的流水线阶段**
   - 如果 Load 数据准备时间过长，可能需要额外的缓冲

## 关键信号监测

在 Verdi 中添加这些信号到波形（搜索路径 `riscv/`）：

- `PC`: 程序计数器
- `out_ins`: ID 级指令
- `id_ex_instr`: EX 级指令
- `stall_ld`: 停顿信号
- `if_id_rs2`: ID 的 rs2 寄存器号
- `cmp_eq_id`: 分支比较结果
- `branch_taken_id`: 分支条件成立
- `U_RF.register[1]`: x1 寄存器值
- `U_RF.register[2]`: x2 寄存器值
- `U_RF.register[5]`: x5 寄存器值
- `U_DM.memory[500]`: 内存地址 2000 的值

