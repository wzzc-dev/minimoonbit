///|
pub typealias @types.Name

///|
pub typealias @types.Type

///|
pub(all) enum Knf {
  Unit
  Int(Int)
  Int64(Int64)
  Double(Double)
  Bool(Bool)
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
  IfEq(Name, Name, Knf, Knf)
  IfLe(Name, Name, Knf, Knf)
  IfLt(Name, Name, Knf, Knf)
  Let((Name, Type), Knf, Knf)
  Var(Name)
  LetRec(FuncDef, Knf)
  Apply(Name, Array[Name])
  Tuple(Array[Name])
  LetTuple(Array[(Name, Type)], Name, Knf)
  FieldAccess(Name, Type, Int)

  Get(Name, Name)
  Put(Name, Name, Name)
  ExternalArray(String)
  ExternalFunctionApplication(String, Array[Name])
  ArrayData(String, Array[Knf])
  
  While(Knf, Knf)   // While(condition, body)
  Assign(Name, Name)
} derive(Show, Eq)

///|
pub(all) struct FuncDef {
  name : Name
  ty : Type
  args : Array[(Name, Type)]
  body : Knf
} derive(Show, Eq)

pub(all) struct StructDef {
  name : Name
  fields : Array[(Name, Type)]
} derive(Show, Eq)