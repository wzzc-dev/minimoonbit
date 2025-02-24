#!/bin/bash

moon run -g src/bin/main.mbt -- $1 -o out.s && zig build-exe -target riscv64-linux -femit-bin=test-exe-file ./out.s ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 && ./rvlinux -n test-exe-file
