///| 将SSA中间表示转换为RISC-V汇编代码
///| 使用基本块参数而非phi函数来实现SSA

// 导入所需的模块
pub fn ssa_emit_riscv(input : @ssa.Ssa) -> Array[AssemblyFunction] {
  let functions = []
  // println("emit riscv for ssa program: " + input.to_string())
  // 遍历所有SSA函数
  for func in input.program.functions {
    let asm_func = emit_function(func)
    functions.push(asm_func)
  }
  
  functions
}

///| 生成函数的RISC-V汇编代码
fn emit_function(func : @ssa.Function) -> AssemblyFunction {
  let asm_instructions = []
  
  // 计算栈帧大小
  let framesize = 24 // 基础栈帧大小
  
  // 函数序言
  asm_instructions.push(Addi(Sp, Sp, -framesize)) // 分配栈帧
  asm_instructions.push(Sd(Ra, { base: Sp, offset: framesize - 8 })) // 保存返回地址
  asm_instructions.push(Sd(Fp, { base: Sp, offset: framesize - 16 })) // 保存帧指针
  asm_instructions.push(Addi(Fp, Sp, framesize)) // 设置帧指针
  
  // 生成基本块代码
  for block in func.blocks {
    // 为基本块参数分配寄存器或栈位置
    allocate_block_params(block)
    
    // 生成指令
    for instr in block.instructions {
      let asm_instrs = emit_instruction(instr)
      asm_instructions.append(asm_instrs)
    }
    
    // 生成终止指令
    let term_instrs = emit_terminator(block.terminator)
    asm_instructions.append(term_instrs)
  }
  
  // 函数尾声
  asm_instructions.push(Ld(Ra, { base: Sp, offset: framesize - 8 })) // 恢复返回地址
  asm_instructions.push(Ld(Fp, { base: Sp, offset: framesize - 16 })) // 恢复帧指针
  asm_instructions.push(Addi(Sp, Sp, framesize)) // 释放栈帧
  asm_instructions.push(Ret) // 返回
  
  { name: func.name, asm_export: true, body: asm_instructions }
}

///| 生成SSA指令的RISC-V汇编代码
fn emit_instruction(instr : @ssa.Instruction) -> Array[RvAsm] {
  let result = []
  
  match instr.opcode {
    @ssa.Opcode::ConstInt(value) => {
      // 加载常量整数到寄存器
      result.push(Li(get_register_for_value(instr.result), value.to_string()))
    }
    @ssa.Opcode::ConstFloat(value) => {
      // 加载常量浮点数到寄存器
      // TODO: 实现浮点常量加载
      let bits = value.reinterpret_as_int64()
      result.push(Li(T0, bits.to_string()))
      // instrs.push(FcvtDl(freg_ret, T0))
      result.push(FmvDX(freg_ret, T0))
    }
    @ssa.Opcode::Add(lhs, rhs) => {
      // 加法运算
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Add(rd, rs1, rs2))
    }
    @ssa.Opcode::Sub(lhs, rhs) => {
      // 减法运算
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Sub(rd, rs1, rs2))
    }
    // TODO: 实现其他指令的代码生成
    _ => {
      // 默认情况下，可以添加注释指令来标识未实现的指令
      result.push(Comment("TODO: implement " + instr.opcode.to_string()))
    }
  }
  
  result
}

///| 生成终止指令的RISC-V汇编代码
fn emit_terminator(terminator : @ssa.Terminator) -> Array[RvAsm] {
  let result = []
  
  match terminator {
    @ssa.Terminator::Return(value) => {
      // 返回指令
      match value {
        Some(val) => {
          // 将返回值移动到a0寄存器
          let src_reg = get_register_for_value(val)
          if src_reg != A0 {
            result.push(Mv(A0, src_reg))
          }
        }
        None => {
          // 无返回值，确保a0为0
          result.push(Li(A0, "0"))
        }
      }
      // 跳转到函数尾声
      result.push(Jalr(Zero))
    }
    @ssa.Terminator::Jump(target, args) => {
      // 无条件跳转
      // 跳转参数需要在目标基本块中作为参数使用
      // 将参数值移动到目标基本块参数对应的寄存器
      for i, arg in args {
        let src_reg = get_register_for_value(arg)
        let dest_reg = match i {
          0 => A0
          1 => A1
          2 => A2
          3 => A3
          4 => A4
          5 => A5
          6 => A6
          _ => A0  // 默认寄存器
        }
        if src_reg != dest_reg {
          result.push(Mv(dest_reg, src_reg))
        }
      }
      // 生成跳转指令
      result.push(J(target.to_string()))
    }
    @ssa.Terminator::Branch(cond, true_block, _false_block) => {
      // 条件分支
      let cond_reg = get_register_for_value(cond)
      // 如果条件为真，跳转到true_block，否则继续执行false_block
      result.push(Bne(cond_reg, Zero, true_block.to_string()))
      // 默认继续执行下一个块（false_block）
    }
  }
  
  result
}

///| 获取值对应的寄存器
fn get_register_for_value(value : @ssa.Value) -> Reg {
  // 简单的寄存器分配策略
  // 实际实现中需要更复杂的寄存器分配算法
  match value.id % 7 {
    0 => T0
    1 => T1
    2 => T2
    3 => T3
    4 => T4
    5 => T5
    _ => T6
  }
}

fn allocate_block_params(block : @ssa.BasicBlock) -> Unit{
  // 为基本块参数分配寄存器或栈位置
  for _i, param in block.params {
    let _reg = get_register_for_value(param.0)
    // 实际实现中需要将寄存器分配信息记录到SSA IR中
    // 例如，将寄存器信息存储在param.1中
    

  }
}