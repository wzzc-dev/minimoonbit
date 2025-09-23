fn gen_func_type(ty : Type, is_closure : Bool, fundefs: Array[FuncDef], body : Expr) -> LowType {
  match ty {
    Fun(args, ty) => match is_closure {
      true => ClosureFn(args.map(ty => ty_to_low_type(ty)), gen_body_ret_type(ty, fundefs, body))
      false => DirectFn(args.map(ty => ty_to_low_type(ty)), gen_body_ret_type(ty, fundefs, body))
    }
    _ => @util.die("gen_func_type: " + ty.to_string())
  }
}

fn gen_body_ret_type(ty : Type, funcdefs: Array[FuncDef], body: Expr) -> LowType {
  match body {
    MakeClosure((_, ret_ty), _, _) => ret_ty
    Let(_, _, body) => gen_body_ret_type(ty, funcdefs, body)
    CallClosure(name, _) => match funcdefs.search_by(fn(f) { f.name.0 == name.name.unwrap() }) {
      Some(index) => match funcdefs.get(index) {
        Some(f) => f.ty
        None => @util.die("gen_body_ret_type: r " + name.name.unwrap() + " not found")
      }
      None => @util.die("gen_body_ret_type: " + name.name.unwrap() + " not found")
    }
    CallDirect(name, _) => match funcdefs.search_by(fn(f) { f.name.0 == name.0 }) {
      Some(index) => match funcdefs.get(index) {
        Some(f) =>{
            match f.ty {
              DirectFn(_, ret_ty) => ret_ty
              ClosureFn(_, ret_ty) => ret_ty
              _ => @util.die("gen_body_ret_type dir: " + name.0 + " not found")
            }
          }
        None => @util.die("gen_body_ret_type dir1: " + name.0 + " not found")
      }
      None => ty_to_low_type(ty)
    }
    Var(name) => match funcdefs.search_by(fn(f) { f.name.0 == name.name.unwrap() }) {
      Some(index) => match funcdefs.get(index) {
        Some(f) => f.ty
        None => ty_to_low_type(ty)
      }
      None => ty_to_low_type(ty)
    }
    _ => {
      ty_to_low_type(ty)
    }
  }
}

///|
fn ty_to_low_type(ty : Type) -> LowType {
  match ty {
    Unit => Unit
    Bool => Bool
    Int => Int
    Double => Double
    Tuple(arr_ty) => Tuple(arr_ty.map(ty => ty_to_low_type(ty)))
    Array(ty) => Array(ty_to_low_type(ty))
    Var(ty) =>
      match ty.val {
        Some(UserDefineType(_, fields)) => {
          let fields_ty = fields.val.map(field => ty_to_low_type(field.1))
          Tuple(fields_ty)
        }
        Some(ty) => ty_to_low_type(ty)
        _ => @util.die("ty_to_low_type: Var" + ty.to_string())
      }
    Ptr => Ptr
    Enum(_name, _) | Struct(_name, _) =>
      @util.die("ty_to_low_type: Enum or Struct" + ty.to_string())
    UserDefineType(_, fields) => {
      let fields_ty = fields.val.map(field => ty_to_low_type(field.1))
      Tuple(fields_ty)
    }
    ArrayData(_) => @util.die("ty_to_low_type: ArrayData" + ty.to_string())
    Fun(args_ty, ret_ty) =>
      DirectFn(args_ty.map(ty => ty_to_low_type(ty)), ty_to_low_type(ret_ty))
  }
}
fn arr_ty_to_low_type(ty : Type) -> LowType {
  match ty {
    Unit => Unit
    Bool => Bool
    Int => Int
    Double => Double
    Tuple(arr_ty) => Tuple(arr_ty.map(ty => ty_to_low_type(ty)))
    Array(ty) => Array(ty_to_low_type(ty))
    Var(ty) =>
      match ty.val {
        Some(UserDefineType(_, fields)) => {
          let fields_ty = fields.val.map(field => ty_to_low_type(field.1))
          Tuple(fields_ty)
        }
        Some(ty) => ty_to_low_type(ty)
        _ => @util.die("ty_to_low_type: Var" + ty.to_string())
      }
    Ptr => Ptr
    Enum(_name, _) | Struct(_name, _) =>
      @util.die("ty_to_low_type: Enum or Struct" + ty.to_string())
    UserDefineType(_, fields) => {
      let fields_ty = fields.val.map(field => ty_to_low_type(field.1))
      Tuple(fields_ty)
    }
    ArrayData(_) => @util.die("ty_to_low_type: ArrayData" + ty.to_string())
    Fun(args_ty, ret_ty) =>
      ClosureFn(args_ty.map(ty => ty_to_low_type(ty)), ty_to_low_type(ret_ty))
  }
}
