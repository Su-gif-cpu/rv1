# 📌 快速参考：为什么 IR 必须是时序逻辑

## 一句话总结
**同步 IM 需要时序 IR 来缓冲指令，否则停顿时流水线信号不稳定，导致死锁。**

---

## 对比表

| 因素 | 组合 IM | 同步 IM |
|------|--------|--------|
| **读取延迟** | 0 拍 | 1 拍 |
| **IR 应该是** | ✅ 可组合可时序 | ❌ **必须时序** |
| **停顿时指令** | ✅ 稳定 | ❌ **不稳定**（如果 IR 是组合） |
| **流水线影响** | 无 | 有（多 1 拍延迟） |

---

## 三个关键时序

### 原始设计（✅ 正确）：组合 IM + 时序 IR

```
Cyc N:
  ┌─ PC 更新
  ├─ IM 组合输出 → in_ins（立即有效）
  ├─ IR 时序缓冲 → out_ins <= in_ins（下一拍生效）
  └─ 同一拍完成，流水线顺畅
```

### 您的修改（❌ 错误）：同步 IM + 组合 IR

```
Cyc N: PC 更新
       in_ins 未准备好（IM 同步延迟）
       out_ins = in_ins（组合直通，跟随 in_ins 变化）
       ❌ 信号不稳定

Cyc N+1: in_ins 才有效（来自 IM）
         out_ins 跟随更新
         ❌ 指令推迟一拍
```

### 正确的修改（✅ 正确）：同步 IM + 时序 IR

```
Cyc N:   PC 更新
Cyc N+1: IM 输出 → in_ins
         IR 缓冲 → out_ins <= in_ins（缓冲）
Cyc N+2: out_ins 有效，流水线继续

停顿时：
  IRWrite = 0
  out_ins 被锁定（时序逻辑，不更新）
  ✅ ID 级指令稳定
```

---

## 死锁的根本原因

### Hazard B 在您的修改下为什么死锁

```
Cyc 3: stall_ld = 1（Load-Branch 冒险触发）
       ├─ ir_we = 0（IR 不更新）
       ├─ ❌ 但 IR 改成了组合逻辑
       ├─ out_ins = in_ins（直通）
       ├─ in_ins 来自同步 IM，还在变化中
       └─ out_ins 不稳定 → 分支条件评估错误 ❌

Cyc 4-7: stall_ld 无法释放
         PC 被永久锁定
         ❌ 死锁
```

### 修复后为什么能工作

```
Cyc 3: stall_ld = 1（Load-Branch 冒险触发）
       ├─ ir_we = 0（IR 不更新）
       ├─ ✅ IR 是时序逻辑
       ├─ out_ins 保持上一拍的值（lw 指令）
       ├─ ID 级指令稳定 ✅
       └─ 分支条件评估正确

Cyc 4-5: 停顿继续
         out_ins 被锁定为 lw
         ✅ 流水线稳定

Cyc 6: stall_ld 释放
       Load 数据已可用（x5=2000）
       IR 更新为 bne

Cyc 7: branch_taken_id = 1
       PC 跳转到 0x18 ✅
```

---

## 三个必须理解的点

### 1️⃣ IM 的同步读延迟

```verilog
同步 IM 的实现：
always @(posedge clk) begin
    RD <= memory[addr];  // 读在时钟沿，输出延迟一拍
end

结果：
  t=0ns: addr=0x00
  t=0-100ns: 内部异步取址
  t=100ns: RD 在时钟上升沿更新 → memory[0x00] 的值
          但 addr 已经变成 0x04 了
         RD 仍然是旧值，要到下一拍才是 addr=0x04 的值
```

### 2️⃣ IR 的缓冲作用

```verilog
时序 IR 的实现：
always @(posedge clk) begin
    if (IRWrite)
        out_ins <= in_ins;  // 下一拍才生效
end

结果：
  缓冲了一拍，补偿了同步 IM 的延迟
  停顿时（IRWrite=0）保持不变，锁定指令
```

### 3️⃣ 停顿时的信号稳定性

```
停顿（stall_ld=1）时：
  ├─ PC 不更新 → IM 持续读同一个地址
  ├─ IM 输出可能有毛刺（同步切换）
  ├─ ✅ 时序 IR 保持稳定，不受毛刺影响
  └─ ID 级指令锁定，冒险检测结果可靠

无停顿（stall_ld=0）时：
  ├─ PC 推进 → IM 读新地址
  ├─ IM 下一拍输出新指令
  ├─ ✅ IR 下一个时钟沿捕获新指令
  └─ 流水线继续推进
```

---

## 修复清单

- [ ] IR.v：恢复 `output reg` 和 `always @(posedge clk)`
- [ ] IR.v：添加 `rst` 输入和复位逻辑
- [ ] IR.v：恢复 `if (IRWrite)` 条件判断
- [ ] riscv.v：U_IR 实例化添加 `.rst(rst)`
- [ ] sim：`make clean` 删除旧编译
- [ ] sim：`make b_debug` 重新编译和运行
- [ ] 检查：hazard_b.log 显示 `[PASS]`

---

## 原文件 vs 修复文件

### IR.v

**错误**（您的版本）：
```verilog
assign out_ins = in_ins;  // ← 组合逻辑，IRWrite 无效
```

**正确**（修复后）：
```verilog
output reg [31:0] out_ins;  // ← 时序逻辑

always @(posedge clk or posedge rst) begin
    if (rst) out_ins <= 32'h0000_0013;
    else if (IRWrite) out_ins <= in_ins;  // ← 只在写使能时更新
end
```

### riscv.v

**错误**（缺少 rst）：
```verilog
IR U_IR (.clk(clk), .IRWrite(ir_we), .in_ins(ir_din), .out_ins(out_ins));
```

**正确**（添加 rst）：
```verilog
IR U_IR (.clk(clk), .rst(rst), .IRWrite(ir_we), .in_ins(ir_din), .out_ins(out_ins));
```

---

## 最后验证

运行这个命令：
```bash
cd p:/IC/rv2/sim
make -f Makefile.hazard clean b_debug && \
grep -E "PASS|FAIL" hazard_b.log
```

**预期输出**:
```
[PASS] x2 has expected value 0x63
```

✅ 成功！您的 CPU 现在支持同步 IM/DM 和 Load-Branch 冒险处理。

---

## 为什么这个修复很重要？

1. **流水线正确性** - 停顿时指令不能跟随 IM 输出变化
2. **时序一致性** - 同步 IM 需要时序 IR 补偿延迟
3. **冒险处理** - Load-Branch 冒险需要稳定的 ID 级指令
4. **可扩展性** - 为后续 SRAM 替换做准备

这个修改虽然看似简单（一行代码变十几行），但对于流水线的正确性至关重要！

