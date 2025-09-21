///| 将闭包IR转换为SSA形式

///| 使用基本块参数而非phi函数来实现SSA

///|
/// 将闭包IR程序转换为SSA程序
pub fn to_ssa(input : @closure.Program) -> Ssa {
  @util.logger("to_ssa: " + input.to_json().stringify())
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
  // 创建函数参数
  let params = fundef.args.map(fn(arg) {
    // 为每个参数创建SSA值
    (Value::{ id: new_value_id() }, convert_type(arg.1))
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
  let context = {
    current_block: entry_block,
    blocks,
    block_map: @immut/hashmap.new(), // 块映射，用于控制流
    var_env: @immut/hashmap.new(), // 变量环境
  }
  let result = convert_expr(context, fundef.body)
  // 使用转换后的上下文更新块列表
  let updated_blocks = result.context.blocks
  {
    name: fundef.name.0.to_string(),
    params,
    return_type: convert_type(fundef.ty),
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

  // 更新块列表
  let updated_blocks = result.context.blocks
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
}

///|
/// 表达式转换结果
priv struct ExprResult {
  value : Value?
  context : Context
}

///|
/// 转换闭包IR表达式为SSA指令
fn convert_expr(context : Context, expr : @closure.Expr) -> ExprResult {
  match expr {
    Unit
    | LetTuple(_, _, _)
    | MakeTuple(_)
    | TupleGet(_, _, _)
    | ArrayPut(_, _, _)
    | ArrayGet(_, _)
    | ExternalArray(Label(_))
    | Assign(_, _)
    | While(_, _)
    | StaticArrayRef(Label(_)) => ExprResult::{ value: None, context }
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
    Neg(x) | FNeg(x) => {
      // 转换操作数
      let result = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result.context
      let value = result.value.unwrap()
      @util.die(
        "Neg: " +
        value.to_string() +
        "\n context: " +
        context1.blocks.to_string(),
      )
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
      // 先转换条件表达式
      let result1 = convert_expr(context, @closure.Expr::Var(x))
      let context1 = result1.context
      // 转换右操作数
      let result2 = convert_expr(context1, @closure.Expr::Var(y))
      let context2 = result2.context
      
      // 获取两个操作数的值
      let value1 = result1.value.unwrap()
      let _value2 = result2.value.unwrap()

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

      // 创建合并块
      let merge_block = BasicBlock::{
        id: merge_block_id,
        params: [],
        instructions: [],
        terminator: Terminator::Jump(merge_block_id, []),
      }

      // 更新当前块的终止指令
      let terminator = match expr {
        IfEq(_, _, _, _) => Terminator::Branch(value1, then_block_id, else_block_id)
        IfLe(_, _, _, _) => Terminator::Branch(value1, then_block_id, else_block_id)
        IfLt(_, _, _, _) => Terminator::Branch(value1, then_block_id, else_block_id)
        _ => @util.die("unexpected expression type")
      }


      let updated_current_block = BasicBlock::{
        id: context2.current_block.id,
        params: context2.current_block.params,
        instructions: context2.current_block.instructions,
        terminator: terminator,
      }

      // 更新块列表
      context2.blocks.append([updated_current_block, then_block, else_block, merge_block])

      // 更新块映射
      let updated_block_map = context2.block_map
        .add(then_block_id.id, then_block)
        .add(else_block_id.id, else_block)
        .add(merge_block_id.id, merge_block)

      // 更新上下文
      let context_with_blocks = Context::{
        current_block: then_block,
        blocks: context2.blocks,
        block_map: updated_block_map,
        var_env: context2.var_env  // 保持变量环境
      }

      // 转换then分支
      let then_result = convert_expr(context_with_blocks, e1)
      let then_context = then_result.context

      // 更新then块的终止指令，跳转到合并块
      let updated_then_block = BasicBlock::{
        id: then_context.current_block.id,
        params: then_context.current_block.params,
        instructions: then_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, []),
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
      let else_context = else_result.context

      // 更新else块的终止指令，跳转到合并块
      let updated_else_block = BasicBlock::{
        id: else_context.current_block.id,
        params: else_context.current_block.params,
        instructions: else_context.current_block.instructions,
        terminator: Terminator::Jump(merge_block_id, []),
      }

      // 更新块列表
      let final_blocks = else_context.blocks.map(fn(b) {
        if b.id == updated_then_block.id {
          updated_then_block
        } else if b.id == updated_else_block.id {
          updated_else_block
        } else {
          b
        }
      })

      // 创建结果值（Phi节点）
      let result_value = Value::{ id: new_value_id() }
      
      // 更新上下文
      let final_context = Context::{
        current_block: merge_block,
        blocks: final_blocks,
        block_map: else_context.block_map,
        var_env: context2.var_env  // 保持变量环境
      }
      
      ExprResult::{ value: Some(result_value), context: final_context }
    }
    Var(name) => {
      // 变量引用，从环境中查找对应的Value
      match context.var_env.get(name) {
        Some(value) => 
          ExprResult::{ value: Some(value), context }
        None => {
          
          // 如果在环境中找不到，创建一个新的Value（这种情况不应该发生）
          let value = Value::{ id: new_value_id() }
          ExprResult::{ value: Some(value), context }
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
    CallDirect(label, _args) => {
      // 直接函数调用
      // 先转换所有参数
      let arg_values = [] // 实际应该转换参数
      let result_value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::Call(label.0, arg_values),
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
      ExprResult::{ value: Some(result_value), context: updated_context }
    }
    MakeClosure((name, _ty), c, e) => {
      // 闭包创建
      // 先转换闭包体
      let result = convert_expr(context, e)
      let updated_context = result.context

      // 创建闭包值
      let closure_value = Value::{ id: new_value_id() }

      // 创建闭包创建指令
      let instruction = Instruction::{
        result: closure_value,
        opcode: Opcode::MakeClosure(
          name.to_string(),
          c.name.0,
          c.actual_free_vars,
        ),
      }

      // 更新当前块的指令列表
      updated_context.current_block.instructions.push(instruction)
      let updated_block = BasicBlock::{
        id: updated_context.current_block.id,
        params: updated_context.current_block.params,
        instructions: updated_context.current_block.instructions,
        terminator: updated_context.current_block.terminator,
      }

      // 更新上下文
      let updated_blocks = updated_context.blocks.map(fn(b) {
        if b.id == updated_block.id {
          updated_block
        } else {
          b
        }
      })
      let final_context = Context::{
        current_block: updated_block,
        blocks: updated_blocks,
        block_map: updated_context.block_map,
        var_env: updated_context.var_env, // 变量环境
      }
      ExprResult::{ value: Some(closure_value), context: final_context }
    }
    CallClosure(n, xs) => {
      // 闭包调用
      // 先转换闭包引用
      let closure_result = convert_expr(context, @closure.Expr::Var(n))
      let context1 = closure_result.context

      // 转换所有参数
      let arg_results = xs.map(fn(x) {
        convert_expr(context1, @closure.Expr::Var(x))
      })

      // 获取闭包值
      let closure_value = closure_result.value.unwrap()

      // 获取参数值
      let arg_values = arg_results.map(fn(result) { result.value.unwrap() })

      // 创建结果值和指令
      let result_value = Value::{ id: new_value_id() }
      let instruction = Instruction::{
        result: result_value,
        opcode: Opcode::CallClosure(closure_value, arg_values),
      }

      // 更新当前块的指令列表
      context1.current_block.instructions.push(instruction)
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
        var_env: context1.var_env, // 变量环境
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
