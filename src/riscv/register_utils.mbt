///| 寄存器分配辅助函数
///|
///| 提供寄存器获取、溢出存储等辅助功能

///|
///| 生成溢出存储指令（如果需要）
pub fn generate_spill_store_if_needed(
  value_id : Int,
  reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  match allocator.value_to_spill.get(value_id) {
    Some(spill_offset) => [Sd(reg, { base: Fp, offset: -(24 + spill_offset + allocator.saved_callee_regs.length() * 8) })]
    None => [] // 不需要溢出存储
  }
}

///|
///| 获取值对应的寄存器或生成溢出加载代码
pub fn get_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
  fallback? : Reg = reg_swap,
) -> (Reg, Array[RvAsm]) {
  match allocator.value_to_reg.get(value_id) {
    Some(reg) => (reg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          // 值被溢出到内存，需要加载
          let load_instr = Ld(fallback, {
            base: Fp,
            offset: -(24 +
            spill_offset +
            allocator.saved_callee_regs.length() * 8),
          })
          (fallback, [load_instr])
        }
        None =>
          @util.die(
            "Value " + value_id.to_string() + " has no register or spill slot",
          )
      }
  }
}

///|
///| 获取浮点寄存器或生成溢出加载代码
pub fn get_float_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
  fallback? : FReg = freg_swap,
) -> (FReg, Array[RvAsm]) {
  match allocator.value_to_freg.get(value_id) {
    Some(freg) =>
      (freg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          // 值被溢出到内存，需要加载
          let load_instr = Fld(fallback, {
            base: Fp,
            offset: -(24 + spill_offset + allocator.saved_callee_fregs.length() * 8),
          })
          (fallback, [load_instr])
        }
        None =>
          @util.die(
            "Value " + value_id.to_string() + " has no register or spill slot",
          )
      }
  }
}

///|
///| 生成浮点溢出存储指令（如果需要）
pub fn generate_float_spill_store_if_needed(
  value_id : Int,
  freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  match allocator.value_to_spill.get(value_id) {
    Some(spill_offset) => [Fsd(freg, { base: Fp, offset: -(24 + spill_offset + allocator.saved_callee_fregs.length() * 8) })]
    None => [] // 不需要溢出存储
  }
}

///|
fn allocate_value_to_dest_reg(
  value : @ssa.Value,
  dest_reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let result = []
  match allocator.value_to_reg.get(value.id) {
    Some(reg) => if reg != dest_reg { result.push(Mv(dest_reg, reg)) }
    None =>
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) =>
          result.push(
            Ld(dest_reg, {
              base: Fp,
              offset: -(24 +
              spill_offset +
              allocator.saved_callee_regs.length() * 8),
            }),
          )
        None => @util.die("TODO: 跳转参数需要溢出栈槽")
      }
  }
  result
}


///|
fn allocate_value_to_dest_freg(
  value : @ssa.Value,
  dest_freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let result = []
  match allocator.value_to_freg.get(value.id) {
    Some(freg) => if freg != dest_freg { result.push(FmvD(dest_freg, freg)) }
    None =>
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) =>
          result.push(
            Fld(dest_freg, {
              base: Fp,
              offset: -(24 +
              spill_offset +
              allocator.saved_callee_regs.length() * 8),
            }),
          )
        None => @util.die("TODO: 跳转参数需要溢出栈槽")
      }
  }
  result
}

///|
fn store_value_to_allocator_reg_or_spill(
  value : @ssa.Value,
  input_reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let result = []
  match allocator.value_to_reg.get(value.id) {
    Some(reg) => if reg != input_reg { result.push(Mv(reg, input_reg)) }
    None =>
      // 检查该参数是否之前已经被计算/溢出
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) =>
          result.push(
            Sd(input_reg, {
              base: Fp,
              offset: -(24 +
              spill_offset +
              allocator.saved_callee_regs.length() * 8),
            }),
          )
        None =>
          @util.die("TODO: 普通参数需要分配寄存器或溢出栈槽")
      }
  }
  result
}

///|
fn store_value_to_allocator_freg_or_spill(
  value : @ssa.Value,
  input_freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let result = []
  match allocator.value_to_freg.get(value.id) {
    Some(freg) => if freg != input_freg { result.push(FmvD(freg, input_freg)) }
    None =>
      // 检查该参数是否之前已经被计算/溢出
      match allocator.value_to_spill.get(value.id) {
        Some(spill_offset) =>
          result.push(
            Fsd(input_freg, {
              base: Fp,
              offset: -(24 +
              spill_offset +
              allocator.saved_callee_regs.length() * 8),
            }),
          )
        None =>
          @util.die("TODO: 普通参数需要分配寄存器或溢出栈槽")
      }
  }
  result
}
