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
      let float_reg = get_float_register_for_value(instr.result)
      let bits = value.reinterpret_as_int64()
      result.push(Li(T0, bits.to_string()))
      result.push(FmvDX(float_reg, T0))
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
    @ssa.Opcode::Mul(lhs, rhs) => {
      // 乘法运算
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Mul(rd, rs1, rs2))
    }
    @ssa.Opcode::Div(lhs, rhs) => {
      // 除法运算
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Div(rd, rs1, rs2))
    }
    @ssa.Opcode::Mod(lhs, rhs) => {
      // 取模运算
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Rem(rd, rs1, rs2))
    }
    @ssa.Opcode::FAdd(lhs, rhs) => {
      // 浮点加法
      let rd = get_float_register_for_value(instr.result)
      let rs1 = get_float_register_for_value(lhs)
      let rs2 = get_float_register_for_value(rhs)
      result.push(FaddD(rd, rs1, rs2))
    }
    @ssa.Opcode::FSub(lhs, rhs) => {
      // 浮点减法
      let rd = get_float_register_for_value(instr.result)
      let rs1 = get_float_register_for_value(lhs)
      let rs2 = get_float_register_for_value(rhs)
      result.push(FsubD(rd, rs1, rs2))
    }
    @ssa.Opcode::FMul(lhs, rhs) => {
      // 浮点乘法
      let rd = get_float_register_for_value(instr.result)
      let rs1 = get_float_register_for_value(lhs)
      let rs2 = get_float_register_for_value(rhs)
      result.push(FmulD(rd, rs1, rs2))
    }
    @ssa.Opcode::FDiv(lhs, rhs) => {
      // 浮点除法
      let rd = get_float_register_for_value(instr.result)
      let rs1 = get_float_register_for_value(lhs)
      let rs2 = get_float_register_for_value(rhs)
      result.push(FdivD(rd, rs1, rs2))
    }
    @ssa.Opcode::Eq(lhs, rhs) => {
      // 相等比较
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.append([
        Sub(rd, rs1, rs2),  // rd = rs1 - rs2
        Sltiu(rd, rd, 1)       // rd = (rd == 0) ? 1 : 0
      ])
    }
    @ssa.Opcode::Ne(lhs, rhs) => {
      // 不等比较
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.append([
        Sub(rd, rs1, rs2),  // rd = rs1 - rs2
        Sltu(rd, Zero, rd)       // rd = (rd != 0) ? 1 : 0
      ])
    }
    @ssa.Opcode::Lt(lhs, rhs) => {
      // 小于比较
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Slt(rd, rs1, rs2))
    }
    @ssa.Opcode::Le(lhs, rhs) => {
      // 小于等于比较 (!(rs2 < rs1))
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.append([
        Slt(rd, rs2, rs1),   // rd = rs2 < rs1
        Xori(rd, rd, 1)      // rd = !rd
      ])
    }
    @ssa.Opcode::Gt(lhs, rhs) => {
      // 大于比较 (rs2 < rs1)
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.push(Slt(rd, rs2, rs1))
    }
    @ssa.Opcode::Ge(lhs, rhs) => {
      // 大于等于比较 (!(rs1 < rs2))
      let rd = get_register_for_value(instr.result)
      let rs1 = get_register_for_value(lhs)
      let rs2 = get_register_for_value(rhs)
      result.append([
        Slt(rd, rs1, rs2),   // rd = rs1 < rs2
        Xori(rd, rd, 1)      // rd = !rd
      ])
    }
    @ssa.Opcode::Call(name, args) => {
      // 函数调用
      // 将参数放入参数寄存器
      for i, arg in args {
        let arg_reg = get_register_for_value(arg)
        let param_reg = match i {
          0 => A0
          1 => A1
          2 => A2
          3 => A3
          4 => A4
          5 => A5
          6 => A6
          7 => A7
          _ => A0  // 超过8个参数需要通过栈传递
        }
        if arg_reg != param_reg {
          result.push(Mv(param_reg, arg_reg))
        }
      }
      // 调用函数
      result.push(Call(name))
      // 将返回值移动到结果寄存器
      let result_reg = get_register_for_value(instr.result)
      if result_reg != A0 {
        result.push(Mv(result_reg, A0))
      }
    }
    @ssa.Opcode::Load(addr) => {
      // 内存加载
      let rd = get_register_for_value(instr.result)
      let addr_reg = get_register_for_value(addr)
      result.push(Ld(rd, { base: addr_reg, offset: 0 }))
    }
    @ssa.Opcode::Store(addr, value) => {
      // 内存存储
      let addr_reg = get_register_for_value(addr)
      let value_reg = get_register_for_value(value)
      result.push(Sd(value_reg, { base: addr_reg, offset: 0 }))
    }
    @ssa.Opcode::Tuple(_values) => {
      // 元组创建 - 简化实现，实际需要分配内存
      let result_reg = get_register_for_value(instr.result)
      result.push(Comment("TODO: implement tuple creation"))
      result.push(Li(result_reg, "0")) // 临时实现
    }
    @ssa.Opcode::GetElement(tuple, _index) => {
      // 元组元素访问
      let rd = get_register_for_value(instr.result)
      let tuple_reg = get_register_for_value(tuple)
      result.push(Comment("TODO: implement tuple element access"))
      result.push(Mv(rd, tuple_reg)) // 临时实现
    }
    _ => {
      // 默认情况下，添加注释指令来标识未实现的指令
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

///| 获取值对应的整数寄存器
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

///| 获取值对应的浮点寄存器
fn get_float_register_for_value(value : @ssa.Value) -> FReg {
  // 简单的浮点寄存器分配策略
  match value.id % 8 {
    0 => Ft0
    1 => Ft1
    2 => Ft2
    3 => Ft3
    4 => Ft4
    5 => Ft5
    6 => Ft6
    _ => Ft7
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