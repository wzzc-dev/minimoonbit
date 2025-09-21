///| SSA解释器

///| 用于执行SSA中间表示

///|
/// SSA解释器状态
struct SsaInterpreter {
  // 值存储：Value ID -> 实际值
  values : @immut/hashmap.HashMap[Int, SsaValue]
  // 函数定义映射
  functions : @immut/hashmap.HashMap[String, @ssa.Function]
}

///|
/// SSA值类型
enum SsaValue {
  IntVal(Int)
  FloatVal(Double)
  BoolVal(Bool)
  UnitVal
} derive(Show)

///|
/// 创建新的SSA解释器
pub fn SsaInterpreter::new() -> SsaInterpreter {
  { values: @immut/hashmap.new(), functions: @immut/hashmap.new() }
}

///|
/// 执行SSA程序
pub fn SsaInterpreter::eval_full(
  self : SsaInterpreter,
  program : @ssa.Ssa,
) -> Result[SsaValue, String]{
  // 注册所有函数
  for func in program.program.functions {
    let _ = self.functions.add(func.name, func)

  }

  // 查找主函数并执行
  match self.functions.get("minimbt_main") {
    Some(main_func) => self.eval_function(main_func, [])
    None => Err("Main function not found")
  }
}

///|
/// 执行函数
fn SsaInterpreter::eval_function(self : SsaInterpreter, func : @ssa.Function, args : Array[SsaValue]) -> Result[SsaValue, String] {
  // 设置函数参数
  for i, param_value_type in func.params {
    let arg_val = if i < args.length() { args[i] } else { SsaValue::UnitVal }
    let _ = self.values.add(param_value_type.0.id, arg_val)
    
  }
  
  // 执行第一个基本块
  if func.blocks.length() > 0 {
    self.eval_block(func.blocks[0])
  } else {
    Ok(SsaValue::UnitVal)
  }
}

///|
/// 执行基本块
fn SsaInterpreter::eval_block(self : SsaInterpreter, block : @ssa.BasicBlock) -> Result[SsaValue, String] {
  // 执行所有指令
  for instr in block.instructions {
    let _ = self.eval_instruction(instr)
  }
  
  // 执行终止指令
  self.eval_terminator(block.terminator)
}

///|
/// 执行指令
fn SsaInterpreter::eval_instruction(self : SsaInterpreter, instr : @ssa.Instruction) -> Result[Unit, String] {
  let result_value = match instr.opcode {
    @ssa.Opcode::ConstInt(i) => SsaValue::IntVal(i)
    @ssa.Opcode::ConstFloat(f) => SsaValue::FloatVal(f)
    
    @ssa.Opcode::Add(lhs, rhs) => {
      let lhs_val = self.get_value(lhs).unwrap()
      let rhs_val = self.get_value(rhs).unwrap()
      match (lhs_val, rhs_val) {
        (SsaValue::IntVal(a), SsaValue::IntVal(b)) => SsaValue::IntVal(a + b)
        _ => return Err("Type error in Add")
      }
    }
    
    @ssa.Opcode::Sub(lhs, rhs) => {
      let lhs_val = self.get_value(lhs).unwrap()
      let rhs_val = self.get_value(rhs).unwrap()
      match (lhs_val, rhs_val) {
        (SsaValue::IntVal(a), SsaValue::IntVal(b)) => SsaValue::IntVal(a - b)
        _ => return Err("Type error in Sub")
      }
    }
    
    @ssa.Opcode::Mul(lhs, rhs) => {
      let lhs_val = self.get_value(lhs).unwrap()
      let rhs_val = self.get_value(rhs).unwrap()
      match (lhs_val, rhs_val) {
        (SsaValue::IntVal(a), SsaValue::IntVal(b)) => SsaValue::IntVal(a * b)
        _ => return Err("Type error in Mul")
      }
    }
    
    @ssa.Opcode::Eq(lhs, rhs) => {
      let lhs_val = self.get_value(lhs).unwrap()
      let rhs_val = self.get_value(rhs).unwrap()
      match (lhs_val, rhs_val) {
        (SsaValue::IntVal(a), SsaValue::IntVal(b)) => SsaValue::BoolVal(a == b)
        (SsaValue::FloatVal(a), SsaValue::FloatVal(b)) => SsaValue::BoolVal(a == b)
        _ => return Err("Type error in Eq")
      }
    }
    
    @ssa.Opcode::Lt(lhs, rhs) => {
      let lhs_val = self.get_value(lhs).unwrap()
      let rhs_val = self.get_value(rhs).unwrap()
      match (lhs_val, rhs_val) {
        (SsaValue::IntVal(a), SsaValue::IntVal(b)) => SsaValue::BoolVal(a < b)
        (SsaValue::FloatVal(a), SsaValue::FloatVal(b)) => SsaValue::BoolVal(a < b)
        _ => return Err("Type error in Lt")
      }
    }
    
    _ => {
      return Err("Unimplemented instruction: " + instr.opcode.to_string())
    }
  }
  
  // 存储结果值
  let _ = self.values.add(instr.result.id, result_value)
  Ok(())
}

///|
/// 执行终止指令
fn SsaInterpreter::eval_terminator(self : SsaInterpreter, terminator : @ssa.Terminator) -> Result[SsaValue, String] {
  match terminator {
    @ssa.Terminator::Return(value) => {
      match value {
        Some(val) => {
          let result = self.get_value(val).unwrap()
          Ok(result)
        }
        None => Ok(SsaValue::UnitVal)
      }
    }
    _ => Err("Unimplemented terminator: " + terminator.to_string())
  }
}

///|
/// 获取值
fn SsaInterpreter::get_value(
  self : SsaInterpreter,
  value : @ssa.Value,
) -> Result[SsaValue, String] {
  match self.values.get(value.id) {
    Some(val) => Ok(val)
    None => Err("Undefined value: " + value.id.to_string())
  }
}
