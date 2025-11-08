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
