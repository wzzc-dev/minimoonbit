///|
pub(all) enum Syntax {
  Unit
  Bool(Bool) // true false
  Int(Int) // int
  Int64(Int64) // int64
  Double(Double) // double
  Var(String) // _
  Tuple(Array[Syntax]) // (_, _, _)
  Not(Syntax) // not(_)
  Array(Syntax, Syntax) // Array::make(_, _)
  ArrayExpr(Array[Syntax])
  Neg(Syntax, mut kind~ : Kind?) // -_
  App(Syntax, Array[Syntax]) // _(_, _, _) or _()
  Get(Syntax, Syntax) // _[_]
  If(Syntax, Syntax, Syntax) // if _ { _ } else { _ }
  Prim(Syntax, Syntax, Op, mut kind~ : Kind?) // _+ - * / _
  Eq(Syntax, Syntax) // _==_
  LE(Syntax, Syntax) // _<=_
  LT(Syntax, Syntax) // _<_
  GE(Syntax, Syntax) // _>=_
  GT(Syntax, Syntax) // _>_
  NE(Syntax, Syntax) // _!=_
  And(Syntax, Syntax) // _&&_
  Or(Syntax, Syntax) // _||_
  Let((String, Type), Syntax, Syntax) // let _: _ = _; _
  LetRec(Fundef, Syntax) // fn f() {} ; _
  LetTuple(Array[(String, Type)], Syntax, Syntax) // let (_ , _) : (_, _)= _; _
  Put(Syntax, Syntax, Syntax) // _[_] = _;
  Assign(Syntax, Syntax) // _ = _
  Struct(String, String, Array[(String, Type)], Syntax) // struct _ [_] { _: _, _: _ }  _
  StructConstruct(String, Array[(String, Syntax)]) // _::{ _: _, _: _ }
  FieldAccess(Syntax, String) // _.field
  Enum(String, String, Array[(String, Array[Type])], Syntax) // enum [_] { A, B, C }  _
  EnumConstruct(String, Array[Syntax]) // _(_,_,_)
  Match(Syntax, Array[(Pattern, Syntax)])
  While(Syntax, Syntax) // while x { ... }
  Return(Syntax?) // return _;
  ArrayData(String, Array[Syntax])
  ExternalArray(String)
} derive(Show, ToJson)

///|
pub(all) enum Pattern {
  PVar(String)
  PInt(Int)
  PBool(Bool)
  PTuple(Array[Pattern])
  PEnumVariant(String, Array[Pattern])
  PWildcard
} derive(Show, ToJson)

///|
pub(all) enum Kind {
  Int
  Double
} derive(Show, Eq, ToJson)

///|
pub(all) enum Op {
  Add
  Sub
  Mul
  Div
  Mod
} derive(Show, Eq, ToJson)

///|
pub(all) struct Fundef {
  name : (String, Type)
  args : Array[(String, Type)]
  body : Syntax
} derive(Show, ToJson)

///|
pub(all) enum Type {
  Unit
  Bool
  Int
  Double
  Fun(Array[Type], Type) // (_, _, _) -> _
  Tuple(Array[Type]) // (_, _, _)
  Array(Type) // Array[_]
  Struct(String, Array[(String, Type)]) // struct _ { _: _, _: _ }
  Enum(String, Array[String]) // enum _ { A, B, C }
  UserDefineType(String, Ref[Array[(String, Type)]])
  Var(Ref[Type?])
  Ptr
  /// Represents data for static arrays stored in data segment
  ArrayData(Array[Syntax])
} derive(Show)

///|
pub impl ToJson for Type with to_json(self : Type) -> Json {
  match self {
    Unit
    | Bool
    | Int
    | Double
    | Fun(_)
    | Tuple(_)
    | Array(_)
    | Ptr
    | Enum(_)
    | Struct(_)
    | Var(_)
    | ArrayData(_) => self.to_json()
    UserDefineType(name, val) => ["UserDefineType", name, val.val.to_json()]
  }
}

///|
pub fn Type::is_float_like(self : Type) -> Bool {
  match self {
    Double => true
    Var(t) =>
      match t.val {
        Some(t) => t.is_float_like()
        None => false
      }
    _ => false
  }
}

///|
pub fn Type::size_of(self : Type, size_of_ptr : Int) -> Int {
  match self {
    Unit => 0
    Bool => 4
    Int => 4
    Double => 8
    Struct(_, fs) =>
      fs.fold(init=0, (sum, elem) => sum + elem.1.size_of(size_of_ptr))
    UserDefineType(_) => 8
    Enum(_, _) => 4
    Tuple(_) | Fun(_, _) | Array(_) | Ptr | ArrayData(_) => size_of_ptr
    Var(t) =>
      match t.val {
        Some(t) => t.size_of(size_of_ptr)
        None => @util.die("Uninstantiated type variable")
      }
  }
}

///|
pub impl Eq for Type with equal(self, other) -> Bool {
  match (self, other) {
    (Type::Unit, Type::Unit) => true
    (Type::Bool, Type::Bool) => true
    (Type::Int, Type::Int) => true
    (Type::Double, Type::Double) => true
    (Type::Fun(xs, x), Type::Fun(ys, y)) =>
      if xs.length() != ys.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < xs.length(); i = i + 1 {
          if not(xs[i].equal(ys[i])) {
            equal = false
            break
          }
        }
        equal && x.equal(y)
      }
    (Type::Tuple(xs), Type::Tuple(ys)) =>
      if xs.length() != ys.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < xs.length(); i = i + 1 {
          if not(xs[i].equal(ys[i])) {
            equal = false
            break
          }
        }
        equal
      }
    (Type::Array(x), Type::Array(y)) => x.equal(y)
    (Type::Struct(name1, fields1), Type::Struct(name2, fields2)) =>
      name1 == name2 &&
      (if fields1.length() != fields2.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < fields1.length(); i = i + 1 {
          if fields1[i].0 != fields2[i].0 ||
            not(fields1[i].1.equal(fields2[i].1)) {
            equal = false
            break
          }
        }
        equal
      })
    (Type::Enum(name1, variants1), Type::Enum(name2, variants2)) =>
      name1 == name2 && variants1 == variants2
    (Type::UserDefineType(name1, fields1), Type::UserDefineType(name2, fields2)) =>
      name1 == name2 && fields1.val == fields2.val
    (Type::Ptr, Type::Ptr) => true
    (Type::ArrayData(_), Type::ArrayData(_)) => true
    (Type::Var(x), Type::Var(y)) => x.val.equal(y.val)
    _ => false
  }
}

///|
pub fn Type::repr(self : Type) -> Type {
  match self {
    Bool | Int | Unit | Double | Ptr | UserDefineType(_) => self
    Var(t) as tvar =>
      match t.val {
        Some(ty) => {
          let actual_ty = ty.repr()
          t.val = Some(actual_ty)
          actual_ty
        }
        None => tvar
      }
    Fun(xs, x) => Fun(xs.map(t => t.repr()), x.repr())
    Tuple(xs) => Tuple(xs.map(t => t.repr()))
    Array(x) => Array(x.repr())
    ArrayData(_) => self
    Struct(name, fs) => Struct(name, fs.map(f => (f.0, f.1.repr())))
    Enum(name, fs) => Enum(name, fs)
  }
}

///|
pub fn Type::new_tvar() -> Type {
  Var({ val: None })
}
