# 环境
moon 0.1.20250801 (edae1ae 2025-08-01)

git submodule update --init --recursive

cd riscv_rt
zig build

cd ./libriscv/emulator
./build.sh

# 流程

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'fontFamily': 'Comic Sans MS', 'primaryColor': '#fffbd5', 'edgeLabelBackground':'#fffbed', 'lineColor': '#582f0e'}}}%%
flowchart LR
  srcCode["Code"]
  lexTokens["Tokens"]
  parserAST["AST"]
  TypedAST["Typed AST"]
  knfIr["KNF IR"]
  closureIr["Closure IR"]
  ssa["SSA"]
  Assembly["Assembly RISC-V/WASM"]
  srcCode -->|"lex"| lexTokens
  lexTokens -->|"parser"| parserAST
  parserAST -->|"typing"| TypedAST
  TypedAST -->|"A-Normalization"| knfIr
  knfIr -->|"Closure Conversion"| closureIr
  TypedAST -->|"SSA Construction"| ssa
  closureIr -->|"emit"| Assembly
  ssa -->|"emit"| Assembly
  closureIr -->|"emit"| javascript
```