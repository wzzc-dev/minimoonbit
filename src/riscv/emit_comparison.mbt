///|
/// 比较类型枚举
pub enum ComparisonType {
  Equal
  NotEqual
  LessThan
  LessEqual
  GreaterThan
  GreaterEqual
}

///|
pub fn emit_comparison_instruction(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  comparison_type : ComparisonType,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (lhs_reg, load_lhs) = get_register_or_spill_load(lhs.id, allocator, fallback=T0)
  instrs.append(load_lhs)
  let (rhs_reg, load_rhs) = get_register_or_spill_load(rhs.id, allocator, fallback=T1)
  instrs.append(load_rhs)
  let (rd, load_rd) = get_register_or_spill_load(result_val.id, allocator)
  instrs.append(load_rd)
  let comparison_instrs = match comparison_type {
    ComparisonType::Equal => [Sub(rd, lhs_reg, rhs_reg), Sltiu(rd, rd, 1)]
    ComparisonType::NotEqual =>
      [Sub(rd, lhs_reg, rhs_reg), Sltiu(rd, rd, 1), Xori(rd, rd, 1)]
    ComparisonType::LessThan => [Slt(rd, lhs_reg, rhs_reg)]
    ComparisonType::LessEqual => [Slt(rd, rhs_reg, lhs_reg), Xori(rd, rd, 1)]
    ComparisonType::GreaterThan => [Slt(rd, rhs_reg, lhs_reg)]
    ComparisonType::GreaterEqual => [Slt(rd, lhs_reg, rhs_reg), Xori(rd, rd, 1)]
  }
  instrs.append(comparison_instrs)
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}
