///| 基于def-use链的活跃区间分析模块

///|

///| 为SSA IR实现基于def-use链的直接活跃区间计算
///| 在SSA形式下，每个值只定义一次，因此活跃区间可以直接计算：
///| 活跃区间 = [定义位置, 最后使用位置 + 1]
///| 无需传统的活跃变量分析迭代计算

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
  is_call_result : Bool // 是否是函数调用结果
} derive(Show)

///| 基于def-use链直接计算SSA函数的活跃区间

///|
///| 在SSA形式下，每个值只定义一次，因此活跃区间可以直接通过def-use链计算：
///| 活跃区间 = [定义位置, 最后使用位置 + 1]
///| 无需传统的活跃变量分析迭代计算
pub fn compute_live_intervals_for_function(
  func : @ssa.Function,
) -> (Array[LiveInterval], @sorted_map.SortedMap[Int, Int], Array[Int]) {
  let mut def_positions = @immut/hashmap.new()  // 值ID -> 定义位置
  let mut last_use_positions = @immut/hashmap.new()  // 值ID -> 最后使用位置
  let mut value_types = @immut/hashmap.new()  // 值ID -> 类型
  let mut block_param_indices = @immut/hashmap.new()  // 值ID -> 块参数索引
  let mut is_call_results = @immut/hashmap.new()  // 值ID -> 是否是函数调用结果
  let mut instruction_count = 0

  // 处理函数参数：在位置0定义
  let func_param_ids = @sorted_map.new()
  let has_closure = func.closure_param.length() > 0
  for i, param in func.params + func.closure_param {
    let value_id = param.id
    func_param_ids.set(value_id, i + has_closure.to_int())
    def_positions = def_positions.add(value_id, 0)
    value_types = value_types.add(value_id, param.ty)
    block_param_indices = block_param_indices.add(value_id, None)
    is_call_results = is_call_results.add(value_id, false)
  }

  let kill_points = []

  // 单次遍历所有基本块和指令，收集def-use信息
  for block in func.blocks {
    // 处理基本块参数：在基本块入口处定义
    for i, param in block.params {
      let value_id = param.id
      def_positions = def_positions.add(value_id, instruction_count)
      value_types = value_types.add(value_id, param.ty)
      block_param_indices = block_param_indices.add(value_id, Some(i + 1))
      is_call_results = is_call_results.add(value_id, false)
    }

    // 处理基本块内的指令
    for instr in block.instructions {
      // 记录kill points（函数调用位置）
      match instr.opcode {
        Call(_) | CallRef(_, _) | CallClosure(_, _) | MakeClosure(_) =>
          kill_points.push(instruction_count)
        _ => ()
      }

      // 收集当前指令使用的所有值
      let used_value_ids = get_instruction_uses_ids(instr)
      for used_id in used_value_ids {
        // 更新该值的最后使用位置
        last_use_positions = last_use_positions.add(used_id, instruction_count)

        // 如果是未知的值（可能是函数参数），记录其类型
        if not(value_types.contains(used_id)) {
          value_types = value_types.add(used_id, instr.result.ty)
          block_param_indices = block_param_indices.add(used_id, None)
          is_call_results = is_call_results.add(used_id, false)
        }
      }

      // 记录当前指令定义的值
      let def_value_id = instr.result.id
      def_positions = def_positions.add(def_value_id, instruction_count)
      value_types = value_types.add(def_value_id, instr.result.ty)
      block_param_indices = block_param_indices.add(def_value_id, None)

      // 检查是否是函数调用结果
      let is_call_result = match instr.opcode {
        @ssa.Opcode::Call(_, _)
        | @ssa.Opcode::CallRef(_, _)
        | @ssa.Opcode::CallClosure(_, _)
        | @ssa.Opcode::MakeClosure(_) => true
        _ => false
      }
      is_call_results = is_call_results.add(def_value_id, is_call_result)

      instruction_count = instruction_count + 1
    }

    // 处理终止指令
    let term_uses = get_terminator_uses_ids(block.terminator)
    for used_id in term_uses {
      // 更新该值的最后使用位置
      last_use_positions = last_use_positions.add(used_id, instruction_count)

      // 如果是未知的值，记录其类型
      if not(value_types.contains(used_id)) {
        value_types = value_types.add(used_id, Unit)
        block_param_indices = block_param_indices.add(used_id, None)
        is_call_results = is_call_results.add(used_id, false)
      }
    }
    instruction_count = instruction_count + 1
  }

  // 直接构建活跃区间：[定义位置, 最后使用位置 + 1]
  let result = []
  def_positions.each(fn(value_id, def_pos) {
    let ty = value_types.get(value_id).unwrap()
    let block_param_index = block_param_indices.get(value_id).unwrap()
    let is_call_result = is_call_results.get(value_id).unwrap()

    // 计算活跃区间的结束位置
    let end_pos = match last_use_positions.get(value_id) {
      Some(use_pos) => use_pos + 1  // 活跃区间包含最后使用的指令
      None => def_pos + 1  // 如果没有被使用，活跃区间仅包含定义指令
    }

    result.push({
      value_id,
      block_param_index,
      ty,
      start: def_pos,
      end: end_pos,
      reg: None,
      freg: None,
      spill_slot: None,
      is_call_result,
    })
  })

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
    ConstFloat(_) | ConstInt(_) | ConstBool(_) => ()
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