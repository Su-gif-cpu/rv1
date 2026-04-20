# 🔧 IR 设计修复指南

## ✅ 已完成的修改

### 1. IR.v 修复
```verilog
// ❌ 错误（您的修改）
assign out_ins = in_ins;

// ✅ 正确（已修复）
always @(posedge clk or posedge rst) begin
    if (rst) begin
        out_ins <= 32'h0000_0013;  // NOP
    end else if (IRWrite) begin
        out_ins <= in_ins;
    end
end
```

### 2. riscv.v 修复
```verilog
// ❌ 错误（缺少 rst）
IR U_IR (
    .clk(clk), .IRWrite(ir_we), .in_ins(ir_din), .out_ins(out_ins)
);

// ✅ 正确（添加 rst）
IR U_IR (
    .clk(clk), .rst(rst), .IRWrite(ir_we), .in_ins(ir_din), .out_ins(out_ins)
);
```

---

## 为什么这样修复？

### 同步 IM + 组合 IR 的问题

当您将 IM 改为同步读时：
```verilog
always @(posedge clk) begin
    in_ins <= memory[addr];  // ← 延迟一拍
end
```

如果 IR 仍为组合逻辑：
```verilog
assign out_ins = in_ins;  // ← 直通，丧失缓存
```

**结果**：流水线在停顿时信号不稳定

### 同步 IM + 时序 IR 的解决方案

正确的设计：
```verilog
// IM 同步读
always @(posedge clk) begin
    in_ins <= memory[addr];  // Cyc N → N+1
end

// IR 缓存
always @(posedge clk) begin
    if (IRWrite) 
        out_ins <= in_ins;  // Cyc N+1 → N+2
end
```

**效果**：
- Cyc N: PC 更新，IM 开始读取
- Cyc N+1: IM 输出有效，IR 缓存
- Cyc N+2: IR 输出有效，ID 级获得指令
- **停顿时**：IR 被锁定，ID 级指令稳定 ✅

---

## 修复后应该看到什么

### 仿真输出变化

**修复前（死锁）**:
```
[WARNING] PC stuck at 0000000C, possible deadlock
[TIMEOUT] Simulation reached 20000ps timeout
[FAIL] x2 has unexpected value
```

**修复后（正常）**:
```
[T=100] Cyc=0] PC=00000000 | IR(ID)=00000000 (NOP)   | x5=00000000 x2=00000000
[T=150] Cyc=1] PC=00000004 | IR(ID)=7d006093 (ori)   | x5=00000000 x2=00000000
[T=200] Cyc=2] PC=00000008 | IR(ID)=0010a023 (sw)    | x5=00000000 x2=00000000
     [MEM] SW to addr=500, data=00000000
[T=250] Cyc=3] PC=0000000C | IR(ID)=0000a283 (lw)    | x5=00000000 x2=00000000
[T=300] Cyc=4] PC=0000000C | IR(ID)=0000a283 (lw)    | x5=00000000 x2=00000000
     停顿：stall_ld=1，IR 锁定为 lw，PC 停止
[T=350] Cyc=5] PC=0000000C | IR(ID)=0000a283 (lw)    | x5=00000000 x2=00000000
[T=400] Cyc=6] PC=0000000C | IR(ID)=00029663 (bne)   | x5=000007d0 x2=00000000
     停顿释放，IR 更新，x5 已通过旁路获得值
[T=450] Cyc=7] PC=00000018 | IR(ID)=06306113 (ori)   | x5=000007d0 x2=00000000
     分支跳转成功，PC 更新到 0x18

...（继续执行）...

[FINAL RESULT]
  x1=000007d0
  x2=00000063      ← 正确值 (99)
  x5=000007d0
  PC=0000001c
[PASS] x2 has expected value 0x63
```

### 波形信号变化

在 Verdi 中观察 `out_ins` 信号：

**修复前（组合逻辑）**:
```
Cyc 3: out_ins = lw   (当前)
Cyc 4: out_ins = ???  (不稳定，跟随 in_ins)
Cyc 5: out_ins = bne? (混乱)
```

**修复后（时序逻辑）**:
```
Cyc 3: out_ins = lw   (稳定，上一拍 load 进来)
Cyc 4: out_ins = lw   (锁定，停顿时保持)
Cyc 5: out_ins = lw   (锁定，停顿持续)
Cyc 6: out_ins = bne  (在 Cyc 6 的时钟沿更新)
```

---

## 立即验证修复

### Step 1: 清理旧编译文件
```bash
cd p:/IC/rv2/sim
make -f Makefile.hazard clean
```

### Step 2: 重新编译和运行
```bash
make -f Makefile.hazard b_debug
```

### Step 3: 检查结果
```bash
grep "PASS\|FAIL" hazard_b.log
tail -20 hazard_b.log
```

**预期结果**: `[PASS] x2 has expected value 0x63`

---

## 如果仍有问题

### 检查清单

- [ ] IR.v 已改为时序逻辑（有 `output reg` 和 `always @(posedge clk)`)
- [ ] IR.v 有 rst 输入参数
- [ ] riscv.v 中 U_IR 实例化包含 `.rst(rst)`
- [ ] Makefile.hazard clean 已清理旧文件
- [ ] VCS 编译无 ERROR（WARNING 可忽略）

### 调试步骤

如果仍未通过，检查以下信号：

1. **IR 的输出**:
   ```
   在 t=200-500ps 之间，观察 out_ins
   应该在 t=250-350ps 期间锁定为 lw 指令（0x0000a283）
   ```

2. **停顿信号**:
   ```
   stall_ld 应该在 Cyc 3-5（t=200-350ps）为 1
   ```

3. **分支判定**:
   ```
   branch_taken_id 应该在 Cyc 7（t=400-450ps）为 1
   ```

4. **PC 更新**:
   ```
   PC 应该从 0x0C 在 Cyc 8 跳到 0x18
   ```

---

## 核心概念总结

### ✅ 正确的设计模式（同步 IM）

```verilog
// IM：同步读，延迟一拍
always @(posedge clk) begin
    in_ins <= memory[addr];  // Cyc N → N+1
end

// IR：时序缓冲，停顿时锁定
always @(posedge clk) begin
    if (IRWrite) begin
        out_ins <= in_ins;   // 只在写使能时更新
    end
    // 否则保持，停顿时锁定
end
```

### ❌ 错误的设计模式

```verilog
// IM：同步读，延迟一拍
always @(posedge clk) begin
    in_ins <= memory[addr];
end

// IR：组合逻辑，失去缓冲 ❌
assign out_ins = in_ins;  // 停顿时无法锁定
```

---

## 为什么原始设计用组合 IM + 时序 IR?

### 原始架构（组合 IM + 时序 IR）
```
Cyc N:
  PC 更新 → IM 立即输出（组合）
  in_ins 有效 → IR 缓冲（时序）
  同一拍内完成，无延迟
```

### 新架构（同步 IM + 时序 IR）
```
Cyc N:   PC 更新
Cyc N+1: in_ins 有效（IM 同步输出）
Cyc N+2: out_ins 有效（IR 缓冲）

相比组合 IM 多延迟一拍，但必须保持 IR 为时序逻辑
```

---

## 验证成功的标志

✅ **修复成功的指标**:
- Hazard B 仿真不卡死
- x2 最终值为 0x63（99 in decimal）
- PC 从 0x0C 跳到 0x18
- 没有 `[WARNING]` 或 `[TIMEOUT]` 消息
- 日志显示 `[PASS]`

---

**立即重新编译并测试！** 🚀

```bash
cd p:/IC/rv2/sim
make -f Makefile.hazard clean
make -f Makefile.hazard b_debug
grep "PASS" hazard_b.log && echo "✅ 修复成功！" || echo "❌ 仍有问题，检查波形"
```

