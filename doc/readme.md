# doc


• RISC-V 相关测试：

```bash
moon run src/bin/main.mbt -- <input> -o <output>
zig build-exe -target riscv64-linux -femit-bin=<exe_file> \
 <out_file> /runtime/riscv_rt/zig-out/lib/libmincaml.a \
 -O Debug -fno-strip -mcpu=baseline_rv64
rvlinux -n <exe_file>
```

• WASM 后端：

```bash
moon run src/bin/main.mbt -- <input> -o <output> --wasm
wasm-tools parse <output> -o <output>.wasm
node runner.js <output>.wasm
```
输出文件需要是一个 WAT 格式的完整 WASM 模块，可以在 Node.js 22.8.0 版本下运行。

• JS 后端：
```bash
moon run src/bin/main.mbt -- <input> -o <output> --js
node runner.js <output>
```
输出文件需要是一个 JS 文件，可以在 Node.js 22.8.0 和提供了给定的函数实现的前提下运
行。