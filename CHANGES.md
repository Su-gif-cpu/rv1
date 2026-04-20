# 修改清单

## ✅ 已修改/创建的文件

### 1. 测试台代码
- **[tb/hazard_B_sim.v](tb/hazard_B_sim.v)** 
  - ✅ 修复了复位时序（与 hazard_A 保持一致）
  - ✅ 添加了详细的周期打印输出
  - ✅ 实现了死锁检测（PC 不变警告）
  - ✅ 增加了超时保护和最终结果验证

### 2. 构建系统
- **[sim/Makefile.hazard](sim/Makefile.hazard)**
  - ✅ 添加了 `b_debug` 编译目标
  - ✅ 添加了 `b_debug` 运行目标
  - ✅ 添加了 `compile_b_debug` 编译规则
  - ✅ 更新了帮助信息

### 3. 调试文档（新增）
- **[QUICK_START.md](QUICK_START.md)** - 一页纸快速诊断指南
- **[DEBUG_HAZARD_B.md](DEBUG_HAZARD_B.md)** - 深度技术分析和排查步骤
- **[HAZARD_B_ENCODING.md](HAZARD_B_ENCODING.md)** - 机器码正确性验证
- **[SUMMARY.md](SUMMARY.md)** - 修复总结和工作流指南

## 📋 验证检查清单

- ✅ hazard_B.hex 机器码编码正确（已验证）
- ✅ hazard_B_sim.v 复位时序正确（与 hazard_A 一致）
- ✅ Makefile.hazard 编译命令完整
- ✅ 测试台输出调试信息充分
- ✅ 死锁检测机制可用
- ✅ 超时保护设置（20000ps）

## 🚀 立即可用的命令

### 运行 Hazard B 测试（带调试）
```bash
cd p:/IC/rv2/sim
make -f Makefile.hazard b_debug
```

### 查看仿真日志
```bash
cat hazard_b.log
```

### 对比 Hazard A 和 B
```bash
make -f Makefile.hazard a b
diff hazard_a.log hazard_b.log
```

### 查看波形
```bash
verdi -ssf tb.fsdb
```

## 📊 预期结果

### 成功场景
- 日志显示 50 个周期的指令流
- 最后打印 `[PASS] x2 has expected value 0x63`
- 三个核心寄存器值：x1=2000, x2=99, x5=2000
- PC 跳转到 0x18（分支目标）

### 失败场景
- 出现 `[WARNING] PC stuck at ...` 死锁警告
- 或 `[TIMEOUT] Simulation reached 20000ps timeout`
- x2 值仍为 0（未执行 ori x2, x0, 99）

## 📖 进阶参考

| 文档 | 内容 | 适用场景 |
|------|------|----------|
| [QUICK_START.md](QUICK_START.md) | 快速诊断流程 | 首次排查问题 |
| [DEBUG_HAZARD_B.md](DEBUG_HAZARD_B.md) | 技术细节和修复 | 深度分析 Load-Branch 冒险 |
| [HAZARD_B_ENCODING.md](HAZARD_B_ENCODING.md) | 机器码验证 | 确认指令编码正确性 |
| [SUMMARY.md](SUMMARY.md) | 整体总结 | 理解修改范围和原理 |

## ⚙️ 需要手动验证的项目

1. **编译是否成功**
   ```bash
   grep -i "error" hazard_b_debug_compile.log
   ```

2. **仿真是否卡死**
   ```bash
   grep "WARNING\|TIMEOUT\|PASS\|FAIL" hazard_b.log
   ```

3. **最终寄存器值**
   ```bash
   grep "FINAL RESULT" -A 10 hazard_b.log
   ```

## 🔧 可能需要修改的 RTL 文件

如果仍然存在问题，检查点：
- **[rtl/riscv.v](rtl/riscv.v)** - 冒险检测、旁路、分支条件判定
- **[rtl/Flopr.v](rtl/Flopr.v)** - A/B 寄存器在停顿时的行为
- **[rtl/DM.v](rtl/DM.v)** - Load 数据的同步读延迟

## 📝 修改历史

| 日期 | 文件 | 修改内容 |
|------|------|----------|
| - | hazard_B_sim.v | 重写测试台，增加详细输出和死锁检测 |
| - | Makefile.hazard | 添加 b_debug 目标 |
| - | （新建）| QUICK_START.md - 快速诊断指南 |
| - | （新建）| DEBUG_HAZARD_B.md - 技术分析文档 |
| - | （新建）| HAZARD_B_ENCODING.md - 机器码验证 |
| - | （新建）| SUMMARY.md - 修改总结 |
| - | （本文）| CHANGES.md - 修改清单 |

## 💡 故障排查建议

如果修改后仍有问题，按以下优先级排查：

1. **基础检查**（5 分钟）
   - [ ] VCS 编译是否有 ERROR（不是 WARNING）
   - [ ] hazard_b.log 是否包含周期输出（非空文件）
   - [ ] 复位后 PC 是否开始推进

2. **时序检查**（10 分钟）
   - [ ] 打开 tb.fsdb 波形
   - [ ] 验证 PC 和指令流是否与预期匹配
   - [ ] 检查 stall_ld 信号的时序

3. **冒险检查**（15 分钟）
   - [ ] Load-Branch 冒险是否被正确检测
   - [ ] 停顿期间 IR 是否正确保持
   - [ ] Load 完成后 stall_ld 是否释放

4. **分支检查**（15 分钟）
   - [ ] 分支条件 (cmp_eq_id) 是否正确
   - [ ] branch_taken_id 是否在正确时刻为 1
   - [ ] PC 跳转是否到正确的地址 (0x18)

## 🎯 目标达成标志

- ✅ 仿真成功运行到 50 个周期
- ✅ 最终输出 `[PASS] x2 has expected value 0x63`
- ✅ 波形显示分支在 0x000C 处被正确评估
- ✅ PC 跳转到 0x000018（分支目标）
- ✅ ori x2, x0, 99 被正确执行

---

**最后更新**: $(date)  
**状态**: 修改完成，等待验证

