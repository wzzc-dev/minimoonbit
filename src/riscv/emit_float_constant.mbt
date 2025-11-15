///|
/// 生成浮点常量加载指令
pub fn emit_float_constant_instruction(
  result_val : @ssa.Value,
  value : Double,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []

  // 获取目标浮点寄存器
  let (float_reg, float_spill_loads) = get_float_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(float_spill_loads)
  let bits = value.reinterpret_as_int64()

  // 加载64位常量到临时寄存器
  instrs.push(Li(T0, bits.to_string()))
  instrs.push(FmvDX(float_reg, T0))
  instrs
}
