# 环境
moon 0.1.20250513 (5aa200a 2025-05-13)

git submodule update --init --recursive

cd riscv_rt
zig build

zig 0.13
./libriscv/emulator/build.sh

