///|
/// 生成溢出存储指令（如果需要）
pub fn generate_spill_store_if_needed(
  value_id : Int,
  reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
    allocator.saved_callee_fregs.length() * 8
  match allocator.value_to_spill.get(value_id) {
    Some(spill_offset) =>
      [
        Sd(reg, {
          base: Fp,
          offset: -(24 + spill_offset + saved_callee_size),
        }),
      ]
    None => [] // 不需要溢出存储
  }
}

///|
/// 获取值对应的寄存器或生成溢出加载代码
pub fn get_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
  fallback? : Reg = reg_swap,
) -> (Reg, Array[RvAsm]) raise {
  match allocator.value_to_reg.get(value_id) {
    Some(reg) => (reg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
            allocator.saved_callee_fregs.length() * 8
          // 值被溢出到内存，需要加载
          let load_instr = Ld(fallback, {
            base: Fp,
            offset: -(24 + spill_offset + saved_callee_size),
          })
          (fallback, [load_instr])
        }
        None =>
          fail(
            "Value " + value_id.to_string() + " has no register or spill slot",
          )
      }
  }
}

///|
/// 获取浮点寄存器或生成溢出加载代码
pub fn get_float_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
  fallback? : FReg = freg_swap,
) -> (FReg, Array[RvAsm]) {
  match allocator.value_to_freg.get(value_id) {
    Some(freg) => (freg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
            allocator.saved_callee_fregs.length() * 8
          // 值被溢出到内存，需要加载
          let load_instr = Fld(fallback, {
            base: Fp,
            offset: -(24 + spill_offset + saved_callee_size),
          })
          (fallback, [load_instr])
        }
        None =>
          @util.die(
            "Value " +
            value_id.to_string() +
            " has no float register or spill slot",
          )
      }
  }
}

///|
/// 生成浮点溢出存储指令（如果需要）
pub fn generate_float_spill_store_if_needed(
  value_id : Int,
  freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
    allocator.saved_callee_fregs.length() * 8
  match allocator.value_to_spill.get(value_id) {
    Some(spill_offset) =>
      [
        Fsd(freg, {
          base: Fp,
          offset: -(24 + spill_offset + saved_callee_size),
        }),
      ]
    None => [] // 不需要溢出存储
  }
}

///|
fn allocate_value_to_dest_reg(
  value : @ssa.Value,
  dest_reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  match allocator.value_to_reg.get(value.id) {
    Some(reg) => if reg != dest_reg { result.push(Mv(dest_reg, reg)) }
    None =>
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) => {
          let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
            allocator.saved_callee_fregs.length() * 8
          result.push(
            Ld(dest_reg, {
              base: Fp,
              offset: -(24 + spill_offset + saved_callee_size),
            }),
          )
        }
        None =>
          fail(
            "allocate_value_to_dest_reg 分配寄存器或溢出栈槽 value_id=" +
            value.id.to_string(),
          )
      }
  }
  result
}

///|
fn allocate_value_to_dest_freg(
  value : @ssa.Value,
  dest_freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  match allocator.value_to_freg.get(value.id) {
    Some(freg) => if freg != dest_freg { result.push(FmvD(dest_freg, freg)) }
    None =>
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) => {
          let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
            allocator.saved_callee_fregs.length() * 8
          result.push(
            Fld(dest_freg, {
              base: Fp,
              offset: -(24 + spill_offset + saved_callee_size),
            }),
          )
        }
        None =>
          fail(
            "allocate_value_to_dest_freg 分配寄存器或溢出栈槽 value_id=" +
            value.id.to_string(),
          )
      }
  }
  result
}

///|
fn store_value_to_allocator_reg_or_spill(
  value : @ssa.Value,
  input_reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  match allocator.value_to_reg.get(value.id) {
    Some(reg) => if reg != input_reg { result.push(Mv(reg, input_reg)) }
    None =>
      // 检查该参数是否之前已经被计算/溢出
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) => {
          let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
            allocator.saved_callee_fregs.length() * 8
          result.push(
            Sd(input_reg, {
              base: Fp,
              offset: -(24 + spill_offset + saved_callee_size),
            }),
          )
        }
        None =>
          fail(
            "store_value_to_allocator_reg_or_spill 分配寄存器或溢出栈槽 value_id=" +
            value.id.to_string(),
          )
      }
  }
  result
}

///|
fn store_value_to_allocator_freg_or_spill(
  value : @ssa.Value,
  input_freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  match allocator.value_to_freg.get(value.id) {
    Some(freg) => if freg != input_freg { result.push(FmvD(freg, input_freg)) }
    None =>
      // 检查该参数是否之前已经被计算/溢出
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) => {
          let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
            allocator.saved_callee_fregs.length() * 8
          result.push(
            Fsd(input_freg, {
              base: Fp,
              offset: -(24 + spill_offset + saved_callee_size),
            }),
          )
        }
        None =>
          fail(
            "store_value_to_allocator_freg_or_spill 分配寄存器或溢出栈槽 value_id=" +
            value.id.to_string(),
          )
      }
  }
  result
}

///|
/// 移动基本块参数到目标寄存器或溢出栈
fn move_block_params_to_target_reg_or_spill(
  block_map : @hashmap.HashMap[@ssa.Block, @ssa.BasicBlock],
  args : Array[@ssa.Value],
  target : @ssa.Block,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  let target_block = block_map.get(target)
  if target_block is None {
    @util.die("找不到目标块 id=" + target.id.to_string())
  }
  let target = target_block.unwrap()
  if args.length() != target.params.length() {
    @util.logger(
      "Jump 参数数量与目标块参数数量不匹配: " +
      "block " +
      target.id.to_string() +
      " args " +
      args.map(fn(arg) { arg.id.to_string() }).join(", ") +
      " target params " +
      target.params.map(fn(param) { param.id.to_string() }).join(", "),
    )
  }
  for i, arg in args {
    if arg.ty == @ssa.Type::Unit {
      continue
    }
    match arg.ty {
      Float(_) => {
        // args 对应的值移动到 target 对应的参数寄存器或栈位置
        let (arg_freg, spill_instrs) = get_float_register_or_spill_load(
          arg.id,
          allocator,
        )
        result.append(spill_instrs)
        result.append(
          store_value_to_allocator_freg_or_spill(
            target.params[i],
            arg_freg,
            allocator,
          ),
        )
      }
      _ => {
        // args 对应的值移动到 target 对应的参数寄存器或栈位置
        let (arg_reg, spill_instrs) = get_register_or_spill_load(
          arg.id,
          allocator,
        )
        result.append(spill_instrs)
        result.append(
          store_value_to_allocator_reg_or_spill(
            target.params[i],
            arg_reg,
            allocator,
          ),
        )
      }
    }
  }
  result
}

///|
/// 从栈加载参数到寄存器或溢出槽（整数参数）
fn store_value_to_reg_or_spill_from_stack(
  value : @ssa.Value,
  stack_index : Int,  // 栈上参数的索引（0开始）
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
    allocator.saved_callee_fregs.length() * 8

  match allocator.value_to_reg.get(value.id) {
    Some(reg) => {
      // 从栈加载到分配的寄存器
      let stack_offset = stack_index * 8 + 16  // 16字节用于调用者保存区域
      result.push(Ld(reg, { base: Sp, offset: stack_offset }))
    }
    None => {
      // 检查该参数是否需要溢出到栈槽
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) => {
          // 从栈参数位置加载到临时寄存器，然后存储到溢出槽
          let stack_offset = stack_index * 8 + 16
          result.push(Ld(T0, { base: Sp, offset: stack_offset }))
          result.push(Sd(T0, {
            base: Fp,
            offset: -(24 + spill_offset + saved_callee_size),
          }))
        }
        None =>
          fail(
            "store_value_to_reg_or_spill_from_stack 分配寄存器或溢出栈槽 value_id=" +
            value.id.to_string(),
          )
      }
    }
  }
  result
}

///|
/// 从栈加载参数到浮点寄存器或溢出槽（浮点参数）
fn store_value_to_freg_or_spill_from_stack(
  value : @ssa.Value,
  stack_index : Int,  // 栈上参数的索引（0开始）
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let result = []
  let saved_callee_size = allocator.saved_callee_regs.length() * 8 +
    allocator.saved_callee_fregs.length() * 8

  match allocator.value_to_freg.get(value.id) {
    Some(freg) => {
      // 从栈加载到分配的浮点寄存器
      let stack_offset = stack_index * 8 + 16  // 16字节用于调用者保存区域
      result.push(Fld(freg, { base: Sp, offset: stack_offset }))
    }
    None => {
      // 检查该参数是否需要溢出到栈槽
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) => {
          // 从栈参数位置加载到临时浮点寄存器，然后存储到溢出槽
          let stack_offset = stack_index * 8 + 16
          result.push(Fld(Ft0, { base: Sp, offset: stack_offset }))
          result.push(Fsd(Ft0, {
            base: Fp,
            offset: -(24 + spill_offset + saved_callee_size),
          }))
        }
        None =>
          fail(
            "store_value_to_freg_or_spill_from_stack 分配寄存器或溢出栈槽 value_id=" +
            value.id.to_string(),
          )
      }
    }
  }
  result
}
