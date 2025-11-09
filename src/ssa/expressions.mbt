///| 表达式转换模块

///|

///| 提供将闭包IR表达式转换为SSA指令的功能

///|
/// 表达式转换结果
pub struct ExprResult {
  value : Value?
  context : Context
} derive(Show)

///|

///|
/// 转换闭包IR表达式为SSA指令
pub fn convert_expr(context : Context, expr : @closure.Expr) -> ExprResult {
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
      let element_type = if index == 0 {
        convert_type(tuple_type)
      } else {
        match convert_type(tuple_type) {
          Type::Tuple(types) => types[index - 1]
          _ =>
            @util.die(
              "Expected tuple type in TupleGet: " + tuple_type.to_string(),
            )
        }
      }
      let (result_value, new_context) = create_get_element(
        context, tuple_value, index, element_type,
      )
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
        opcode: Opcode::CallRef(label.0, []),
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
          let updated_var_env = context.var_env.add(
            lhs_name.to_string(),
            rhs_value,
          )
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
    While(cond_expr, body_expr) =>
      // 调用控制流模块处理While循环
      convert_while(context, cond_expr, body_expr)
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
        _ =>
          @util.die(
            "Expected array type in ArrayGet: name " +
            array_name.to_string() +
            ", type: " +
            array_value.ty.to_string(),
          )
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
      let (result_value, final_context) = create_binary_op(
        context2,
        BinaryOpType::Sub,
        zero_value,
        operand_value,
        Type::Int,
      )
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
      let (result_value, final_context) = create_binary_op(
        context2,
        BinaryOpType::FSub,
        zero_value,
        operand_value,
        Type::Float,
      )
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
      let (result_value, new_context) = create_binary_op(
        context, op_type, value1, value2, result_type,
      )
      ExprResult::{ value: Some(result_value), context: new_context }
    }
    IfEq(x, y, e1, e2) | IfLe(x, y, e1, e2) | IfLt(x, y, e1, e2) =>
      // 调用条件表达式模块处理条件分支
      convert_conditional(context, expr, x, y, e1, e2)
    Var(name) => {
      let var_name = name.to_string()
      // @util.logger("Var: " + var_name + " context.func_env: " + context.func_env.to_string())

      // 安全地查找变量
      match safe_get_var(context.var_env, var_name) {
        Ok(value) => ExprResult::{ value: Some(value), context }
        Err(_) =>
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
              @util.logger(
                "Warning: Variable or function not found: " + var_name,
              )
              ExprResult::{ value: None, context }
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
          let updated_var_env = context1.var_env.add(name.to_string(), Value::{
            id: value.id,
            ty: convert_type(ty),
          })
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
      let func_type = cached_infer_type(
        @closure.Expr::CallDirect(label, args),
        current_context,
      )
      let return_type = match func_type {
        Type::Function(_, ret_type) => ret_type
        _ =>
          @util.die(
            "CallDirect: not a function type: " +
            func_type.to_string() +
            " for function: " +
            label.0.to_string(),
          )
      }
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
      // println("var_env: " + context.var_env.to_string())
      // println("func_env: " + context.func_env.to_string())

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
        Err(_) =>
          // 尝试从函数环境中查找
          match safe_get_func_type(context.func_env, func_name) {
            Ok(_) =>
              Opcode::CallClosure(Func::Label(func_name), call_arg_values)
            Err(_) => {
              @util.logger(
                "Error: Function not found for CallClosure: " + func_name,
              )
              Opcode::Call(Func::Label(func_name), call_arg_values)
            }
          }
      }
      let func_type = cached_infer_type(
        @closure.Expr::CallClosure(n, xs),
        current_context,
      )
      let return_type = match func_type {
        Type::Function(_, ret_type) => ret_type
        _ =>
          @util.die(
            "CallClosure: not a function type: " +
            func_type.to_string() +
            " for function: " +
            func_name,
          )
      }
      // 闭包调用时，需要先传递捕获的变量（自由变量），然后传递调用时的参数
      // 但在当前的CallClosure实现中，我们只需要传递调用参数
      // 因为捕获的变量已经在闭包创建时绑定了
      let result_value = Value::{ id: new_value_id(), ty: return_type }
      // println("CallClosure result_value: " + result_value.to_string())
      // println("CallClosure name: " + func_name)

      let instruction = Instruction::{ result: result_value, opcode }

      // 更新当前块的指令列表
      context.current_block.instructions.push(instruction)
      ExprResult::{ value: Some(result_value), context }
    }
  }
}
