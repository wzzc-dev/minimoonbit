///|
/// 生成整数二元运算指令
pub fn emit_binary_integer_instruction(
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
pub fn emit_binary_float_instruction(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  emitter : (FReg, FReg, FReg) -> RvAsm,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, float_spill_loads) = get_float_register_or_spill_load(
    result_val.id,
    allocator,
  )
  let (rs1, load_rs1) = get_float_register_or_spill_load(lhs.id, allocator)
  let (rs2, load_rs2) = get_float_register_or_spill_load(rhs.id, allocator)
  instrs.append(float_spill_loads)
  instrs.append(load_rs1)
  instrs.append(load_rs2)
  instrs.push(emitter(rd, rs1, rs2))
  let spill_instrs = generate_float_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成浮点取模运算（需要库函数支持）
pub fn emit_float_mod_operation(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, load_result_instrs) = get_float_register_or_spill_load(
    result_val.id,
    allocator,
  )
  let (rs1, load_lhs_instrs) = get_float_register_or_spill_load(
    lhs.id,
    allocator,
  )
  let (rs2, load_rhs_instrs) = get_float_register_or_spill_load(
    rhs.id,
    allocator,
  )
  instrs.append(load_result_instrs)
  instrs.append(load_lhs_instrs)
  instrs.append(load_rhs_instrs)

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
