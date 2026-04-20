#!/bin/bash
# 快速验证脚本

echo "========================================"
echo "Hazard B 测试用例验证"
echo "========================================"
echo ""

# 检查 hex 文件
echo "1. 检查 hex 文件内容："
if [ -f "../hex/hazard_B.hex" ]; then
    echo "   hazard_B.hex 存在"
    echo "   内容："
    cat ../hex/hazard_B.hex | head -10
else
    echo "   ERROR: hazard_B.hex 不存在"
fi

echo ""
echo "2. 检查测试台文件："
if [ -f "../tb/hazard_B_sim.v" ]; then
    echo "   hazard_B_sim.v 存在"
    echo "   行数: $(wc -l < ../tb/hazard_B_sim.v)"
else
    echo "   ERROR: hazard_B_sim.v 不存在"
fi

echo ""
echo "3. 检查编译文件列表："
if [ -f "files_B.f" ]; then
    echo "   files_B.f 内容:"
    cat files_B.f
else
    echo "   ERROR: files_B.f 不存在"
fi

echo ""
echo "========================================"
echo "建议运行："
echo "  cd p:/IC/rv2/sim"
echo "  make -f Makefile.hazard b_debug"
echo ""
echo "然后查看 hazard_b.log 文件"
echo "========================================"
