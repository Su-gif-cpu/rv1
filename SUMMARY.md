# Hazard B 测试修复总结

## 已完成的修改

### 1. ✅ 改进测试台 [tb/hazard_B_sim.v](tb/hazard_B_sim.v)

**变更内容**:
- 修复复位时序，与 hazard_A 保持一致 (clk=1, rst 持续 20ps)
- 添加详细的周期打印输出（PC、指令、寄存器值）
- 实现死锁检测（连续 6 个周期 PC 不变时发出警告）
- 增加超时保护（20000ps）
- 添加最终结果验证和报告

**关键改进**:
```verilog
// 周期追踪 - 每个周期打印关键信号
$display("[T=%0t Cyc=%0d] PC=%08X | IR(IF)=%08X | IR(ID)=%08X | IR(EX)=%08X | x5=%08X x2=%08X",
    $time, cycle_cnt, U_RISCV.PC, U_RISCV.in_ins, U_RISCV.out_ins, 
    U_RISCV.id_ex_instr, U_RISCV.U_RF.register[5], U_RISCV.U_RF.register[2]);

// Load/Store 操作追踪
if (U_RISCV.ex_mem_memwrite) begin
    $display("     [MEM] SW to addr=%0d, data=%08X", 
        U_RISCV.ex_mem_alu[11:2], U_RISCV.ex_mem_rs2);
end
```

### 2. ✅ 更新 Makefile [sim/Makefile.hazard](sim/Makefile.hazard)

**变更内容**:
- 添加 `b_debug` 编译和运行目标
- 统一编译和运行命令的调用方式
- 更新帮助信息，说明 b_debug 选项

**新增命令**:
```makefile
b_debug: compile_b_debug run_b_debug

compile_b_debug:
	vcs -f ./files_B.f ... | tee hazard_b_debug_compile.log

run_b_debug:
	./simv +vcs+loopdetect +vcs+loopreport -l hazard_b.log ...
```

### 3. ✅ 机器码验证 [HAZARD_B_ENCODING.md](HAZARD_B_ENCODING.md)

**内容**:
- 详细的 RISC-V 指令编码规则说明
- 逐条验证 hazard_B.hex 中的所有机器码
- 指令内存布局和地址映射
- 预期执行流程（理想和实际）
- 故障诊断参考表

**验证结果**: ✅ 所有机器码编码正确

### 4. ✅ 调试指南 [DEBUG_HAZARD_B.md](DEBUG_HAZARD_B.md)

**内容**:
- Load-Branch 冒险的细节分析
- 可能的死锁原因（4 种）
- 详细的调试步骤
- 关键信号监测清单
- Verdi 波形查看建议

### 5. ✅ 快速开始指南 [QUICK_START.md](QUICK_START.md)

**内容**:
- 一页纸快速诊断流程
- 正常/死锁情况对比
- 波形观察点和预期行为
- 三种常见问题及修复建议
- 命令速查表

## 问题根源分析

### Load-Branch 冒险流程

```
Cyc 3: lw进EX, bne进ID
       → 检测冒险: lw.rd(x5) == bne.rs1(x5)
       → stall_ld = 1, PC锁住, EX清空为NOP

Cyc 4-5: lw推进到MEM/WB, bne停顿在ID
       → stall_ld保持1, 等待Load完成
       
Cyc 6: lw离开流水线, Load数据可用
       → stall_ld变为0, bne可以评估分支条件
       → rs1_fwd获得x5=2000（通过旁路）
       
Cyc 7: bne评估条件(bne x5,x0)
       → cmp_eq_id = (2000==0) = 0
       → branch_taken_id = !cmp_eq_id = 1
       → PC更新到目标地址 (0x18)
```

### 关键要点

1. **停顿机制** - 当Load指令的目标寄存器被后续指令（特别是分支）需要时触发
2. **旁路优先级** - WB阶段的结果优先级最低，需要等待Load完成
3. **时序关键** - 分支必须在停顿释放后才能评估条件，否则无法看到Load的结果

## 如何使用改进后的测试

### 基本运行
```bash
cd p:/IC/rv2/sim
make -f Makefile.hazard b_debug
```

### 预期输出（成功）
```
[hazard B] Instruction memory initialized
[T=100] Cyc=0] PC=00000000 | IR(IF)=7d006093 | ... | x5=00000000 x2=00000000
[T=150] Cyc=1] PC=00000004 | IR(IF)=0010a023 | ... | x5=00000000 x2=00000000
     [MEM] SW to addr=500, data=00000000
...
[T=...] Cyc=...] ... x5=00000000 x2=00000063
[FINAL RESULT]
  x1=000007d0
  x2=00000063      <-- 正确值
  x5=000007d0
  PC=0000001c
  DM[500]=000007d0
[PASS] x2 has expected value 0x63
```

### 预期输出（故障）
```
...
[WARNING] PC stuck at 0000000C, possible deadlock at time ...
...
[TIMEOUT] Simulation reached 20000ps timeout
[FINAL RESULT]
  ...
[FAIL] x2 has unexpected value ...
```

## 调试工作流

### Phase 1: 快速检查
1. 运行 `make -f Makefile.hazard b_debug`
2. 查看是否有 `[PASS]` 或 `[FAIL]` 输出
3. 如果失败，查看 `[WARNING]` 或 `[TIMEOUT]` 消息

### Phase 2: 信号级调查
1. 打开 tb.fsdb 波形文件
2. 观察关键信号变化（见 DEBUG_HAZARD_B.md）
3. 比对实际波形与预期时序

### Phase 3: 对标测试
1. 运行 `make -f Makefile.hazard a` (hazard_A)
2. 比较 hazard_A 和 hazard_B 的日志
3. 确定差异点（通常在分支判定阶段）

### Phase 4: RTL 修改
根据波形分析结果，可能需要修改：
- [rtl/riscv.v](rtl/riscv.v) 中的冒险检测逻辑
- 旁路的优先级
- 停顿时的流水线清空逻辑

## 文件对应关系

```
p:/IC/rv2/
├── QUICK_START.md          ← 从这里开始
├── DEBUG_HAZARD_B.md       ← 详细技术分析
├── HAZARD_B_ENCODING.md    ← 机器码验证
├── tb/
│   └── hazard_B_sim.v      ✅ 已改进（详细输出）
├── hex/
│   └── hazard_B.hex        ✅ 已验证（编码正确）
├── rtl/
│   └── riscv.v             ← 设计文件（如需修改）
└── sim/
    ├── Makefile.hazard     ✅ 已更新（新增b_debug）
    └── files_B.f           ✅ 包含hazard_B_sim.v
```

## 下一步建议

1. **立即验证**
   ```bash
   cd p:/IC/rv2/sim
   make -f Makefile.hazard b_debug
   tail -50 hazard_b.log
   ```

2. **如果仍有问题**
   - 参考 [DEBUG_HAZARD_B.md](DEBUG_HAZARD_B.md) 的故障排查部分
   - 在 Verdi 中对比 hazard_A 和 hazard_B 的波形

3. **可能的 RTL 修复**
   - 确保 `stall_ld` 包含了所有必要的冒险检测
   - 验证分支指令的 rs1/rs2 使用情况
   - 检查 Load 数据的旁路延迟

4. **性能优化**（可选）
   - 考虑是否需要 Load-Branch Forwarding 单独处理
   - 评估增加 bypass stage 是否能减少停顿

## 已知限制

当前改进的测试台和文档针对以下场景：
- VCS 仿真环境
- 使用 fsdb 波形格式
- 标准 RISC-V 指令集

如果使用其他仿真器或扩展指令集，可能需要调整。

