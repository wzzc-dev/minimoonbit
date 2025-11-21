///| 静态单赋值（SSA）中间表示

///|
/// SSA值标识符
pub(all) struct Value {
  id : Int
  ty : Type
} derive(Show, Eq, Hash)

///|
/// 基本块标识符
pub(all) struct Block {
  id : Int
} derive(Show, Eq, Hash)

///|
/// 操作码类型
pub(all) enum Opcode {
  // 常量
  ConstInt(Int)
  ConstFloat(Double)
  ConstBool(Bool)

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

  // 函数调用
  Call(Func, Array[Value])
  // 函数引用
  CallRef(String, Array[Value])

  // 静态数组引用
  ArrayRef(String)

  // 内存操作
  Malloc(Int) // 分配内存，大小参数
  Store(Value, Value, Int) // 存储值到内存地址：值，基地址，偏移量
  Load(Value, Int, Type) // 从内存地址加载值：基地址，偏移量，类型
  ConstFuncPtr(String) // 常量函数指针

  CallClosure(Func, Array[Value]) // 调用闭包：闭包值，参数列表

  // 元组操作
  Tuple(Array[Value])
  GetElement(Value, Int)

  // 数组操作
  ArrayGet(Value, Value)
  ArrayPut(Value, Value, Value)
} derive(Show)

///|
pub(all) enum Func {
  Label(String)
  Call(Value)
} derive(Show, Eq)

///|
/// SSA指令
pub(all) struct Instruction {
  result : Value // 指令结果值
  opcode : Opcode // 操作码
} derive(Show)

///|
/// 基本块
pub(all) struct BasicBlock {
  id : Block // 基本块标识符
  params : Array[Value] // 基本块参数
  instructions : Array[Instruction] // 指令序列
  terminator : Terminator // 终止指令
} derive(Show)

///|
/// 终止指令
pub(all) enum Terminator {
  Jump(Block, Array[Value]) // 无条件跳转
  Branch(Value, Block, Array[Value], Block, Array[Value]) // 条件分支，支持为每个目标传递参数
  Return(Value?) // 函数返回
} derive(Show)

///|
/// 函数定义
pub(all) struct Function {
  name : String // 函数名
  params : Array[Value] // 函数参数（不包括闭包参数）
  closure_vars : Array[Value] // 闭包捕获的变量
  ty : Type // 函数类型（包含参数、返回类型和闭包信息）
  blocks : Array[BasicBlock] // 基本块列表
} derive(Show)

///|
/// Function 的便捷访问方法
pub fn Function::return_type(self : Function) -> Type {
  self.ty.get_return_type()
}

///|
pub fn Function::all_params(self : Function) -> Array[Value] {
  // 返回所有参数：普通参数 + 闭包变量
  let all = self.params.copy()
  all.append(self.closure_vars)
  all
}

///|
pub fn Function::is_closure(self : Function) -> Bool {
  self.ty.is_closure_function()
}

///|
/// SSA程序
pub(all) struct Program {
  functions : Array[Function] // 函数定义列表
  static_arrays : Array[@closure.StaticArrayData] // 静态数组数据
} derive(Show)

///|
/// 类型系统
pub(all) enum Type {
  Unit
  Int
  Float
  Bool
  Pointer(Type)
  ClosureFn(Array[Type], Type) // 闭包函数类型：参数类型, 返回类型
  DirectFn(Array[Type], Type) // 直接函数类型：参数类型, 返回类型
  Tuple(Array[Type])
  Array(Type)
} derive(Show, Eq, Hash)

///|
/// 从函数类型中提取返回类型
pub fn Type::get_return_type(self : Type) -> Type {
  match self {
    ClosureFn(_, ret_type) | DirectFn(_, ret_type) => ret_type
    _ => Unit  // 非函数类型的默认返回类型
  }
}

///|
/// 从函数类型中提取参数类型列表
pub fn Type::get_param_types(self : Type) -> Array[Type] {
  match self {
    ClosureFn(param_types, _) | DirectFn(param_types, _) => param_types
    _ => []  // 非函数类型没有参数
  }
}

///|
/// 检查是否为闭包函数类型
pub fn Type::is_closure_function(self : Type) -> Bool {
  match self {
    ClosureFn(_, _) => true
    _ => false
  }
}

///|
/// SSA中间表示主结构
pub(all) struct Ssa {
  program : Program
} derive(Show)
