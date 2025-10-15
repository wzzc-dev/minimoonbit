///| 线性扫描寄存器分配算法

///| 为SSA IR实现线性扫描寄存器分配，包含优化后的活跃区间分析

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
///| 检查寄存器是否是被调用者保存寄存器（callee-saved）
fn is_callee_saved(reg : Reg) -> Bool {
  match reg {
    S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 => true
    _ => false
  }
}

///|

///| 计算SSA函数的活跃区间

///|
/// 跟踪每个值的实际最后一次使用位置，确保寄存器分配准确
pub fn compute_live_intervals_for_function(
  func : @ssa.Function,
) -> (Array[LiveInterval], Array[Int]) {
  let mut intervals = @immut/hashmap.new()
  let mut last_use_positions = @immut/hashmap.new()
  let mut instruction_count = 0

  // 1. 首先记录参数的定义位置，设置合理的初始活跃区间
  let param_ids = []
  for param in func.params {
    let value_id = param.id
    param_ids.push(value_id)
    // 参数在函数开始时（位置0）定义，先设置结束位置为0
    intervals = intervals.add(value_id, {
      value_id,
      start: 0,
      end: 0,
      reg: None,
      spill_slot: None,
    })
  }

  // 遍历所有基本块和指令，计算每个值的定义和使用位置
  for block in func.blocks {
    // 基本块参数在块开始时定义
    // 不需要额外增加instruction_count，因为基本块参数应该与跳转指令在同一位置
    for param in block.params {
      let value_id = param.id
      intervals = intervals.add(value_id, {
        value_id,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        spill_slot: None,
      })
    }
    instruction_count = instruction_count + 1

    // 处理块内指令
    for instr in block.instructions {
      // 首先记录指令使用的值的最后使用位置
      let used_value_ids = get_instruction_uses_ids(instr)
      for used_id in used_value_ids {
        // 记录该值的最后使用位置
        last_use_positions = last_use_positions.add(used_id, instruction_count)

        // 如果没有找到定义，可能是函数参数，创建一个区间
        match intervals.get(used_id) {
          None =>
            intervals = intervals.add(used_id, {
              value_id: used_id,
              start: 0, // 对于参数，假设从位置0开始
              end: instruction_count, // 当前指令位置
              reg: None,
              spill_slot: None,
            })
          Some(_) => () // 已存在的区间，稍后统一更新结束位置
        }
      }

      // 记录当前指令定义的值
      let def_value_id = instr.result.id
      intervals = intervals.add(def_value_id, {
        value_id: def_value_id,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        spill_slot: None,
      })
      instruction_count = instruction_count + 1
    }

    // 处理终止指令
    let term_uses = get_terminator_uses_ids(block.terminator)
    for used_id in term_uses {
      // 记录该值的最后使用位置
      last_use_positions = last_use_positions.add(used_id, instruction_count)

      // 如果没有找到定义，可能是函数参数，创建一个区间
      match intervals.get(used_id) {
        None =>
          intervals = intervals.add(used_id, {
            value_id: used_id,
            start: 0, // 对于参数，假设从位置0开始
            end: instruction_count, // 当前指令位置
            reg: None,
            spill_slot: None,
          })
        Some(_) => () // 已存在的区间，稍后统一更新结束位置
      }
    }
    instruction_count = instruction_count + 1
  }

  // 3. 最后统一更新所有值的end为实际最后一次使用位置
  let result = []
  intervals.each(fn(value_id, interval) {
    // 检查该值是否有记录的最后使用位置
    let updated_end = match last_use_positions.get(value_id) {
      Some(pos) => pos + 1 // 活跃区间应该包含最后使用的指令
      None => interval.end
    }

    // 对于函数参数，使用实际的最后使用位置，不延长生命周期
    // 这样可以避免寄存器被长时间占用
    let final_end = updated_end
    result.push({ ..interval, end: final_end })
  })
  (result, param_ids)
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
    @ssa.Opcode::Call(func, args) => {
      match func {
        @ssa.Func::Call(callee) => uses.push(callee.id)
        @ssa.Func::Label(_) => () // 直接函数标签不需要
      }
      for arg in args {
        uses.push(arg.id)
      }
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
      for free_var in free_vars {
        uses.push(free_var.id)
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
    @ssa.Terminator::Branch(cond, _, true_args, _, false_args) => {
      uses.push(cond.id)
      for arg in true_args {
        uses.push(arg.id)
      }
      for arg in false_args {
        uses.push(arg.id)
      }
    }
    _ => ()
  }
  uses
}

///|
/// 线性扫描寄存器分配算法
pub fn linear_scan_register_allocation(
  intervals : Array[LiveInterval],
  param_ids : Array[Int],
) -> RegisterAllocator {
  // 初始化寄存器分配器
  // 优先使用调用者保存寄存器（t0-t5），因为它们不需要在函数调用间保存
  // 注意：T6在RV64中通常是线程指针，不用于通用分配
  let allocator = {
    available_regs: [
      // 参数寄存器（调用者保存）
      A0,
      A1,
      A2,
      A3,
      A4,
      A5,
      A6,
      A7,

      // 临时寄存器（调用者保存）
      T0,
      T1,
      T2,
      T3,
      T4,
      T5,
      T6,
      // 将调用者保存寄存器（caller-saved）放在前面
      // 只有在没有可用寄存器时才使用被调用者保存寄存器（callee-saved）
      S2,
      S3,
      S4,
      S5,
      S6,
      S7,
      S8,
      S9,
      S10,
      S11, // 添加缺失的S11寄存器
    ],
    active_intervals: [],
    value_to_reg: @immut/hashmap.new(),
    value_to_spill: @immut/hashmap.new(),
    next_spill_slot: 0,
  }

  // 按开始位置排序区间
  let sorted_intervals = intervals.copy()
  sorted_intervals.sort_by(fn(a, b) { a.start - b.start })

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

      // 检查是否是函数参数，如果是且被分配到callee-saved寄存器，则强制溢出
      let is_function_param = param_ids.contains(interval.value_id)
      if is_function_param && is_callee_saved(reg) {
        // 将寄存器放回可用列表
        allocator.available_regs.push(reg)
        // 强制溢出函数参数，避免递归调用时的覆盖问题
        spill_at_interval(allocator, interval)
      } else {
        allocator.value_to_reg = allocator.value_to_reg.add(
          interval.value_id,
          reg,
        )

        // 将区间添加到活跃列表（按结束位置排序）
        let new_interval = { ..interval, reg: Some(reg) }
        insert_active_interval(allocator, new_interval)
      }
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
    if interval.end <= current_pos {
      // 区间已结束，释放寄存器
      match interval.reg {
        Some(reg) => {
          // 将寄存器放回可用池
          allocator.available_regs.push(reg)
          // 注意：不要从value_to_reg映射中移除该值！
          // 寄存器分配应该在整个函数期间保持有效
          // 活跃区间只用于跟踪当前使用中的寄存器，不用于最终的分配映射
        }
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

  // 使用智能算法找到最优的溢出候选
  let (spill_candidate, spill_index) = find_best_spill_candidate(
    allocator.active_intervals,
    interval,
  )
  if spill_candidate.end > interval.end {
    // 溢出候选区间，将其寄存器分配给当前区间
    match spill_candidate.reg {
      Some(reg) => {
        // 从value_to_reg中移除被溢出的值，避免寄存器冲突
        // 这样在生成代码时会正确地从内存加载被溢出的值
        allocator.value_to_reg = allocator.value_to_reg.remove(
          spill_candidate.value_id,
        )

        // 将寄存器分配给当前区间
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
/// 检查两个活跃区间是否重叠
fn intervals_overlap(a : LiveInterval, b : LiveInterval) -> Bool {
  not(a.end <= b.start || b.end <= a.start)
}

///|
/// 查找最优的溢出候选（考虑区间长度和重叠情况）
fn find_best_spill_candidate(
  active_intervals : Array[LiveInterval],
  current_interval : LiveInterval,
) -> (LiveInterval, Int) {
  if active_intervals.length() == 0 {
    @util.die("Cannot find spill candidate from empty active intervals")
  }

  let mut best_candidate = active_intervals[0]
  let mut best_index = 0
  let mut best_score = calculate_spill_score(best_candidate, current_interval)

  for i in 1..<active_intervals.length() {
    let candidate = active_intervals[i]
    let score = calculate_spill_score(candidate, current_interval)
    if score > best_score {
      best_score = score
      best_candidate = candidate
      best_index = i
    }
  }

  (best_candidate, best_index)
}

///|
/// 计算溢出分数（分数越高越适合溢出）
fn calculate_spill_score(candidate : LiveInterval, current : LiveInterval) -> Int {
  // 优先溢出：1) 结束位置更晚的区间 2) 长度更长的区间 3) 与当前区间重叠的区间
  let end_bonus = candidate.end * 2
  let length_bonus = (candidate.end - candidate.start)
  let overlap_penalty = if intervals_overlap(candidate, current) { -100 } else { 0 }

  end_bonus + length_bonus + overlap_penalty
}

///|
/// 获取值对应的寄存器或生成溢出加载代码
pub fn get_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
) -> (Reg, Array[RvAsm]) {
  match allocator.value_to_reg.get(value_id) {
    Some(reg) =>
      // @util.logger("Value " + value_id.to_string() + " has register " + reg.to_string())
      // 值有寄存器分配，直接使用
      // 即使值也被溢出，优先使用寄存器
      (reg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          // 值被溢出到内存，需要加载
          // 智能选择临时寄存器，优先选择非caller-saved寄存器以避免冲突
          let temp_reg = match value_id % 10 {
            0 => T0
            1 => T1
            2 => T2
            3 => T3
            4 => T4
            5 => T5
            6 => S2  // 优先使用callee-saved寄存器作为临时寄存器
            7 => S3
            8 => S4
            _ => S5
          }
          let load_instr = Ld(temp_reg, {
            base: Fp,
            offset: -(24 + spill_offset),
          })
          (temp_reg, [load_instr])
        }
        None => {
          @util.die(
            "Value " + value_id.to_string() + " has no register or spill slot",
          )
          // 如果都没有分配，说明这是一个错误情况
          // 在活跃区间计算正确的情况下，所有使用的值都应该有寄存器分配
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

///|
/// 验证寄存器分配的一致性（用于调试）
pub fn verify_allocation_consistency(allocator : RegisterAllocator) -> Bool {
  // 检查是否有重复的寄存器分配
  let allocated_regs = []
  allocator.value_to_reg.each(fn(_value_id, reg) {
    if allocated_regs.contains(reg) {
      @util.logger("Warning: Register " + reg.to_string() + " allocated to multiple values")
    }
    allocated_regs.push(reg)
  })

  // 检查活跃区间与分配映射的一致性
  for interval in allocator.active_intervals {
    match interval.reg {
      Some(reg) => {
        match allocator.value_to_reg.get(interval.value_id) {
          Some(allocated_reg) => {
            if reg != allocated_reg {
              @util.logger("Warning: Inconsistent register allocation for value " + interval.value_id.to_string())
            }
          }
          None => {
            @util.logger("Warning: Active interval has register but no mapping for value " + interval.value_id.to_string())
          }
        }
      }
      None => () // OK - 活跃区间可能没有寄存器（已溢出）
    }
  }

  true
}
