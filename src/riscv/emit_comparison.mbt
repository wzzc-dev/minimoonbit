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
/// 生成比较指令
pub fn emit_comparison_instruction(
  result_val : @ssa.Value,
  lhs : @ssa.Value,
  rhs : @ssa.Value,
  comparison_type : ComparisonType,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  let instrs = []
  let (rd, load_rd) = get_register_or_spill_load(result_val.id, allocator)
  let (rs1, load_rs1) = get_register_or_spill_load(lhs.id, allocator)
  let (rs2, load_rs2) = get_register_or_spill_load(rhs.id, allocator)
  instrs.append(load_rd)
  instrs.append(load_rs1)
  instrs.append(load_rs2)

  // 根据比较类型生成相应的指令序列
  let comparison_instrs = match comparison_type {
    ComparisonType::Equal =>
      [
        Sub(rd, rs1, rs2), // rd = rs1 - rs2
        Sltiu(rd, rd, 1),
      ] // rd = (rd < 1) ? 1 : 0
    // rd = (rd == 0) ? 1 : 0
    ComparisonType::NotEqual =>
      [
        Sub(rd, rs1, rs2), // rd = rs1 - rs2
        Sltiu(rd, rd, 1), // Use signed comparison instead of unsigned
        Xori(rd, rd, 1),
      ] // rd = !rd (if rd != 0, then rd = 1)
    // rd = (rd != 0) ? 1 : 0
    ComparisonType::LessThan => [Slt(rd, rs1, rs2)]
    ComparisonType::LessEqual =>
      [
        Slt(rd, rs2, rs1), // rd = rhs < lhs (检查rhs是否严格小于lhs)
        Xori(rd, rd, 1),
      ] // rd = !rd (如果rhs不严格小于lhs，则lhs <= rhs)
    // rd = !(rhs < lhs) = (lhs <= rhs)
    ComparisonType::GreaterThan => [Slt(rd, rs2, rs1)] // rd = rhs < lhs
    ComparisonType::GreaterEqual =>
      [
        Slt(rd, rs1, rs2), // rd = lhs < rhs
        Xori(rd, rd, 1),
      ]
  } // rd = !rd
  instrs.append(comparison_instrs)
  let spill_instrs = generate_spill_store_if_needed(
    result_val.id,
    rd,
    allocator,
  )
  instrs.append(spill_instrs)
  instrs
}
