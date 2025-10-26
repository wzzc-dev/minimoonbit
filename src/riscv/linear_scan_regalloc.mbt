///| 线性扫描寄存器分配算法

///| 为SSA IR实现线性扫描寄存器分配，包含优化后的活跃区间分析

///|
/// 生命周期区间，表示一个SSA值的活跃范围
struct LiveInterval {
  value_id : Int // SSA值的ID
  block_param_index : Int? // 块参数索引（如果是块参数）
  ty : @ssa.Type // 值的类型
  start : Int // 开始位置（指令编号）
  end : Int // 结束位置（指令编号）  
  reg : Reg? // 分配的整数寄存器（如果有）
  freg : FReg? // 分配的浮点寄存器（如果有）
  spill_slot : Int? // 溢出栈槽位置（如果溢出）
} derive(Show)

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

///| 计算SSA函数的活跃区间

///|
/// 跟踪每个值的实际最后一次使用位置，确保寄存器分配准确
pub fn compute_live_intervals_for_function(
  func : @ssa.Function,
) -> (Array[LiveInterval], @sorted_map.SortedMap[Int, Int], Array[Int]) {
  let mut intervals = @immut/hashmap.new()
  let mut last_use_positions = @immut/hashmap.new()
  let mut instruction_count = 0

  // 1. 首先记录参数的定义位置，设置合理的初始活跃区间
  let func_param_ids = @sorted_map.new()
  let has_closure = func.closure_param.length() > 0
  for i, param in func.params {
    let value_id = param.id
    func_param_ids.set(value_id, i + has_closure.to_int())
    // 参数在函数开始时（位置0）定义，先设置结束位置为0
    intervals = intervals.add(value_id, {
      value_id,
      block_param_index: None,
      ty: param.ty,
      start: 0,
      end: 0,
      reg: None,
      freg: None,
      spill_slot: None,
    })
  }
  // @util.logger("func name: " + func.name + " func_param_ids: " + func_param_ids.to_string())
  let kill_points = []

  // 遍历所有基本块和指令，计算每个值的定义和使用位置
  for block in func.blocks {
    // 基本块参数在块开始时定义
    // 基本块参数的开始位置是当前指令位置，结束位置稍后根据使用情况更新
    for i,param in block.params {
      let value_id = param.id
      intervals = intervals.add(value_id, {
        value_id,
        block_param_index: Some(i + 1),
        ty: param.ty,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        freg: None,
        spill_slot: None,
      })
    }
    // 不在这里递增instruction_count，因为基本块参数的定义位置与第一条指令相同

    // 处理块内指令
    for instr in block.instructions {
      match instr.opcode {
          Call(_) | CallRef(_, _) | CallClosure(_, _) | MakeClosure(_) => {
            kill_points.push(instruction_count)
          }
          _ => ()
        }

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
              block_param_index: None,
              ty: instr.result.ty,
              start: 0, // 对于参数，假设从位置0开始
              end: instruction_count, // 当前指令位置
              reg: None,
              freg: None,
              spill_slot: None,
            })
          Some(_) => () // 已存在的区间，稍后统一更新结束位置
        }
      }

      // 记录当前指令定义的值
      let def_value_id = instr.result.id
      intervals = intervals.add(def_value_id, {
        value_id: def_value_id,
        block_param_index: None,
        ty: instr.result.ty,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        freg: None,
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
            block_param_index: None,
            ty: Unit,
            start: 0, // 对于参数，假设从位置0开始
            end: instruction_count, // 当前指令位置
            reg: None,
            freg: None,
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
  // @util.logger("func name: " + func.name + " kill_points: " + kill_points.to_string())
  (result, func_param_ids, kill_points)
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
      match closure {
        @ssa.Func::Call(callee) => uses.push(callee.id)
        @ssa.Func::Label(_) => () // 直接函数标签不需要
      }
      for arg in args {
        uses.push(arg.id)
      }
    }
    Alloc(_) => ()
    FMod(lhs, rhs) => {
      uses.push(lhs.id)
      uses.push(rhs.id)
    }
    CallRef(_, arr) =>
      for arg in arr {
        uses.push(arg.id)
      }
    ArrayGet(arr, index) => {
      uses.push(arr.id)
      uses.push(index.id)
    }
    ArrayPut(arr, index, value) => {
      uses.push(arr.id)
      uses.push(index.id)
      uses.push(value.id)
    }
    ConstFloat(_) |
    ConstInt(_) |
    ConstBool(_) => ()
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
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> RegisterAllocator {
  // 初始化寄存器分配器
  // 对于函数参数，优先使用argument registers (A0-A7)，这样可以直接使用参数而无需移动
  // 对于其他值，使用临时寄存器和callee-saved寄存器
  let allocator = {
    available_regs: @set.from_array([
      .. reg_arg_list,
      .. reg_temp_list,
      .. reg_saved_list
    ]),
    available_fregs: @set.from_array([
      .. freg_arg_list,
      .. freg_temp_list,
      .. freg_saved_list
    ]),
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
  sorted_intervals.sort_by(fn(a, b) { a.start - b.start + (if a.start == b.start { a.value_id - b.value_id } else { 0 }) })
  
  // for interval in sorted_intervals {
  //   @util.logger(" interval: " + interval.to_string())
  // }

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

fn live_interval_crosses_kill_point(interval: LiveInterval, kill_points: Array[Int]) -> Bool {
    // 找到第一个 kill point 的位置 >= interval.start
    // 并且 < interval.end（因为 end 是最后一个 use 的位置，通常 inclusive）
    for kp in kill_points {
        if kp >= interval.start && kp <= interval.end {
            return true;
        }
    }
    return false;
}

///|
///| 分配整数寄存器给区间
fn allocate_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> Unit {
  if func_param_ids.contains(interval.value_id) {
    allocate_function_param_register(allocator, interval, func_param_ids, kill_points)
  } else {
    allocate_normal_register(allocator, interval, kill_points)
  }
}

///|
///| 分配浮点寄存器给区间
fn allocate_float_register(
  allocator : RegisterAllocator,
  interval : LiveInterval,
  func_param_ids : @sorted_map.SortedMap[Int, Int],
  kill_points : Array[Int],
) -> Unit {
  if func_param_ids.contains(interval.value_id) {
    allocate_function_param_float_register(allocator, interval, func_param_ids, kill_points)
  } else {
    allocate_normal_float_register(allocator, interval, kill_points)
  }
}

///|
///| 为函数参数分配整数寄存器
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
    // 先判断 reg 寄存器是否已被分配
    if allocator.available_regs.contains(reg) {
      // 检查 live range 是否跨越 kill point。
      if live_interval_crosses_kill_point(interval, kill_points) {
        // 分配寄存器到
        reg = allocator.available_regs.to_array().filter(r => reg_callee_saved_list.contains(r))[0]
      }
    }
    allocate_reg(allocator, reg, interval)
    // @util.logger(" allocate reg: " + reg.to_string() + " interval: " + interval.to_string())
  } else {
    // 其他参数，溢出
    spill_at_interval(allocator, interval)
  }
}

///|
///| 为函数参数分配浮点寄存器
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
    // 先判断 reg 寄存器是否已被分配
    if allocator.available_fregs.contains(freg) {
      // 检查 live range 是否跨越 kill point。
      if live_interval_crosses_kill_point(interval, kill_points) {
        // 分配寄存器到
        freg = allocator.available_fregs.to_array().filter(r => freg_callee_saved_list.contains(r))[0]
      }
    }
    allocate_freg(allocator, freg, interval)
    // @util.logger(" allocate reg: " + reg.to_string() + " interval: " + interval.to_string())
  } else {
    // 其他参数，溢出
    spill_at_interval(allocator, interval)
  }
}

///|
///| 为普通值分配整数寄存器
fn allocate_normal_register(allocator : RegisterAllocator, interval : LiveInterval, kill_points : Array[Int]) -> Unit {
  if allocator.available_regs.size() == 0 {
    // 没有可用寄存器，需要溢出
    spill_at_interval(allocator, interval)
  } else {
    match interval.block_param_index {
      Some(index) => {
        // 基本块参数，分配到对应的寄存器
        let reg = reg_temp_list[index]
        if allocator.available_regs.contains(reg) {
          allocate_reg(allocator, reg, interval)
        } else {
          spill_at_interval(allocator, interval)
        }
      }
      None => {
        // 优先分配 A0-A7, T1-T5, 没有的话分配 S2-S10
        let mut reg = Zero
        if live_interval_crosses_kill_point(interval, kill_points) {
          // 分配寄存器到
          for r in [..reg_temp_list[2:], ..reg_callee_saved_list] {
            if allocator.available_regs.contains(r) {
              reg = r
              break
            }
          }
        } else {
          for r in [..reg_arg_list[1:], ..reg_temp_list[2:], ..reg_callee_saved_list] {
            if allocator.available_regs.contains(r) {
              reg = r
              break
            }
          }
        }
        
        if reg == Zero {
          @util.die("No available register for allocation")
        }
        allocate_reg(allocator, reg, interval)
      }
    }
    // @util.logger(" allocate reg: " + reg.to_string() + " interval: " + interval.to_string())
  }
}

///|
///| 为普通值分配浮点寄存器
fn allocate_normal_float_register(allocator : RegisterAllocator, interval : LiveInterval, kill_points : Array[Int]) -> Unit {
  if allocator.available_fregs.size() == 0 {
    // 没有可用寄存器，需要溢出
    spill_at_interval(allocator, interval)
  } else {
    match interval.block_param_index {
      Some(index) => {
        // 基本块参数，分配到对应的寄存器
        let freg = freg_temp_list[index]
        if allocator.available_fregs.contains(freg) {
          allocate_freg(allocator, freg, interval)
        } else {
          spill_at_interval(allocator, interval)
        }
      }
      None => {
        // 优先分配 A0-A7, T1-T5, 没有的话分配 S2-S10
        let mut freg = Ft0
        if live_interval_crosses_kill_point(interval, kill_points) {
          // 分配寄存器到
          for r in [..freg_temp_list[2:], ..freg_callee_saved_list] {
            if allocator.available_fregs.contains(r) {
              freg = r
              break
            }
          }
        } else {
          for r in [..freg_arg_list[1:], ..freg_temp_list[2:], ..freg_callee_saved_list] {
            if allocator.available_fregs.contains(r) {
              freg = r
              break
            }
          }
        }
        
        if freg == Ft0 {
          @util.die("No available register for allocation")
        }
        allocate_freg(allocator, freg, interval)
      }
    }
  }
}


fn allocate_reg(allocator: RegisterAllocator, reg: Reg, interval: LiveInterval) -> Unit {
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

fn allocate_freg(allocator: RegisterAllocator, freg: FReg, interval: LiveInterval) -> Unit {
  if allocator.available_fregs.contains(freg) {
    allocator.available_fregs.remove(freg)
    allocator.value_to_freg = allocator.value_to_freg.add(interval.value_id, freg)
    track_callee_saved_freg(allocator, freg)
    let new_interval = { ..interval, freg: Some(freg) }
    insert_active_interval(allocator, new_interval)
  } else {
    spill_at_interval(allocator, interval)
  }
}

///|
///| 跟踪需要保存的callee-saved寄存器
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
///| 跟踪需要保存的callee-saved浮点寄存器
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
    if interval.end <= current_pos {
      // 区间已结束，释放寄存器
      match interval.reg {
        Some(reg) => {
          // 将寄存器放回可用池
          allocator.available_regs.add(reg)
        }
        None => ()
      }
      match interval.freg {
        Some(freg) => {
          // 将寄存器放回可用池
          allocator.available_fregs.add(freg)
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
      (reg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          // 值被溢出到内存，需要加载
          // 智能选择临时寄存器，避免与已分配的寄存器冲突
          let temp_reg = T0
          let load_instr = Ld(temp_reg, {
            base: Fp,
            offset: -(24 + spill_offset + allocator.saved_callee_regs.length() * 8),
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
    Some(spill_offset) => [Sd(reg, { base: Fp, offset: -(24 + spill_offset + allocator.saved_callee_regs.length() * 8) })]
    None => [] // 不需要溢出存储
  }
}

pub fn get_float_register_or_spill_load(
  value_id : Int,
  allocator : RegisterAllocator,
) -> (FReg, Array[RvAsm]) {
  match allocator.value_to_freg.get(value_id) {
    Some(freg) =>
      // @util.logger("Value " + value_id.to_string() + " has register " + freg.to_string())
      // 值有寄存器分配，直接使用
      // 即使值也被溢出，优先使用寄存器
      (freg, [])
    None =>
      // 值没有寄存器分配，检查是否被溢出
      match allocator.value_to_spill.get(value_id) {
        Some(spill_offset) => {
          // 值被溢出到内存，需要加载
          // 智能选择临时浮点寄存器，避免与已分配的寄存器冲突
          let temp_freg = Ft0
          let load_instr = Fld(temp_freg, {
            base: Fp,
            offset: -(24 + spill_offset + allocator.saved_callee_fregs.length() * 8),
          })
          (temp_freg, [load_instr])
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

pub fn generate_float_spill_store_if_needed(
  value_id : Int,
  freg : FReg,
  allocator : RegisterAllocator,
) -> Array[RvAsm] {
  match allocator.value_to_spill.get(value_id) {
    Some(spill_offset) => [Fsd(freg, { base: Fp, offset: -(24 + spill_offset + allocator.saved_callee_fregs.length() * 8) })]
    None => [] // 不需要溢出存储
  }
}