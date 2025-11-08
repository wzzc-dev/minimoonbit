///|
/// 生成布尔常量加载指令
pub fn emit_bool_constant_instruction(
  result_val : @ssa.Value,
  value : Bool,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, load_instrs) = get_register_or_spill_load(result_val.id, allocator)
  instrs.append(load_instrs)
  instrs.push(Li(rd, value.to_string()))
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}
