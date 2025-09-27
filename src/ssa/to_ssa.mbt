///| 将闭包IR转换为SSA形式

///| 使用基本块参数而非phi函数来实现SSA

///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {
  // @util.logger("closure ir: " + input.to_json().stringify())
  // 初始化SSA程序
  let functions = []

  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      let ssa_func = convert_function(fundef)
      // @util.logger("convert_function: " + ssa_func.to_json().stringify())
      functions.push(ssa_func)
    }
  }

  // 转换主函数体
  let main_func = convert_main_function(input.body)
  functions.push(main_func)
  { program: { functions, } }
}

///|
/// 转换函数定义为SSA形式
fn convert_function(fundef : @closure.FuncDef) -> Function {
  // 创建函数参数（包括正常参数和自由变量）
  let regular_params = fundef.args.map(fn(arg) {
    (Value::{ id: new_value_id() }, convert_type(arg.1))
  })
  
  let free_var_params = fundef.formal_free_vars.map(fn(free_var) {
    (Value::{ id: new_value_id() }, convert_type(free_var.1))
  })
  
  // 合并所有参数
  let all_params = []
  all_params.append(regular_params)
  all_params.append(free_var_params)

  // 创建基本块列表
  let blocks = []

  // 创建入口基本块
  let entry_block = BasicBlock::{
    id: new_block_id(),
    params: [], // 函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None), // 默认返回
  }
  blocks.push(entry_block)
  
  // 创建变量环境，将函数参数添加到环境中
  let mut var_env = @immut/hashmap.new()
  for i, arg in fundef.args {
    let param_name = arg.0
    let param_value = regular_params[i].0
    var_env = var_env.add(param_name, param_value)
  }
  
  // 添加自由变量到环境中
  for i, free_var in fundef.formal_free_vars {
    let free_var_name = free_var.0
    let free_var_value = free_var_params[i].0
    var_env = var_env.add(free_var_name, free_var_value)
  }
  
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env: var_env, // 包含参数和自由变量的环境
  }
  let result = convert_expr(context, fundef.body)
  
  // 更新最后一个块的终止指令，使其返回表达式的结果
  let final_context = result.context
  let return_value = result.value
  let updated_final_block = BasicBlock::{
    id: final_context.current_block.id,
    params: final_context.current_block.params,
    instructions: final_context.current_block.instructions,
    terminator: Terminator::Return(return_value),
  }
  
  // 使用转换后的上下文更新块列表
  let updated_blocks = final_context.blocks.map(fn(b) {
    if b.id == updated_final_block.id {
      updated_final_block
    } else {
      b
    }
  })
  
  {
    name: fundef.name.0.to_string(),
    params: all_params,
    return_type: match fundef.ty {
      @closure.LowType::DirectFn(_, ret) => convert_type(ret)
      @closure.LowType::ClosureFn(_, ret) => convert_type(ret)
      _ => convert_type(fundef.ty)
    },
    blocks: updated_blocks,
  }
}

///|
/// 转换主函数体为SSA形式
fn convert_main_function(body : @closure.Expr) -> Function {
  // 创建主函数参数（通常为空）
  let params = []

  // 创建基本块列表
  let blocks = []

  // 创建入口基本块
  let entry_block_id = new_block_id()
  let entry_block = BasicBlock::{
    id: entry_block_id,
    params: [], // 主函数入口块没有参数
    instructions: [],
    terminator: Terminator::Return(None), // 默认返回
  }
  blocks.push(entry_block)
  // 实现主函数体转换逻辑 这里需要将闭包IR表达式转换为SSA指令
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env: @immut/hashmap.new(), // 变量环境
  }
  // 转换表达式
  let result = convert_expr(context, body)

  // 更新最后一个块的终止指令
  let final_context = result.context
  // let return_value = result.value

  let updated_final_block = BasicBlock::{
    id: final_context.current_block.id,
    params: final_context.current_block.params,
    instructions: final_context.current_block.instructions,
    terminator: Terminator::Return(None), // 主函数通常返回Unit，但可能有值
  }
  
  // 更新块列表
  let updated_blocks = final_context.blocks.map(fn(b) {
    if b.id == updated_final_block.id {
      updated_final_block
    } else {
      b
    }
  })
  
  {
    name: "minimbt_main",
    params,
    return_type: Type::Unit,
    blocks: updated_blocks,
  }
}

///|
/// 转换上下文
priv struct Context {
  current_block : BasicBlock
  blocks : Array[BasicBlock]
  block_map : @immut/hashmap.HashMap[Int, BasicBlock]
  // 添加变量环境：Name到Value的映射
  var_env : @immut/hashmap.HashMap[@types.Name, Value]
} derive(Show)

///|
/// 表达式转换结果
priv struct ExprResult {
  value : Value?
  context : Context
} derive(Show)

///|
/// 转换闭包IR表达式为SSA指令
fn convert_expr(context : Context, expr : @closure.Expr) -> ExprResult {
  // @util.logger("convert_expr: " + expr.to_string())
  match expr {
    Unit => {
      // Unit值，不产生实际值
      ExprResult::{ value: None, context }
    }
    MakeTuple(elements) => {
      // 元组创建
      let mut current_context = context
      let element_values = []
      
      // 转换所有元素
      for elem in elements {
        let elem_result = convert_expr(current_context, @closure.Expr::Var(elem))
        current_context = elem_result.context
        match elem_result.value {
          Some(val) => element_values.push(val)
          None => () // 跳过Unit元素
        }
      }
      
      // 创建元组值
      let result_value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::Tuple(element_values),
      }
      
      // 更新当前块
      current_context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: current_context.current_block.id,
        params: current_context.current_block.params,
        instructions: current_context.current_block.instructions,
        terminator: current_context.current_block.terminator,
      }
      
      let updated_blocks = current_context.blocks.map(fn(b) {
        if b.id == updated_block.id { updated_block } else { b }
      })
      
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: current_context.block_map,
        var_env: current_context.var_env,
      }
      
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    // 其他未实现的表达式暂时返回None
    LetTuple(_, _, _)
    | TupleGet(_, _, _)
    | ArrayPut(_, _, _)
    | ArrayGet(_, _)
    | ExternalArray(Label(_))
    | Assign(_, _)
    | While(_, _)
    | StaticArrayRef(Label(_)) => {
      @util.logger("Warning: Unimplemented expression type in SSA conversion: " + expr.to_string())
      ExprResult::{ value: None, context }
    }
    Int(i) => {
      let value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: value,
        opcode: Opcode::ConstInt(i),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: context.current_block.id,
        params: context.current_block.params,
        instructions: context.current_block.instructions,
        terminator: context.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context.block_map,
        var_env: context.var_env, // 变量环境
      }
      ExprResult::{ value: Some(value), context: updated_context }
    }
    Int64(i) => {
      let value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: value,
        opcode: Opcode::ConstInt(i.to_int()),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: context.current_block.id,
        params: context.current_block.params,
        instructions: context.current_block.instructions,
        terminator: context.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context.block_map,
        var_env: context.var_env, // 变量环境
      }
      ExprResult::{ value: Some(value), context: updated_context }
    }
    Neg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = result.value.unwrap()

      // 创建结果值和指令 (整数取负: 0 - x)
      let result_value = Value::{ id: new_value_id() }
      let zero_value = Value::{ id: new_value_id() }
      
      // 先创建常量0
      let zero_instruction = Instruction::{
        result: zero_value,
        opcode: Opcode::ConstInt(0),
      }
      
      // 然后执行减法 (0 - operand)
      let neg_instruction = Instruction::{
        result: result_value,
        opcode: Opcode::Sub(zero_value, operand_value),
      }

      // 更新当前块的指令列表
      context1.current_block.instructions.append([zero_instruction, neg_instruction])
      let updated_block = BasicBlock::{
        id: context1.current_block.id,
        params: context1.current_block.params,
        instructions: context1.current_block.instructions,
        terminator: context1.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = context1.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context1.block_map,
        var_env: context1.var_env,
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    FNeg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = result.value.unwrap()

      // 创建结果值和指令 (浮点取负: 0.0 - x)
      let result_value = Value::{ id: new_value_id() }
      let zero_value = Value::{ id: new_value_id() }
      
      // 先创建浮点常量0.0
      let zero_instruction = Instruction::{
        result: zero_value,
        opcode: Opcode::ConstFloat(0.0),
      }
      
      // 然后执行浮点减法 (0.0 - operand)
      let neg_instruction = Instruction::{
        result: result_value,
        opcode: Opcode::FSub(zero_value, operand_value),
      }

      // 更新当前块的指令列表
      context1.current_block.instructions.append([zero_instruction, neg_instruction])
      let updated_block = BasicBlock::{
        id: context1.current_block.id,
        params: context1.current_block.params,
        instructions: context1.current_block.instructions,
        terminator: context1.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = context1.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context1.block_map,
        var_env: context1.var_env,
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    Double(d) => {
      let value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: value,
        opcode: Opcode::ConstFloat(d),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: context.current_block.id,
        params: context.current_block.params,
        instructions: context.current_block.instructions,
        terminator: context.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context.block_map,
        var_env: context.var_env, // 变量环境
      }
      ExprResult::{ value: Some(value), context: updated_context }
    }
    Add(x, y)
    | Sub(x, y)
    | Mul(x, y)
    | Div(x, y)
    | Mod(x, y)
    | FAdd(x, y)
    | FSub(x, y)
    | FMul(x, y)
    | FDiv(x, y)
    | FMod(x, y) => {
      // 先转换左操作数
      let result1 = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result1.context
      // 再转换右操作数
      let result2 = convert_expr(context1, @closure.Expr::Var(y))
      let context2 = result2.context

      // 获取两个操作数的值
      let value1 = result1.value.unwrap()
      let value2 = result2.value.unwrap()

      // 创建结果值和指令
      let result_value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: result_value,
        opcode: match (expr, value1, value2) {
          (Add(_, _), _, _) => Opcode::Add(value1, value2)
          (Sub(_, _), _, _) => Opcode::Sub(value1, value2)
          (Mul(_, _), _, _) => Opcode::Mul(value1, value2)
          (Div(_, _), _, _) => Opcode::Div(value1, value2)
          (Mod(_, _), _, _) => Opcode::Mod(value1, value2)
          (FAdd(_, _), _, _) => Opcode::FAdd(value1, value2)
          (FSub(_, _), _, _) => Opcode::FSub(value1, value2)
          (FMul(_, _), _, _) => Opcode::FMul(value1, value2)
          (FDiv(_, _), _, _) => Opcode::FDiv(value1, value2)
          (FMod(_, _), _, _) => Opcode::FMod(value1, value2)
          _ => @util.die("unexpected expression type")
        },
      }

      // 更新当前块的指令列表
      context2.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: context2.current_block.id,
        params: context2.current_block.params,
        instructions: context2.current_block.instructions,
        terminator: context2.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = context2.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context2.block_map,
        var_env: context2.var_env, // 变量环境
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    IfEq(x, y, e1, e2) | IfLe(x, y, e1, e2) | IfLt(x, y, e1, e2) => {
      // 先转换条件表达式的左操作数
      let result1 = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result1.context
      // 转换右操作数
      let result2 = convert_expr(context1, @closure.Expr::Var(y))
      let context2 = result2.context
      
      // 获取两个操作数的值
      let value1 = result1.value.unwrap()
      let value2 = result2.value.unwrap()

      // 创建比较指令的结果值
      let cmp_result = Value::{ id: new_value_id() }
      let cmp_instruction = Instruction::{
        result: cmp_result,
        opcode: match expr {
          IfEq(_, _, _, _) => Opcode::Eq(value1, value2)
          IfLe(_, _, _, _) => Opcode::Le(value1, value2)  
          IfLt(_, _, _, _) => Opcode::Lt(value1, value2)
          _ => @util.die("unexpected expression type")
        }
      }

      // 将比较指令添加到当前块
      context2.current_block.instructions.push(cmp_instruction)

      // 创建两个分支的块
      let then_block_id = new_block_id()
      let else_block_id = new_block_id()
      let merge_block_id = new_block_id()

      // 创建then块
      let then_block = BasicBlock::{
        id: then_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []),
      }

      // 创建else块
      let else_block = BasicBlock::{
        id: else_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []),
      }

      // 创建合并块 - 修复无限循环问题，应该返回到调用者
      let merge_block = BasicBlock::{
        id: merge_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置，后续会被正确的终止指令替换
      }

      // 更新当前块的终止指令 - 使用比较结果作为分支条件
      let terminator = Terminator::Branch(cmp_result, then_block_id, else_block_id)


      let updated_current_block = BasicBlock::{
        id: context2.current_block.id,
        params: context2.current_block.params,
        instructions: context2.current_block.instructions,
        terminator: terminator,
      }

      // 更新块列表 - 先更新现有块，再添加新块
      let updated_blocks = context2.blocks.map(fn(b) {
        if b.id == updated_current_block.id {
          updated_current_block
        } else {
          b
        }
      })
      updated_blocks.append([then_block, else_block, merge_block])

      // 更新块映射
      let updated_block_map = context2.block_map
        .add(then_block_id.id, then_block)
        .add(else_block_id.id, else_block)
        .add(merge_block_id.id, merge_block)

      // 更新上下文
      let context_with_blocks = Context::{
        current_block: then_block,
        blocks: updated_blocks,
        block_map: updated_block_map,
        var_env: context2.var_env  // 保持变量环境
      }

      // 转换then分支
      let then_result = convert_expr(context_with_blocks, e1)
      let then_context = then_result.context
      let then_value = then_result.value

      // 更新then块的终止指令，跳转到合并块并传递值
      let then_args = match then_value {
        Some(v) => [v]
        None => []
      }
      let updated_then_block = BasicBlock::{
        id: then_context.current_block.id,
        params: then_context.current_block.params,
        instructions: then_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, then_args),
      }

      // 更新上下文，切换到else块
      let else_context = Context::{
        current_block: else_block,
        blocks: then_context.blocks,
        block_map: then_context.block_map,
        var_env: context2.var_env  // 保持变量环境
      }

      // 转换else分支
      let else_result = convert_expr(else_context, e2)
      let final_else_context = else_result.context
      let else_value = else_result.value

      // 更新else块的终止指令，跳转到合并块并传递值
      let else_args = match else_value {
        Some(v) => [v]
        None => []
      }
      let updated_else_block = BasicBlock::{
        id: final_else_context.current_block.id,
        params: final_else_context.current_block.params,
        instructions: final_else_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, else_args),
      }

      // 创建合并块的参数（用于接收then/else分支的值）
      let merge_param = match (then_value, else_value) {
        (Some(_), Some(_)) => {
          let param_value = Value::{ id: new_value_id() }
          [(param_value, Type::Int)] // 假设类型为Int，实际应该根据表达式类型推断
        }
        _ => []
      }

      // 更新合并块设置参数
      let updated_merge_block = BasicBlock::{
        id: merge_block_id,
        params: merge_param,
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置
      }

      // 更新块列表
      let final_blocks = final_else_context.blocks.map(fn(b) {
        if b.id == updated_then_block.id {
          updated_then_block
        } else if b.id == updated_else_block.id {
          updated_else_block
        } else if b.id == merge_block_id {
          updated_merge_block
        } else {
          b
        }
      })

      // 获取合并后的结果值
      let result_value = match merge_param {
        [(param_val, _)] => Some(param_val)
        _ => None
      }
      
      // 更新上下文
      let final_context = Context::{
        current_block: updated_merge_block,
        blocks: final_blocks,
        block_map: final_else_context.block_map,
        var_env: context2.var_env  // 保持变量环境
      }
      
      ExprResult::{ value: result_value, context: final_context }
    }
    Var(name) => {
      // 变量引用，从环境中查找对应的Value
      match context.var_env.get(name) {
        Some(value) => 
          ExprResult::{ value: Some(value), context }
        None => {
          // 如果在环境中找不到变量，这是一个错误
          @util.die("Undefined variable in SSA conversion: " + name.to_string())
        }
      }
    }
    Let((name, _ty), e1, e2) => {
      // Let绑定：先计算e1
      let result1 = convert_expr(context, e1)
      let context1 = result1.context
      
      // 将e1的结果绑定到name
      match result1.value {
        Some(value) => {
          // 更新环境，将name映射到value
          let updated_var_env = context1.var_env.add(name, value)
          let updated_context = Context::{
            current_block: context1.current_block,
            blocks: context1.blocks,
            block_map: context1.block_map,
            var_env: updated_var_env
          }
          
          // 计算e2，使用更新后的环境
          let result2 = convert_expr(updated_context, e2)
          result2
        }
        None => {
          // 如果e1没有返回值，直接计算e2
          let result2 = convert_expr(context1, e2)
          result2
        }
      }
    }
    CallDirect(label, args) => {
      // @util.logger("CallDirect: " + label.0)
      // 直接函数调用
      // 先转换所有参数
      let mut current_context = context
      let arg_values = []

      // 依次转换每个参数
      for arg in args {
        let arg_result = convert_expr(current_context, @closure.Expr::Var(arg))
        current_context = arg_result.context
        let _debug = arg_result.to_string()
        // @util.logger("CallDirect arg: " + _debug)
        match arg_result.value {
          Some(val) => arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      let result_value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::Call(label.0, arg_values),
      }

      // 更新当前块的指令列表
      current_context.current_block.instructions.push(instruction)

      let updated_block = BasicBlock::{
        id: current_context.current_block.id,
        params: current_context.current_block.params,
        instructions: current_context.current_block.instructions,
        terminator: current_context.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = current_context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: current_context.block_map,
        var_env: current_context.var_env, // 变量环境
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    MakeClosure((name, _ty), c, e) => {
      // 闭包创建
      // 创建闭包值
      let closure_value = Value::{ id: new_value_id() }

      // 创建闭包创建指令
      let instruction = Instruction::{
        result: closure_value,
        opcode: Opcode::MakeClosure(
          name.to_string(),
          c.actual_free_vars,
        ),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: context.current_block.id,
        params: context.current_block.params,
        instructions: context.current_block.instructions,
        terminator: context.current_block.terminator,
      }

      // 更新块列表
      let updated_blocks = context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })

      // 将闭包值绑定到name变量
      let updated_var_env = context.var_env.add(name, closure_value)

      let intermediate_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context.block_map,
        var_env: updated_var_env, // 包含新绑定的变量环境
      }

      let result = convert_expr(intermediate_context, e)
      ExprResult::{ value: result.value, context: result.context }
    }
    CallClosure(n, xs) => {
      // 闭包调用
      // 先转换闭包引用
      let closure_result = convert_expr(context, @closure.Expr::Var(n))
      let mut current_context = closure_result.context

      // 转换所有参数，正确链式传递上下文
      let arg_values = []
      for x in xs {
        let arg_result = convert_expr(current_context, @closure.Expr::Var(x))
        current_context = arg_result.context
        match arg_result.value {
          Some(val) => arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      // 获取闭包值
      let closure_value = closure_result.value.unwrap()

      // 创建结果值和指令
      let result_value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::CallClosure(closure_value, arg_values),
      }

      // 更新当前块的指令列表
      current_context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: current_context.current_block.id,
        params: current_context.current_block.params,
        instructions: current_context.current_block.instructions,
        terminator: current_context.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = current_context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let updated_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: current_context.block_map,
        var_env: current_context.var_env, // 变量环境
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
  }
}

///|
/// 转换类型
fn convert_type(ty : @closure.LowType) -> Type {
  match ty {
    Unit => Type::Unit
    Bool => Type::Bool
    Int => Type::Int
    Double => Type::Float
    DirectFn(args, ret) =>
      Type::Function(args.map(convert_type), convert_type(ret))
    ClosureFn(args, ret) =>
      Type::Function(args.map(convert_type), convert_type(ret))
    Tuple(elements) => Type::Tuple(elements.map(convert_type))
    Array(element) => Type::Array(convert_type(element))
    Ptr => Type::Pointer(Type::Int)
  }
}

///|
/// 全局值ID计数器
let global_value_counter : Ref[Int] = Ref::new(0)

///|
/// 生成新的值ID
fn new_value_id() -> Int {
  global_value_counter.val = global_value_counter.val + 1
  global_value_counter.val
}

///|
/// 全局块ID计数器
let global_block_counter : Ref[Int] = Ref::new(0)

///|
/// 生成新的块ID
fn new_block_id() -> Block {
  global_block_counter.val = global_block_counter.val + 1
  Block::{
    id: global_block_counter.val,
  }
}
