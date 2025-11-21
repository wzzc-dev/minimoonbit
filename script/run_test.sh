#!/bin/bash

# 定义输出文件的前缀
OUT_PREFIX="out"

# 初始化通过测试计数器和成功测试列表
PASSED_COUNT=0
FAILED_COUNT=0
PASSED_TESTS=()
FAILED_TESTS=()

# 定义所有包含测试用例的目录（只包含有 .ans 文件的目录）
TEST_DIRS=("codegen" "optional-asm" "optional-enum-only" "optional-generic-only" "optional-mixed" "optional-struct-only" "size" "speed" "strenth")

# 遍历所有测试目录
for TEST_DIR in "${TEST_DIRS[@]}"; do
  FULL_PATH="contest-2025-data/test_cases/$TEST_DIR"

  # 检查目录是否存在
  if [[ ! -d "$FULL_PATH" ]]; then
    echo "Warning: Directory $FULL_PATH does not exist, skipping..."
    continue
  fi

  echo "Processing directory: $TEST_DIR"

  # 找到当前目录中所有 .mbt 结尾的文件并循环处理
  for MBT_FILE in "$FULL_PATH"/*.mbt; do
    # 检查是否有 .mbt 文件（避免当目录为空时的错误）
    if [[ ! -f "$MBT_FILE" ]]; then
      echo "No .mbt files found in $FULL_PATH, skipping..."
      break
    fi

    # 提取文件的基础名称（不带路径和扩展名），用于匹配 .ans 文件
    BASE_NAME=$(basename "$MBT_FILE" .mbt)
    ANS_FILE="$FULL_PATH/$BASE_NAME.ans"
    OUTPUT_FILE="$OUT_PREFIX.s"

    echo "Processing $TEST_DIR/$BASE_NAME.mbt..."

    # 运行 moonc 编译器并生成汇编文件
    moon run -g src/bin/main.mbt -- "$MBT_FILE" -o "$OUTPUT_FILE" --ssa &&
    zig build-exe -target riscv64-linux -femit-bin=test-exe-file "$OUTPUT_FILE" ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 &&

    # 运行模拟器并将输出提取到临时文件（只取 >>> 前内容）
    ./rvlinux -n test-exe-file | sed '/>>>/q' > output.txt

    # 检查对应的 .ans 文件是否存在
    if [[ -f "$ANS_FILE" ]]; then
      # 比较运行结果和 .ans 文件的内容（忽略行尾差异和 ans 文件末尾换行符）
      if cmp -s \
          <(tr -d '\r' < output.txt | sed '$ { /^$/ d; }' | perl -pe 'chomp if eof') \
          <(tr -d '\r' < "$ANS_FILE" | sed '$ { /^$/ d; }' | perl -pe 'chomp if eof'); then
        echo "Test $TEST_DIR/$BASE_NAME passed: Output matches"
        # 增加通过测试计数器
        ((PASSED_COUNT++))
        # 添加到成功测试列表（包含目录名）
        PASSED_TESTS+=("$TEST_DIR/$BASE_NAME")
      else
        echo "Test $TEST_DIR/$BASE_NAME failed: Output differs from $ANS_FILE"
        echo "Differences:"
        diff --strip-trailing-cr output.txt "$ANS_FILE"
        # 增加失败测试计数器
        ((FAILED_COUNT++))
        # 添加到失败测试列表（包含目录名）
        FAILED_TESTS+=("$TEST_DIR/$BASE_NAME")
      fi
    else
      echo "Warning: No answer file found for $MBT_FILE. Expected at $ANS_FILE"
    fi

    # 清理临时文件
    rm -f output.txt test-exe-file "$OUTPUT_FILE"
  done
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

echo "passed tests: $PASSED_COUNT"
echo "failed tests: $FAILED_COUNT"
