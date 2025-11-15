///|
/// 生成闭包创建指令
pub fn emit_closure_creation(
  result_val : @ssa.Value,
  func_name : String,
  free_vars : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
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
pub fn emit_closure_call(
  result_val : @ssa.Value,
  closure : @ssa.Func,
  args : Array[@ssa.Value],
  allocator : RegisterAllocator,
  live_intervals : Array[LiveInterval],
  current_instruction_index : Int,
) -> Array[RvAsm] raise {
  let instrs = []

  let saved_caller_regs = save_caller_saved_regs(
    live_intervals, current_instruction_index, allocator,
  )
  instrs.append(saved_caller_regs)

  match closure {
    @ssa.Func::Call(callee) => {
      let (closure_reg, load_closure_instrs) = get_register_or_spill_load(
        callee.id,
        allocator,
      )
      instrs.append(load_closure_instrs)
      instrs.push(Comment("CallClosure: setting up function call"))
      instrs.push(Mv(A0, closure_reg))
    }
    @ssa.Func::Label(_) => ()
  }

  // 3. 将显式参数放入参数寄存器（从A1开始）
  for i, arg in args {
    match arg.ty {
      Float => {
        let (arg_freg, load_instrs) = get_float_register_or_spill_load(
          arg.id,
          allocator,
        )
        instrs.append(load_instrs)
        let param_freg = match i {
          0 => Fa1 // 第一个显式参数放到A1
          1 => Fa2 // 第二个显式参数放到A2
          2 => Fa3
          3 => Fa4
          4 => Fa5
          5 => Fa6
          6 => Fa7
          _ => @util.die("TODO")
        }
        if arg_freg != param_freg {
          instrs.push(FmvD(param_freg, arg_freg))
        }
      }
      _ => {
        let (arg_reg, load_instrs) = get_register_or_spill_load(
          arg.id,
          allocator,
        )
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
    }
  }

  // 4. 调用函数
  instrs.push(Comment("Extract function pointer and call"))
  instrs.push(Ld(T1, { base: A0, offset: 0 })) // 函数指针在偏移0处，从当前闭包对象A0获取
  instrs.push(Jalr(T1))

  let restored_caller_regs = restore_caller_saved_regs(
    live_intervals, current_instruction_index, allocator,
  )
  instrs.append(restored_caller_regs)

  // 5. 将返回值移动到结果寄存器
  instrs.append(emit_move_result_to_result_register(result_val, allocator))
  instrs
}
