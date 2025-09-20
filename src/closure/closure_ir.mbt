///|
/// Represents static array data that will be placed in the data segment
pub(all) struct StaticArrayData {
  label : Label
  elements : Array[LowTypeValue]
} derive(Show, ToJson)

///|
/// Represents a value in a static array
pub(all) enum LowTypeValue {
  IntValue(Int)
  DoubleValue(Double)
  PtrValue(Array[LowTypeValue])
} derive(Show, ToJson(style="flat"))

///|
pub(all) struct Label(String) derive(Show, ToJson)

///|
pub typealias @types.Name

///|
pub typealias @types.Type

///|
pub(all) enum Expr {
  Unit
  Int(Int)
  Int64(Int64)
  Double(Double)
  Neg(Name)
  Add(Name, Name)
  Sub(Name, Name)
  Mul(Name, Name)
  Div(Name, Name)
  Mod(Name, Name)
  FNeg(Name)
  FAdd(Name, Name)
  FSub(Name, Name)
  FMul(Name, Name)
  FDiv(Name, Name)
  FMod(Name, Name)
  IfEq(Name, Name, Expr, Expr)
  IfLe(Name, Name, Expr, Expr)
  IfLt(Name, Name, Expr, Expr)
  Let((Name, LowType), Expr, Expr)
  Var(Name)
  MakeClosure((Name, LowType), Closure, Expr)
  CallClosure(Name, Array[Name])
  CallDirect(Label, Array[Name])
  MakeTuple(Array[Name])
  LetTuple(Array[(Name, LowType)], Name, Expr)
  TupleGet(Name, LowType, Int)
  ArrayGet(Name, Name)
  ArrayPut(Name, Name, Name)
  ExternalArray(Label)
  ExternalFunctionApplication(Label, Array[Name])
  While(Expr, Expr)
  Assign(Name, Name)
  /// Reference to static array data in data segment
  StaticArrayRef(Label)
} derive(Show, ToJson(style="flat"))

///|
pub(all) struct Closure {
  name : Label
  actual_free_vars : Array[Name]
} derive(Show, ToJson)

///|
pub(all) struct FuncDef {
  name : Label
  old_name : Name
  /// true if the function is a closure function, and the closure will be available at `s11` on 
  /// function entry.
  is_closure : Bool
  ty : LowType
  args : Array[(Name, LowType)]
  formal_free_vars : Array[(Name, LowType)]
  body : Expr
} derive(Show, ToJson)

///|
pub(all) struct Program {
  fundefs : Array[FuncDef]
  body : Expr
  /// Static array data to be placed in data segment
  static_arrays : Array[StaticArrayData]
} derive(Show, ToJson)
