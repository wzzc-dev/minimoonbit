///| 将闭包IR转换为SSA形式

///| 使用基本块参数来实现SSA

// ==================== 辅助函数 ====================

///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {
  // @util.logger("closure ir: " + input.to_json().stringify())
  // 初始化SSA程序
  let functions = []

  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      let ssa_func = convert_function(fundef, functions)
      // @util.logger("convert_function: " + ssa_func.to_json().stringify())
      functions.push(ssa_func)
    }
  }

  // 转换主函数体
  let main_func = convert_main_function(input.body, functions)
  functions.push(main_func)
  { program: { functions, } }
}

///|
/// 转换函数定义为SSA形式
fn convert_function(
  fundef : @closure.FuncDef,
  functions : Array[Function],
) -> Function {
  // 创建函数参数（包括正常参数和自由变量）
  let regular_params = fundef.args.map(fn(arg) {
    Value::{ id: new_value_id(), ty: convert_type(arg.1) }
  })
  let free_var_params = fundef.formal_free_vars.map(fn(free_var) {
    Value::{ id: new_value_id(), ty: convert_type(free_var.1) }
  })

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
  // 注意：由于我们改变了参数顺序，需要相应调整索引
  let mut var_env = @immut/hashmap.new()
  for i, free_var in fundef.formal_free_vars {
    let free_var_name = free_var.0
    let free_var_value = free_var_params[i]
    var_env = var_env.add(free_var_name.to_string(), free_var_value)
  }

  // 再添加正常参数到环境中（现在在参数列表的后面）
  for i, arg in fundef.args {
    let param_name = arg.0.to_string()
    let param_value = regular_params[i]
    var_env = var_env.add(param_name, param_value)
  }
  let mut func_env = @immut/hashmap.new().add(
    fundef.name.0.to_string(),
    convert_type(fundef.ty),
  )
  for func in functions {
    func_env = func_env.add(func.name, func.return_type)
  }
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env,
    func_env,
  } // 包含参数和自由变量的环境
  let result = convert_expr(context, fundef.body)
  // @util.logger("convert_expr: " + result.to_string())
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
    params: regular_params,
    closure_param: free_var_params,
    return_type: match fundef.ty {
      @closure.LowType::DirectFn(_, ret) => convert_type(ret)
      @closure.LowType::ClosureFn(_, ret) => convert_type(ret)
      _ => @util.die("unexpected fundef type: " + fundef.ty.to_string())
    },
    blocks: updated_blocks,
  }
}

///|
/// 转换主函数体为SSA形式
fn convert_main_function(
  body : @closure.Expr,
  functions : Array[Function],
) -> Function {
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
  let mut func_env = @immut/hashmap.new()
  for func in functions {
    func_env = func_env.add(func.name, func.return_type)
  }
  // 实现主函数体转换逻辑 这里需要将闭包IR表达式转换为SSA指令
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env: @immut/hashmap.new(), // 变量环境
    func_env,
  } // 函数环境
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
    closure_param: [], // 主函数没有自由变量
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
  var_env : @immut/hashmap.HashMap[String, Value]
  // 添加函数环境：函数名到函数类型的映射
  func_env : @immut/hashmap.HashMap[String, Type]
} derive(Show)

///|
/// 表达式转换结果
priv struct ExprResult {
  value : Value?
  context : Context
} derive(Show)

// ==================== 辅助函数 ====================

///| 更新当前块并返回新的上下文
fn update_current_block(
  context : Context,
  instructions : Array[Instruction],
  terminator : Terminator
) -> Context {
  let updated_block = BasicBlock::{
    id: context.current_block.id,
    params: context.current_block.params,
    instructions,
    terminator,
  }

  let updated_blocks = context.blocks.map(fn(b) {
    if b.id == updated_block.id { updated_block } else { b }
  })

  Context::{
    current_block: updated_block,
    blocks: updated_blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///| 向当前块添加指令并更新上下文
fn add_instruction(context : Context, instruction : Instruction) -> Context {
  let new_instructions = []
  for inst in context.current_block.instructions {
    new_instructions.push(inst)
  }
  new_instructions.push(instruction)
  update_current_block(context, new_instructions, context.current_block.terminator)
}

///| 创建常量值并添加到当前块
fn create_const_int(context : Context, value : Int) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Int }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstInt(value),
  }
  (const_value, add_instruction(context, instruction))
}

///| 创建浮点常量值并添加到当前块
fn create_const_float(context : Context, value : Double) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Float }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstFloat(value),
  }
  (const_value, add_instruction(context, instruction))
}

///| 创建二元运算指令
fn create_binary_op(
  context : Context,
  op_type : BinaryOpType,
  left : Value,
  right : Value,
  result_type : Type
) -> (Value, Context) {
  let result_value = Value::{ id: new_value_id(), ty: result_type }
  let opcode = match op_type {
    BinaryOpType::Add => Opcode::Add(left, right)
    BinaryOpType::Sub => Opcode::Sub(left, right)
    BinaryOpType::Mul => Opcode::Mul(left, right)
    BinaryOpType::Div => Opcode::Div(left, right)
    BinaryOpType::Mod => Opcode::Mod(left, right)
    BinaryOpType::FAdd => Opcode::FAdd(left, right)
    BinaryOpType::FSub => Opcode::FSub(left, right)
    BinaryOpType::FMul => Opcode::FMul(left, right)
    BinaryOpType::FDiv => Opcode::FDiv(left, right)
    BinaryOpType::FMod => Opcode::FMod(left, right)
  }

  let instruction = Instruction::{ result: result_value, opcode }
  (result_value, add_instruction(context, instruction))
}

///| 二元运算类型
priv enum BinaryOpType {
  Add
  Sub
  Mul
  Div
  Mod
  FAdd
  FSub
  FMul
  FDiv
  FMod
}

///| 创建GetElement指令
fn create_get_element(
  context : Context,
  tuple_value : Value,
  index : Int,
  element_type : Type
) -> (Value, Context) {
  let element_value = Value::{ id: new_value_id(), ty: element_type }
  let instruction = Instruction::{
    result: element_value,
    opcode: Opcode::GetElement(tuple_value, index),
  }
  (element_value, add_instruction(context, instruction))
}


///|
/// 转换闭包IR表达式为SSA指令
fn convert_expr(context : Context, expr : @closure.Expr) -> ExprResult {
  // @util.logger("convert_expr: " + expr.to_string())
  match expr {
    Unit =>
      // Unit值，不产生实际值
      ExprResult::{ value: None, context }
    MakeTuple(elements) => {
      // 元组创建
      let mut current_context = context
      let element_values = []

      // 转换所有元素
      for elem in elements {
        let elem_result = convert_expr(
          current_context,
          @closure.Expr::Var(elem),
        )
        current_context = elem_result.context
        match elem_result.value {
          Some(val) => element_values.push(val)
          None => () // 跳过Unit元素
        }
      }

      // 创建元组值
      let result_value = Value::{
        id: new_value_id(),
        ty: Type::Tuple(element_values.map(fn(v) { v.ty })),
      }
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
        var_env: current_context.var_env,
        func_env: current_context.func_env,
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    LetTuple(pattern_vars, tuple_name, body_expr) => {
      // 元组解构：let (x1, x2, ...) = tuple_name in body_expr
      // 获取元组值
      let tuple_value = context.var_env.get(tuple_name.to_string()).unwrap()

      // 为每个模式变量创建元组获取指令
      let mut current_context = context
      let mut updated_var_env = current_context.var_env

      // 为每个变量创建GetElement指令
      let len = pattern_vars.length()
      for i = 0; i < len; i = i + 1 {
        let (var_name, var_type) = pattern_vars[i]
        let element_value = Value::{
          id: new_value_id(),
          ty: convert_type(var_type),
        }
        let instruction = Instruction::{
          result: element_value,
          opcode: Opcode::GetElement(tuple_value, i),
        }

        // 添加指令到当前块
        current_context.current_block.instructions.push(instruction)
        let updated_block = BasicBlock::{
          id: current_context.current_block.id,
          params: current_context.current_block.params,
          instructions: current_context.current_block.instructions,
          terminator: current_context.current_block.terminator,
        }

        // 更新块列表
        let updated_blocks = current_context.blocks.map(fn(b) {
          if b.id == updated_block.id {
            updated_block
          } else {
            b
          }
        })

        // 更新变量环境
        updated_var_env = updated_var_env.add(
          var_name.to_string(),
          element_value,
        )

        // 更新上下文
        current_context = Context::{
          current_block: updated_block,
          blocks: updated_blocks,
          block_map: current_context.block_map,
          var_env: updated_var_env,
          func_env: current_context.func_env,
        }
      }

      // 使用更新后的环境转换body表达式
      convert_expr(current_context, body_expr)
    }
    TupleGet(tuple_name, tuple_type, index) => {
      // 元组访问：tuple_name.index
      let tuple_value = context.var_env.get(tuple_name.to_string()).unwrap()

      // 从元组类型中推断元素类型
      let element_type = match convert_type(tuple_type) {
        Type::Tuple(types) => types[index]
        _ => @util.die("Expected tuple type in TupleGet")
      }

      let (result_value, new_context) = create_get_element(context, tuple_value, index, element_type)
      ExprResult::{ value: Some(result_value), context: new_context }
    }
    ExternalArray(label) => {
      // 外部数组引用：创建一个指向外部数组的值
      let array_value = Value::{
        id: new_value_id(),
        ty: Type::Array(Type::Int),
      } // 默认Int数组

      // 创建外部数组引用指令（使用Call指令）
      let instruction = Instruction::{
        result: array_value,
        opcode: Opcode::Call(Func::Label(label.0), []),
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
        var_env: context.var_env,
        func_env: context.func_env,
      }
      ExprResult::{ value: Some(array_value), context: updated_context }
    }
    Assign(lhs_name, rhs_name) => {
      // 变量赋值：lhs = rhs
      let rhs_value = context.var_env.get(rhs_name.to_string()).unwrap()

      // 在SSA中，赋值操作实际上是更新变量环境
      // 将lhs名称映射到rhs的值
      let updated_var_env = context.var_env.add(lhs_name.to_string(), rhs_value)
      let updated_context = Context::{
        current_block: context.current_block,
        blocks: context.blocks,
        block_map: context.block_map,
        var_env: updated_var_env,
        func_env: context.func_env,
      }

      // 赋值表达式返回Unit类型
      ExprResult::{ value: None, context: updated_context }
    }
    While(cond_expr, body_expr) => {
      // While循环：使用基本块参数实现SSA
      @util.logger("While: cond=" + cond_expr.to_string() + " body=" + body_expr.to_string())

      // 创建新的块ID
      let loop_header_id = new_block_id()
      let body_block_id = new_block_id()
      let exit_block_id = new_block_id()

      // 1. 创建循环头块 - 需要参数来接收循环变量
      // 简化实现：暂时不处理循环变量，假设条件不依赖循环内修改的变量
      let loop_header = BasicBlock::{
        id: loop_header_id,
        params: [], // TODO: 如果条件依赖循环变量，这里需要添加参数
        instructions: [],
        terminator: Terminator::Return(None),
      }

      // 2. 在循环头中转换条件表达式
      let loop_header_context = Context::{
        current_block: loop_header,
        blocks: context.blocks,
        block_map: context.block_map,
        var_env: context.var_env, // 使用初始变量环境
        func_env: context.func_env,
      }

      let cond_result = convert_expr(loop_header_context, cond_expr)
      let cond_context = cond_result.context
      @util.logger("While: cond_result.value=" + cond_result.value.to_string())

      let cond_value = match cond_result.value {
        Some(val) => val
        None => {
          let (default_val, _) = create_const_int(cond_context, 0)
          default_val
        }
      }

      // 3. 更新循环头块，包含条件分支
      let updated_loop_header = BasicBlock::{
        id: loop_header_id,
        params: [],
        instructions: cond_context.current_block.instructions,
        terminator: Terminator::Branch(cond_value, body_block_id, exit_block_id),
      }

      // 4. 创建循环体块
      let body_start_block = BasicBlock::{
        id: body_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(loop_header_id, []), // 跳回循环头
      }

      // 5. 在循环体中转换body表达式
      // 关键修复：确保body_context的blocks包含body_start_block
      let body_blocks = {
        let blocks = []
        for block in cond_context.blocks {
          blocks.push(block)
        }
        blocks.push(body_start_block) // 添加循环体块
        blocks
      }

      let body_context = Context::{
        current_block: body_start_block,
        blocks: body_blocks,
        block_map: cond_context.block_map,
        var_env: cond_context.var_env, // 继承条件评估后的环境
        func_env: cond_context.func_env,
      }
      let body_result = convert_expr(body_context, body_expr)
      let body_final_context = body_result.context

      // 6. 更新循环体块
      let updated_body_block = BasicBlock::{
        id: body_block_id,
        params: [],
        instructions: body_final_context.current_block.instructions,
        terminator: Terminator::Jump(loop_header_id, []), // 跳回循环头，不传参数
      }

      // 7. 创建循环退出块
      let exit_block = BasicBlock::{
        id: exit_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Return(None), // 临时终止符
      }

      // 8. 更新当前块，跳转到循环头
      let updated_current_block = BasicBlock::{
        id: context.current_block.id,
        params: context.current_block.params,
        instructions: context.current_block.instructions,
        terminator: Terminator::Jump(loop_header_id, []),
      }

      // 9. 构建最终块列表 - 确保包含所有块且不重复
      let final_blocks = {
        let blocks = []

        // 首先添加原始上下文中的块（替换当前块）
        for block in context.blocks {
          if block.id == context.current_block.id {
            blocks.push(updated_current_block)
          } else {
            blocks.push(block)
          }
        }

        // 添加循环头块
        blocks.push(updated_loop_header)

        // 关键修复：添加body_final_context中的新块，但避免重复
        // 收集已存在的块ID以避免重复
        let existing_block_ids = blocks.map(fn(b) { b.id })

        for block in body_final_context.blocks {
          if block.id == body_block_id {
            blocks.push(updated_body_block) // 使用我们更新的版本
          } else if not(existing_block_ids.contains(block.id)) {
            blocks.push(block) // 只添加新创建的块
          }
        }

        // 添加退出块
        blocks.push(exit_block)
        blocks
      }

      // 10. 创建最终上下文
      // 注意：如果循环修改了变量，需要通过块参数正确处理
      let final_context = Context::{
        current_block: exit_block,
        blocks: final_blocks,
        block_map: context.block_map,
        var_env: context.var_env, // 暂时保持原有环境
        func_env: context.func_env,
      }

      // While循环返回Unit类型
      ExprResult::{ value: None, context: final_context }
    }
    StaticArrayRef(label) => {
      // 静态数组引用：类似于ExternalArray，但引用的是静态数据段中的数组
      let array_value = Value::{
        id: new_value_id(),
        ty: Type::Array(Type::Int),
      } // 默认Int数组

      // 创建静态数组引用指令
      let instruction = Instruction::{
        result: array_value,
        opcode: Opcode::Call(Func::Label("static_array_" + label.0), []), // 使用特殊的函数名标识静态数组
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
        var_env: context.var_env,
        func_env: context.func_env,
      }
      ExprResult::{ value: Some(array_value), context: updated_context }
    }
    ArrayPut(array_name, index_name, value_name) => {
      // 数组赋值：array[index] = value
      // 获取数组、索引和值的Value
      let array_value = context.var_env.get(array_name.to_string()).unwrap()
      let index_value = context.var_env.get(index_name.to_string()).unwrap()
      let value_to_store = context.var_env.get(value_name.to_string()).unwrap()

      // 验证数组类型
      match array_value.ty {
        Type::Array(_) => () // 验证确实是数组类型
        _ => @util.die("Expected array type in ArrayPut")
      }

      // 创建ArrayPut指令
      let instruction = Instruction::{
        result: Value::{ id: new_value_id(), ty: Type::Unit }, // ArrayPut返回Unit
        opcode: Opcode::ArrayPut(array_value, index_value, value_to_store),
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
        var_env: context.var_env,
        func_env: context.func_env,
      }

      // ArrayPut是表达式，返回Unit类型
      ExprResult::{ value: None, context: updated_context }
    }
    ArrayGet(array_name, index_name) => {
      // 数组访问：array[index]
      // 获取数组和索引的值
      let array_value = context.var_env.get(array_name.to_string()).unwrap()
      let index_value = context.var_env.get(index_name.to_string()).unwrap()

      // 创建结果值 - 数组元素的类型需要从数组类型中推断
      let element_type = match array_value.ty {
        Type::Array(elem_type) => elem_type
        _ => @util.die("Expected array type in ArrayGet")
      }
      let result_value = Value::{ id: new_value_id(), ty: element_type }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::ArrayGet(array_value, index_value),
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
        var_env: context.var_env,
        func_env: context.func_env,
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    Int(i) => {
      let (value, new_context) = create_const_int(context, i)
      ExprResult::{ value: Some(value), context: new_context }
    }
    Int64(i) => {
      let (value, new_context) = create_const_int(context, i.to_int())
      ExprResult::{ value: Some(value), context: new_context }
    }
    Neg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = result.value.unwrap()

      // 整数取负: 0 - x
      let (zero_value, context2) = create_const_int(context1, 0)
      let (result_value, final_context) = create_binary_op(context2, BinaryOpType::Sub, zero_value, operand_value, Type::Int)
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    FNeg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = result.value.unwrap()

      // 浮点取负: 0.0 - x
      let (zero_value, context2) = create_const_float(context1, 0.0)
      let (result_value, final_context) = create_binary_op(context2, BinaryOpType::FSub, zero_value, operand_value, Type::Float)
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    Double(d) => {
      let (value, new_context) = create_const_float(context, d)
      ExprResult::{ value: Some(value), context: new_context }
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
      // 获取两个操作数的值
      let value1 = context.var_env.get(x.to_string()).unwrap()
      let value2 = context.var_env.get(y.to_string()).unwrap()

      // 确定运算类型和结果类型
      let (op_type, result_type) = match expr {
        Add(_, _) => (BinaryOpType::Add, Type::Int)
        Sub(_, _) => (BinaryOpType::Sub, Type::Int)
        Mul(_, _) => (BinaryOpType::Mul, Type::Int)
        Div(_, _) => (BinaryOpType::Div, Type::Int)
        Mod(_, _) => (BinaryOpType::Mod, Type::Int)
        FAdd(_, _) => (BinaryOpType::FAdd, Type::Float)
        FSub(_, _) => (BinaryOpType::FSub, Type::Float)
        FMul(_, _) => (BinaryOpType::FMul, Type::Float)
        FDiv(_, _) => (BinaryOpType::FDiv, Type::Float)
        FMod(_, _) => (BinaryOpType::FMod, Type::Float)
        _ => @util.die("unexpected expression type")
      }

      let (result_value, new_context) = create_binary_op(context, op_type, value1, value2, result_type)
      ExprResult::{ value: Some(result_value), context: new_context }
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
      let cmp_result = Value::{ id: new_value_id(), ty: Type::Bool }
      let cmp_instruction = Instruction::{
        result: cmp_result,
        opcode: match expr {
          IfEq(_, _, _, _) => Opcode::Eq(value1, value2)
          IfLe(_, _, _, _) => Opcode::Le(value1, value2)
          IfLt(_, _, _, _) => Opcode::Lt(value1, value2)
          _ => @util.die("unexpected expression type")
        },
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
      let terminator = Terminator::Branch(
        cmp_result, then_block_id, else_block_id,
      )
      let updated_current_block = BasicBlock::{
        id: context2.current_block.id,
        params: context2.current_block.params,
        instructions: context2.current_block.instructions,
        terminator,
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
        var_env: context2.var_env, // 保持变量环境
        func_env: context2.func_env,
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
        var_env: context2.var_env, // 保持变量环境
        func_env: context2.func_env,
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
          let param_value = Value::{ id: new_value_id(), ty: Type::Int }
          [param_value]
        } // 假设类型为Int，实际应该根据表达式类型推断
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
        [param_val] => Some(param_val)
        _ => None
      }

      // 更新上下文
      let final_context = Context::{
        current_block: updated_merge_block,
        blocks: final_blocks,
        block_map: final_else_context.block_map,
        var_env: context2.var_env, // 保持变量环境
        func_env: context2.func_env,
      }
      ExprResult::{ value: result_value, context: final_context }
    }
    Var(name) => {
      // @util.logger("Var: " + name.to_string() + " context.func_env: " + context.func_env.to_string())
      // 变量引用，先从变量环境中查找
      match context.var_env.get(name.to_string()) {
        Some(value) => ExprResult::{ value: Some(value), context }
        None =>
          // 如果在变量环境中找不到，尝试从函数环境中查找
          match context.func_env.get(name.to_string()) {
            Some(func_type) => {
              // 找到函数，创建一个函数引用值
              // 对于函数引用，我们也应该创建一条指令
              let result_value = Value::{ id: new_value_id(), ty: func_type }
              let instruction = Instruction::{
                result: result_value,
                opcode: Opcode::CallRef(name.to_string(), []),
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
                var_env: context.var_env,
                func_env: context.func_env,
              }
              ExprResult::{ value: Some(result_value), context: updated_context }
            }
            None =>
              // @util.logger("Var: " + name.to_string() + " not found")
              // 如果在函数环境中也找不到，这是一个错误
              ExprResult::{ value: None, context }
          }
      }
    }
    Let((name, _ty), e1, e2) => {

      // Let绑定：先计算e1
      let result1 = convert_expr(context, e1)
      let context1 = result1.context
      // @util.logger(
      //   "Let: " +
      //   name.to_string() +
      //   " = " +
      //   e1.to_string() +
      //   " in " +
      //   e2.to_string() +
      //   ", result1: " +
      //   result1.value.to_string(),
      // )
      // 将e1的结果绑定到name
      match result1.value {
        Some(value) => {
          // 更新环境，将name映射到value
          let updated_var_env = context1.var_env.add(name.to_string(), value)
          let updated_context = Context::{
            current_block: context1.current_block,
            blocks: context1.blocks,
            block_map: context1.block_map,
            var_env: updated_var_env,
            func_env: context1.func_env,
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
      // @util.logger("CallDirect args: " + args.to_string())
      // @util.logger(
      //   "CallDirect var: " +
      //   context.var_env.to_string() +
      //   " func_env: " +
      //   context.func_env.to_string(),
      // )
      // 直接函数调用
      // 先转换所有参数
      let mut current_context = context
      let arg_values = []

      // 依次转换每个参数
      for arg in args {
        // @util.logger("CallDirect arg: " + arg.to_string())
        let arg_result = convert_expr(current_context, @closure.Expr::Var(arg))
        current_context = arg_result.context
        let _debug = arg_result.to_string()
        // @util.logger("CallDirect arg: " + _debug)
        match arg_result.value {
          Some(val) => arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      // 根据函数名确定返回类型
      // 优先从Context的函数环境中查找
      let return_type = match current_context.func_env.get(label.0) {
        Some(func_type) =>
          // 从函数环境中找到函数类型，提取返回类型
          match func_type {
            Type::Function(_, ret_type) => ret_type
            _ => Type::Int // 默认返回Int
          }
        None =>
          // 从外部环境中查找类型信息
          match @typing.extenv.get(label.0) {
            Some(func_type) =>
              // 从外部环境中找到函数类型，提取返回类型
              match func_type {
                @types.Type::Fun(_, ret_type) =>
                  convert_type_from_types(ret_type)
                _ => Type::Int // 默认返回Int
              }
            None =>
              match context.var_env.get(label.0.to_string()) {
                Some(v) =>
                  match v.ty {
                    Type::Function(_, ret_type) => ret_type
                    _ => Type::Int // 默认返回Int
                  }
                None => Type::Int // 默认返回Int
              }
          }
      }
      let opcode = match context.var_env.get(label.0.to_string()) {
        Some(v) => Opcode::Call(Func::Call(v), arg_values)
        None => Opcode::Call(Func::Label(label.0), arg_values)
      }
      let result_value = Value::{ id: new_value_id(), ty: return_type }
      let instruction = Instruction::{ result: result_value, opcode }

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
        func_env: current_context.func_env,
      }
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    MakeClosure((name, ty), c, e) => {
      // 闭包创建
      // 创建闭包值
      let closure_value = Value::{ id: new_value_id(), ty: convert_type(ty) }

      // 创建闭包创建指令
      let instruction = Instruction::{
        result: closure_value,
        opcode: Opcode::MakeClosure(
          name.to_string(),
          c.actual_free_vars.map(fn(fv) {
            context.var_env.get(fv.to_string()).unwrap()
          }),
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
      let updated_var_env = context.var_env.add(name.to_string(), closure_value)
      let intermediate_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: context.block_map,
        var_env: updated_var_env, // 包含新绑定的变量环境
        func_env: context.func_env,
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
      let call_arg_values = []
      for x in xs {
        let arg_result = convert_expr(current_context, @closure.Expr::Var(x))
        current_context = arg_result.context
        match arg_result.value {
          Some(val) => call_arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      // 获取闭包值
      let closure_value = closure_result.value.unwrap()

      // 闭包调用时，需要先传递捕获的变量（自由变量），然后传递调用时的参数
      // 但在当前的CallClosure实现中，我们只需要传递调用参数
      // 因为捕获的变量已经在闭包创建时绑定了
      let result_value = Value::{ id: new_value_id(), ty: Type::Int }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::CallClosure(closure_value, call_arg_values),
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
        func_env: current_context.func_env,
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
/// 从 @types.Type 转换到 SSA Type
fn convert_type_from_types(ty : @types.Type) -> Type {
  match ty {
    @types.Type::Unit => Type::Unit
    @types.Type::Bool => Type::Bool
    @types.Type::Int => Type::Int
    @types.Type::Double => Type::Float
    @types.Type::Fun(args, ret) =>
      Type::Function(
        args.map(convert_type_from_types),
        convert_type_from_types(ret),
      )
    @types.Type::Tuple(elements) =>
      Type::Tuple(elements.map(convert_type_from_types))
    @types.Type::Array(element) => Type::Array(convert_type_from_types(element))
    @types.Type::Ptr => Type::Pointer(Type::Int)
    @types.Type::Var(_) => Type::Int // 类型变量，默认为Int
    @types.Type::UserDefineType(_, _) => Type::Int // 用户自定义类型，默认为Int
    @types.Type::Struct(_, _) => Type::Int // 结构体，默认为Int
    @types.Type::Enum(_, _) => Type::Int // 枚举，默认为Int
    @types.Type::ArrayData(_) => Type::Array(Type::Int) // 静态数组数据，默认Int数组
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
  Block::{ id: global_block_counter.val }
}
