///| 将闭包IR转换为SSA形式

///| 使用基本块参数来实现SSA
///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {

  @util.logger("closure ir: " + input.to_json().stringify())
  // 初始化SSA程序
  let functions = []

  // 转换每个函数定义
  for fundef in input.fundefs {
    if not(@typing.extenv.contains(fundef.old_name.to_string())) {
      let block_id = new_block_id()
      let ssa_func = convert_function(block_id, fundef, functions)
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
  block_id : Block,
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
    id: block_id,
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
  let block_id = new_block_id()
  convert_function(
    block_id,
    @closure.FuncDef::{
      name: @closure.Label("minimbt_main"),
      old_name: (try? @types.Name::from_string("minimbt_main")).unwrap(),
      is_closure: false,
      ty: @closure.LowType::DirectFn([], @closure.LowType::Unit),
      args: [],
      formal_free_vars: [],
      body,
    },
    functions,
  )
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

///| 更新上下文中的当前块
fn update_current_block(context : Context, block : BasicBlock) -> Context {
  let updated_blocks = context.blocks.map(fn(b) {
      if b.id == block.id { block } else { b }
    })
  Context::{
    current_block: block,
    blocks: updated_blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///| 更新上下文中的变量环境
fn update_var_env(context : Context, var_env : @immut/hashmap.HashMap[String, Value]) -> Context {
  Context::{
    current_block: context.current_block,
    blocks: context.blocks,
    block_map: context.block_map,
    var_env: var_env,
    func_env: context.func_env,
  }
}

///| 更新上下文中的块列表
fn update_blocks(context : Context, blocks : Array[BasicBlock]) -> Context {
  Context::{
    current_block: context.current_block,
    blocks: blocks,
    block_map: context.block_map,
    var_env: context.var_env,
    func_env: context.func_env,
  }
}

///| 安全地添加块到上下文，避免重复
fn add_block_to_context(context : Context, block : BasicBlock) -> Context {
  let existing_ids = context.blocks.map(fn(b) { b.id })
  if existing_ids.contains(block.id) {
    // 替换现有块
    let updated_blocks = context.blocks.map(fn(b) {
      if b.id == block.id { block } else { b }
    })
    update_blocks(context, updated_blocks)
  } else {
    // 添加新块
    let new_blocks = context.blocks.copy()
    new_blocks.push(block)
    update_blocks(context, new_blocks)
  }
}

///| 添加多个块到上下文
fn add_blocks_to_context(context : Context, blocks : Array[BasicBlock]) -> Context {
  let mut result_context = context
  for block in blocks {
    result_context = add_block_to_context(result_context, block)
  }
  result_context
}

fn update_current_terminator(context : Context, terminator : Terminator) -> Context {
  let updated_current_block = BasicBlock::{
    id: context.current_block.id,
    params: context.current_block.params,
    instructions: context.current_block.instructions,
    terminator,
  }
  update_current_block(context, updated_current_block)
}
///| SSA转换错误类型
priv enum SsaError {
  VariableNotFound(String)
  // TypeInferenceFailed(String)
  // UnsupportedConstruct(String)
  // InternalError(String)
} derive(Show)

///| 安全地获取变量值，带错误处理
fn safe_get_var(var_env : @immut/hashmap.HashMap[String, Value], name : String) -> Result[Value, SsaError] {
  match var_env.get(name) {
    Some(value) => Ok(value)
    None => Err(SsaError::VariableNotFound("Variable not found: " + name))
  }
}

///| 安全地获取函数类型，带错误处理
fn safe_get_func_type(func_env : @immut/hashmap.HashMap[String, Type], name : String) -> Result[Type, SsaError] {
  match func_env.get(name) {
    Some(func_type) => Ok(func_type)
    None => {
      // 尝试从外部环境查找
      match @typing.extenv.get(name) {
        Some(@types.Type::Fun(_, ret_type)) => Ok(convert_type_from_types(ret_type))
        Some(_) => Err(SsaError::VariableNotFound("Not a function: " + name))
        None => Err(SsaError::VariableNotFound("Function not found: " + name))
      }
    }
  }
}

///|
/// 表达式转换结果
priv struct ExprResult {
  value : Value?
  context : Context
} derive(Show)

///| 创建常量值并添加到当前块
fn create_const_int(context : Context, value : Int) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Int }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstInt(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}

///| 创建浮点常量值并添加到当前块
fn create_const_float(context : Context, value : Double) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Float }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstFloat(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
}

///| 创建布尔常量值并添加到当前块
fn create_const_bool(context : Context, value : Bool) -> (Value, Context) {
  let const_value = Value::{ id: new_value_id(), ty: Type::Bool }
  let instruction = Instruction::{
    result: const_value,
    opcode: Opcode::ConstBool(value),
  }
  context.current_block.instructions.push(instruction)
  (const_value, context)
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
  context.current_block.instructions.push(instruction)
  (result_value, context)
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
  context.current_block.instructions.push(instruction)
  (element_value, context)
}


///| 分析表达式中修改的变量
fn analyze_modified_variables(expr : @closure.Expr, var_env : @immut/hashmap.HashMap[String, Value]) -> @immut/hashmap.HashMap[String, Value] {
  let mut modified = @immut/hashmap.new()

  match expr {
    Assign(lhs_name, _) => {
      match var_env.get(lhs_name.to_string()) {
        Some(value) => modified = modified.add(lhs_name.to_string(), value)
        None => ()
      }
    }
    Let((_, _), e1, e2) => {
      // 递归分析let绑定的两个表达式
      modified = merge_modified_vars(modified, analyze_modified_variables(e1, var_env))
      modified = merge_modified_vars(modified, analyze_modified_variables(e2, var_env))
    }
    While(_, body_expr) => {
      // 递归分析while循环体
      modified = merge_modified_vars(modified, analyze_modified_variables(body_expr, var_env))
    }
    IfEq(_, _, e1, e2) | IfLe(_, _, e1, e2) | IfLt(_, _, e1, e2) => {
      // 递归分析if的两个分支
      modified = merge_modified_vars(modified, analyze_modified_variables(e1, var_env))
      modified = merge_modified_vars(modified, analyze_modified_variables(e2, var_env))
    }
    MakeTuple(elements) => {
      for elem in elements {
        modified = merge_modified_vars(modified, analyze_modified_variables(@closure.Expr::Var(elem), var_env))
      }
    }
    CallDirect(_, args) => {
      for arg in args {
        modified = merge_modified_vars(modified, analyze_modified_variables(@closure.Expr::Var(arg), var_env))
      }
    }
    CallClosure(_, args) => {
      for arg in args {
        modified = merge_modified_vars(modified, analyze_modified_variables(@closure.Expr::Var(arg), var_env))
      }
    }
    MakeClosure(_, _, body_expr) => {
      modified = merge_modified_vars(modified, analyze_modified_variables(body_expr, var_env))
    }
    _ => () // 其他表达式不修改变量
  }

  modified
}

///| 合并两个修改变量集合
fn merge_modified_vars(
  vars1 : @immut/hashmap.HashMap[String, Value],
  vars2 : @immut/hashmap.HashMap[String, Value]
) -> @immut/hashmap.HashMap[String, Value] {
  let mut result = vars1
  for key in vars2.keys() {
    match vars2.get(key) {
      Some(value) => result = result.add(key, value)
      None => ()
    }
  }
  result
}

///| 推断表达式的类型
fn infer_expression_type(expr : @closure.Expr, context : Context) -> Type {
  match expr {
    Unit => Type::Unit
    Int(_) | Int64(_) => Type::Int
    Double(_) => Type::Float
    Var(name) => {
      match context.var_env.get(name.to_string()) {
        Some(value) => value.ty
        None => {
          match context.func_env.get(name.to_string()) {
            Some(func_type) => func_type
            None => Type::Int // 默认类型，应该报错
          }
        }
      }
    }
    Add(_, _) | Sub(_, _) | Mul(_, _) | Div(_, _) | Mod(_) => Type::Int
    FAdd(_, _) | FSub(_, _) | FMul(_, _) | FDiv(_, _) | FMod(_) => Type::Float
    IfEq(_, _, e1, _) | IfLe(_, _, e1, _) | IfLt(_, _, e1, _) => infer_expression_type(e1, context)
    Let(_, e2, _) => infer_expression_type(e2, context)
    While(_, _) => Type::Unit
    MakeTuple(elements) => {
      let element_types = []
      for elem in elements {
        element_types.push(infer_expression_type(@closure.Expr::Var(elem), context))
      }
      Type::Tuple(element_types)
    }
    CallDirect(label, _) => {
      match context.func_env.get(label.0) {
        Some(Type::Function(_, ret_type)) => ret_type
        Some(_) => Type::Int
        None => {
          // 从外部环境查找
          match @typing.extenv.get(label.0) {
            Some(@types.Type::Fun(_, ret_type)) => convert_type_from_types(ret_type)
            Some(_) => Type::Int
            None => Type::Int
          }
        }
      }
    }
    CallClosure(name, _) => {
      match context.func_env.get(name.to_string()) {
        Some(Type::Function(_, ret_type)) => ret_type
        Some(_) => Type::Int
        None => {
          // 从外部环境查找
          match @typing.extenv.get(name.to_string()) {
            Some(@types.Type::Fun(_, ret_type)) => convert_type_from_types(ret_type)
            Some(_) => Type::Int
            None => Type::Int
          }
        }
      }
    }
    MakeClosure((_, ty), _, _) => convert_type(ty) // 闭包值的类型需要更精确的推断
    _ => Type::Int // 默认类型
  }
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
      ExprResult::{ value: Some(result_value), context: current_context }
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

        // 更新变量环境
        updated_var_env = updated_var_env.add(
          var_name.to_string(),
          element_value,
        )

        // 更新上下文
        current_context = Context::{
          current_block: current_context.current_block,
          blocks: current_context.blocks,
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

      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(array_value), context }
    }
    Assign(lhs_name, rhs_name) => {
      // 变量赋值：lhs = rhs
      let rhs_name_str = rhs_name.to_string()
      match safe_get_var(context.var_env, rhs_name_str) {
        Ok(rhs_value) => {
          // 在SSA中，赋值操作实际上是更新变量环境
          let updated_var_env = context.var_env.add(lhs_name.to_string(), rhs_value)
          let updated_context = update_var_env(context, updated_var_env)

          // 赋值表达式返回Unit类型
          ExprResult::{ value: None, context: updated_context }
        }
        Err(err) => {
          @util.logger("Error in Assign: " + err.to_string())
          ExprResult::{ value: None, context }
        }
      }
    }
    While(cond_expr, body_expr) => {
      // 创建While循环需要的块
      let loop_header_block_id = new_block_id()  // 循环头块（条件检查）
      let modified_vars = analyze_modified_variables(body_expr, context.var_env)

      // 为循环头块创建参数，用于接收循环体中更新的变量
      let loop_header_params = []
      for var_name in modified_vars.keys() {
        match modified_vars.get(var_name) {
          Some(original_value) => {
            let param_value = Value::{ id: new_value_id(), ty: original_value.ty }
            loop_header_params.push(param_value)
          }
          None => ()
        }
      }

      // 更新当前变量环境，将修改的变量映射到新的参数
      let mut updated_var_env_for_header = context.var_env
      let var_names = modified_vars.keys().to_array()
      for i = 0; i < var_names.length() && i < loop_header_params.length(); i = i + 1 {
        let var_name = var_names[i]
        updated_var_env_for_header = updated_var_env_for_header.add(var_name, loop_header_params[i])
      }

      let terminator = Terminator::Jump(loop_header_block_id, modified_vars.values().to_array())
      let context = update_current_terminator(context, terminator)


      let loop_body_block_id = new_block_id()    // 循环体块
      let loop_exit_block_id = new_block_id()    // 循环退出块
      
      // 创建循环头块，用于判断循环条件
      let loop_header_block = BasicBlock::{
        id: loop_header_block_id,
        params: loop_header_params,  // 循环头块接收修改的变量作为参数
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置
      }
      
      // 将循环头块添加到上下文
      let context_with_header = add_block_to_context(context, loop_header_block)
      
      // 切换到循环头块进行条件表达式的转换
      let header_context = update_current_block(context_with_header, loop_header_block)
      let header_context_with_var_env = update_var_env(header_context, updated_var_env_for_header) // 使用更新后的变量环境
      
      // 转换条件表达式
      let cond_result = convert_expr(header_context_with_var_env, cond_expr)
      let header_context_final = cond_result.context
      let cond_value = match cond_result.value {
        Some(v) => v
        None => @util.die("Condition expression has no value")
      }
      
      // 更新循环头块的终止指令，使其根据条件跳转到循环体或退出块
      // 当跳转到退出块时，需要传递当前的循环变量值
      let current_var_values = []
      for var_name in modified_vars.keys() {
        match header_context_final.var_env.get(var_name) {
          Some(current_value) => current_var_values.push(current_value)
          None => {
            // 如果在当前环境中找不到，使用原始值
            match modified_vars.get(var_name) {
              Some(original_value) => current_var_values.push(original_value)
              None => ()
            }
          }
        }
      }

      // 为false分支（退出块）准备当前的变量值
      let current_values_for_exit = []
      for var_name in modified_vars.keys() {
        match header_context_final.var_env.get(var_name) {
          Some(current_value) => current_values_for_exit.push(current_value)
          None => {
            // 如果在当前环境中找不到，使用原始值
            match modified_vars.get(var_name) {
              Some(original_value) => current_values_for_exit.push(original_value)
              None => ()
            }
          }
        }
      }

      let updated_loop_header_block = BasicBlock::{
        id: header_context_final.current_block.id,
        params: header_context_final.current_block.params,
        instructions: header_context_final.current_block.instructions,
        terminator: Terminator::Branch(cond_value, loop_body_block_id, [], loop_exit_block_id, current_values_for_exit),
      }
      
      // 将更新后的循环头块添加回上下文
      let context_with_updated_header = add_block_to_context(header_context_final, updated_loop_header_block)
      
      // 创建循环体块
      let loop_body_block = BasicBlock::{
        id: loop_body_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(loop_header_block_id, []), // 跳回循环头块进行条件检查
      }
      
      // 将循环体块添加到上下文
      let context_with_body = add_block_to_context(context_with_updated_header, loop_body_block)
      
      // 切换到循环体块进行转换
      let body_context = update_current_block(context_with_body, loop_body_block)
      // 循环体应该使用循环头块的参数值，而不是原始值
      let body_context_with_var_env = update_var_env(body_context, updated_var_env_for_header)  // 使用更新后的变量环境
      
      // 转换循环体
      let body_result = convert_expr(body_context_with_var_env, body_expr)
      let body_context_final = body_result.context
      
      // 收集循环体中修改的变量的最新值
      let body_modified_vars = analyze_modified_variables(body_expr, context.var_env)
      let body_updated_values = []
      for var_name in body_modified_vars.keys() {
        match body_context_final.var_env.get(var_name) {
          Some(updated_value) => body_updated_values.push(updated_value)
          None => {
            // 如果在循环体中没有找到更新的值，使用原始值
            match modified_vars.get(var_name) {
              Some(original_value) => body_updated_values.push(original_value)
              None => ()
            }
          }
        }
      }

      // 更新循环体块的终止指令，使其跳回循环头块并传递更新后的变量值
      let updated_loop_body_block = BasicBlock::{
        id: body_context_final.current_block.id,
        params: body_context_final.current_block.params,
        instructions: body_context_final.current_block.instructions,
        terminator: Terminator::Jump(loop_header_block_id, body_updated_values), // 跳回循环头块并传递更新后的值
      }
      
      // 将更新后的循环体块添加回上下文
      let context_with_updated_body = add_block_to_context(body_context_final, updated_loop_body_block)
      
      // 创建循环退出块 - 接收循环结束时变量的最终值
      let loop_exit_params = []
      for var_name in modified_vars.keys() {
        match modified_vars.get(var_name) {
          Some(original_value) => {
            let param_value = Value::{ id: new_value_id(), ty: original_value.ty }
            loop_exit_params.push(param_value)
          }
          None => ()
        }
      }

      let loop_exit_block = BasicBlock::{
        id: loop_exit_block_id,
        params: loop_exit_params, // 接收循环结束时变量的最终值
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置
      }
      
      // 将循环退出块添加到上下文
      let context_with_exit = add_block_to_context(context_with_updated_body, loop_exit_block)
      
      // 为退出块创建变量环境映射
      let mut exit_var_env = context_with_updated_body.var_env
      let var_names = modified_vars.keys().to_array()
      for i = 0; i < var_names.length() && i < loop_exit_params.length(); i = i + 1 {
        let var_name = var_names[i]
        exit_var_env = exit_var_env.add(var_name, loop_exit_params[i])
      }

      // 切换到循环退出块，准备继续后续代码
      let final_context = update_current_block(context_with_exit, loop_exit_block)
      let final_context_with_var_env = update_var_env(final_context, exit_var_env) // 使用退出块的变量环境
      
      // While循环返回Unit类型
      ExprResult::{ value: None, context: final_context_with_var_env }
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

      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(array_value), context }
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
      // ArrayPut是表达式，返回Unit类型
      ExprResult::{ value: None, context }
    }
    ArrayGet(array_name, index_name) => {
      // 数组访问：array[index]
      // 获取数组和索引的值
      let array_value = context.var_env.get(array_name.to_string()).unwrap()
      let index_value = context.var_env.get(index_name.to_string()).unwrap()

      // 创建结果值 - 数组元素的类型需要从数组类型中推断
      let element_type = match array_value.ty {
        Type::Array(elem_type) => elem_type
        _ => @util.die("Expected array type in ArrayGet: name " + array_name.to_string() + ", type: " + array_value.ty.to_string())
      }
      let result_value = Value::{ id: new_value_id(), ty: element_type }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::ArrayGet(array_value, index_value),
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context }
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
      let operand_value = match result.value {
        Some(v) => v
        None => @util.die("Operand of negation has no value")
      }

      // 整数取负: 0 - x
      let (zero_value, context2) = create_const_int(context1, 0)
      let (result_value, final_context) = create_binary_op(context2, BinaryOpType::Sub, zero_value, operand_value, Type::Int)
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    FNeg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let operand_value = match result.value {
        Some(v) => v
        None => @util.die("Operand of float negation has no value")
      }

      // 浮点取负: 0.0 - x
      let (zero_value, context2) = create_const_float(context1, 0.0)
      let (result_value, final_context) = create_binary_op(context2, BinaryOpType::FSub, zero_value, operand_value, Type::Float)
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    Double(d) => {
      let (value, new_context) = create_const_float(context, d)
      ExprResult::{ value: Some(value), context: new_context }
    }
    Bool(b) => {
      let (value, new_context) = create_const_bool(context, b)
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
      let value1 = match result1.value {
        Some(v) => v
        None => @util.die("Left operand of comparison has no value")
      }
      let value2 = match result2.value {
        Some(v) => v
        None => @util.die("Right operand of comparison has no value")
      }

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

      // 创建合并值 - 用于接收两个分支的返回值
      let merge_value = Value::{ id: new_value_id(), ty: Type::Int }

      // 分析两个分支中修改的变量
      let then_modified_vars = analyze_modified_variables(e1, context2.var_env)
      let else_modified_vars = analyze_modified_variables(e2, context2.var_env)

      // 如果有变量修改，创建合并块的参数
      let merge_params = []
      let all_modified_vars = merge_modified_vars(then_modified_vars, else_modified_vars)
      for var_name in all_modified_vars.keys() {
        match all_modified_vars.get(var_name) {
          Some(original_value) => {
            let param_value = Value::{ id: new_value_id(), ty: original_value.ty }
            merge_params.push(param_value)
          }
          None => ()
        }
      }

      // 如果有变量修改，将合并值作为第一个参数
      let final_merge_params = if merge_params.length() > 0 {
        [merge_value] + merge_params
      } else {
        [merge_value]
      }

      // 创建then块
      let then_block = BasicBlock::{
        id: then_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []), // 稍后更新
      }

      // 创建else块
      let else_block = BasicBlock::{
        id: else_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []), // 稍后更新
      }

      // 创建合并块
      let merge_block = BasicBlock::{
        id: merge_block_id,
        params: final_merge_params,
        instructions: [],
        terminator: Terminator::Return(None), // 临时设置
      }

      // 更新当前块的终止指令
      let terminator = Terminator::Branch(
        cmp_result, then_block_id, [], else_block_id, [],
      )
      let updated_current_block = BasicBlock::{
        id: context2.current_block.id,
        params: context2.current_block.params,
        instructions: context2.current_block.instructions,
        terminator,
      }

      // 使用辅助函数更新块列表
      let mut context_with_blocks = add_block_to_context(context2, updated_current_block)
      context_with_blocks = add_blocks_to_context(context_with_blocks, [then_block, else_block, merge_block])
      context_with_blocks = update_current_block(context_with_blocks, then_block)
      context_with_blocks = update_var_env(context_with_blocks, context2.var_env)

      // 转换then分支
      let then_result = convert_expr(context_with_blocks, e1)
      let then_context = then_result.context
      let then_branch_value = match then_result.value {
        Some(v) => v
        None => {
          // 如果分支没有返回值，但有修改变量，使用第一个修改变量的值
          let var_names = then_modified_vars.keys().to_array()
          if var_names.length() > 0 {
            let first_var_name = var_names[0]
            match then_context.var_env.get(first_var_name) {
              Some(var_val) => var_val
              None => @util.die("Failed to get modified variable value in then branch")
            }
          } else {
            Value::{ id: new_value_id(), ty: Type::Unit }
          }
        }
      }

      // 为then分支准备参数
      let then_args = [then_branch_value]
      // 添加修改变量的值
      let var_names = all_modified_vars.keys().to_array()
      for i = 0; i < var_names.length(); i = i + 1 {
        let var_name = var_names[i]
        let var_value = match then_context.var_env.get(var_name) {
          Some(current_val) => current_val
          None => {
            match all_modified_vars.get(var_name) {
              Some(original_val) => original_val
              None => merge_params[i]
            }
          }
        }
        then_args.push(var_value)
      }

      let updated_then_block = BasicBlock::{
        id: then_context.current_block.id,
        params: then_context.current_block.params,
        instructions: then_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, then_args),
      }

      // 更新上下文，切换到else块
      let else_context = update_current_block(then_context, else_block)
      let else_context = update_var_env(else_context, context2.var_env)

      // 转换else分支
      let else_result = convert_expr(else_context, e2)
      let final_else_context = else_result.context
      let else_branch_value = match else_result.value {
        Some(v) => v
        None => {
          // 如果分支没有返回值，但有修改变量，使用第一个修改变量的值
          let var_names = else_modified_vars.keys().to_array()
          if var_names.length() > 0 {
            let first_var_name = var_names[0]
            match final_else_context.var_env.get(first_var_name) {
              Some(var_val) => var_val
              None => @util.die("Failed to get modified variable value in else branch")
            }
          } else {
            @util.die("Else branch has no return value and no modified variables")
          }
        }
      }

      // 为else分支准备参数
      let else_args = [else_branch_value]
      // 添加修改变量的值
      for i = 0; i < var_names.length(); i = i + 1 {
        let var_name = var_names[i]
        let var_value = match final_else_context.var_env.get(var_name) {
          Some(current_val) => current_val
          None => {
            match all_modified_vars.get(var_name) {
              Some(original_val) => original_val
              None => merge_params[i]
            }
          }
        }
        else_args.push(var_value)
      }

      let updated_else_block = BasicBlock::{
        id: final_else_context.current_block.id,
        params: final_else_context.current_block.params,
        instructions: final_else_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, else_args),
      }

      // 使用辅助函数更新最终块
      let mut final_context = add_block_to_context(final_else_context, updated_then_block)
      final_context = add_block_to_context(final_context, updated_else_block)
      final_context = add_block_to_context(final_context, merge_block)
      final_context = update_current_block(final_context, merge_block)

      // 更新变量环境，使合并后的值可以被访问
      let mut updated_var_env = context2.var_env
      for i = 0; i < var_names.length(); i = i + 1 {
        let var_name = var_names[i]
        let param_index = if merge_params.length() > 0 { i + 1 } else { 0 }
        if param_index < final_merge_params.length() {
          updated_var_env = updated_var_env.add(var_name, final_merge_params[param_index])
        }
      }

      final_context = update_var_env(final_context, updated_var_env)

      // 返回合并值作为结果
      // @util.logger("IfExpr result: " + merge_value.to_string())
      ExprResult::{ value: Some(merge_value), context: final_context }
    }
    Var(name) => {
      let var_name = name.to_string()
      // @util.logger("Var: " + var_name + " context.func_env: " + context.func_env.to_string())

      // 安全地查找变量
      match safe_get_var(context.var_env, var_name) {
        Ok(value) => ExprResult::{ value: Some(value), context }
        Err(_) => {
          // 尝试从函数环境中查找
          match safe_get_func_type(context.func_env, var_name) {
            Ok(func_type) => {
              // 找到函数，创建函数引用指令
              let result_value = Value::{ id: new_value_id(), ty: func_type }
              let instruction = Instruction::{
                result: result_value,
                opcode: Opcode::CallRef(var_name, []),
              }

              // 更新当前块的指令列表
              context.current_block.instructions.push(instruction)
              ExprResult::{ value: Some(result_value), context }
            }
            Err(_) => {
              // 变量未找到，返回None并记录警告
              @util.logger("Warning: Variable or function not found: " + var_name)
              ExprResult::{ value: None, context }
            }
          }
        }
      }
    }
    Let((name, ty), e1, e2) => {

      // Let绑定：先计算e1
      let result1 = convert_expr(context, e1)
      let result1_value = result1.value
      let context1 = result1.context
      // 将e1的结果绑定到name
      match result1_value {
        Some(value) => {
          // 更新环境，将name映射到value
          let updated_var_env = context1.var_env.add(name.to_string(), Value::{ id: value.id, ty: convert_type(ty) })
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

      // 使用缓存的类型推断函数确定返回类型
      let return_type = cached_infer_type(@closure.Expr::CallDirect(label, args), current_context)
      let opcode = match context.var_env.get(label.0.to_string()) {
        Some(v) => Opcode::Call(Func::Call(v), arg_values)
        None => Opcode::Call(Func::Label(label.0), arg_values)
      }
      let result_value = Value::{ id: new_value_id(), ty: return_type }
      let instruction = Instruction::{ result: result_value, opcode }

      // 更新当前块的指令列表
      current_context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context: current_context }
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

      // 将闭包值绑定到name变量
      let updated_var_env = context.var_env.add(name.to_string(), closure_value)
      let intermediate_context = Context::{
        current_block: context.current_block,
        blocks: context.blocks,
        block_map: context.block_map,
        var_env: updated_var_env, // 包含新绑定的变量环境
        func_env: context.func_env,
      }
      let result = convert_expr(intermediate_context, e)
      ExprResult::{ value: result.value, context: result.context }
    }
    CallClosure(n, xs) => {

      
      // 闭包调用
      // 特殊处理：如果n是已定义的函数，直接创建函数引用
      let func_name = n.to_string()
      println("var_env: " + context.var_env.to_string())
      println("func_env: " + context.func_env.to_string())

      // 转换所有参数，正确链式传递上下文
      let mut current_context = context
      let call_arg_values = []
      for x in xs {
        let arg_result = convert_expr(current_context, @closure.Expr::Var(x))
        current_context = arg_result.context
        match arg_result.value {
          Some(val) => call_arg_values.push(val)
          None => () // 参数可能为Unit类型
        }
      }

      let opcode = match safe_get_var(context.var_env, func_name) {
        Ok(value) => Opcode::CallClosure(Func::Call(value), call_arg_values) // 变量环境中找到，直接使用
        Err(_) => {
          // 尝试从函数环境中查找
          match safe_get_func_type(context.func_env, func_name) {
            Ok(_) => {
              Opcode::CallClosure(Func::Label(func_name), call_arg_values)
            }
            Err(_) => {
              @util.logger("Error: Function not found for CallClosure: " + func_name)
              Opcode::Call(Func::Label(func_name), call_arg_values)
            }
          }
        }
      }

      

      // 闭包调用时，需要先传递捕获的变量（自由变量），然后传递调用时的参数
      // 但在当前的CallClosure实现中，我们只需要传递调用参数
      // 因为捕获的变量已经在闭包创建时绑定了
      let result_value = Value::{ id: new_value_id(), ty: Type::Int }
      let instruction = Instruction::{
        result: result_value,
        opcode: opcode,
      }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context }
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

///| 简单的LRU类型缓存，避免重复类型推断
let type_cache : Ref[@immut/hashmap.HashMap[String, Type]] = Ref::new(@immut/hashmap.new())

///| 带缓存的类型推断
fn cached_infer_type(expr : @closure.Expr, context : Context) -> Type {
  let expr_key = expr.to_string()
  match type_cache.val.get(expr_key) {
    Some(cached_type) => cached_type
    None => {
      let inferred_type = infer_expression_type(expr, context)
      type_cache.val = type_cache.val.add(expr_key, inferred_type)
      inferred_type
    }
  }
}