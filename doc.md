# miniju - MiniMoonBit Compiler

## Project Overview

miniju is a MoonBit compiler implementation that compiles MoonBit source code to RISC-V assembly and other targets. This is an educational compiler project called "MiniMoonBit in MoonBit" designed as a teaching tool for the "Program Language Theory Design and Implementation" course. The compiler is built using MoonBit language itself and follows a multi-stage compilation pipeline with stages including lexing, parsing, type checking, KNF (K-Normal Form), closure conversion, SSA (Static Single Assignment), and code generation.

The project is based on the MoonBit language and was developed as part of the curriculum for the "Modern Programming Concepts" course, which teaches language implementation techniques using a subset of MoonBit as the teaching example.

## Architecture Overview

### Compilation Pipeline
The compiler implements the following transformation pipeline:

1. **Lexing** (`src/lex/`) - Tokenizes MoonBit source code
2. **Parsing** (`src/parser/`) - Builds Abstract Syntax Tree (AST) from tokens
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
- **Runtime support**: RISC-V runtime built with Zig (`riscv_rt/`), RISC-V emulator (`libriscv/`), `js_rt/`**, **`wasm_rt/`** - JavaScript and WebAssembly runtime support

### Type System
The compiler uses a rich type system supporting:
- Primitive types (Int, Double, Bool, Unit)
- Composite types (Tuple, Array, Functions)
- User-defined types (Struct, Enum)
- Type variables for inference

### Project Structure
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
js_rt/                   # JavaScript runtime
wasm_rt/                 # WebAssembly runtime
script/                  # Build and test scripts
```

## Building and Running

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
# Compile and run a single file using simple pipeline
./script/single_run_simple.sh contest-2025-data/test_cases/mbt/conv_pool.mbt

# Compile and run a single file using SSA pipeline
./script/single_run.sh contest-2025-data/test_cases/mbt/conv_pool.mbt

# Run all tests
./script/run_test_simple.sh

# Clean build artifacts
./clear.sh
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

# Compile with different backends
moon run src/bin/main.mbt -- <input> --js      # JavaScript backend
moon run src/bin/main.mbt -- <input> --wasm    # WebAssembly backend
moon run src/bin/main.mbt -- <input> --llvmir  # LLVM IR backend

# 编译运行经过 SSA IR 转换生成汇编
./script/single_run.sh contest-2025-data/test_cases/mbt/adder.mbt
```

## Development Conventions

### Testing
The test suite uses `.mbt` files in `contest-2025-data/test_cases/mbt/` with expected outputs in `contest-2025-data/test_cases/ans/`. Tests compile to RISC-V assembly, execute in the emulator, and compare outputs.

### Build System
Uses MoonBit's build system (`moon`) with package definitions in `moon.mod.json` and `moon.pkg.json` files. The `minimoonbit.json` configures assembly emission.

### Development Practices
- This is an educational project focused on teaching compiler construction techniques
- Each compilation stage is implemented as a separate module with clear interfaces
- Multiple backends are supported (RISC-V, JavaScript, WebAssembly, LLVM IR)
- Interpreters are provided for each intermediate representation for educational purposes