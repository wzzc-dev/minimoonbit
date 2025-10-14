///| 将SSA中间表示转换为RISC-V汇编代码

///|
/// 实现线性扫描寄存器分配算法
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

///|
/// 生成函数的RISC-V汇编代码
fn emit_function(func : @ssa.Function) -> AssemblyFunction {
  // 执行寄存器分配
  let (live_intervals, param_ids) = compute_live_intervals_for_function(func)
  @util.logger("func name: " + func.name + " live_intervals: " + live_intervals.to_string())
  let allocator = linear_scan_register_allocation(live_intervals, param_ids)
  @util.logger("func name: " + func.name + " allocator: " + allocator.to_string())
  let asm_instructions = []

  // 确定需要保存的被调用者保存的寄存器
  let saved_callee_regs = []
  allocator.value_to_reg.each(fn(_, reg) {
    // 检查是否是被调用者保存的寄存器（s0-s11）
    match reg {
      S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 =>
        if not(saved_callee_regs.contains(reg)) {
          saved_callee_regs.push(reg)
        }
      _ => ()
    }
  })

  // 计算栈帧大小：基础24字节 + spill槽空间 + 被调用者保存寄存器空间
  let spill_size = allocator.next_spill_slot
  let framesize = 24 + spill_size + saved_callee_regs.length() * 8

  // 函数序言
  asm_instructions.push(Addi(Sp, Sp, -framesize)) // 分配栈帧
  asm_instructions.push(Sd(Ra, { base: Sp, offset: framesize - 8 })) // 保存返回地址
  asm_instructions.push(Sd(Fp, { base: Sp, offset: framesize - 16 })) // 保存帧指针
  asm_instructions.push(Addi(Fp, Sp, framesize)) // 设置帧指针

  // 保存被调用者保存的寄存器到栈上
  let mut offset = 24
  for reg in saved_callee_regs {
    asm_instructions.push(Sd(reg, { base: Fp, offset: -offset }))
    offset += 8
  }
  if func.closure_param.length() > 0 {
    // 函数有闭包参数（自由变量），需要从参数寄存器加载
    // 闭包参数在A0，普通参数从A1开始

    // 1. 首先设置闭包参数（自由变量）
    let (param_reg, _) = get_register_or_spill_load(
      func.closure_param[0].id,
      allocator,
    )
    // 闭包参数从A0开始（闭包对象指针） ，不需要移动
    if param_reg != A0 {
      asm_instructions.push(Mv(param_reg, A0))
    }
    // 如果参数需要溢出，立即保存到栈槽
    let spill_instrs = generate_spill_store_if_needed(
      func.closure_param[0].id,
      param_reg,
      allocator,
    )
    asm_instructions.append(spill_instrs)

    // 2. 然后设置普通参数（从A1开始）
    for i, param in func.params {
      let (param_reg, _) = get_register_or_spill_load(param.id, allocator)
      // 普通参数从A1开始（A0被闭包参数占用）
      let input_reg = match i {
        0 => A1
        1 => A2
        2 => A3
        3 => A4
        4 => A5
        5 => A6
        6 => A7
        _ => @util.die("TODO")
      }
      if param_reg != input_reg {
        asm_instructions.push(Mv(param_reg, input_reg))
      }
      // 如果参数需要溢出，立即保存到栈槽
      let spill_instrs = generate_spill_store_if_needed(
        param.id,
        param_reg,
        allocator,
      )
      asm_instructions.append(spill_instrs)
    }
  } else {
    // 函数没有闭包参数，普通参数从A0开始
    for i, param in func.params {
      let (param_reg, _) = get_register_or_spill_load(param.id, allocator)
      if i < 8 {
        let input_reg = match i {
          0 => A0
          1 => A1
          2 => A2
          3 => A3
          4 => A4
          5 => A5
          6 => A6
          7 => A7
          _ => @util.die("TODO")
        }
        if param_reg != input_reg {
          asm_instructions.push(Mv(param_reg, input_reg))
        }
      }
      // 如果参数需要溢出，立即保存到栈槽
      let spill_instrs = generate_spill_store_if_needed(
        param.id,
        param_reg,
        allocator,
      )
      asm_instructions.append(spill_instrs)
    }
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

  {
    name: func.name,
    asm_export: func.name == "minimbt_main",
    body: asm_instructions,
  }
}

///|
/// 生成SSA指令的RISC-V汇编代码（重构版本 - 分离不同类型的指令生成逻辑）
fn emit_instruction_with_regalloc(
  instr : @ssa.Instruction,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  match instr.opcode {
    // 常量操作
    @ssa.Opcode::ConstInt(value) =>
      emit_constant_instruction(instr.result, value, allocator)
    @ssa.Opcode::ConstFloat(value) =>
      emit_float_constant_instruction(instr.result, value, allocator)

    // 整数算术运算
    @ssa.Opcode::Add(lhs, rhs) =>
      emit_binary_integer_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => Add(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::Sub(lhs, rhs) =>
      emit_binary_integer_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => Sub(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::Mul(lhs, rhs) =>
      emit_binary_integer_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => Mul(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::Div(lhs, rhs) =>
      emit_binary_integer_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => Div(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::Mod(lhs, rhs) =>
      emit_binary_integer_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => Rem(rd, rs1, rs2),
        allocator,
      )

    // 浮点算术运算
    @ssa.Opcode::FAdd(lhs, rhs) =>
      emit_binary_float_instruction(instr.result, lhs, rhs, (rd, rs1, rs2) => FaddD(
        rd, rs1, rs2,
      ))
    @ssa.Opcode::FSub(lhs, rhs) =>
      emit_binary_float_instruction(instr.result, lhs, rhs, (rd, rs1, rs2) => FsubD(
        rd, rs1, rs2,
      ))
    @ssa.Opcode::FMul(lhs, rhs) =>
      emit_binary_float_instruction(instr.result, lhs, rhs, (rd, rs1, rs2) => FmulD(
        rd, rs1, rs2,
      ))
    @ssa.Opcode::FDiv(lhs, rhs) =>
      emit_binary_float_instruction(instr.result, lhs, rhs, (rd, rs1, rs2) => FdivD(
        rd, rs1, rs2,
      ))
    @ssa.Opcode::FMod(lhs, rhs) =>
      emit_float_mod_operation(instr.result, lhs, rhs)

    // 比较运算
    @ssa.Opcode::Eq(lhs, rhs) =>
      emit_comparison_instruction(
        instr.result,
        lhs,
        rhs,
        ComparisonType::Equal,
        allocator,
      )
    @ssa.Opcode::Ne(lhs, rhs) =>
      emit_comparison_instruction(
        instr.result,
        lhs,
        rhs,
        ComparisonType::NotEqual,
        allocator,
      )
    @ssa.Opcode::Lt(lhs, rhs) =>
      emit_comparison_instruction(
        instr.result,
        lhs,
        rhs,
        ComparisonType::LessThan,
        allocator,
      )
    @ssa.Opcode::Le(lhs, rhs) =>
      emit_comparison_instruction(
        instr.result,
        lhs,
        rhs,
        ComparisonType::LessEqual,
        allocator,
      )
    @ssa.Opcode::Gt(lhs, rhs) =>
      emit_comparison_instruction(
        instr.result,
        lhs,
        rhs,
        ComparisonType::GreaterThan,
        allocator,
      )
    @ssa.Opcode::Ge(lhs, rhs) =>
      emit_comparison_instruction(
        instr.result,
        lhs,
        rhs,
        ComparisonType::GreaterEqual,
        allocator,
      )

    // 函数调用
    @ssa.Opcode::Call(name, args) =>
      emit_function_call_instruction(instr.result, name, args, allocator)
    // 函数引用调用
    @ssa.Opcode::CallRef(name, args) =>
      emit_function_ref_call_instruction(instr.result, name, args, allocator)

    // 内存操作
    @ssa.Opcode::Load(addr) =>
      emit_memory_load_instruction(instr.result, addr, allocator)
    @ssa.Opcode::Store(addr, value) =>
      emit_memory_store_instruction(addr, value, allocator)

    // 数组操作
    @ssa.Opcode::ArrayGet(array, index) =>
      emit_array_access_instruction(instr.result, array, index, allocator)
    @ssa.Opcode::ArrayPut(array, index, value) =>
      emit_array_store_instruction(array, index, value, allocator)

    // 元组操作（暂时保留原有实现）
    @ssa.Opcode::Tuple(_values) => {
      let (result_reg, spill_loads) = get_register_or_spill_load(
        instr.result.id,
        allocator,
      )
      spill_loads +
      [Comment("TODO: implement tuple creation"), Li(result_reg, "0")]
    }
    @ssa.Opcode::GetElement(tuple, _index) => {
      let (result_reg, spill_loads) = get_register_or_spill_load(
        instr.result.id,
        allocator,
      )
      let (tuple_reg, tuple_spill_loads) = get_register_or_spill_load(
        tuple.id,
        allocator,
      )
      spill_loads +
      tuple_spill_loads +
      [
        Comment("TODO: implement tuple element access"),
        Mv(result_reg, tuple_reg),
      ]
    }

    // 内存分配
    @ssa.Opcode::Alloc(ty) => emit_memory_allocation(instr.result, ty)

    // 闭包操作
    @ssa.Opcode::MakeClosure(func_name, free_vars) =>
      emit_closure_creation(instr.result, func_name, free_vars, allocator)
    @ssa.Opcode::CallClosure(closure, args) =>
      emit_closure_call(instr.result, closure, args, allocator)
  }
}

///|
/// 生成常量加载指令
fn emit_constant_instruction(
  result_val : @ssa.Value,
  value : Int,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, load_instrs) = get_register_or_spill_load(result_val.id, allocator)
  instrs.append(load_instrs)
  instrs.push(Li(rd, value.to_string()))
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成浮点常量加载指令
fn emit_float_constant_instruction(
  result_val : @ssa.Value,
  value : Double,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []

  // 获取目标浮点寄存器
  let float_reg = get_float_register_for_value(result_val)
  let bits = value.reinterpret_as_int64()

  // 寻找一个安全的临时寄存器
  // 按优先级顺序尝试可用的临时寄存器
  let candidate_temps = [T1, T2, T3, T4, T5, T6, T0]
  let mut temp_reg = T0 // 默认使用T0
  for temp in candidate_temps {
    let mut temp_is_used = false
    allocator.value_to_reg.each(fn(_value_id, reg) {
      if reg == temp {
        temp_is_used = true
      }
    })
    if not(temp_is_used) {
      temp_reg = temp
      break
    }
  }

  // 加载64位常量到临时寄存器
  instrs.push(Li(temp_reg, bits.to_string()))
  instrs.push(FmvDX(float_reg, temp_reg))
  instrs
}

///|
/// 生成整数二元运算指令
fn emit_binary_integer_instruction(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  emitter : (Reg, Reg, Reg) -> RvAsm,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rs1, load1) = get_register_or_spill_load(lhs.id, allocator)
  let (rs2, load2) = get_register_or_spill_load(rhs.id, allocator)
  let (rd, load_rd) = get_register_or_spill_load(result_val.id, allocator)
  instrs.append(load1)
  instrs.append(load2)
  instrs.append(load_rd)
  instrs.push(emitter(rd, rs1, rs2))
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成浮点二元运算指令
fn emit_binary_float_instruction(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  emitter : (FReg, FReg, FReg) -> RvAsm,
) -> Array[RvAsm] {
  let instrs = []
  let rd = get_float_register_for_value(result_val)
  let rs1 = get_float_register_for_value(lhs)
  let rs2 = get_float_register_for_value(rhs)
  instrs.push(emitter(rd, rs1, rs2))
  instrs
}

///|
/// 比较类型枚举
priv enum ComparisonType {
  Equal
  NotEqual
  LessThan
  LessEqual
  GreaterThan
  GreaterEqual
}

///|
/// 生成比较指令
fn emit_comparison_instruction(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  comparison_type : ComparisonType,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, load_rd) = get_register_or_spill_load(result_val.id, allocator)
  let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
  let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
  instrs.append(load_rd)
  instrs.append(load_rs1)
  instrs.append(load_rs2)

  // 根据比较类型生成相应的指令序列
  let comparison_instrs = match comparison_type {
    ComparisonType::Equal =>
      [
        Sub(rd, rs1, rs2), // rd = rs1 - rs2
        Slti(rd, rd, 1),  // Use signed comparison instead of unsigned
      ] // rd = (rd == 0) ? 1 : 0
    ComparisonType::NotEqual =>
      [
        Sub(rd, rs1, rs2), // rd = rs1 - rs2
        Sltiu(rd, rd, 1),  // Use signed comparison instead of unsigned
        Xori(rd, rd, 1),   // rd = !rd (if rd != 0, then rd = 1)
      ] // rd = (rd != 0) ? 1 : 0
    ComparisonType::LessThan => [Slt(rd, rs1, rs2)]
    ComparisonType::LessEqual =>
      [
        Slt(rd, rs2, rs1), // rd = rhs < lhs (检查rhs是否严格小于lhs)
        Xori(rd, rd, 1),   // rd = !rd (如果rhs不严格小于lhs，则lhs <= rhs)
      ] // rd = !(rhs < lhs) = (lhs <= rhs)
    ComparisonType::GreaterThan => [Slt(rd, rs2, rs1)] // rd = rhs < lhs
    ComparisonType::GreaterEqual =>
      [
        Slt(rd, rs1, rs2), // rd = lhs < rhs
        Xori(rd, rd, 1),
      ]
  } // rd = !rd
  instrs.append(comparison_instrs)
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成函数调用指令
fn emit_function_call_instruction(
  result_val : @ssa.Value,
  func : @ssa.Func,
  args : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  match func {
    Label(_) => ()
    Call(func) => {
      let (_, load_func_instrs) = get_register_or_spill_load(func.id, allocator)
      instrs.append(load_func_instrs)
    }
  }
  for i, arg in args {
    if i < 8 {
      let (arg_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
      instrs.append(load_instrs)
      let param_reg = match i {
        0 => A0 // 第一个显式参数放到A0
        1 => A1 // 第二个显式参数放到A1
        2 => A2
        3 => A3
        4 => A4
        5 => A5
        6 => A6
        7 => A7
        _ => @util.die("TODO")
      }
      if arg_reg != param_reg {
        instrs.push(Mv(param_reg, arg_reg))
      }
    } else {
      // 超过8个参数需要通过栈传递
      let (arg_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
      instrs.append(load_instrs)
      instrs.push(
        Sd(arg_reg, { base: Sp, offset: (i - 8) * 8 }),
      )
    }
  }
  match func {
    Label(name) => instrs.push(Call(name))
    Call(func) => {
      let (func_reg, _) = get_register_or_spill_load(func.id, allocator)
      instrs.push(Jalr(func_reg))
    }
  }
  // 5. 将返回值移动到结果寄存器
  let (result_reg, load_result_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_result_instrs)
  if result_reg != A0 {
    instrs.push(Mv(result_reg, A0))
  }

  // 如果结果需要溢出，生成存储指令
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    result_reg,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成函数引用调用指令
fn emit_function_ref_call_instruction(
  result_val : @ssa.Value,
  label : String,
  _args : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (result_reg, load_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.push(La(T0, label))
  if result_reg != T0 {
    instrs.push(Mv(result_reg, T0))
  }
  instrs.append(load_instrs)
  instrs
}

///|
/// 生成内存加载指令
fn emit_memory_load_instruction(
  result_val : @ssa.Value,
  address_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, load_rd) = get_register_or_spill_load(result_val.id, allocator)
  let (addr_reg, load_addr) = get_register_or_spill_load(
    address_val.id,
    allocator,
  )
  instrs.append(load_rd)
  instrs.append(load_addr)
  instrs.push(Ld(rd, { base: addr_reg, offset: 0 }))
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成内存存储指令
fn emit_memory_store_instruction(
  address_val : @ssa.Value,
  value_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (addr_reg, load_addr) = get_register_or_spill_load(
    address_val.id,
    allocator,
  )
  let (value_reg, load_value) = get_register_or_spill_load(
    value_val.id,
    allocator,
  )
  instrs.append(load_addr)
  instrs.append(load_value)
  instrs.push(Sd(value_reg, { base: addr_reg, offset: 0 }))
  instrs
}

///|
/// 生成数组访问指令
fn emit_array_access_instruction(
  result_val : @ssa.Value,
  array_val : @ssa.Value,
  index_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  instrs.push(Comment("ArrayGet: accessing array element"))

  // 获取数组基地址和索引值的寄存器
  let (array_reg, load_array_instrs) = get_register_or_spill_load(
    array_val.id,
    allocator,
  )
  let (index_reg, load_index_instrs) = get_register_or_spill_load(
    index_val.id,
    allocator,
  )
  instrs.append(load_array_instrs)
  instrs.append(load_index_instrs)

  // 加载数组指针
  instrs.push(Ld(T0, { base: array_reg, offset: 0 }))

  // 计算元素偏移量
  let scale = match result_val.ty {
    @ssa.Type::Int => 2 // 2^2 = 4 bytes
    _ => 3 // 2^3 = 8 bytes
  }
  instrs.push(Slli(T1, index_reg, scale)) // T1 = index * scale

  // 计算元素地址：base + offset
  instrs.push(Add(T0, T0, T1))

  // 根据元素类型加载值
  match result_val.ty {
    @ssa.Type::Int => {
      let (result_reg, load_result_instrs) = get_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      instrs.push(Lw(T2, { base: T0, offset: 0 }))
      if result_reg != T2 {
        instrs.push(Mv(result_reg, T2))
      }
      let spill_instrs = generate_spill_store_if_needed(
        result_val.id,
        result_reg,
        allocator,
      )
      instrs.append(spill_instrs)
    }
    @ssa.Type::Float => {
      let result_reg = get_float_register_for_value(result_val)
      let float_temp_reg = get_float_register_for_value(result_val)
      instrs.push(Fld(float_temp_reg, { base: T0, offset: 0 }))
      if result_reg != float_temp_reg {
        instrs.push(FmvD(result_reg, float_temp_reg))
      }
    }
    _ => {
      let (result_reg, load_result_instrs) = get_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      instrs.push(Ld(T2, { base: T0, offset: 0 }))
      if result_reg != T2 {
        instrs.push(Mv(result_reg, T2))
      }
      let spill_instrs = generate_spill_store_if_needed(
        result_val.id,
        result_reg,
        allocator,
      )
      instrs.append(spill_instrs)
    }
  }
  instrs
}

///|
/// 生成数组存储指令
fn emit_array_store_instruction(
  array_val : @ssa.Value,
  index_val : @ssa.Value,
  value_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  instrs.push(Comment("ArrayPut: storing array element"))

  // 获取数组基地址和索引值的寄存器
  let (array_reg, load_array_instrs) = get_register_or_spill_load(
    array_val.id,
    allocator,
  )
  let (index_reg, load_index_instrs) = get_register_or_spill_load(
    index_val.id,
    allocator,
  )
  instrs.append(load_array_instrs)
  instrs.append(load_index_instrs)

  // 加载数组指针
  instrs.push(Ld(T0, { base: array_reg, offset: 0 }))

  // 计算元素偏移量
  let scale = match value_val.ty {
    @ssa.Type::Int => 2 // 2^2 = 4 bytes
    _ => 3 // 2^3 = 8 bytes
  }
  instrs.push(Slli(T1, index_reg, scale)) // T1 = index * scale

  // 计算元素地址：base + offset
  instrs.push(Add(T0, T0, T1))

  // 根据元素类型存储值
  match value_val.ty {
    @ssa.Type::Float => {
      let float_temp_reg = get_float_register_for_value(value_val)
      instrs.push(Fsd(float_temp_reg, { base: T0, offset: 0 }))
    }
    _ => {
      let (value_reg, load_value_instrs) = get_register_or_spill_load(
        value_val.id,
        allocator,
      )
      instrs.append(load_value_instrs)
      if value_reg != T2 {
        instrs.push(Mv(T2, value_reg))
      }
      match value_val.ty {
        @ssa.Type::Int => instrs.push(Sw(T2, { base: T0, offset: 0 }))
        _ => instrs.push(Sd(T2, { base: T0, offset: 0 }))
      }
    }
  }
  instrs
}

///|
/// 生成浮点取模运算（需要库函数支持）
fn emit_float_mod_operation(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
) -> Array[RvAsm] {
  let instrs = []
  let rd = get_float_register_for_value(result_val)
  let rs1 = get_float_register_for_value(lhs)
  let rs2 = get_float_register_for_value(rhs)

  // 将参数移动到浮点参数寄存器
  if rs1 != Fa0 {
    instrs.push(FmvD(Fa0, rs1))
  }
  if rs2 != Fa1 {
    instrs.push(FmvD(Fa1, rs2))
  }

  // 调用浮点取模库函数
  instrs.push(Call(Label("fmod")))

  // 将返回值移动到结果寄存器
  if rd != Fa0 {
    instrs.push(FmvD(rd, Fa0))
  }
  instrs
}

///|
/// 生成内存分配指令
fn emit_memory_allocation(
  result_val : @ssa.Value,
  ty : @ssa.Type,
) -> Array[RvAsm] {
  let instrs = []
  let (result_reg, load_instrs) = get_register_or_spill_load(result_val.id, {
    available_regs: [],
    active_intervals: [],
    value_to_reg: @immut/hashmap.new(),
    value_to_spill: @immut/hashmap.new(),
    next_spill_slot: 0,
  })
  instrs.append(load_instrs)

  // 将分配大小放入参数寄存器
  let size = match ty {
    @ssa.Type::Unit => "8"
    _ => "0" // 其他类型暂不支持
  }
  instrs.push(Li(A0, size.to_string()))
  instrs.push(Call(Label("minimbt_malloc")))

  // 将返回的指针移动到结果寄存器
  if result_reg != A0 {
    instrs.push(Mv(result_reg, A0))
  }
  instrs
}

///|
/// 生成闭包创建指令
fn emit_closure_creation(
  result_val : @ssa.Value,
  func_name : String,
  free_vars : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  instrs.push(Comment("MakeClosure: " + func_name))
  let (result_reg, load_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_instrs)

  // 总是创建闭包对象
  // 1. 计算需要的内存大小 (函数指针 + 自由变量)
  let size = if free_vars.length() * 8 + 8 < 16 {
    16
  } else {
    free_vars.length() * 8 + 8
  }

  // 2. 调用 malloc 分配内存
  instrs.push(Li(A0, size.to_string()))
  instrs.push(Call(Label("minimbt_malloc")))

  // 3. 存储函数指针到闭包对象的偏移0处
  instrs.push(La(T0, Label(func_name)))
  instrs.push(Sd(T0, { base: A0, offset: 0 }))
  if free_vars.length() > 0 {
    // 有自由变量，存储它们
    for i, free_var in free_vars {
      // 获取自由变量的寄存器
      let (var_reg, load_instrs) = get_register_or_spill_load(
        free_var.id,
        allocator,
      )
      instrs.append(load_instrs)
      // 存储到闭包对象的偏移 (i+1)*8 处
      instrs.push(Sd(var_reg, { base: A0, offset: (i + 1) * 8 }))
    }
  } else {
    @util.die("No free vars for closure " + func_name)
  }

  // 4. 将闭包对象指针移动到结果寄存器
  if result_reg != A0 {
    instrs.push(Mv(result_reg, A0))
  }

  // 如果结果需要溢出，生成存储指令
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    result_reg,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成闭包调用指令
fn emit_closure_call(
  result_val : @ssa.Value,
  closure : @ssa.Value,
  args : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (closure_reg, load_closure_instrs) = get_register_or_spill_load(
    closure.id,
    allocator,
  )
  instrs.append(load_closure_instrs)
  instrs.push(Comment("CallClosure: setting up function call"))

  // 1. 将闭包对象指针加载到一个临时寄存器（T0）
  instrs.push(Mv(T0, closure_reg))

  // 2. 从闭包对象中加载自由变量到A0
  // 自由变量存储在闭包对象的偏移8处
  instrs.push(Ld(A0, { base: T0, offset: 8 }))

  // 3. 将显式参数放入参数寄存器（从A1开始）
  for i, arg in args {
    let (arg_reg, load_instrs) = get_register_or_spill_load(arg.id, allocator)
    instrs.append(load_instrs)
    let param_reg = match i {
      0 => A1 // 第一个显式参数放到A1
      1 => A2 // 第二个显式参数放到A2
      2 => A3
      3 => A4
      4 => A5
      5 => A6
      6 => A7
      _ => @util.die("TODO")
    }
    if arg_reg != param_reg {
      instrs.push(Mv(param_reg, arg_reg))
    }
  }

  // 4. 调用函数
  instrs.push(Comment("Extract function pointer and call"))
  instrs.push(Ld(T1, { base: T0, offset: 0 })) // 函数指针在偏移0处
  instrs.push(Jalr(T1))

  // 5. 将返回值移动到结果寄存器
  let (result_reg, load_result_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_result_instrs)
  if result_reg != A0 {
    instrs.push(Mv(result_reg, A0))
  }

  // 如果结果需要溢出，生成存储指令
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    result_reg,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 获取值对应的浮点寄存器
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

///|
/// 使用寄存器分配器为基本块参数分配寄存器
fn allocate_block_params_with_regalloc(
  block : @ssa.BasicBlock,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let result = []
  for i, param in block.params {
    let (param_reg, load_instrs) = get_register_or_spill_load(
      param.id,
      allocator,
    )
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
    let spill_instrs = generate_spill_store_if_needed(
      param.id,
      param_reg,
      allocator,
    )
    result.append(spill_instrs)
  }
  result
}

///|
/// 使用寄存器分配器生成终止指令
fn emit_terminator_with_regalloc(
  terminator : @ssa.Terminator,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let result = []
  match terminator {
    @ssa.Terminator::Return(value) => {
      match value {
        Some(val) =>
          // Check if the return value is a float
          match val.ty {
            @ssa.Type::Float => {
              let float_reg = get_float_register_for_value(val)
              if float_reg != Fa0 {
                result.push(FmvD(Fa0, float_reg))
              }
            }
            _ => {
              let (src_reg, load_instrs) = get_register_or_spill_load(
                val.id,
                allocator,
              )
              result.append(load_instrs)
              if src_reg != A0 {
                result.push(Mv(A0, src_reg))
              }
            }
          }
        None => result.push(Li(A0, "0"))
      }
      // 确定需要保存的被调用者保存的寄存器
      let saved_callee_regs = []
      allocator.value_to_reg.each(fn(_, reg) {
        // 检查是否是被调用者保存的寄存器（s0-s11）
        match reg {
          S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 =>
            if not(saved_callee_regs.contains(reg)) {
              saved_callee_regs.push(reg)
            }
          _ => ()
        }
      })

      // 计算栈帧大小：基础24字节 + spill槽空间 + 被调用者保存寄存器空间
      let framesize = 24 +
        allocator.next_spill_slot +
        saved_callee_regs.length() * 8

      // 恢复被调用者保存的寄存器从栈上
      let mut offset = 24
      for reg in saved_callee_regs {
        result.push(Ld(reg, { base: Fp, offset: -offset }))
        offset += 8
      }
      result.push(Ld(Ra, { base: Sp, offset: framesize - 8 }))
      result.push(Ld(Fp, { base: Sp, offset: framesize - 16 }))
      result.push(Addi(Sp, Sp, framesize))
      result.push(Ret)
    }
    @ssa.Terminator::Jump(target, args) => {
      for i, arg in args {
        let (src_reg, load_instrs) = get_register_or_spill_load(
          arg.id,
          allocator,
        )
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
    @ssa.Terminator::Branch(cond, true_block, true_args, false_block, false_args) => {
      let (cond_reg, load_instrs) = get_register_or_spill_load(
        cond.id,
        allocator,
      )
      result.append(load_instrs)

      // 保存false分支的参数到临时寄存器（避免与true参数冲突）
      let false_param_regs = []
      for i, arg in false_args {
        let (src_reg, load_instrs) = get_register_or_spill_load(
          arg.id,
          allocator,
        )
        let temp_reg = match i {
          0 => T0
          1 => T1
          2 => T2
          3 => T3
          4 => T4
          5 => T5
          _ => T6
        }
        result.append(load_instrs)
        if src_reg != temp_reg {
          result.push(Mv(temp_reg, src_reg))
        }
        false_param_regs.push(temp_reg)
      }

      // 加载true分支的参数到寄存器（在分支指令之前）
      for i, arg in true_args {
        let (src_reg, load_instrs) = get_register_or_spill_load(
          arg.id,
          allocator,
        )
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

      // 生成分支指令
      result.push(Bne(cond_reg, Zero, "block_" + true_block.id.to_string()))

      // 设置false分支的参数（在分支指令之后）
      for i = 0; i < false_param_regs.length(); i = i + 1 {
        let temp_reg = false_param_regs[i]
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
        if temp_reg != dest_reg {
          result.push(Mv(dest_reg, temp_reg))
        }
      }

      result.push(J("block_" + false_block.id.to_string()))
    }
  }
  result
}
