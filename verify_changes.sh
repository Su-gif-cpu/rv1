#!/bin/bash
# 验证 Hazard B 修改是否完整

echo "=================================================="
echo "Hazard B 修改完整性检查"
echo "=================================================="
echo ""

PASS=0
FAIL=0

check_file() {
    local file=$1
    local desc=$2
    if [ -f "$file" ]; then
        echo "✅ $desc: $file"
        PASS=$((PASS+1))
    else
        echo "❌ $desc: $file (不存在)"
        FAIL=$((FAIL+1))
    fi
}

check_content() {
    local file=$1
    local pattern=$2
    local desc=$3
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc (未找到)"
        FAIL=$((FAIL+1))
    fi
}

echo "1. 核心文件检查："
check_file "../hex/hazard_B.hex" "机器码文件"
check_file "../tb/hazard_B_sim.v" "测试台文件"
check_file "files_B.f" "文件列表"
check_file "Makefile.hazard" "Makefile"

echo ""
echo "2. 测试台修改检查："
check_content "../tb/hazard_B_sim.v" "print_cycle_info" "周期打印函数"
check_content "../tb/hazard_B_sim.v" "print_final_state" "最终状态函数"
check_content "../tb/hazard_B_sim.v" "\[WARNING\].*deadlock" "死锁检测"
check_content "../tb/hazard_B_sim.v" "clk = 1" "时钟初始化为1"
check_content "../tb/hazard_B_sim.v" "#20 rst = 0" "复位持续20ps"

echo ""
echo "3. Makefile 修改检查："
check_content "Makefile.hazard" "b_debug:" "b_debug 目标"
check_content "Makefile.hazard" "compile_b_debug:" "compile_b_debug 规则"
check_content "Makefile.hazard" "run_b_debug:" "run_b_debug 规则"

echo ""
echo "4. 文档文件检查："
check_file "../QUICK_START.md" "快速开始指南"
check_file "../DEBUG_HAZARD_B.md" "调试指南"
check_file "../HAZARD_B_ENCODING.md" "机器码验证"
check_file "../SUMMARY.md" "修改总结"
check_file "../CHANGES.md" "修改清单"

echo ""
echo "5. 文件列表完整性检查:"
check_content "files_B.f" "hazard_B_sim.v" "测试台在files_B.f中"
check_content "files_B.f" "riscv.v" "设计文件在files_B.f中"

echo ""
echo "=================================================="
echo "检查结果: ✅ 通过 $PASS   ❌ 失败 $FAIL"
echo "=================================================="

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "✅ 所有检查通过! 可以开始运行测试:"
    echo ""
    echo "  cd $(pwd)"
    echo "  make -f Makefile.hazard b_debug"
    echo ""
    exit 0
else
    echo ""
    echo "❌ 有 $FAIL 项检查失败，请先进行修复"
    exit 1
fi
