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

///|
/// 新的内存操作指令生成函数

///|
/// 生成malloc指令
pub fn emit_malloc_instruction(
  result_val : @ssa.Value,
  size : Int,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  instrs.push(Comment("Malloc: " + size.to_string() + " bytes"))

  let (result_reg, load_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_instrs)

  // 调用minimbt_malloc
  instrs.push(Li(A0, size.to_string()))
  instrs.push(Call(Label("minimbt_malloc")))

  // 将返回值移动到结果寄存器
  if result_reg != A0 {
    instrs.push(Mv(result_reg, A0))
  }

  // 如果结果需要溢出，生成存储指令
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    result_reg,
    allocator,
  )
  instrs.append(spill_instrs)

  instrs
}

///|
/// 生成存储指令
pub fn emit_store_instruction(
  result_val : @ssa.Value,
  value : @ssa.Value,
  base : @ssa.Value,
  offset : Int,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  instrs.push(Comment("Store: offset " + offset.to_string()))

  // 获取各个操作数的寄存器
  let (value_reg, value_load_instrs) = get_register_or_spill_load(
    value.id,
    allocator,
  )
  instrs.append(value_load_instrs)

  let (base_reg, base_load_instrs) = get_register_or_spill_load(
    base.id,
    allocator,
  )
  instrs.append(base_load_instrs)

  // 生成存储指令
  instrs.push(Sd(value_reg, { base: base_reg, offset: offset }))

  // Store指令的返回值是Unit，通常不需要处理
  instrs
}

///|
/// 生成加载指令
pub fn emit_load_instruction(
  result_val : @ssa.Value,
  base : @ssa.Value,
  offset : Int,
  ty : @ssa.Type,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  instrs.push(Comment("Load: offset " + offset.to_string() + " type " + ty.to_string()))

  let (result_reg, load_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_instrs)

  let (base_reg, base_load_instrs) = get_register_or_spill_load(
    base.id,
    allocator,
  )
  instrs.append(base_load_instrs)

  // 目前只用于指针类型，使用整数加载
  instrs.push(Ld(result_reg, { base: base_reg, offset: offset }))

  // 如果结果需要溢出，生成存储指令
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    result_reg,
    allocator,
  )
  instrs.append(spill_instrs)

  instrs
}

///|
/// 生成函数指针指令
pub fn emit_func_ptr_instruction(
  result_val : @ssa.Value,
  name : String,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  instrs.push(Comment("ConstFuncPtr: " + name))

  let (result_reg, load_instrs) = get_register_or_spill_load(
    result_val.id,
    allocator,
  )
  instrs.append(load_instrs)

  // 加载函数地址到结果寄存器
  instrs.push(La(result_reg, Label(name)))

  // 如果结果需要溢出，生成存储指令
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    result_reg,
    allocator,
  )
  instrs.append(spill_instrs)

  instrs
}
