///|
pub(all) struct AssemblyFunction {
  name : String
  asm_export : Bool
  body : Array[RvAsm]
  static_data : Bool
} derive(Show)

///|
pub fn AssemblyFunction::output(
  self : AssemblyFunction,
  logger : &Logger,
) -> Unit {
  let name = self.name
  if self.asm_export {
    logger.write_string(".global \{name}\n")
  }
  logger.write_string("\{name}:\n")
  for rv_asm in self.body {
    Show::output(rv_asm, logger)
    logger.write_string("\n")
  }
}

///| 将SSA中间表示转换为RISC-V汇编代码

///|
/// 实现线性扫描寄存器分配算法
pub fn emit(input : @ssa.Ssa) -> Array[AssemblyFunction] {
  let functions = []
  // println("emit riscv for ssa program: \n" + input.to_json().stringify())
  for static_array in input.program.static_arrays {
    fn get_elems(name : String, arr : Array[@closure.LowTypeValue]) {
      let body = []
      let elems = []
      for i, elem in arr {
        match elem {
          DoubleValue(d) => elems.push(d.to_string())
          IntValue(i) => elems.push(i.to_string())
          PtrValue(a) => {
            get_elems(name + "_" + i.to_string(), a)
            elems.push(name + "_" + i.to_string())
          }
        }
      }
      if elems.length() > 0 {
        match arr[0] {
          PtrValue(_) => body.push(Data(".dword", elems))
          IntValue(_) => body.push(Data(".word", elems))
          DoubleValue(_) => body.push(Data(".double", elems))
        }
      }
      functions.push({ name, asm_export: false, body, static_data: true })
    }

    get_elems(static_array.label.0, static_array.elements)
  }

  // 遍历所有SSA函数
  for func in input.program.functions {
    let asm_func = emit_function(func) catch {
      e => @util.die("Compilation error: " + e.to_string())
    }
    functions.push(asm_func)
  }
  functions
}

///|
/// 生成函数的RISC-V汇编代码
fn emit_function(func : @ssa.Function) -> AssemblyFunction raise {
  // 执行寄存器分配
  let (live_intervals, param_ids, kill_points) = compute_live_intervals_for_function(
    func,
  )
  // @util.logger("func name: " + func.name + " live_intervals: " + live_intervals.to_string())
  let allocator = linear_scan_register_allocation(
    live_intervals, param_ids, kill_points,
  )
  // @util.logger("func name: " + func.name + " allocator: " + allocator.to_string())
  let asm_instructions = []

  // 计算栈帧大小：基础24字节 + spill槽空间 + 被调用者保存寄存器空间
  let spill_size = allocator.next_spill_slot
  let saved_callee_size =
    allocator.saved_callee_regs.length() * 8 +
    allocator.saved_callee_fregs.length() * 8
  
  let framesize = 24 +
    spill_size +
    saved_callee_size
  
  // 函数序言
  asm_instructions.push(Addi(Sp, Sp, -framesize)) // 分配栈帧
  asm_instructions.push(Sd(Ra, { base: Sp, offset: framesize - 8 })) // 保存返回地址
  asm_instructions.push(Sd(Fp, { base: Sp, offset: framesize - 16 })) // 保存帧指针
  asm_instructions.push(Addi(Fp, Sp, framesize)) // 设置帧指针

  // 保存被调用者保存的寄存器到栈上
  let mut offset = 24
  for reg in allocator.saved_callee_regs {
    asm_instructions.push(Sd(reg, { base: Fp, offset: -offset }))
    offset += 8
  }
  // 保存被调用者保存的浮点寄存器到栈上
  for freg in allocator.saved_callee_fregs {
    asm_instructions.push(Fsd(freg, { base: Fp, offset: -offset }))
    offset += 8
  }
  if func.closure_param.length() > 0 {
    // 函数有闭包参数（自由变量），需要从参数寄存器加载
    // 闭包参数在A0，普通参数从A1开始

    // 1. 首先设置闭包参数（自由变量）
    // 闭包对象指针在A0，从其中加载各个自由变量
    for i, closure_param in func.closure_param {
      match closure_param.ty {
        Float =>
          match allocator.value_to_freg.get(closure_param.id) {
            Some(freg) =>
              asm_instructions.push(
                Fld(freg, { base: A0, offset: (i + 1) * 8 }),
              )
            None =>
              match allocator.value_to_spill.get(closure_param.id) {
                Some(spill_offset) => {
                  asm_instructions.push(
                    Fld(Ft0, { base: A0, offset: (i + 1) * 8 }),
                  )
                  asm_instructions.push(
                    Fsd(Ft0, {
                      base: Fp,
                      offset: -(24 + spill_offset + saved_callee_size),
                    }),
                  )
                }
                None => @util.die("TODO")
              }
          }
        _ =>
          match allocator.value_to_reg.get(closure_param.id) {
            Some(reg) =>
              asm_instructions.push(Ld(reg, { base: A0, offset: (i + 1) * 8 }))
            None =>
              match allocator.value_to_spill.get(closure_param.id) {
                Some(spill_offset) => {
                  asm_instructions.push(
                    Ld(T0, { base: A0, offset: (i + 1) * 8 }),
                  )
                  asm_instructions.push(
                    Sd(T0, {
                      base: Fp,
                      offset: -(24 + spill_offset + saved_callee_size),
                    }),
                  )
                }
                None => @util.die("TODO: 闭包参数需要溢出栈槽")
              }
          }
      }
    }

    // 2. 然后设置普通参数（从A1开始）
    for i, param in func.params {
      match param.ty {
        Float => {
          let input_freg = match i {
            0 => Fa1
            1 => Fa2
            2 => Fa3
            3 => Fa4
            4 => Fa5
            5 => Fa6
            6 => Fa7
            _ => @util.die("TODO: 普通参数超过8个")
          }
          asm_instructions.append(
            store_value_to_allocator_freg_or_spill(param, input_freg, allocator),
          )
        }
        _ => {
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
          asm_instructions.append(
            store_value_to_allocator_reg_or_spill(param, input_reg, allocator),
          )
        }
      }
    }
  } else {
    // 函数没有闭包参数，普通参数从A0开始
    for i, param in func.params {
      match param.ty {
        Float => {
          let input_freg = match i {
            0 => Fa0
            1 => Fa1
            2 => Fa2
            3 => Fa3
            4 => Fa4
            5 => Fa5
            6 => Fa6
            7 => Fa7
            _ => Ft0
          }
          asm_instructions.append(
            store_value_to_allocator_freg_or_spill(param, input_freg, allocator),
          )
        }
        _ => {
          let input_reg = match i {
            0 => A0
            1 => A1
            2 => A2
            3 => A3
            4 => A4
            5 => A5
            6 => A6
            7 => A7
            _ => @util.die("TODO: 参数超过8个")
          }
          asm_instructions.append(
            store_value_to_allocator_reg_or_spill(param, input_reg, allocator),
          )
        }
      }
    }
  }

  // 生成基本块代码
  for block in func.blocks {
    // 为基本块标签添加前缀
    let block_label = "block_" + block.id.id.to_string()
    asm_instructions.push(Label(block_label))

    // // 为基本块参数分配寄存器或栈位置
    // let param_instrs = allocate_block_params_with_regalloc(block, allocator)
    // asm_instructions.append(param_instrs)

    // 生成指令
    let mut current_index = 0
    for instr in block.instructions {
      let asm_instrs = emit_instruction_with_regalloc(instr, allocator, live_intervals, current_index) catch {
        e =>
          @util.die(
            "Compilation error: [Instruction]: " +
            instr.to_string() +
            ", \n" +
            e.to_string(),
          )
      }
      asm_instructions.append(asm_instrs)
      current_index = current_index + 1
    }
    let block_map = @hashmap.new()
    for b in func.blocks {
      block_map.set(b.id, b)
    }
    // 生成终止指令
    let term_instrs = emit_terminator_with_regalloc(
      block.terminator,
      allocator,
      block_map,
    )
    asm_instructions.append(term_instrs)
  }

  // 函数尾声现在由Return terminator处理

  {
    name: func.name,
    asm_export: func.name == "minimbt_main",
    body: asm_instructions,
    static_data: false,
  }
}

///|
/// 生成SSA指令的RISC-V汇编代码（重构版本 - 分离不同类型的指令生成逻辑）
fn emit_instruction_with_regalloc(
  instr : @ssa.Instruction,
  allocator : RegisterAllocator,
  live_intervals : Array[LiveInterval],
  instr_index : Int,
) -> Array[RvAsm] raise {
  // @util.logger("emit_instruction_with_regalloc: {}" + instr.to_string())
  match instr.opcode {
    // 常量操作
    @ssa.Opcode::ConstInt(value) =>
      emit_constant_instruction(instr.result, value, allocator)
    @ssa.Opcode::ConstFloat(value) =>
      emit_float_constant_instruction(instr.result, value, allocator)
    @ssa.Opcode::ConstBool(value) =>
      emit_bool_constant_instruction(instr.result, value, allocator)

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
      emit_binary_float_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => FaddD(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::FSub(lhs, rhs) =>
      emit_binary_float_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => FsubD(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::FMul(lhs, rhs) =>
      emit_binary_float_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => FmulD(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::FDiv(lhs, rhs) =>
      emit_binary_float_instruction(
        instr.result,
        lhs,
        rhs,
        (rd, rs1, rs2) => FdivD(rd, rs1, rs2),
        allocator,
      )
    @ssa.Opcode::FMod(lhs, rhs) =>
      emit_float_mod_operation(instr.result, lhs, rhs, allocator)

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
      emit_function_call_instruction(instr.result, name, args, allocator, live_intervals, instr_index)
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
    // 元组操作（实现完整逻辑）
    @ssa.Opcode::Tuple(values) =>
      emit_tuple_instruction(instr.result, values, allocator)
    @ssa.Opcode::GetElement(tuple, index) =>
      emit_get_element_instruction(instr.result, tuple, index, allocator)
    // 内存分配
    @ssa.Opcode::Alloc(ty) =>
      emit_memory_allocation(instr.result, ty, allocator)
    // 闭包操作
    @ssa.Opcode::MakeClosure(func_name, free_vars) =>
      emit_closure_creation(instr.result, func_name, free_vars, allocator)
    @ssa.Opcode::CallClosure(closure, args) =>
      emit_closure_call(instr.result, closure, args, allocator)
  }
}
