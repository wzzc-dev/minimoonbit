///|
pub fn emit_get_element_instruction(
  result_val : @ssa.Value,
  tuple_val : @ssa.Value,
  index : Int,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (tuple_reg, tuple_spill_loads) = get_register_or_spill_load(
    tuple_val.id,
    allocator,
    fallback=T0,
  )
  instrs.append(tuple_spill_loads)
  // 计算元素偏移量：index * 8
  let offset = index * 8
  match result_val.ty {
    Float => {
      let (freg_ret, freg_ret_spill_loads) = get_float_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(freg_ret_spill_loads)

      // 从元组地址+偏移量处加载元素值
      instrs.push(Fld(freg_ret, { base: tuple_reg, offset }))
      let spill_instrs = generate_float_spill_store_if_needed(
        result_val.id,
        freg_ret,
        allocator,
      )
      instrs.append(spill_instrs)
    }
    _ => {
      let (result_reg, spill_loads) = get_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(spill_loads)
      instrs.append(tuple_spill_loads)

      // 从元组地址+偏移量处加载元素值
      instrs.push(Ld(result_reg, { base: tuple_reg, offset }))

      // 如果结果需要溢出，生成存储指令
      let spill_instrs = generate_spill_store_if_needed(
        result_val.id,
        result_reg,
        allocator,
      )
      instrs.append(spill_instrs)
    }
  }
  instrs
}
