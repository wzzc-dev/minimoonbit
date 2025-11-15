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

  // 优化：根据自由变量数量决定分配策略
  if free_vars.length() == 0 {
    // 无自由变量：直接使用函数指针，无需堆分配
    instrs.push(Comment("Direct function pointer (no closure allocation)"))
    instrs.push(La(result_reg, Label(func_name)))
  } else {
    // 有自由变量：需要堆分配闭包对象

    // 1. 计算需要的内存大小 (函数指针 + 自由变量)
    let size = free_vars.length() * 8 + 8
    // 对齐到16字节边界以提高内存访问效率
    let aligned_size = if size % 16 == 0 { size } else { size + (16 - size % 16) }

    // 2. 调用 malloc 分配内存
    instrs.push(Comment("Allocate closure object: " + aligned_size.to_string() + " bytes"))
    instrs.push(Li(A0, aligned_size.to_string()))
    instrs.push(Call(Label("minimbt_malloc")))

    // 3. 存储函数指针到闭包对象的偏移0处
    instrs.push(La(T0, Label(func_name)))
    instrs.push(Sd(T0, { base: A0, offset: 0 }))

    // 4. 存储自由变量到闭包对象
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

    // 5. 将闭包对象指针移动到结果寄存器
    if result_reg != A0 {
      instrs.push(Mv(result_reg, A0))
    }
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

  // 3. 将显式参数放入参数寄存器（从A1/Fa1开始，因为A0是闭包指针）
  // 分别跟踪整数和浮点参数计数，遵循RISC-V ABI规范
  let mut int_arg_count = 0
  let mut float_arg_count = 0
  let mut stack_offset = 0

  for arg in args {
    match arg.ty {
      Float => {
        let (arg_freg, load_instrs) = get_float_register_or_spill_load(
          arg.id,
          allocator,
        )
        instrs.append(load_instrs)

        if float_arg_count < 7 {  // 闭包函数中，Fa0被占用，只能用Fa1-Fa7
          let param_freg = match float_arg_count {
            0 => Fa1  // 第一个浮点参数用Fa1（Fa0保留）
            1 => Fa2
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
          float_arg_count += 1
        } else {
          // 超过7个浮点参数，溢出到栈
          instrs.push(Fsd(arg_freg, { base: Sp, offset: stack_offset }))
          stack_offset += 8
        }
      }
      _ => {
        let (arg_reg, load_instrs) = get_register_or_spill_load(
          arg.id,
          allocator,
        )
        instrs.append(load_instrs)

        if int_arg_count < 7 {  // 闭包函数中，A0被占用，只能用A1-A7
          let param_reg = match int_arg_count {
            0 => A1   // 第一个整数参数用A1（A0用于闭包指针）
            1 => A2
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
          int_arg_count += 1
        } else {
          // 超过7个整数参数，溢出到栈
          instrs.push(Sd(arg_reg, { base: Sp, offset: stack_offset }))
          stack_offset += 8
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
