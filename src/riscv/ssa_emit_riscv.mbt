///| 将SSA中间表示转换为RISC-V汇编代码
///| 使用基本块参数而非phi函数来实现SSA
///| 实现线性扫描寄存器分配算法

// 导入所需的模块
pub fn ssa_emit_riscv(input : @ssa.Ssa) -> Array[AssemblyFunction] {
  let functions = []
  println("emit riscv for ssa program: ")
  println(input.to_json().stringify())
  
  // 遍历所有SSA函数
  for func in input.program.functions {
    let asm_func = emit_function(func)
    functions.push(asm_func)
  }
  
  
  functions
}



///| 生成函数的RISC-V汇编代码
fn emit_function(func : @ssa.Function) -> AssemblyFunction {
  // 执行寄存器分配
  let live_intervals = compute_live_intervals_for_function(func)
  let allocator = linear_scan_register_allocation(live_intervals)
  
  let asm_instructions = []
  
  // 计算栈帧大小（包括溢出槽）
  let spill_size = allocator.next_spill_slot
  let framesize = 24 + spill_size // 基础栈帧大小 + 溢出空间
  
  // 函数序言
  asm_instructions.push(Addi(Sp, Sp, -framesize)) // 分配栈帧
  asm_instructions.push(Sd(Ra, { base: Sp, offset: framesize - 8 })) // 保存返回地址
  asm_instructions.push(Sd(Fp, { base: Sp, offset: framesize - 16 })) // 保存帧指针
  asm_instructions.push(Addi(Fp, Sp, framesize)) // 设置帧指针
  
  // 设置函数参数到对应的寄存器
  for i, param in func.params {
    let (param_reg, _) = get_register_or_spill_load(param.id, allocator)
    let input_reg = match i {
      0 => A0
      1 => A1
      2 => A2
      3 => A3
      4 => A4
      5 => A5
      6 => A6
      7 => A7
      _ => A0  // 超过8个参数的情况
    }
    if param_reg != input_reg {
      asm_instructions.push(Mv(param_reg, input_reg))
    }
    // 如果参数需要溢出，立即保存到栈槽
    let spill_instrs = generate_spill_store_if_needed(param.id, param_reg, allocator)
    asm_instructions.append(spill_instrs)
  }
  
  // 生成基本块代码
  for block in func.blocks {
    // 为基本块标签添加前缀
    let block_label = "block_" + block.id.id.to_string()
    asm_instructions.push(Label(block_label))

    // 为基本块参数分配寄存器或栈位置
    let param_instrs = allocate_block_params_with_regalloc(block, allocator)
    asm_instructions.append(param_instrs)
    
    // 生成指令
    for instr in block.instructions {
      let asm_instrs = emit_instruction_with_regalloc(instr, allocator)
      asm_instructions.append(asm_instrs)
    }
    
    // 生成终止指令
    let term_instrs = emit_terminator_with_regalloc(block.terminator, allocator)
    asm_instructions.append(term_instrs)
  }
  
  // 函数尾声现在由Return terminator处理

  { name: func.name, asm_export: func.name == "minimbt_main", body: asm_instructions } 
}

///| 生成二元运算指令（使用新的寄存器分配器）
fn emit_binary_op_with_regalloc(result_val : @ssa.Value, lhs : @ssa.Value, rhs : @ssa.Value,
                  op : (Reg, Reg, Reg) -> RvAsm, allocator : RegisterAllocator) -> Array[RvAsm] {
  let instrs = []

  let (rs1, load1) = get_register_or_spill_load(lhs.id, allocator)
  let (rs2, load2) = get_register_or_spill_load(rhs.id, allocator)
  let (rd, load_rd) = get_register_or_spill_load(result_val.id, allocator)

  instrs.append(load1)
  instrs.append(load2)
  instrs.append(load_rd)

  // 如果目标寄存器与源寄存器冲突，使用临时寄存器
  if rd == rs1 || rd == rs2 {
    let temp_reg = T0
    instrs.push(op(temp_reg, rs1, rs2))
    instrs.push(Mv(rd, temp_reg))
  } else {
    instrs.push(op(rd, rs1, rs2))
  }

  let spill_instrs = generate_spill_store_if_needed(result_val.id, rd, allocator)
  instrs.append(spill_instrs)

  instrs
}

///| 生成SSA指令的RISC-V汇编代码（使用新的寄存器分配器）
fn emit_instruction_with_regalloc(instr : @ssa.Instruction, allocator : RegisterAllocator) -> Array[RvAsm] {
  let result = []
  
  match instr.opcode {
    @ssa.Opcode::ConstInt(value) => {
      // 加载常量整数到寄存器
      let (rd, load_instrs) = get_register_or_spill_load(instr.result.id, allocator)
      result.append(load_instrs)
      result.push(Li(rd, value.to_string()))
      // 如果结果需要溢出，生成存储指令
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::ConstFloat(value) => {
      // 加载常量浮点数到寄存器
      let float_reg = get_float_register_for_value(instr.result)
      let bits = value.reinterpret_as_int64()
      result.push(Li(T0, bits.to_string()))
      result.push(FmvDX(float_reg, T0))
    }
    @ssa.Opcode::Add(lhs, rhs) => {
      result.append(emit_binary_op_with_regalloc(instr.result, lhs, rhs, (rd, rs1, rs2) => Add(rd, rs1, rs2), allocator))
    }
    @ssa.Opcode::Sub(lhs, rhs) => {
      result.append(emit_binary_op_with_regalloc(instr.result, lhs, rhs, (rd, rs1, rs2) => Sub(rd, rs1, rs2), allocator))
    }
    @ssa.Opcode::Mul(lhs, rhs) => {
      result.append(emit_binary_op_with_regalloc(instr.result, lhs, rhs, (rd, rs1, rs2) => Mul(rd, rs1, rs2), allocator))
    }
    @ssa.Opcode::Div(lhs, rhs) => {
      result.append(emit_binary_op_with_regalloc(instr.result, lhs, rhs, (rd, rs1, rs2) => Div(rd, rs1, rs2), allocator))
    }
    @ssa.Opcode::Mod(lhs, rhs) => {
      result.append(emit_binary_op_with_regalloc(instr.result, lhs, rhs, (rd, rs1, rs2) => Rem(rd, rs1, rs2), allocator))
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
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
      let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
      result.append(load_rd)
      result.append(load_rs1)
      result.append(load_rs2)
      result.append([
        Sub(rd, rs1, rs2),   // rd = rs1 - rs2
        Sltiu(rd, rd, 1)   // rd = (rd == 0) ? 1 : 0
      ])
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Ne(lhs, rhs) => {
      // 不等比较
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
      let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
      result.append(load_rd)
      result.append(load_rs1)
      result.append(load_rs2)
      result.append([
        Sub(rd, rs1, rs2),   // rd = rs1 - rs2
        Sltu(rd, Zero, rd)   // rd = (rd != 0) ? 1 : 0
      ])
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Lt(lhs, rhs) => {
      // 小于比较
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
      let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
      result.append(load_rd)
      result.append(load_rs1)
      result.append(load_rs2)
      result.push(Slt(rd, rs1, rs2))
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Le(lhs, rhs) => {
      // 小于等于比较 (lhs <= rhs 等价于 !(rhs < lhs))
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
      let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
      result.append(load_rd)
      result.append(load_rs1)
      result.append(load_rs2)
      result.append([
        Slt(rd, rs2, rs1),     // rd = rhs < lhs
        Xori(rd, rd, 1)      // rd = !rd
      ])
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Gt(lhs, rhs) => {
      // 大于比较 (rs2 < rs1)
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
      let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
      result.append(load_rd)
      result.append(load_rs1)
      result.append(load_rs2)
      result.push(Slt(rd, rs2, rs1))
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Ge(lhs, rhs) => {
      // 大于等于比较 (lhs >= rhs 等价于 !(lhs < rhs))
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
      let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
      result.append(load_rd)
      result.append(load_rs1)
      result.append(load_rs2)
      result.append([
        Slt(rd, rs1, rs2),     // rd = lhs < rhs
        Xori(rd, rd, 1)      // rd = !rd
      ])
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Call(name, args) => {
      // 函数调用
      // 将参数放入参数寄存器
      for i, arg in args {
        let (arg_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
        result.append(load_instrs)
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
      let (result_reg, load_instrs) = get_register_or_spill_load(instr.result.id, allocator)
      result.append(load_instrs)
      if result_reg != A0 {
        result.push(Mv(result_reg, A0))
      }
    }
    @ssa.Opcode::Load(addr) => {
      // 内存加载
      let (rd, load_rd) = get_register_or_spill_load(instr.result.id, allocator)
      let (addr_reg, load_addr) = get_register_or_spill_load(addr.id, allocator)
      result.append(load_rd)
      result.append(load_addr)
      result.push(Ld(rd, { base: addr_reg, offset: 0 }))
      let spill_instrs = generate_spill_store_if_needed(instr.result.id, rd, allocator)
      result.append(spill_instrs)
    }
    @ssa.Opcode::Store(addr, value) => {
      // 内存存储
      let (addr_reg, load_addr) = get_register_or_spill_load(addr.id, allocator)
      let (value_reg, load_value) = get_register_or_spill_load(value.id, allocator)
      result.append(load_addr)
      result.append(load_value)
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
    @ssa.Opcode::MakeClosure(func_name, free_vars) => {
      // 闭包创建 - 总是创建闭包对象，但对无自由变量的情况做特殊标记
      let result_reg = get_register_for_value(instr.result)
      result.push(Comment("MakeClosure: " + func_name))

      // 总是创建闭包对象
      // 1. 计算需要的内存大小 (函数指针 + 自由变量)
      let size = if free_vars.length() * 8 + 8 < 16 { 16 } else { free_vars.length() * 8 + 8 }

      // 2. 调用 malloc 分配内存
      result.push(Li(A0, size.to_string()))
      result.push(Call(Label("minimbt_malloc")))

      // 3. 存储函数指针到闭包对象的偏移0处
      result.push(La(T0, Label(func_name)))
      result.push(Sd(T0, { base: A0, offset: 0 }))

      if free_vars.length() > 0 {
        // 有自由变量，存储它们
        for i, free_var in free_vars {
          // 获取自由变量的寄存器
          let var_reg = get_register_for_value(free_var)
          // 存储到闭包对象的偏移 (i+1)*8 处
          result.push(Sd(var_reg, { base: A0, offset: (i + 1) * 8 }))
        }
      } else {
        // 没有自由变量，存储特殊标记值0到偏移8处
        result.push(Li(T1, "0"))
        result.push(Sd(T1, { base: A0, offset: 8 }))
      }

      // 4. 将闭包对象指针移动到结果寄存器
      if result_reg != A0 {
        result.push(Mv(result_reg, A0))
      }
    }
    @ssa.Opcode::CallClosure(closure, args) => {
      // 闭包调用 - 智能处理捕获变量和显式参数
      let closure_reg = get_register_for_value(closure)

      // 生成唯一标签以避免冲突
      let label_suffix = instr.result.id.to_string()

      result.push(Comment("CallClosure: setting up function call"))

      // 1. 首先将闭包对象指针加载到临时寄存器
      result.push(Mv(T0, closure_reg))

      // 2. 加载偏移8处的值，检查是否为特殊标记0
      result.push(Ld(T1, { base: T0, offset: 8 }))

      // 3. 检查是否为特殊标记值0（表示无捕获变量）
      result.push(Li(T2, "0"))
      result.push(Bne(T1, T2, Label("has_captured_vars_" + label_suffix)))

      // 无捕获变量的情况
      result.push(Comment("No captured vars - direct function call"))
      // 将显式参数放入参数寄存器（从A0开始）
      for i, arg in args {
        let (arg_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
        result.append(load_instrs)
        let param_reg = match i {
          0 => A0  // 第一个显式参数放到A0
          1 => A1  // 第二个显式参数放到A1
          2 => A2
          3 => A3
          4 => A4
          5 => A5
          6 => A6
          7 => A7
          _ => A0  // 超过参数寄存器数量的情况
        }
        if arg_reg != param_reg {
          result.push(Mv(param_reg, arg_reg))
        }
      }
      result.push(J(Label("call_function_" + label_suffix)))

      // 有捕获变量的情况
      result.push(Label("has_captured_vars_" + label_suffix))
      result.push(Comment("Has captured vars - load them first"))
      // 将捕获变量放到A0
      result.push(Mv(A0, T1))
      // 将显式参数放入参数寄存器（从A1开始）
      for i, arg in args {
        let (arg_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
        result.append(load_instrs)
        let param_reg = match i {
          0 => A1  // 第一个显式参数放到A1
          1 => A2  // 第二个显式参数放到A2
          2 => A3
          3 => A4
          4 => A5
          5 => A6
          6 => A7
          _ => A0  // 超过参数寄存器数量的情况
        }
        if arg_reg != param_reg {
          result.push(Mv(param_reg, arg_reg))
        }
      }

      // 4. 调用函数
      result.push(Label("call_function_" + label_suffix))
      result.push(Comment("Extract function pointer and call"))
      result.push(Ld(T1, { base: T0, offset: 0 }))  // 函数指针在偏移0处
      result.push(Jalr(T1))

      // 5. 将返回值移动到结果寄存器
      let result_reg = get_register_for_value(instr.result)
      if result_reg != A0 {
        result.push(Mv(result_reg, A0))
      }
    }
    _ => {
      // 默认情况下，使用简单的寄存器分配策略
      result.push(Comment("TODO: implement " + instr.opcode.to_string() + " with regalloc"))
    }
  }
  
  result
}


///| 回退的寄存器分配策略
fn get_register_for_value_fallback(value : @ssa.Value) -> Reg {
  match value.id % 20 {
    0 => T0
    1 => T1
    2 => T2
    3 => T3
    4 => T4
    5 => T5
    6 => T6
    7 => S2
    8 => S3
    9 => S4
    10 => S5
    11 => S6
    12 => S7
    13 => S8
    14 => S9
    15 => S10
    16 => A2
    17 => A3
    18 => A4
    _ => A5
  }
}

///| 获取值对应的整数寄存器（保持向后兼容）
fn get_register_for_value(value : @ssa.Value) -> Reg {
  get_register_for_value_fallback(value)
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

///| 使用寄存器分配器为基本块参数分配寄存器
fn allocate_block_params_with_regalloc(block : @ssa.BasicBlock, allocator : RegisterAllocator) -> Array[RvAsm] {
  let result = []
  for i, param in block.params {
    let (param_reg, load_instrs) = get_register_or_spill_load(param.id, allocator)
    let source_reg = match i {
      0 => A0
      1 => A1
      2 => A2
      3 => A3
      4 => A4
      5 => A5
      6 => A6
      _ => A0
    }
    
    result.append(load_instrs)
    if param_reg != source_reg {
      result.push(Mv(param_reg, source_reg))
    }
    
    let spill_instrs = generate_spill_store_if_needed(param.id, param_reg, allocator)
    result.append(spill_instrs)
  }
  result
}

///| 使用寄存器分配器生成终止指令
fn emit_terminator_with_regalloc(terminator : @ssa.Terminator, allocator : RegisterAllocator) -> Array[RvAsm] {
  let result = []
  
  match terminator {
    @ssa.Terminator::Return(value) => {
      match value {
        Some(val) => {
          let (src_reg, load_instrs) = get_register_or_spill_load(val.id, allocator)
          result.append(load_instrs)
          if src_reg != A0 {
            result.push(Mv(A0, src_reg))
          }
        }
        None => {
          result.push(Li(A0, "0"))
        }
      }
      let framesize = 24 + allocator.next_spill_slot
      result.push(Ld(Ra, { base: Sp, offset: framesize - 8 }))
      result.push(Ld(Fp, { base: Sp, offset: framesize - 16 }))
      result.push(Addi(Sp, Sp, framesize))
      result.push(Ret)
    }
    @ssa.Terminator::Jump(target, args) => {
      for i, arg in args {
        let (src_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
        let dest_reg = match i {
          0 => A0
          1 => A1
          2 => A2
          3 => A3
          4 => A4
          5 => A5
          6 => A6
          _ => A0
        }
        result.append(load_instrs)
        if src_reg != dest_reg {
          result.push(Mv(dest_reg, src_reg))
        }
      }
      result.push(J("block_" + target.id.to_string()))
    }
    @ssa.Terminator::Branch(cond, true_block, false_block) => {
      let (cond_reg, load_instrs) = get_register_or_spill_load(cond.id, allocator)
      result.append(load_instrs)
      result.push(Bne(cond_reg, Zero, "block_" + true_block.id.to_string()))
      result.push(J("block_" + false_block.id.to_string()))
    }
  }
  
  result
}

// fn allocate_block_params(block : @ssa.BasicBlock) -> Array[RvAsm] {
//   // 为基本块参数分配寄存器或栈位置
//   let result = []
//   for i, param in block.params {
//     let param_reg = get_register_for_value(param.0)
//     let source_reg = match i {
//       0 => A0
//       1 => A1
//       2 => A2
//       3 => A3
//       4 => A4
//       5 => A5
//       6 => A6
//       _ => A0  // 默认寄存器
//     }
//     // 将参数从调用约定寄存器移动到分配的寄存器
//     if param_reg != source_reg {
//       result.push(Mv(param_reg, source_reg))
//     }
//   }
//   result
// }