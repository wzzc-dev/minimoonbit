# CODEBUDDY.md

This file contains information for CodeBuddy Code to operate effectively in this repository.

## Project Overview

This is **miniju** - a MoonBit compiler implementation that compiles MoonBit source code to RISC-V assembly. The compiler follows a multi-stage compilation pipeline: lexing → parsing → type checking → KNF (K-Normal Form) → closure conversion → SSA (Static Single Assignment) → assembly generation.

## Development Commands

### Environment Setup
```bash
# Initialize submodules and build dependencies
git submodule update --init --recursive

# Build RISC-V runtime
cd riscv_rt
zig build
cd ..

# Build RISC-V Linux emulator  
cd ./libriscv/emulator
./build.sh
cd ../..
cp ./libriscv/emulator/rvlinux ./

# Alternative setup scripts
./build_riscvrt.sh    # Build RISC-V runtime only
./build_rvlinux.sh    # Build RISC-V emulator only
```

### Compilation and Testing
```bash
# Compile and run a single file by simple
./script/single_run_simple.sh contest-2025-data/test_cases/mbt/conv_pool.mbt

# Compile and run a single file by ssa
./script/single_run.sh contest-2025-data/test_cases/mbt/conv_pool.mbt

# Run all tests
./script/run_test_simple.sh

# Clean build artifacts
./clean.sh
```

### Compiler Usage
```bash
# Basic compilation (generates RISC-V assembly)
moon run src/bin/main.mbt -- <input.mbt> -o out.s --simple

# Run with interpreters
moon run src/bin/main.mbt -- --knf-interpreter <input>
moon run src/bin/main.mbt -- --closure-interpreter <input>
moon run src/bin/main.mbt -- --ssa-interpreter <input>

# Generate SSA and compile to RISC-V
moon run -g src/bin/main.mbt -- <input> -o out.s
# 编译运行经过 SSA IR 转换生成汇编
./script/single_run.sh contest-2025-data/test_cases/mbt/adder.mbt
```

### Backend Options
```bash
# JavaScript backend
moon run src/bin/main.mbt -- <input> --js

# WebAssembly backend  
moon run src/bin/main.mbt -- <input> --wasm

# LLVM IR backend
moon run src/bin/main.mbt -- <input> --llvmir
```

## Architecture Overview

### Compilation Pipeline
The compiler implements a staged compilation pipeline with the following transformations:

1. **Lexing** (`src/lex/`) - Tokenizes source code
2. **Parsing** (`src/parser/`) - Builds AST from tokens
3. **Type Checking** (`src/typing/`) - Performs type inference and checking
4. **KNF Conversion** (`src/knf/`) - Converts to K-Normal Form (A-normalization)
5. **Closure Conversion** (`src/closure/`) - Handles closure capture and conversion
6. **SSA Construction** (`src/ssa/`) - Builds Static Single Assignment form
7. **Code Generation** (`src/riscv/`, `src/js/`, `src/wasm/`) - Emits target code

### Key Components

- **`src/bin/main.mbt`** - Main compiler driver with command-line interface
- **`src/top.mbt`** - Defines compilation stages and pipeline orchestration
- **`src/types/`** - Core type system definitions (Syntax, Type, Pattern enums)
- **Backend modules**: `src/riscv/`, `src/js/`, `src/wasm/`, `src/llvmir/`
- **Interpreters**: `src/knf_eval/`, `src/closure_eval/`, `src/ssa_eval/`

### Type System
The compiler uses a rich type system supporting:
- Primitive types (Int, Double, Bool, Unit)
- Composite types (Tuple, Array, Functions)
- User-defined types (Struct, Enum)
- Type variables for inference

### Runtime Support
- **`riscv_rt/`** - RISC-V runtime library (built with Zig)
- **`libriscv/`** - RISC-V emulator for testing
- **`js_rt/`**, **`wasm_rt/`** - JavaScript and WebAssembly runtime support

## Project Structure

```
src/
├── bin/main.mbt          # Main compiler entry point
├── top.mbt              # Compilation pipeline orchestration  
├── lex/                 # Lexical analysis
├── parser/              # Syntax analysis
├── typing/              # Type checking and inference
├── knf/                 # K-Normal Form transformation
├── closure/             # Closure conversion
├── ssa/                 # SSA construction
├── riscv/               # RISC-V code generation
├── js/                  # JavaScript backend
├── wasm/                # WebAssembly backend
├── llvmir/              # LLVM IR backend
├── *_eval/              # Stage-specific interpreters
└── util/                # Common utilities

contest-2025-data/       # Test cases and expected outputs
riscv_rt/                # RISC-V runtime (Zig)
libriscv/                # RISC-V emulator
```

## Testing

The test suite uses `.mbt` files in `contest-2025-data/test_cases/mbt/` with expected outputs in `contest-2025-data/test_cases/ans/`. Tests compile to RISC-V assembly, execute in the emulator, and compare outputs.

## Build System

Uses MoonBit's build system (`moon`) with package definitions in `moon.mod.json` and `moon.pkg.json` files. The `minimoonbit.json` configures assembly emission.