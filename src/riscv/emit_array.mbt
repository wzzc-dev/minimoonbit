///|
/// 生成数组访问指令
pub fn emit_array_access_instruction(
  result_val : @ssa.Value,
  array_val : @ssa.Value,
  index_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  instrs.push(Comment("ArrayGet: accessing array element"))

  // 获取数组基地址和索引值的寄存器
  let (array_reg, load_array_instrs) = get_register_or_spill_load(
    array_val.id,
    allocator,
  )
  let (index_reg, load_index_instrs) = get_register_or_spill_load(
    index_val.id,
    allocator,
  )
  instrs.append(load_array_instrs)
  instrs.append(load_index_instrs)

  // 计算元素偏移量
  let scale = match result_val.ty {
    @ssa.Type::Int => 2 // 2^2 = 4 bytes
    _ => 3 // 2^3 = 8 bytes
  }
  instrs.push(Slli(T0, index_reg, scale)) // T0 = index * scale

  // 计算元素地址：base + offset
  instrs.push(Add(T1, array_reg, T0))

  // 根据元素类型加载值
  match result_val.ty {
    @ssa.Type::Int => {
      let (result_reg, load_result_instrs) = get_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      instrs.push(Lw(result_reg, { base: T1, offset: 0 }))
      let spill_instrs = generate_spill_store_if_needed(
        result_val.id,
        result_reg,
        allocator,
      )
      instrs.append(spill_instrs)
    }
    @ssa.Type::Float => {
      let (result_reg, load_result_instrs) = get_float_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      instrs.push(Fld(result_reg, { base: T1, offset: 0 }))
      let spill_instrs = generate_float_spill_store_if_needed(
        result_val.id,
        result_reg,
        allocator,
      )
      instrs.append(spill_instrs)
    }
    @ssa.Type::Function(_) => {
      let (result_reg, load_result_instrs) = get_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      // instrs.push(Mv(result_reg, T0))
      instrs.push(Ld(result_reg, { base: T1, offset: 0 }))
      let spill_instrs = generate_spill_store_if_needed(
        result_val.id,
        result_reg,
        allocator,
      )
      instrs.append(spill_instrs)
    }
    _ => {
      let (result_reg, load_result_instrs) = get_register_or_spill_load(
        result_val.id,
        allocator,
      )
      instrs.append(load_result_instrs)
      instrs.push(Ld(result_reg, { base: T1, offset: 0 }))
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

///|
/// 生成数组存储指令
pub fn emit_array_store_instruction(
  array_val : @ssa.Value,
  index_val : @ssa.Value,
  value_val : @ssa.Value,
  allocator : RegisterAllocator,
) -> Array[RvAsm] raise {
  let instrs = []
  instrs.push(Comment("ArrayPut: storing array element"))

  // 获取数组基地址和索引值的寄存器
  let (array_reg, load_array_instrs) = get_register_or_spill_load(
    array_val.id,
    allocator,
  )
  let (index_reg, load_index_instrs) = get_register_or_spill_load(
    index_val.id,
    allocator,
  )
  instrs.append(load_array_instrs)
  instrs.append(load_index_instrs)

  // 计算元素偏移量
  let scale = match value_val.ty {
    @ssa.Type::Int => 2 // 2^2 = 4 bytes
    _ => 3 // 2^3 = 8 bytes
  }
  instrs.push(Slli(T1, index_reg, scale)) // T1 = index * scale

  // 计算元素地址：base + offset
  instrs.push(Add(T0, array_reg, T1))

  // 根据元素类型存储值
  match value_val.ty {
    @ssa.Type::Float => {
      let (float_reg, load_float_instrs) = get_float_register_or_spill_load(
        value_val.id,
        allocator,
      )
      instrs.append(load_float_instrs)
      instrs.push(Fsd(float_reg, { base: T0, offset: 0 }))
    }
    @ssa.Type::Int => {
      let (value_reg, load_value_instrs) = get_register_or_spill_load(
        value_val.id,
        allocator,
      )
      instrs.append(load_value_instrs)
      instrs.push(Sw(value_reg, { base: T0, offset: 0 }))
    }
    @ssa.Type::Function(_) => {
      let (value_reg, load_value_instrs) = get_register_or_spill_load(
        value_val.id,
        allocator,
      )
      instrs.append(load_value_instrs)
      instrs.push(Sd(value_reg, { base: T0, offset: 0 }))
    }
    _ => {
      let (value_reg, load_value_instrs) = get_register_or_spill_load(
        value_val.id,
        allocator,
      )
      instrs.append(load_value_instrs)
      instrs.push(Sd(value_reg, { base: T0, offset: 0 }))
    }
  }
  instrs
}
