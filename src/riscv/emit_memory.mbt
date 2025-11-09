///|
/// 生成内存加载指令
pub fn emit_memory_load_instruction(
  result_val : @ssa.Value,
  address_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  let (rd, load_rd) = get_register_or_spill_load(
    result_val.id,
    allocator,
    fallback=T0,
  )
  let (addr_reg, load_addr) = get_register_or_spill_load(
    address_val.id,
    allocator,
  )
  instrs.append(load_rd)
  instrs.append(load_addr)
  instrs.push(Ld(rd, { base: addr_reg, offset: 0 }))
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}

///|
/// 生成内存存储指令
pub fn emit_memory_store_instruction(
  address_val : @ssa.Value,
  value_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  let (addr_reg, load_addr) = get_register_or_spill_load(
    address_val.id,
    allocator,
    fallback=T0,
  )
  let (value_reg, load_value) = get_register_or_spill_load(
    value_val.id,
    allocator,
  )
  instrs.append(load_addr)
  instrs.append(load_value)
  instrs.push(Sd(value_reg, { base: addr_reg, offset: 0 }))
  instrs
}

///|
/// 生成内存分配指令
pub fn emit_memory_allocation(
  result_val : @ssa.Value,
  ty : @ssa.Type,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  let (result_reg, load_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_instrs)

  // 将分配大小放入参数寄存器
  let size = match ty {
    @ssa.Type::Unit => "8"
    _ => "0" // 其他类型暂不支持
  }
  instrs.push(Li(A0, size.to_string()))
  instrs.push(Call(Label("minimbt_malloc")))

  // 将返回的指针移动到结果寄存器
  if result_reg != A0 {
    instrs.push(Mv(result_reg, A0))
  }
  instrs
}
