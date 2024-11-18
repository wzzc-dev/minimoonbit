#!/bin/bash

# 定义输出文件的前缀
OUT_PREFIX="out"

# 找到所有 .mbt 结尾的文件并循环处理
for MBT_FILE in test/test_src/*.mbt; do
  # 提取文件的基础名称（不带路径和扩展名），用于匹配 .ans 文件
  BASE_NAME=$(basename "$MBT_FILE" .mbt)
  ANS_FILE="test/test_src/$BASE_NAME.ans"
  OUTPUT_FILE="$OUT_PREFIX.s"

  echo "Processing $MBT_FILE..."
  
  # 运行 moonc 编译器并生成汇编文件
  moon run -g src/bin/main.mbt -- "$MBT_FILE" -o "$OUTPUT_FILE" &&
  zig build-exe -target riscv64-linux -femit-bin=test-exe-file "$OUTPUT_FILE" ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 &&
  
  # 运行模拟器并将输出提取到临时文件（只取 >>> 前内容）
  ./rvlinux -n test-exe-file | sed '/>>>/q' > output.txt

  # 确保输出文件以换行符结尾
  sed -i -e '$a\' output.txt
  
  # 检查对应的 .ans 文件是否存在
  if [[ -f "$ANS_FILE" ]]; then
    # 比较运行结果和 .ans 文件的内容
    if diff -q --strip-trailing-cr output.txt "$ANS_FILE" > /dev/null; then
      echo "Test $MBT_FILE passed: Output matches $ANS_FILE"
    else
      echo "Test $MBT_FILE failed: Output differs from $ANS_FILE"
      echo "Differences:"
      diff --strip-trailing-cr output.txt "$ANS_FILE"
    fi
  else
    echo "Warning: No answer file found for $MBT_FILE. Expected at $ANS_FILE"
  fi
  
  # 清理临时文件
  rm -f output.txt test-exe-file "$OUTPUT_FILE"
done

echo "All files processed."
