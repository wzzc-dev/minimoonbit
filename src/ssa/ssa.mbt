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

  // 内存操作
  Alloc(Type)
  Load(Value)
  Store(Value, Value)

  // 函数调用
  Call(String, Array[Value])

  // 闭包操作
  MakeClosure(String, Array[Value]) // 创建闭包：变量名，函数名，自由变量列表
  CallClosure(Value, Array[Value]) // 调用闭包：闭包值，参数列表

  // 元组操作
  Tuple(Array[Value])
  GetElement(Value, Int)

  // 数组操作
  ArrayGet(Value, Value)
  ArrayPut(Value, Value, Value)
} derive(Show)


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
  Branch(Value, Block, Block) // 条件分支
  Return(Value?) // 函数返回
} derive(Show)


///|
/// 函数定义
pub(all) struct Function {
  name : String // 函数名
  params : Array[Value] // 函数参数
  closure_param : Array[Value] // 闭包参数
  return_type : Type // 返回类型
  blocks : Array[BasicBlock] // 基本块列表
} derive(Show)


///|
/// SSA程序
pub(all) struct Program {
  functions : Array[Function] // 函数定义列表
} derive(Show)



///|
/// 类型系统
pub(all) enum Type {
  Unit
  Int
  Float
  Bool
  Pointer(Type)
  Function(Array[Type], Type)
  Tuple(Array[Type])
  Array(Type)
} derive(Show, Eq, Hash)


///|
/// SSA中间表示主结构
pub(all) struct Ssa {
  program : Program
} derive(Show)
