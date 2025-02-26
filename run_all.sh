#!/bin/bash


# 找到所有 .mbt 结尾的文件并循环处理
for MBT_FILE in test/test_src/*.mbt; do
  moon run -g src/bin/main.mbt -- $MBT_FILE -o out.s && zig build-exe -target riscv64-linux -femit-bin=test-exe-file ./out.s ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 && ./rvlinux -n test-exe-file
done

echo "All files processed."
