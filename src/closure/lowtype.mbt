///|
/// Low-level types. Simplified type system with unified function type.
pub(all) enum LowType {
  Unit
  Bool
  Int
  Double
  Function(Array[LowType], LowType, Bool) // params, result, is_closure
  Tuple(Array[LowType])
  Array(LowType)
  Ptr
} derive(Show, Eq, ToJson)

///|
pub fn LowType::is_ptr_like(self : LowType) -> Bool {
  match self {
    Function(_, _, _) | Tuple(_) | Array(_) | Ptr => true
    _ => false
  }
}

///|
pub fn LowType::is_float_like(self : LowType) -> Bool {
  match self {
    Double => true
    _ => false
  }
}

///|
pub fn LowType::size_of(self : LowType, size_of_ptr : Int) -> Int {
  match self {
    Unit => 0
    Bool => 4
    Int => 4
    Double => 8
    _ => if self.is_ptr_like() { size_of_ptr } else { 4 }
  }
}

///|
pub fn LowType::function_type(self : LowType) -> (Array[LowType], LowType, Bool)? {
  match self {
    Function(params, result, is_closure) => Some((params, result, is_closure))
    _ => None
  }
}

///|
pub fn LowType::make_function(params : Array[LowType], result : LowType, is_closure : Bool) -> LowType {
  Function(params, result, is_closure)
}

///|
pub fn LowType::is_function(self : LowType) -> Bool {
  match self {
    Function(_, _, _) => true
    _ => false
  }
}
