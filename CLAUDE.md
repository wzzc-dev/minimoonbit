# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MiniMoonBit (miniju) is an educational MoonBit compiler written in MoonBit itself. It compiles a subset of MoonBit to RISC-V assembly, JavaScript, WebAssembly, and LLVM IR through a multi-stage compilation pipeline. This is a teaching project for compiler construction courses.

## Architecture and Compilation Pipeline

The compiler follows these stages (defined in `src/top.mbt`):
1. **Lexing** (`src/lex/`) - Tokenization
2. **Parsing** (`src/parser/`) - AST construction
3. **Type Checking** (`src/typing/`) - Type inference and checking
4. **KNF Conversion** (`src/knf/`) - K-Normal Form (A-normalization)
5. **KNF Optimization** (`src/knf/`) - Local optimizations
6. **Closure Conversion** (`src/closure/`) - Closure handling
7. **SSA Construction** (`src/ssa/`) - Static Single Assignment form
8. **Code Generation** - Multiple backends (`src/riscv/`, `src/js/`, `src/wasm/`, `src/llvmir/`)

Key architectural components:
- `src/types/` - Core type definitions (Syntax, Type, Pattern enums)
- `src/bin/main.mbt` - CLI entry point with stage orchestration
- Stage-specific interpreters for educational debugging (`*_eval/` modules)
- Runtime support in `riscv_rt/` (Zig), `js_rt/`, `wasm_rt/`

## Development Commands

### Environment Setup (one-time)
```bash
git submodule update --init --recursive
cd riscv_rt && zig build && cd ..
cd ./libriscv/emulator && ./build.sh && cd ../..
cp ./libriscv/emulator/rvlinux ./
```

### Building and Running
```bash
# Compile and run single file (simple pipeline - KNF → Assembly)
./script/single_run_simple.sh <input.mbt>

# Compile and run single file (SSA pipeline)
./script/single_run.sh <input.mbt>

# Run all tests (simple pipeline)
./script/run_test_simple.sh

# Clean build artifacts
./clear.sh
```

### Direct Compiler Usage
```bash
# Basic compilation (simple pipeline)
moon run src/bin/main.mbt -- <input.mbt> -o out.s --simple

# SSA compilation
moon run -g src/bin/main.mbt -- <input.mbt> -o out.s --ssa

# Stage interpreters for debugging
moon run src/bin/main.mbt -- --knf-interpreter <input>
moon run src/bin/main.mbt -- --closure-interpreter <input>
moon run src/bin/main.mbt -- --ssa-interpreter <input>

# Different backends
moon run src/bin/main.mbt -- <input> --js      # JavaScript
moon run src/bin/main.mbt -- <input> --wasm    # WebAssembly
moon run src/bin/main.mbt -- <input> --llvmir  # LLVM IR
```

## Testing

Test cases are in `contest-2025-data/test_cases/mbt/` with expected outputs in `contest-2025-data/test_cases/ans/`. The test framework compiles to RISC-V, runs in the `rvlinux` emulator, and compares outputs.

## Code Organization

- Each compilation stage is a separate module with clear interfaces
- Multiple interpreter backends for educational debugging
- Cross-platform code generation support
- Type system supports primitives, tuples, arrays, functions, structs, and enums
- MoonBit package structure with `moon.mod.json` and `moon.pkg.json` files

## Build System

Uses MoonBit's native build system (`moon`) with assembly output configured in `minimoonbit.json`. The RISC-V runtime is built with Zig, and the project includes a RISC-V Linux emulator for testing.