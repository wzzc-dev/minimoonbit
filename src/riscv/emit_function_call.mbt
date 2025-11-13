///|
/// 生成函数调用指令
pub fn emit_function_call_instruction(
  result_val : @ssa.Value,
  func : @ssa.Func,
  args : Array[@ssa.Value],
  allocator : RegisterAllocator,
  live_intervals : Array[LiveInterval],
  current_instruction_index : Int,
) -> Array[RvAsm] raise {
  let instrs = []

  // 1. 保存需要在调用后继续使用的caller-saved寄存器
  let saved_caller_regs = save_caller_saved_regs(
    live_intervals, current_instruction_index, allocator,
  )
  instrs.append(saved_caller_regs)

  match func {
    Label(_) => ()
    Call(func) => {
      let (_, load_func_instrs) = get_register_or_spill_load(func.id, allocator)
      instrs.append(load_func_instrs)
    }
  }
  for i, arg in args {
    if i < 8 {
      match arg.ty {
        Float => {
          let (arg_freg, load_instrs) = get_float_register_or_spill_load(
            arg.id,
            allocator,
          )
          instrs.append(load_instrs)
          let param_freg = match i {
            0 => Fa0
            1 => Fa1
            2 => Fa2
            3 => Fa3
            4 => Fa4
            5 => Fa5
            6 => Fa6
            7 => Fa7
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
        }
      }
    } else {
      match arg.ty {
        Float => {
          let (arg_freg, load_instrs) = get_float_register_or_spill_load(
            arg.id,
            allocator,
          )
          instrs.append(load_instrs)
          instrs.push(Fsd(arg_freg, { base: Sp, offset: (i - 8) * 8 }))
        }
        _ => {
          let (arg_reg, load_instrs) = get_register_or_spill_load(
            arg.id,
            allocator,
          )
          instrs.append(load_instrs)
          instrs.push(Sd(arg_reg, { base: Sp, offset: (i - 8) * 8 }))
        }
      }
    }
  }
  match func {
    Label(name) => instrs.push(Call(name))
    Call(func) => {
      let (func_reg, _) = get_register_or_spill_load(func.id, allocator)
      instrs.push(Jalr(func_reg))
    }
  }

  // 4. 恢复caller-saved寄存器
  let restored_caller_regs = restore_caller_saved_regs(
    live_intervals, current_instruction_index, allocator,
  )
  instrs.append(restored_caller_regs)

  // 5. 将返回值移动到结果寄存器
  instrs.append(emit_move_result_to_result_register(result_val, allocator))
  instrs
}

///|
/// 生成函数引用调用指令
pub fn emit_function_ref_call_instruction(
  result_val : @ssa.Value,
  label : String,
  _args : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
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
fn emit_move_result_to_result_register(
  result_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  match result_val.ty {
    Unit => instrs
    Float => {
      let (result_freg, load_result_instrs) = get_float_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      if result_freg != Fa0 {
        instrs.push(FmvD(result_freg, Fa0))
      }

      // 如果结果需要溢出，生成存储指令
      let spill_instrs = generate_float_spill_store_if_needed(
        result_val.id,
        result_freg,
        allocator,
      )
      instrs.append(spill_instrs)
      instrs
    }
    _ => {
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
  }
}

///|
/// 检查值的活跃区间是否跨越调用点
fn value_is_live_across_call(
  value_id : Int,
  call_point : Int,
  live_intervals : Array[LiveInterval],
) -> Bool {
  for interval in live_intervals {
    if interval.value_id == value_id {
      return interval.end > call_point
    }
  }
  false
}

///|
/// 保存需要跨越函数调用点的caller-saved寄存器
fn save_caller_saved_regs(
  live_intervals : Array[LiveInterval],
  current_instruction_index : Int,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let mut spill_offset = 0

  // 首先计算需要多少栈空间
  let mut needed_space = 0
  for entry in allocator.value_to_reg.to_array() {
    let value_id = entry.0
    let reg = entry.1
    if reg_caller_saved_list.contains(reg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        needed_space += 8
      }
    }
  }
  for entry in allocator.value_to_freg.to_array() {
    let value_id = entry.0
    let freg = entry.1
    if freg_caller_saved_list.contains(freg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        needed_space += 8
      }
    }
  }

  // 分配栈空间（按16字节对齐）
  let aligned_space = ((needed_space + 15) / 16) * 16
  if aligned_space > 0 {
    instrs.push(Addi(Sp, Sp, -aligned_space))
  }

  // 保存caller-saved寄存器
  for entry in allocator.value_to_reg.to_array() {
    let value_id = entry.0
    let reg = entry.1
    if reg_caller_saved_list.contains(reg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        // 这个值在调用后还需要使用，需要保存
        instrs.push(Sd(reg, { base: Sp, offset: spill_offset }))
        spill_offset += 8
      }
    }
  }

  // 保存浮点寄存器
  for entry in allocator.value_to_freg.to_array() {
    let value_id = entry.0
    let freg = entry.1
    if freg_caller_saved_list.contains(freg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        // 这个值在调用后还需要使用，需要保存
        instrs.push(Fsd(freg, { base: Sp, offset: spill_offset }))
        spill_offset += 8
      }
    }
  }

  // 释放栈空间的指令将在restore函数中生成
  instrs
  // []
}

///|
/// 恢复跨越函数调用点的caller-saved寄存器
fn restore_caller_saved_regs(
  live_intervals : Array[LiveInterval],
  current_instruction_index : Int,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []

  // 计算栈空间需求
  let mut needed_space = 0
  for entry in allocator.value_to_reg.to_array() {
    let value_id = entry.0
    let reg = entry.1
    if reg_caller_saved_list.contains(reg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        needed_space += 8
      }
    }
  }
  for entry in allocator.value_to_freg.to_array() {
    let value_id = entry.0
    let freg = entry.1
    if freg_caller_saved_list.contains(freg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        needed_space += 8
      }
    }
  }

  // 按相反顺序恢复寄存器（栈的后进先出特性）
  let regs_to_restore = []
  let fregs_to_restore = []

  // 收集需要恢复的整数寄存器
  for entry in allocator.value_to_reg.to_array() {
    let value_id = entry.0
    let reg = entry.1
    if reg_caller_saved_list.contains(reg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        regs_to_restore.push((value_id, reg))
      }
    }
  }

  // 收集需要恢复的浮点寄存器
  for entry in allocator.value_to_freg.to_array() {
    let value_id = entry.0
    let freg = entry.1
    if freg_caller_saved_list.contains(freg) {
      if value_is_live_across_call(
          value_id, current_instruction_index, live_intervals,
        ) {
        fregs_to_restore.push((value_id, freg))
      }
    }
  }

  // 恢复浮点寄存器（按相反顺序）
  // 浮点寄存器保存在整数寄存器之后
  let reg_count = regs_to_restore.length()
  let mut freg_index = fregs_to_restore.length() - 1
  while freg_index >= 0 {
    let freg = fregs_to_restore[freg_index].1
    // 浮点寄存器的偏移 = 整数寄存器总数 + 浮点寄存器索引
    let offset = reg_count * 8 + freg_index * 8
    instrs.push(Fld(freg, { base: Sp, offset: offset }))
    freg_index = freg_index - 1
  }

  // 恢复整数寄存器（按相反顺序）
  let mut reg_index = regs_to_restore.length() - 1
  while reg_index >= 0 {
    let reg = regs_to_restore[reg_index].1
    // 整数寄存器的偏移就是其索引
    let offset = reg_index * 8
    instrs.push(Ld(reg, { base: Sp, offset: offset }))
    reg_index = reg_index - 1
  }

  // 释放栈空间（按16字节对齐）
  let aligned_space = ((needed_space + 15) / 16) * 16
  if aligned_space > 0 {
    instrs.push(Addi(Sp, Sp, aligned_space))
  }

  instrs
  // []
}
