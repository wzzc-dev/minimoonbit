///|
pub fn emit_tuple_instruction(
  result : @ssa.Value,
  values : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise{
  let instrs = []
  // 计算元组大小：每个元素8字节，共values.length()个元素
  let tuple_size = values.length() * 8
  // 分配内存
  instrs.push(Li(A0, tuple_size.to_string()))
  instrs.push(Call(Label("minimbt_malloc")))

  // 存储每个元组元素
  for i, value in values {
    let offset = i * 8
    match value.ty {
      Float => {
        let (freg, freg_spill_loads) = get_float_register_or_spill_load(
          value.id,
          allocator,
        )
        instrs.append(freg_spill_loads)
        instrs.push(Fsd(freg, { base: A0, offset }))
      }
      _ => {
        let (result_reg, spill_loads) = get_register_or_spill_load(
          value.id,
          allocator,
        )
        instrs.append(spill_loads)
        instrs.push(Sd(result_reg, { base: A0, offset }))
      }
    }
  }

  instrs.append(store_value_to_allocator_reg_or_spill(result, A0, allocator))
  instrs
}
