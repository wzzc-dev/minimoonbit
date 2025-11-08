///|
pub fn emit_tuple_instruction(
  result : @ssa.Value,
  values : Array[@ssa.Value],
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
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
  match allocator.value_to_reg.get(result.id) {
    Some(result_reg) =>
      // 将分配的地址保存到结果寄存器
      if result_reg != A0 {
        instrs.push(Mv(result_reg, A0))
      }
    None =>
      match allocator.value_to_spill.get(result.id) {
        Some(spill_offset) =>
          instrs.push(
            Sd(A0, {
              base: Fp,
              offset: -(24 +
              spill_offset +
              allocator.saved_callee_regs.length() * 8),
            }),
          )
        None => @util.die("No spill register found for tuple allocation")
      }
  }
  instrs
}
