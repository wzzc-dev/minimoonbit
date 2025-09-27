///| 线性扫描寄存器分配算法

///| 为SSA IR实现线性扫描寄存器分配

///|
/// 生命周期区间，表示一个SSA值的活跃范围
struct LiveInterval {
  value_id : Int // SSA值的ID
  start : Int // 开始位置（指令编号）
  end : Int // 结束位置（指令编号）  
  reg : Reg? // 分配的寄存器（如果有）
  spill_slot : Int? // 溢出栈槽位置（如果溢出）
} derive(Show)

///|
/// 寄存器分配器状态
struct RegisterAllocator {
  // 可用的通用寄存器池（避开特殊用途寄存器）
  available_regs : Array[Reg]
  // 当前活跃的区间
  active_intervals : Array[LiveInterval]
  // 值ID到寄存器的映射
  mut value_to_reg : @immut/hashmap.HashMap[Int, Reg]
  // 值ID到栈槽的映射  
  mut value_to_spill : @immut/hashmap.HashMap[Int, Int]
  // 下一个可用的栈槽
  mut next_spill_slot : Int
} derive(Show)

///|
/// 计算SSA函数的活跃区间
pub fn compute_live_intervals_for_function(
  func : @ssa.Function,
) -> Array[LiveInterval] {
  let intervals = @immut/hashmap.new()
  let mut instruction_count = 0

  // 遍历所有基本块和指令，计算每个值的定义和使用位置
  for block in func.blocks {
    // 基本块参数在块开始时定义
    for param in block.params {
      let value_id = param.id
      let _ = intervals.add(value_id, {
        value_id,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        spill_slot: None,
      })

    }
    instruction_count += 1

    // 处理块内指令
    for instr in block.instructions {
      // 记录当前指令定义的值
      let def_value_id = instr.result.id
      let _ = intervals.add(def_value_id, {
        value_id: def_value_id,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        spill_slot: None,
      })

      // 更新指令使用的值的结束位置
      let used_value_ids = get_instruction_uses_ids(instr)
      for used_id in used_value_ids {
        match intervals.get(used_id) {
          Some(interval) => {
            let _ = intervals.add(used_id, {
              ..interval,
              end: instruction_count,
            })

          }
          None => {
            // 如果没有找到定义，可能是函数参数或常量，创建一个区间
            let _ = intervals.add(used_id, {
              value_id: used_id,
              start: 0,
              end: instruction_count,
              reg: None,
              spill_slot: None,
            })

          }
        }
      }
      instruction_count += 1
    }

    // 处理终止指令
    let term_uses = get_terminator_uses_ids(block.terminator)
    for used_id in term_uses {
      match intervals.get(used_id) {
        Some(interval) => {
          let _ = intervals.add(used_id, { ..interval, end: instruction_count })

        }
        None => {
          let _ = intervals.add(used_id, {
            value_id: used_id,
            start: 0,
            end: instruction_count,
            reg: None,
            spill_slot: None,
          })

        }
      }
    }
    instruction_count += 1
  }

  // 将HashMap转换为Array
  let result = []
  intervals.each(fn(_key, interval) { result.push(interval) })
  result
}

///|
/// 获取指令使用的SSA值ID
fn get_instruction_uses_ids(instr : @ssa.Instruction) -> Array[Int] {
  let uses = []
  match instr.opcode {
    @ssa.Opcode::Add(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Sub(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Mul(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Div(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Mod(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::FAdd(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::FSub(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::FMul(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::FDiv(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Eq(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Ne(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Lt(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Le(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Gt(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Ge(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    @ssa.Opcode::Call(_, args) =>
      for arg in args {
        uses.push(arg.id)
      }
    @ssa.Opcode::Load(addr) => uses.push(addr.id)
    @ssa.Opcode::Store(addr, value) => {
      uses.push(addr.id)
      uses.push(value.id)
    }
    @ssa.Opcode::Tuple(values) =>
      for val in values {
        uses.push(val.id)
      }
    @ssa.Opcode::GetElement(tuple, _) => uses.push(tuple.id)
    @ssa.Opcode::MakeClosure(_, free_vars) =>
      for _var in free_vars {
        // uses.push(var.0.id)
      }
    @ssa.Opcode::CallClosure(closure, args) => {
      uses.push(closure.id)
      for arg in args {
        uses.push(arg.id)
      }
    }
    _ => () // 常量等不使用其他值
  }
  uses
}

///|
/// 获取终止指令使用的SSA值ID  
fn get_terminator_uses_ids(term : @ssa.Terminator) -> Array[Int] {
  let uses = []
  match term {
    @ssa.Terminator::Return(Some(val)) => uses.push(val.id)
    @ssa.Terminator::Jump(_, args) =>
      for arg in args {
        uses.push(arg.id)
      }
    @ssa.Terminator::Branch(cond, _, _) => uses.push(cond.id)
    _ => ()
  }
  uses
}

///|
/// 线性扫描寄存器分配算法
pub fn linear_scan_register_allocation(
  intervals : Array[LiveInterval],
) -> RegisterAllocator {
  // 初始化寄存器分配器
  let allocator = {
    available_regs: [
      T0,
      T1,
      T2,
      T3,
      T4,
      T5,
      T6,
      S2,
      S3,
      S4,
      S5,
      S6,
      S7,
      S8,
      S9,
      S10,
    ],
    active_intervals: [],
    value_to_reg: @immut/hashmap.new(),
    value_to_spill: @immut/hashmap.new(),
    next_spill_slot: 0,
  }

  // 按开始位置排序区间
  let sorted_intervals = intervals.copy()
  // sorted_intervals.sort(fn(a, b) { a.start - b.start })

  // 为每个区间分配寄存器
  for interval in sorted_intervals {
    // 移除已结束的活跃区间
    expire_old_intervals(allocator, interval.start)
    if allocator.available_regs.length() == 0 {
      // 没有可用寄存器，需要溢出
      spill_at_interval(allocator, interval)
    } else {
      // 分配寄存器
      let reg = allocator.available_regs.unsafe_pop()
      allocator.value_to_reg = allocator.value_to_reg.add(
        interval.value_id,
        reg,
      )

      // 将区间添加到活跃列表（按结束位置排序）
      let new_interval = { ..interval, reg: Some(reg) }
      insert_active_interval(allocator, new_interval)
    }
  }
  allocator
}

///|
/// 移除已结束的活跃区间
fn expire_old_intervals(
  allocator : RegisterAllocator,
  current_pos : Int,
) -> Unit {
  let mut i = 0
  while i < allocator.active_intervals.length() {
    let interval = allocator.active_intervals[i]
    if interval.end < current_pos {
      // 区间已结束，释放寄存器
      match interval.reg {
        Some(reg) => allocator.available_regs.push(reg)
        None => ()
      }
      // 从活跃列表中移除
      let _ = allocator.active_intervals.remove(i)
    } else {
      i += 1
    }
  }
}

///|
/// 溢出区间到内存
fn spill_at_interval(
  allocator : RegisterAllocator,
  interval : LiveInterval,
) -> Unit {
  if allocator.active_intervals.length() == 0 {
    // 没有活跃区间，直接溢出当前区间
    allocator.value_to_spill = allocator.value_to_spill.add(
      interval.value_id,
      allocator.next_spill_slot,
    )
    allocator.next_spill_slot += 8 // 每个槽8字节
    return
  }

  // 找到结束最晚的活跃区间
  let mut spill_candidate = allocator.active_intervals[0]
  let mut spill_index = 0
  for i in 1..<allocator.active_intervals.length() {
    if allocator.active_intervals[i].end > spill_candidate.end {
      spill_candidate = allocator.active_intervals[i]
      spill_index = i
    }
  }
  if spill_candidate.end > interval.end {
    // 溢出候选区间，将其寄存器分配给当前区间
    match spill_candidate.reg {
      Some(reg) => {
        allocator.value_to_reg = allocator.value_to_reg.add(
          interval.value_id,
          reg,
        )
        allocator.value_to_spill = allocator.value_to_spill.add(
          spill_candidate.value_id,
          allocator.next_spill_slot,
        )
        allocator.next_spill_slot += 8

        // 更新活跃区间列表
        let _ = allocator.active_intervals.remove(spill_index)
        let new_interval = { ..interval, reg: Some(reg) }
        insert_active_interval(allocator, new_interval)
      }
      None => {
        // 候选区间没有寄存器，直接溢出当前区间
        allocator.value_to_spill = allocator.value_to_spill.add(
          interval.value_id,
          allocator.next_spill_slot,
        )
        allocator.next_spill_slot += 8
      }
    }
  } else {
    // 溢出当前区间
    allocator.value_to_spill = allocator.value_to_spill.add(
      interval.value_id,
      allocator.next_spill_slot,
    )
    allocator.next_spill_slot += 8
  }
}

///|
/// 将区间插入活跃列表（保持按结束位置排序）
fn insert_active_interval(
  allocator : RegisterAllocator,
  interval : LiveInterval,
) -> Unit {
  let mut inserted = false
  for i in 0..<allocator.active_intervals.length() {
    if interval.end < allocator.active_intervals[i].end {
      allocator.active_intervals.insert(i, interval)
      inserted = true
      break
    }
  }
  if not(inserted) {
    allocator.active_intervals.push(interval)
  }
}

///|
/// 获取值对应的寄存器或生成溢出加载代码
pub fn get_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
) -> (Reg, Array[RvAsm]) {
  match allocator.value_to_reg.get(value_id) {
    Some(reg) => (reg, []) // 直接使用分配的寄存器
    None =>
      // 值被溢出到内存，需要加载
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          let temp_reg = T0 // 使用临时寄存器
          let load_instr = Ld(temp_reg, {
            base: Fp,
            offset: -(24 + spill_offset),
          })
          (temp_reg, [load_instr])
        }
        None => {
          // 如果都没找到，使用简单的基于ID的分配作为回退
          let reg = match value_id % 16 {
            0 => T0
            1 => T1
            2 => T2
            3 => T3
            4 => T4
            5 => T5
            6 => T6
            7 => S2
            8 => S3
            9 => S4
            10 => S5
            11 => S6
            12 => S7
            13 => S8
            14 => S9
            _ => S10
          }
          (reg, [])
        }
      }
  }
}

///|
/// 生成溢出存储代码
pub fn generate_spill_store_if_needed(
  value_id : Int,
  reg : Reg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  match allocator.value_to_spill.get(value_id) {
    Some(spill_offset) => [Sd(reg, { base: Fp, offset: -(24 + spill_offset) })]
    None => [] // 不需要溢出存储
  }
}
