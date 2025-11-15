///| 线性扫描寄存器分配算法

///|

///| 为SSA IR实现线性扫描寄存器分配，使用活跃变量分析的结果

///|
/// 寄存器分配器状态
struct RegisterAllocator {
  // 可用的通用寄存器池（避开特殊用途寄存器）
  available_regs : Set[Reg]
  // 可用的浮点寄存器池
  available_fregs : Set[FReg]
  // 当前活跃的区间
  active_intervals : Array[LiveInterval]
  // 值ID到寄存器的映射
  mut value_to_reg : @immut/hashmap.HashMap[Int, Reg]
  // 值ID到浮点数寄存器的映射
  mut value_to_freg : @immut/hashmap.HashMap[Int, FReg]
  // 值ID到栈槽的映射
  mut value_to_spill : @immut/hashmap.HashMap[Int, Int]
  // 下一个可用的栈槽
  mut next_spill_slot : Int
  // 需要保存的寄存器列表
  saved_callee_regs : Array[Reg]
  // 需要保存的浮点寄存器列表
  saved_callee_fregs : Array[FReg]
} derive(Show)

///|
/// 线性扫描寄存器分配算法
pub fn linear_scan_register_allocation(
  intervals : Array[LiveInterval],
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> RegisterAllocator {
  // 初始化寄存器分配器
  // 对于函数参数，优先使用argument registers (A0-A7)，这样可以直接使用参数而无需移动
  // 对于其他值，使用临时寄存器和callee-saved寄存器
  let allocator = {
    available_regs: @set.from_array(
      [..reg_arg_list, ..reg_temp_list, ..reg_saved_list],
    ),
    available_fregs: @set.from_array(
      [..freg_arg_list, ..freg_temp_list, ..freg_saved_list],
    ),
    active_intervals: [],
    value_to_reg: @immut/hashmap.new(),
    value_to_freg: @immut/hashmap.new(),
    value_to_spill: @immut/hashmap.new(),
    next_spill_slot: 0,
    // 需要保存的寄存器列表
    saved_callee_regs: [],
    // 需要保存的浮点寄存器列表
    saved_callee_fregs: [],
  }

  // 按开始位置排序区间
  let sorted_intervals = intervals.copy()
  sorted_intervals.sort_by(fn(a, b) {
    a.start -
    b.start +
    (if a.start == b.start { a.value_id - b.value_id } else { 0 })
  })
  // 为每个区间分配寄存器
  for interval in sorted_intervals {
    // 统一处理所有类型的区间过期
    expire_old_intervals_all(allocator, interval.start)
    if interval.ty == Float {
      allocate_float_register(allocator, interval, func_param_ids, kill_points)
    } else {
      allocate_register(allocator, interval, func_param_ids, kill_points)
    }
  }
  allocator
}

///|
fn live_interval_crosses_kill_point(
  interval : LiveInterval,
  kill_points : Array[Int],
) -> Bool {
  // 找到第一个 kill point 的位置 >= interval.start
  // 并且 < interval.end（因为 end 是最后一个 use 的位置，通常 inclusive）
  for kp in kill_points {
    if interval.is_call_result {
      if kp > interval.start && kp <= interval.end {
        return true
      }
      // println("call result interval: " + interval.to_string())
    } else if kp >= interval.start && kp <= interval.end {
      return true
    }
  }
  return false
}

///|

///|
/// 分配整数寄存器给区间
fn allocate_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> Unit {
  if func_param_ids.contains(interval.value_id) {
    allocate_function_param_register(
      allocator, interval, func_param_ids, kill_points,
    )
  } else {
    allocate_normal_register(allocator, interval, kill_points)
  }
}

///|

///|
/// 分配浮点寄存器给区间
fn allocate_float_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> Unit {
  if func_param_ids.contains(interval.value_id) {
    allocate_function_param_float_register(
      allocator, interval, func_param_ids, kill_points,
    )
  } else {
    allocate_normal_float_register(allocator, interval, kill_points)
  }
}

///|

///|
/// 为函数参数分配整数寄存器
fn allocate_function_param_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> Unit {
  let param_index = func_param_ids.get(interval.value_id).unwrap()
  // @util.logger(" func_param_ids: " + func_param_ids.to_string())
  if param_index < 8 {
    // 函数参数 (A0-A7)
    let mut reg = reg_arg_list[param_index]
    // println("\n")
    // println(" allocate function param reg: " + reg.to_string() + " interval: " + interval.to_string())
    if live_interval_crosses_kill_point(interval, kill_points) {
      // println(" live interval crosses kill point: " + interval.to_string())
      // 分配寄存器到
      reg = allocator.available_regs
        .to_array()
        .filter(r => reg_callee_saved_list.contains(r))[0]
    }
    allocate_reg(allocator, reg, interval)
    // println("\n")
    // @util.logger(" allocate reg: " + reg.to_string() + " interval: " + interval.to_string())
  } else {
    // 其他参数，溢出
    spill_at_interval(allocator, interval)
  }
}

///|

///|
/// 为函数参数分配浮点寄存器
fn allocate_function_param_float_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> Unit {
  let param_index = func_param_ids.get(interval.value_id).unwrap()
  // @util.logger(" func_param_ids: " + func_param_ids.to_string())
  if param_index < 8 {
    // 函数参数 (A0-A7)
    let mut freg = freg_arg_list[param_index]
    if live_interval_crosses_kill_point(interval, kill_points) {
      // 分配寄存器到
      freg = allocator.available_fregs
        .to_array()
        .filter(r => freg_callee_saved_list.contains(r))[0]
    }
    allocate_freg(allocator, freg, interval)
    // @util.logger(" allocate reg: " + reg.to_string() + " interval: " + interval.to_string())
  } else {
    // 其他参数，溢出
    spill_at_interval(allocator, interval)
  }
}

///|

///|
/// 为普通值分配整数寄存器
fn allocate_normal_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  kill_points : Array[Int],
) -> Unit {
  if allocator.available_regs.size() == 0 {
    // 没有可用寄存器，需要溢出
    spill_at_interval(allocator, interval)
  } else {
    match interval.block_param_index {
      Some(_index) => {
        // 基本块参数，分配到对应的寄存器
        let mut reg = Zero 
        for r in reg_saved_list[2:] {
          if allocator.available_regs.contains(r) {
            reg = r
            break
          }
        }
        if reg != Zero {
          allocate_reg(allocator, reg, interval)
        } else {
          spill_at_interval(allocator, interval)
        }
      }
      None => {
        let mut reg = Zero
        if live_interval_crosses_kill_point(interval, kill_points) {
          // 分配寄存器到
          for r in [..reg_temp_list[2:], ..reg_callee_saved_list] {
            if allocator.available_regs.contains(r) {
              reg = r
              break
            }
          }
        } else if false &&
          // 函数调用结果优先分配A0，然后按正常优先级分配
          interval.is_call_result &&
          allocator.available_regs.contains(A0) {
          // 函数调用结果优先分配到A0（返回值寄存器）
          reg = A0
        } else {
          for
            r in [
              ..reg_arg_list[1:],
              ..reg_temp_list[2:],
              ..reg_callee_saved_list,
            ] {
            if allocator.available_regs.contains(r) {
              reg = r
              break
            }
          }
        }
        if reg == Zero {
          spill_at_interval(allocator, interval)
        } else {
          // 没有可用寄存器，需要溢出
          allocate_reg(allocator, reg, interval)
        }
      }
    }
    // @util.logger(" allocate reg: " + reg.to_string() + " interval: " + interval.to_string())
  }
}

///|

///|
/// 为普通值分配浮点寄存器
fn allocate_normal_float_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  kill_points : Array[Int],
) -> Unit {
  if allocator.available_fregs.size() == 0 {
    // 没有可用寄存器，需要溢出
    spill_at_interval(allocator, interval)
  } else {
    match interval.block_param_index {
      Some(_index) => {
        // 基本块参数，分配到对应的寄存器
        let mut freg = Fa0 
        for r in freg_saved_list[2:] {
          if allocator.available_fregs.contains(r) {
            freg = r
            break
          }
        }
        if freg != Ft0 {
          allocate_freg(allocator, freg, interval)
        } else {
          spill_at_interval(allocator, interval)
        }
      }
      None => {
        // 函数调用结果优先分配Fa0，然后按正常优先级分配
        let mut freg = Ft0
        if live_interval_crosses_kill_point(interval, kill_points) {
          // 分配寄存器到
          for r in [..freg_temp_list[2:], ..freg_callee_saved_list] {
            if allocator.available_fregs.contains(r) {
              freg = r
              break
            }
          }
        } else if false &&
          // 函数调用结果优先分配Fa0，然后按正常优先级分配
          interval.is_call_result &&
          allocator.available_fregs.contains(Fa0) {
          // 函数调用结果优先分配到Fa0（返回值寄存器）
          freg = Fa0
        } else {
          for
            r in [
              ..freg_arg_list[1:],
              ..freg_temp_list[2:],
              ..freg_callee_saved_list,
            ] {
            if allocator.available_fregs.contains(r) {
              freg = r
              break
            }
          }
        }
        if freg == Ft0 {
          @util.die("No available float register for allocation")
        }
        allocate_freg(allocator, freg, interval)
      }
    }
  }
}

///|
fn allocate_reg(
  allocator : RegisterAllocator,
  reg : Reg,
  interval : LiveInterval,
) -> Unit {
  if allocator.available_regs.contains(reg) {
    allocator.available_regs.remove(reg)
    allocator.value_to_reg = allocator.value_to_reg.add(interval.value_id, reg)
    track_callee_saved_reg(allocator, reg)
    let new_interval = { ..interval, reg: Some(reg) }
    insert_active_interval(allocator, new_interval)
  } else {
    spill_at_interval(allocator, interval)
  }
  // @util.logger(" allocate reg: " + reg.to_string() + " allocator.available_regs: " + allocator.available_regs.to_string())
}

///|
fn allocate_freg(
  allocator : RegisterAllocator,
  freg : FReg,
  interval : LiveInterval,
) -> Unit {
  if allocator.available_fregs.contains(freg) {
    allocator.available_fregs.remove(freg)
    allocator.value_to_freg = allocator.value_to_freg.add(
      interval.value_id,
      freg,
    )
    track_callee_saved_freg(allocator, freg)
    let new_interval = { ..interval, freg: Some(freg) }
    insert_active_interval(allocator, new_interval)
  } else {
    spill_at_interval(allocator, interval)
  }
}

///|

///|
/// 跟踪需要保存的callee-saved寄存器
fn track_callee_saved_reg(allocator : RegisterAllocator, reg : Reg) -> Unit {
  match reg {
    S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 =>
      if not(allocator.saved_callee_regs.contains(reg)) {
        allocator.saved_callee_regs.push(reg)
      }
    _ => ()
  }
}

///|

///|
/// 跟踪需要保存的callee-saved浮点寄存器
fn track_callee_saved_freg(allocator : RegisterAllocator, freg : FReg) -> Unit {
  match freg {
    Fs2 | Fs3 | Fs4 | Fs5 | Fs6 | Fs7 | Fs8 | Fs9 | Fs10 | Fs11 =>
      if not(allocator.saved_callee_fregs.contains(freg)) {
        allocator.saved_callee_fregs.push(freg)
      }
    _ => ()
  }
}




///|
/// 移除已结束的活跃区间（处理所有类型）
fn expire_old_intervals_all(
  allocator : RegisterAllocator,
  current_pos : Int,
) -> Unit {
  let mut i = 0
  while i < allocator.active_intervals.length() {
    let interval = allocator.active_intervals[i]
    if interval.end < current_pos {
      // 区间已结束，释放寄存器
      match interval.reg {
        Some(reg) =>
          // 将寄存器放回可用池
          allocator.available_regs.add(reg)
        None => ()
      }
      match interval.freg {
        Some(freg) =>
          // 将寄存器放回可用池
          allocator.available_fregs.add(freg)
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
fn calculate_spill_score(
  candidate : LiveInterval,
  current : LiveInterval,
) -> Int {
  // 优先溢出：1) 结束位置更晚的区间 2) 长度更长的区间 3) 与当前区间重叠的区间
  let end_bonus = candidate.end * 2
  let length_bonus = candidate.end - candidate.start
  let overlap_penalty = if intervals_overlap(candidate, current) {
    -100
  } else {
    0
  }
  end_bonus + length_bonus + overlap_penalty
}
