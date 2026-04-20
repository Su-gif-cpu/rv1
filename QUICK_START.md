# Hazard B 快速开始指南

## 问题概述
测试用例 B (Load-Branch 冒险) 在仿真 450ps 时卡死，没有任何输出。

## 快速诊断方案

### 步骤 1: 运行改进的仿真
```bash
cd p:\IC\rv2\sim
make -f Makefile.hazard b_debug
```

这会编译并运行 hazard_B，输出将包含：
- 每个时钟周期的状态
- 寄存器值的变化
- Load/Store 操作
- 死锁检测警告

### 步骤 2: 检查控制台输出
查找以下信息：

#### ✅ 正常情况应该看到：
```
[T=...Cyc=0] PC=00000000 | IR(IF)=7d006093 | IR(ID)=00000000 | IR(EX)=00000013 | x5=00000000 x2=00000000
[T=...Cyc=1] PC=00000004 | IR(IF)=0010a023 | IR(ID)=7d006093 | IR(EX)=00000013 | x5=00000000 x2=00000000
     [MEM] SW to addr=500, data=00000000
...
[T=...Cyc=...] x2=00000063  <- 最终结果应该是 0x63 = 99
[FINAL RESULT] x2 has expected value 0x63
```

#### ❌ 死锁情况会看到：
```
[WARNING] PC stuck at 0000000C, possible deadlock at time ...
[TIMEOUT] Simulation reached 20000ps timeout
[FINAL RESULT] x2 has unexpected value ...
```

### 步骤 3: 查看波形分析
```bash
verdi -f simv.f -ssf tb.fsdb
```

在波形中观察 time=200-700ps 区间（复位释放后）：

| 信号 | 预期行为 |
|------|----------|
| `PC` | 0 → 4 → 8 → 12 → 16 → ... → 24 (跳转) |
| `out_ins` (ID级指令) | ori → sw → lw → bne → ... |
| `id_ex_instr` (EX级) | NOP → ori → sw → lw → bne |
| `stall_ld` | 0 → 0 → 0 → 1 → 1 → 0 (停顿2-3拍) |
| `x5` 寄存器 | 0 → 0 → ... → 2000 (Cyc 6-7后) |
| `x2` 寄存器 | 0 → ... → 99 (最后) |
| `DM[500]` | 0 → 2000 (Cyc 4-5) |

## 可能的问题及解决方案

### 问题 A: PC 一直停留在 0x0C
**症状**: `PC stuck at 0000000C`

**原因分析**: 分支永远不能判定，PC 被锁住。

**检查点**:
1. `stall_ld` 是否在正确的周期（Cyc 3-5）为 1
2. `stall_ld` 是否在 Load 完成后释放（应该在 Cyc 6 变为 0）
3. `if_id_uses_rs2` 是否为 1（分支使用 rs2）

**修复建议**:
- 检查 `riscv.v` 中冒险检测条件是否遗漏了 BTYPE 指令的 rs1 检查
- 验证 `stall_ex_hzd` 和 `stall_mem_hzd` 的计算逻辑

### 问题 B: x2 最终值不是 0x63
**症状**: `x2 has unexpected value`

**原因分析**: 要么分支没有跳转，要么 ori x2 没有执行。

**检查点**:
1. `branch_taken_id` 是否在停顿释放后变为 1
2. `npc_b_tgt` 是否计算正确 (= PC + 12)
3. 在分支跳转后，后续指令是否被正确取回

**修复建议**:
- 检查分支的偏移量计算 (12 字节)
- 验证 `cmp_eq_id` 在停顿释放后的值

### 问题 C: 寄存器值不更新
**症状**: 所有寄存器保持为 0

**原因分析**: 指令未能正确推进或执行。

**检查点**:
1. 复位释放是否正确 (rst 应在 t=20ps 释放)
2. PC 是否在复位后开始推进
3. 指令是否被正确加载到各个流水线阶段

**修复建议**:
- 比较 hazard_A_sim.v 和 hazard_B_sim.v 的复位时序
- 确保 clk 初始值为 1，rst 高电平时间至少 20ps

## 文档参考

- [详细调试指南](DEBUG_HAZARD_B.md) - 流水线执行细节和冒险分析
- [机器码验证](HAZARD_B_ENCODING.md) - 指令编码正确性验证
- [Makefile 帮助](sim/Makefile.hazard) - `make -f Makefile.hazard help`

## 关键文件位置

| 文件 | 位置 |
|------|------|
| 改进的测试台 | [tb/hazard_B_sim.v](tb/hazard_B_sim.v) |
| 测试用例机器码 | [hex/hazard_B.hex](hex/hazard_B.hex) |
| RTL 设计 | [rtl/riscv.v](rtl/riscv.v) |
| Makefile | [sim/Makefile.hazard](sim/Makefile.hazard) |

## 快速命令速查

```bash
# 编译和运行 B 测试
cd p:/IC/rv2/sim
make -f Makefile.hazard b_debug

# 查看日志
cat hazard_b.log | tail -100

# 清理旧文件
make -f Makefile.hazard clean

# 运行 A 测试进行对比
make -f Makefile.hazard a

# 打开波形
verdi -ssf tb.fsdb
```

## 故障恢复清单

- [ ] 确认 hazard_B_sim.v 已更新（包含详细的 print 语句）
- [ ] 确认 Makefile.hazard 包含 b_debug 目标
- [ ] 重新编译 (clean 后重新 make)
- [ ] 检查 hexdump -C hex/hazard_B.hex 是否有 11 行指令
- [ ] 对比 hazard_A 和 hazard_B 的日志输出
- [ ] 在 Verdi 中打开 tb.fsdb 波形查看细节

