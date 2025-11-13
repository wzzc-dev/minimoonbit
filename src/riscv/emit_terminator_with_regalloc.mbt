///|
/// 使用寄存器分配器生成终止指令
fn emit_terminator_with_regalloc(
  terminator : @ssa.Terminator,
  allocator : RegisterAllocator,
  block_map : @hashmap.HashMap[@ssa.Block, @ssa.BasicBlock],
) -> Array[RvAsm] raise {
  let result = []
  match terminator {
    @ssa.Terminator::Return(value) => {
      match value {
        Some(val) =>
          // Check if the return value is a float
          match val.ty {
            Unit => ()
            @ssa.Type::Float =>
              result.append(allocate_value_to_dest_freg(val, Fa0, allocator))
            _ => result.append(allocate_value_to_dest_reg(val, A0, allocator))
          }
        None => ()
      }

      // 使用函数序言中计算的被调用者保存寄存器列表，确保一致性
      let saved_callee_regs = allocator.saved_callee_regs
      let saved_callee_fregs = allocator.saved_callee_fregs

      // 计算栈帧大小：与函数序言中的计算保持一致
      let spill_size = allocator.next_spill_slot
      let saved_callee_size =
        allocator.saved_callee_regs.length() * 8 +
        allocator.saved_callee_fregs.length() * 8

      let framesize = 24 +
        spill_size +
        saved_callee_size

      // 恢复被调用者保存的寄存器从栈上
      let mut offset = 24
      for reg in saved_callee_regs {
        result.push(Ld(reg, { base: Fp, offset: -offset }))
        offset += 8
      }
      // 恢复被调用者保存的浮点寄存器从栈上
      for freg in saved_callee_fregs {
        result.push(Fld(freg, { base: Fp, offset: -offset }))
        offset += 8
      }
      result.push(Ld(Ra, { base: Sp, offset: framesize - 8 }))
      result.push(Ld(Fp, { base: Sp, offset: framesize - 16 }))
      result.push(Addi(Sp, Sp, framesize))
      result.push(Ret)
    }
    @ssa.Terminator::Jump(target, args) => {
      let move_instrs = move_block_params_to_target_reg_or_spill(
        block_map, args, target, allocator,
      ) catch {
        e =>
          fail(
            "Compilation error: [Jump]: target:" +
            target.id.to_string() +
            ", args:" +
            args.to_string() +
            ", " +
            e.to_string(),
          )
      }
      result.append(move_instrs)
      result.push(J("block_" + target.id.to_string()))
    }
    @ssa.Terminator::Branch(
      cond,
      true_block,
      true_args,
      false_block,
      false_args
    ) => {
      result.append(
        move_block_params_to_target_reg_or_spill(
          block_map, true_args, true_block, allocator,
        ),
      )
      let saved_callee_size =
        allocator.saved_callee_regs.length() * 8 +
        allocator.saved_callee_fregs.length() * 8
      
      let cond_reg = match allocator.value_to_reg.get(cond.id) {
        Some(cond_reg) => cond_reg
        None =>
          match allocator.value_to_spill.get(cond.id) {
            Some(spill_offset) => {
              result.push(
                Ld(T0, {
                  base: Fp,
                  offset: -(24 + spill_offset + saved_callee_size),
                }),
              )
              T0
            }
            None =>
              @util.die(
                "TODO: 条件分支需要分配寄存器或溢出栈槽",
              )
          }
      }
      result.push(Bne(cond_reg, Zero, "block_" + true_block.id.to_string()))
      let false_target_block = block_map.get(false_block)
      if false_target_block is None {
        @util.die("找不到目标块 id=" + false_block.id.to_string())
      }
      result.append(
        move_block_params_to_target_reg_or_spill(
          block_map, false_args, false_block, allocator,
        ),
      )
      result.push(J("block_" + false_block.id.to_string()))
    }
  }
  result
}
