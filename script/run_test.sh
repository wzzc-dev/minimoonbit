#!/bin/bash

# 定义输出文件的前缀
OUT_PREFIX="out"

# 初始化通过测试计数器和成功测试列表
PASSED_COUNT=0
PASSED_TESTS=()
FAILED_TESTS=()
# 找到所有 .mbt 结尾的文件并循环处理
for MBT_FILE in contest-2025-data/test_cases/mbt/*.mbt; do
  # 提取文件的基础名称（不带路径和扩展名），用于匹配 .ans 文件
  BASE_NAME=$(basename "$MBT_FILE" .mbt)
  ANS_FILE="contest-2025-data/test_cases/ans/$BASE_NAME.ans"
  OUTPUT_FILE="$OUT_PREFIX.s"

  echo "Processing $MBT_FILE..."
  
  # 运行 moonc 编译器并生成汇编文件
  moon run -g src/bin/main.mbt -- "$MBT_FILE" -o "$OUTPUT_FILE" --ssa &&
  zig build-exe -target riscv64-linux -femit-bin=test-exe-file "$OUTPUT_FILE" ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 &&
  
  # 运行模拟器并将输出提取到临时文件（只取 >>> 前内容）
  ./rvlinux -n test-exe-file | sed '/>>>/q' > output.txt

  # 检查对应的 .ans 文件是否存在
  if [[ -f "$ANS_FILE" ]]; then
    # 比较运行结果和 .ans 文件的内容（忽略行尾差异和 ans 文件末尾换行符）
    if cmp -s <(tr -d '\r' < output.txt) <(tr -d '\r' < "$ANS_FILE" | sed '$ { /^$/ d; }' | perl -pe 'chomp if eof'); then
      echo "Test $MBT_FILE passed: Output matches $ANS_FILE"
      # 增加通过测试计数器
      ((PASSED_COUNT++))
      # 添加到成功测试列表
      PASSED_TESTS+=("$BASE_NAME")
    else
      echo "Test $MBT_FILE failed: Output differs from $ANS_FILE"
      echo "Differences:"
      diff --strip-trailing-cr output.txt "$ANS_FILE"
      # 添加到失败测试列表
      FAILED_TESTS+=("$BASE_NAME")
    fi
  else
    echo "Warning: No answer file found for $MBT_FILE. Expected at $ANS_FILE"
  fi
  
  # 清理临时文件
  rm -f output.txt test-exe-file "$OUTPUT_FILE"
done

# 输出通过测试的总数
echo "All files processed. Total passed tests: $PASSED_COUNT"

# 输出所有成功的测试用例
if [ $PASSED_COUNT -gt 0 ]; then
  echo "Successful test cases:"
  for test in "${PASSED_TESTS[@]}"; do
    echo "  - $test"
  done
  echo "Failed test cases:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
else
  echo "No tests passed."
fi
