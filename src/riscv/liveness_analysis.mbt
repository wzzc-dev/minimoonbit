///| 基于def-use链的活跃区间分析模块

///|

///| 为SSA IR实现活跃变量分析，计算每个值的生命周期区间

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

///| 计算SSA函数的活跃区间

///|

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
  let has_closure = func.closure_vars.length() > 0

  // 处理闭包参数（自由变量）
  for closure_vars in func.closure_vars {
    let value_id = closure_vars.id
    // 闭包参数在函数开始时（位置0）定义，先设置结束位置为0
    intervals = intervals.add(value_id, {
      value_id,
      block_param_index: None,
      ty: closure_vars.ty,
      start: 0,
      end: 0,
      reg: None,
      freg: None,
      spill_slot: None,
      is_call_result: false,
    })
  }

  // 处理普通参数
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
      is_call_result: false,
    })
  }
  // @util.logger("func name: " + func.name + " func_param_ids: " + func_param_ids.to_string())
  let kill_points = []

  // 2. 构建控制流图和循环信息
  let (_block_positions, loop_info) = analyze_control_flow(func)
  // @util.logger("block_positions: " + block_positions.to_string())
  // @util.logger("loop_info: " + loop_info.to_string())
  // 遍历所有基本块和指令，计算每个值的定义和使用位置
  for block in func.blocks {
    // 基本块参数在块开始时定义
    // 基本块参数的开始位置是当前指令位置，结束位置稍后根据使用情况更新
    for i, param in block.params {
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
        is_call_result: false,
      })
    }

    // 处理基本块内的指令
    for instr in block.instructions {
      // 记录kill points（函数调用位置）
      match instr.opcode {
        Call(_) | CallRef(_, _) | CallClosure(_, _) | MakeClosure(_) | Tuple(_) =>
          kill_points.push(instruction_count)
        _ => ()
      }

      // 收集当前指令使用的所有值
      let used_value_ids = get_instruction_uses_ids(instr)
      for used_id in used_value_ids {
        // 更新该值的最后使用位置
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
              is_call_result: false,
            })
          Some(_) => () // 已存在的区间，稍后统一更新结束位置
        }
      }

      // 记录当前指令定义的值
      let def_value_id = instr.result.id
      // 检查是否是函数调用结果
      let is_call_result = match instr.opcode {
        @ssa.Opcode::Call(_, _)
        | @ssa.Opcode::CallRef(_, _)
        | @ssa.Opcode::CallClosure(_, _)
        | @ssa.Opcode::MakeClosure(_) => true
        _ => false
      }
      intervals = intervals.add(def_value_id, {
        value_id: def_value_id,
        block_param_index: None,
        ty: instr.result.ty,
        start: instruction_count,
        end: instruction_count,
        reg: None,
        freg: None,
        spill_slot: None,
        is_call_result,
      })
      instruction_count = instruction_count + 1
    }

    // 处理终止指令
    let term_uses = get_terminator_uses_ids(block.terminator)
    for used_id in term_uses {
      // 更新该值的最后使用位置
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
            is_call_result: false,
          })
        Some(_) => () // 已存在的区间，稍后统一更新结束位置
      }
    }
    
    instruction_count = instruction_count + 1
  }

  // 构建活跃区间，考虑循环结构的影响
  let result = []
  intervals.each(fn(value_id, interval) {
    let updated_end = match last_use_positions.get(value_id) {
      Some(pos) => pos + 1 // 活跃区间应该包含最后使用的指令
      None => interval.end
    }
    let interval = { ..interval, end: updated_end }

    // 检查该值是否在循环中使用，如果是则扩展活跃区间
    // @util.logger("is_used_in_loop : " + (interval, loop_info).to_string())
    let final_end = used_in_loop_pos(interval, loop_info)
    // @util.logger("value_id: " + value_id.to_string() + " final_end: " + final_end.to_string() + "\n")
    // @util.logger("value_id: " + value_id.to_string() + " interval: " + interval.to_string() + " final_end: " + final_end.to_string() + "\n")
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
    ArrayRef(_) => ()
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

pub struct LoopInfo {
  loop_head_block_id: Int
  loop_blocks: Array[Int]
  start_pos: Int
  end_pos: Int
} derive (ToJson, Show)
///|
/// 分析控制流图，识别循环结构
fn analyze_control_flow(func : @ssa.Function) -> (@immut/hashmap.HashMap[Int, (Int, Int)], Array[LoopInfo]) {
  let mut block_positions = @immut/hashmap.new()
  let loop_info =[]
  let mut instruction_count = 0

  // 记录每个基本块的指令位置范围
  for block in func.blocks {
    let start_pos = instruction_count
    for _ in block.instructions {
      instruction_count = instruction_count + 1
    }
    let end_pos = instruction_count + 1 // +1 for terminator
    block_positions = block_positions.add(block.id.id, (start_pos, end_pos))
    instruction_count = end_pos
  }

  // 识别循环结构：通过后向边检测
  for block in func.blocks {
    match block.terminator {
      @ssa.Terminator::Jump(target_block, _) => {
        // 检查是否跳回到前面已经处理过的块（循环）
        match block_positions.get(target_block.id) {
          Some((target_start, _)) => {
            match block_positions.get(block.id.id) {
              Some((current_start, current_end)) => {
                if target_start <= current_start {
                  // 发现循环：从当前块跳回到前面的块
                  let loop_blocks = [target_block.id, block.id.id]
                  loop_info.push({loop_head_block_id: target_block.id, loop_blocks: loop_blocks, start_pos: target_start, end_pos: current_end}) // 使用目标块ID作为循环头
                }
              }
              None => ()
            }
          }
          None => ()
        }
      }
      @ssa.Terminator::Branch(_, _true_block, _, _false_block, _) => {
        // 检查两个分支是否形成循环
        // for target_block in [true_block, false_block] {
        //   match block_positions.get(target_block.id) {
        //     Some((target_start, _)) => {
        //       match block_positions.get(block.id.id) {
        //         Some((current_start, _)) => {
        //           if target_start <= current_start {
        //             // 发现循环
        //             let loop_blocks = [target_block.id, block.id.id]
        //             loop_info.push({loop_head_block_id: target_block.id, loop_blocks: loop_blocks, start_pos: target_start, end_pos: current_start}) // 使用目标块ID作为循环头
        //           }
        //         }
        //         None => ()
        //       }
        //     }
        //     None => ()
        //   }
        // }
        ()
      }
      _ => ()
    }
  }
  // @util.logger("block_positions: " + block_positions.to_string())
  (block_positions, loop_info)
}

///|
/// 检查值是否在循环中使用
fn used_in_loop_pos(
  interval : LiveInterval,
  loop_info : Array[LoopInfo],
) -> Int {
  let mut end_pos = interval.end
  for _, loop_blocks in loop_info {
    if interval.start <= loop_blocks.start_pos && interval.end >= loop_blocks.start_pos {
      // @util.logger("interval: " + interval.to_string() + "\nloop_info: " + loop_info.to_string()+"\n\n")
      end_pos = @cmp.maximum(end_pos, loop_blocks.end_pos)
    }
  }
  end_pos
}