///|
pub fn to_llvmir(input: @closure.Program) -> LLVMIR {
    // 创建基础 LLVMIR 结构
    let functions = [];
    let globals = [];
    let types = [];
    let metadata = [];
    
    // 处理函数定义
    for fundef in input.fundefs {
        if not(@util.extenv.contains(fundef.old_name.to_string())) {
            let basic_blocks = [];
            // 创建入口基本块
            let entry_block = {
                name: "entry",
                instructions: convert_expr_to_instructions(fundef.body)
            };
            basic_blocks.push(entry_block);
            
            // 创建函数
            let func = {
                name: fundef.name.to_string(),
                return_type: convert_type(fundef.ty),
                parameters: convert_parameters(fundef.args),
                basic_blocks: basic_blocks
            };
            functions.push(func);
        }
    }
    
    // 处理主函数
    let main_instructions = convert_expr_to_instructions(input.body);
    let main_block = {
        name: "entry",
        instructions: main_instructions
    };
    
    let main_function = {
        name: "main",
        return_type: Type::Integer(32),
        parameters: [],
        basic_blocks: [main_block]
    };
    functions.push(main_function);
    
    // 返回完整的 LLVMIR
    {
        name: "module",
        globals: globals,
        functions: functions,
        types: types,
        metadata: metadata
    }
}

// 辅助函数:转换表达式到指令序列
fn convert_expr_to_instructions(expr: @closure.Expr) -> Array[Instruction] {
    let instructions = [];
    match expr {
        Let((var, ty), value, body) => {
            // 处理赋值
            instructions.push(convert_value_to_instruction(var.to_string(), value));
            // 递归处理 body
            instructions.append(convert_expr_to_instructions(body));
        }
        CallDirect(func, args) => {
            // 处理函数调用
            instructions.push(Instruction::Call(
                Type::Integer(32),
                func.to_string(),
                convert_args_to_values(args)
            ));
        }
        // ... 处理其他表达式类型 ...
    }
    instructions
}

// 辅助函数:转换类型
fn convert_type(ty: @closure.LowType) -> Type {
    match ty {
        Int => Type::Integer(32)  // 整数类型默认为 i32
        Bool => Type::Integer(1)     // 布尔类型在 LLVM 中用 i1 表示
        Unit => Type::Void            // Unit 类型转换为 void
        Double => Type::Float          // 浮点类型
        ClosureFn(params, ret_ty) => {
            // 函数类型：转换参数类型和返回类型
            let param_types = params.map(fn(p) {convert_type(p)})
            // .map(|p| convert_type(p))

            let return_type = convert_type(ret_ty);
            Type::Function(return_type, param_types)
        }
        // 如果有其他类型，可以继续添加匹配分支
    }
}

// 辅助函数：将值转换为 LLVM IR 指令
fn convert_value_to_instruction(var: String, value: @closure.Expr) -> Instruction {
    match value {
        // 处理基本字面量
        // Int(n) => Instruction::Alloca(
        //     var,
        //     Type::Integer(32),
        //     Some(Value::Constant(n))
        // )
      
        // 处理函数调用
        CallDirect(func_name, args) => {
            // let arg_values = args.map(fn(arg) { convert_operand_to_value(arg) });
            // Instruction::Call(
            //     var,
            //     func_name.to_string(),
            //     arg_values
            // )
            Unit
        }
        
        // 处理变量引用
        Var(name) => Instruction::Load(
            Type::Integer(32),  // 这里可能需要根据实际类型调整
            Value::Parameter(name.to_string())
        )
    }
}

// 辅助函数：将操作数转换为值
fn convert_operand_to_value(operand: @closure.Expr) -> Value {
    match operand {
        Int(n) => Value::Constant(Constant::Int(n))
        // Bool(b) => Value::Constant(if b { 1 } else { 0 })
        // Float(f) => Value::FloatConstant(f)
        // Var(name) => Value::Register(name)
        // _ => panic!("Unsupported operand type")
    }
}

// ... 其他辅助函数定义 ...

fn convert_parameters(parameters: Array[(@minimbt.Name, @closure.LowType)]) -> Array[Parameter] {
    return parameters.map(
        fn  { 
            (name, ty) => {name: name.to_string(), ty: convert_type(ty), attributes: []}
        }
    )
}

fn convert_args_to_values(args: Array[@minimbt.Name]) -> Array[Value] {
    return args.map(
        fn(arg) { Null }
    )
}