///| 静态单赋值（SSA）中间表示
///| 使用基本块参数而非phi函数来实现SSA

///| SSA值标识符
pub(all) struct Value {
  id : Int
} derive(Show, Eq, Hash)

///| Value结构体的JSON序列化
pub fn Value::to_json(self : Value) -> Json {
  { "id": self.id }
}

///| Value结构体的JSON反序列化
pub fn Value::from_json(json : Json) -> Value raise {
  match json {
    { "id": id, .. } => Value::{ id: id.as_number().unwrap().to_int() }
    _ => fail("invalid json for Value")
  }
}

///| 基本块标识符
pub(all) struct Block {
  id : Int
} derive(Show, Eq, Hash)

///| Block结构体的JSON序列化
pub fn Block::to_json(self : Block) -> Json {
  { "id": self.id }
}

///| Block结构体的JSON反序列化
pub fn Block::from_json(json : Json) -> Block raise {
  match json {
    { "id": id, .. } => Block::{ id: id.as_number().unwrap().to_int() }
    _ => fail("invalid json for Block")
  }
}

///| 操作码类型
pub(all) enum Opcode {
  // 常量
  ConstInt(Int)
  ConstFloat(Double)
  
  // 算术运算
  Add(Value, Value)
  Sub(Value, Value)
  Mul(Value, Value)
  Div(Value, Value)
  Mod(Value, Value)
  
  // 浮点运算
  FAdd(Value, Value)
  FSub(Value, Value)
  FMul(Value, Value)
  FDiv(Value, Value)
  FMod(Value, Value)
  
  // 比较运算
  Eq(Value, Value)
  Ne(Value, Value)
  Lt(Value, Value)
  Le(Value, Value)
  Gt(Value, Value)
  Ge(Value, Value)
  
  // 控制流
  Jump(Block, Array[Value])  // 跳转到基本块，传递参数
  Branch(Value, Block, Block) // 条件分支
  Return(Value?)              // 返回值
  
  // 内存操作
  Alloc(Type)
  Load(Value)
  Store(Value, Value)
  
  // 函数调用
  Call(String, Array[Value])
  
  // 参数访问（用于基本块参数）
  BlockArg(Int)  // 基本块的第n个参数
  
  // 元组操作
  Tuple(Array[Value])
  GetElement(Value, Int)
  
  // 数组操作
  ArrayGet(Value, Value)
  ArrayPut(Value, Value, Value)
} derive(Show)

///| Opcode枚举的JSON序列化
pub fn Opcode::to_json(self : Opcode) -> Json {
  match self {
    Opcode::ConstInt(i) => ["ConstInt", i]
    Opcode::ConstFloat(f) => ["ConstFloat", f]
    Opcode::Add(v1, v2) => ["Add", v1.to_json(), v2.to_json()]
    Opcode::Sub(v1, v2) => ["Sub", v1.to_json(), v2.to_json()]
    Opcode::Mul(v1, v2) => ["Mul", v1.to_json(), v2.to_json()]
    Opcode::Div(v1, v2) => ["Div", v1.to_json(), v2.to_json()]
    Opcode::Mod(v1, v2) => ["Mod", v1.to_json(), v2.to_json()]
    Opcode::FAdd(v1, v2) => ["FAdd", v1.to_json(), v2.to_json()]
    Opcode::FSub(v1, v2) => ["FSub", v1.to_json(), v2.to_json()]
    Opcode::FMul(v1, v2) => ["FMul", v1.to_json(), v2.to_json()]
    Opcode::FDiv(v1, v2) => ["FDiv", v1.to_json(), v2.to_json()]
    Opcode::FMod(v1, v2) => ["FMod", v1.to_json(), v2.to_json()]
    Opcode::Eq(v1, v2) => ["Eq", v1.to_json(), v2.to_json()]
    Opcode::Ne(v1, v2) => ["Ne", v1.to_json(), v2.to_json()]
    Opcode::Lt(v1, v2) => ["Lt", v1.to_json(), v2.to_json()]
    Opcode::Le(v1, v2) => ["Le", v1.to_json(), v2.to_json()]
    Opcode::Gt(v1, v2) => ["Gt", v1.to_json(), v2.to_json()]
    Opcode::Ge(v1, v2) => ["Ge", v1.to_json(), v2.to_json()]
    Opcode::Jump(block, values) => {
      let values_json = values.map(Value::to_json)
      ["Jump", block.to_json(), values_json]
    }
    Opcode::Branch(value, block1, block2) => ["Branch", value.to_json(), block1.to_json(), block2.to_json()]
    Opcode::Return(value) => {
      match value {
        Some(v) => ["Return", v.to_json()]
        None => ["Return", "None"]
      }
    }
    Opcode::Alloc(ty) => ["Alloc", ty.to_json()]
    Opcode::Load(value) => ["Load", value.to_json()]
    Opcode::Store(v1, v2) => ["Store", v1.to_json(), v2.to_json()]
    Opcode::Call(name, values) => {
      let values_json = values.map(Value::to_json)
      ["Call", name, values_json]
    }
    Opcode::BlockArg(i) => ["BlockArg", i]
    Opcode::Tuple(values) => {
      let values_json = values.map(Value::to_json)
      ["Tuple", values_json]
    }
    Opcode::GetElement(value, i) => ["GetElement", value.to_json(), i]
    Opcode::ArrayGet(v1, v2) => ["ArrayGet", v1.to_json(), v2.to_json()]
    Opcode::ArrayPut(v1, v2, v3) => ["ArrayPut", v1.to_json(), v2.to_json(), v3.to_json()]
  }
}

///| Opcode枚举的JSON反序列化
pub fn Opcode::from_json(json : Json) -> Opcode raise {
  match json {
    ["ConstInt", i] => Opcode::ConstInt(i.as_number().unwrap().to_int())
    ["ConstFloat", f] => Opcode::ConstFloat(f.as_number().unwrap())
    ["Add", v1, v2] => Opcode::Add(Value::from_json(v1), Value::from_json(v2))
    ["Sub", v1, v2] => Opcode::Sub(Value::from_json(v1), Value::from_json(v2))
    ["Mul", v1, v2] => Opcode::Mul(Value::from_json(v1), Value::from_json(v2))
    ["Div", v1, v2] => Opcode::Div(Value::from_json(v1), Value::from_json(v2))
    ["Mod", v1, v2] => Opcode::Mod(Value::from_json(v1), Value::from_json(v2))
    ["FAdd", v1, v2] => Opcode::FAdd(Value::from_json(v1), Value::from_json(v2))
    ["FSub", v1, v2] => Opcode::FSub(Value::from_json(v1), Value::from_json(v2))
    ["FMul", v1, v2] => Opcode::FMul(Value::from_json(v1), Value::from_json(v2))
    ["FDiv", v1, v2] => Opcode::FDiv(Value::from_json(v1), Value::from_json(v2))
    ["FMod", v1, v2] => Opcode::FMod(Value::from_json(v1), Value::from_json(v2))
    ["Eq", v1, v2] => Opcode::Eq(Value::from_json(v1), Value::from_json(v2))
    ["Ne", v1, v2] => Opcode::Ne(Value::from_json(v1), Value::from_json(v2))
    ["Lt", v1, v2] => Opcode::Lt(Value::from_json(v1), Value::from_json(v2))
    ["Le", v1, v2] => Opcode::Le(Value::from_json(v1), Value::from_json(v2))
    ["Gt", v1, v2] => Opcode::Gt(Value::from_json(v1), Value::from_json(v2))
    ["Ge", v1, v2] => Opcode::Ge(Value::from_json(v1), Value::from_json(v2))
    ["Jump", block, Array(values)] => {
      let values_res = []
      for v in values {
        values_res.push(Value::from_json(v))
      }
      Opcode::Jump(Block::from_json(block), values_res)
    }
    ["Branch", value, block1, block2] => Opcode::Branch(Value::from_json(value), Block::from_json(block1), Block::from_json(block2))
    ["Return", "None"] => Opcode::Return(None)
    ["Return", value] => Opcode::Return(Some(Value::from_json(value)))
    ["Alloc", ty] => Opcode::Alloc(Type::from_json(ty))
    ["Load", value] => Opcode::Load(Value::from_json(value))
    ["Store", v1, v2] => Opcode::Store(Value::from_json(v1), Value::from_json(v2))
    ["Call", String(name), Array(values)] => {
      let values_res = []
      for v in values {
        values_res.push(Value::from_json(v))
      }
      Opcode::Call(name, values_res)
    }
    ["BlockArg", i] => Opcode::BlockArg(i.as_number().unwrap().to_int())
    ["Tuple", Array(values)] => {
      let values_res = []
      for v in values {
        values_res.push(Value::from_json(v))
      }
      Opcode::Tuple(values_res)
    }
    ["GetElement", value, i] => Opcode::GetElement(Value::from_json(value), i.as_number().unwrap().to_int())
    ["ArrayGet", v1, v2] => Opcode::ArrayGet(Value::from_json(v1), Value::from_json(v2))
    ["ArrayPut", v1, v2, v3] => Opcode::ArrayPut(Value::from_json(v1), Value::from_json(v2), Value::from_json(v3))
    _ => fail("invalid json for Opcode")
  }
}

///| SSA指令
pub(all) struct Instruction {
  result : Value      // 指令结果值
  opcode : Opcode     // 操作码
} derive(Show)

///| Instruction结构体的JSON序列化
pub fn Instruction::to_json(self : Instruction) -> Json {
  {
    "result": self.result.to_json(),
    "opcode": self.opcode.to_json()
  }
}

///| Instruction结构体的JSON反序列化
pub fn Instruction::from_json(json : Json) -> Instruction raise {
  match json {
    { "result": result, "opcode": opcode, .. } => {
      Instruction::{ 
        result: Value::from_json(result), 
        opcode: Opcode::from_json(opcode) 
      }
    }
    _ => fail("invalid json for Instruction")
  }
}

///| 基本块
pub(all) struct BasicBlock {
  id : Block                    // 基本块标识符
  params : Array[(Value, Type)] // 基本块参数（替代phi函数）
  instructions : Array[Instruction]  // 指令序列
  terminator : Terminator       // 终止指令
} derive(Show)

///| BasicBlock结构体的JSON序列化
pub fn BasicBlock::to_json(self : BasicBlock) -> Json {
  {
    "id": self.id.to_json(),
    "params": self.params.map(fn(p) { [p.0.to_json(), p.1.to_json()] }),
    "instructions": self.instructions.map(Instruction::to_json),
    "terminator": self.terminator.to_json()
  }
}

///| BasicBlock结构体的JSON反序列化
pub fn BasicBlock::from_json(json : Json) -> BasicBlock raise {
  match json {
    { "id": id, "params": Array(params), "instructions": Array(instructions), "terminator": terminator, .. } => {
      let params_res = []
      for p in params {
        match p {
          [value, ty] => params_res.push((Value::from_json(value), Type::from_json(ty)))
          _ => fail("invalid json for BasicBlock params")
        }
      }
      
      let instructions_res = []
      for i in instructions {
        instructions_res.push(Instruction::from_json(i))
      }
      
      BasicBlock::{ 
        id: Block::from_json(id), 
        params: params_res, 
        instructions: instructions_res, 
        terminator: Terminator::from_json(terminator) 
      }
    }
    _ => fail("invalid json for BasicBlock")
  }
}

///| 终止指令
pub(all) enum Terminator {
  Jump(Block, Array[Value])     // 无条件跳转
  Branch(Value, Block, Block)   // 条件分支
  Return(Value?)                // 函数返回
} derive(Show)

///| Terminator枚举的JSON序列化
pub fn Terminator::to_json(self : Terminator) -> Json {
  match self {
    Terminator::Jump(block, values) => {
      let values_json = values.map(Value::to_json)
      ["Jump", block.to_json(), values_json]
    }
    Terminator::Branch(value, block1, block2) => {
      ["Branch", value.to_json(), block1.to_json(), block2.to_json()]
    }
    Terminator::Return(value) => {
      match value {
        Some(v) => ["Return", v.to_json()]
        None => ["Return", "None"]
      }
    }
  }
}

///| Terminator枚举的JSON反序列化
pub fn Terminator::from_json(json : Json) -> Terminator raise {
  match json {
    ["Jump", block, Array(values)] => {
      let values_res = []
      for v in values {
        values_res.push(Value::from_json(v))
      }
      Terminator::Jump(Block::from_json(block), values_res)
    }
    ["Branch", value, block1, block2] => {
      Terminator::Branch(Value::from_json(value), Block::from_json(block1), Block::from_json(block2))
    }
    ["Return", "None"] => {
      Terminator::Return(None)
    }
    ["Return", value] => {
      Terminator::Return(Some(Value::from_json(value)))
    }
    _ => fail("invalid json for Terminator")
  }
}

///| 函数定义
pub(all) struct Function {
  name : String           // 函数名
  params : Array[(Value, Type)] // 函数参数
  return_type : Type      // 返回类型
  blocks : Array[BasicBlock]    // 基本块列表
} derive(Show)

///| Function结构体的JSON序列化
pub fn Function::to_json(self : Function) -> Json {
  {
    "name": self.name,
    "params": self.params.map(fn(p) { [p.0.to_json(), p.1.to_json()] }),
    "return_type": self.return_type.to_json(),
    "blocks": self.blocks.map(BasicBlock::to_json)
  }
}

///| Function结构体的JSON反序列化
pub fn Function::from_json(json : Json) -> Function raise {
  match json {
    { "name": String(name), "params": Array(params), "return_type": return_type, "blocks": Array(blocks), .. } => {
      let params_res = []
      for p in params {
        match p {
          [value, ty] => params_res.push((Value::from_json(value), Type::from_json(ty)))
          _ => fail("invalid json for Function params")
        }
      }
      
      let blocks_res = []
      for b in blocks {
        blocks_res.push(BasicBlock::from_json(b))
      }
      
      Function::{ 
        name: name, 
        params: params_res, 
        return_type: Type::from_json(return_type), 
        blocks: blocks_res 
      }
    }
    _ => fail("invalid json for Function")
  }
}

///| SSA程序
pub(all) struct Program {
  functions : Array[Function]   // 函数定义列表
} derive(Show)

///| Program结构体的JSON序列化
pub fn Program::to_json(self : Program) -> Json {
  {
    "functions": self.functions.map(Function::to_json)
  }
}

///| Program结构体的JSON反序列化
pub fn Program::from_json(json : Json) -> Program raise {
  match json {
    { "functions": Array(functions), .. } => {
      let functions_res = []
      for f in functions {
        functions_res.push(Function::from_json(f))
      }
      Program::{ functions: functions_res }
    }
    _ => fail("invalid json for Program")
  }
}

///| 类型系统
pub(all) enum Type {
  Unit
  Int
  Float
  Bool
  Pointer(Type)
  Function(Array[Type], Type)
  Tuple(Array[Type])
  Array(Type)
} derive(Show, Eq)

///| Type枚举的JSON序列化
pub fn Type::to_json(self : Type) -> Json {
  match self {
    Type::Unit => "Unit"
    Type::Int => "Int"
    Type::Float => "Float"
    Type::Bool => "Bool"
    Type::Pointer(ty) => ["Pointer", ty.to_json()]
    Type::Function(args, ret) => {
      let args_json = args.map(Type::to_json)
      ["Function", args_json, ret.to_json()]
    }
    Type::Tuple(elements) => {
      let elements_json = elements.map(Type::to_json)
      ["Tuple", elements_json]
    }
    Type::Array(element) => ["Array", element.to_json()]
  }
}

///| Type枚举的JSON反序列化
pub fn Type::from_json(json : Json) -> Type raise {
  match json {
    "Unit" => Type::Unit
    "Int" => Type::Int
    "Float" => Type::Float
    "Bool" => Type::Bool
    ["Pointer", ty] => Type::Pointer(Type::from_json(ty))
    ["Function", Array(args), ret] => {
      let args_res = []
      for a in args {
        args_res.push(Type::from_json(a))
      }
      Type::Function(args_res, Type::from_json(ret))
    }
    ["Tuple", Array(elements)] => {
      let elements_res = []
      for e in elements {
        elements_res.push(Type::from_json(e))
      }
      Type::Tuple(elements_res)
    }
    ["Array", element] => Type::Array(Type::from_json(element))
    _ => fail("invalid json for Type")
  }
}

///| SSA中间表示主结构
pub(all) struct Ssa {
  program : Program
} derive(Show)
