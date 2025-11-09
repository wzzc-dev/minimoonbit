///|
/// 生成函数调用指令
pub fn emit_function_call_instruction(
  result_val : @ssa.Value,
  func : @ssa.Func,
  args : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
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
