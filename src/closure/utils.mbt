///|
fn gen_func_type(
  ty : Type,
  is_closure : Bool,
  fundefs : Array[FuncDef],
  env : @immut/hashmap.HashMap[Name, LowType],
  body : Expr,
) -> LowType {
  // @util.logger("gen_func_type: " + ty.to_string() + " is_closure: " + is_closure.to_string() + " body: " + body.to_string())
  match ty {
    Fun(args, ty) =>
      if is_closure {
        ClosureFn(
          args.map(ty => ty_to_low_type(ty)),
          gen_body_ret_type(ty, fundefs, env, body),
        )
      } else {
        DirectFn(
          args.map(ty => {
            match ty_to_low_type(ty) {
              DirectFn(arg_tys, ret_ty) => ClosureFn(arg_tys, ret_ty)
              ty => ty
            }
          }),
          gen_body_ret_type(ty, fundefs, env, body),
        )
      }
    _ => @util.die("gen_func_type: " + ty.to_string())
  }
}

// fn gen_cls_func_type(ty : LowType) -> LowType {
//   match ty {
//     ClosureFn(args, ty) | DirectFn(args, ty) => {
//       ClosureFn(args, ty)
//     }
//     _ => @util.die("gen_func_type: " + ty.to_string())
//   }
// }

///|
fn gen_body_ret_type(
  ty : Type,
  funcdefs : Array[FuncDef],
  env : @immut/hashmap.HashMap[Name, LowType],
  body : Expr,
) -> LowType {
  match body {
    MakeClosure(_, _, ret_expr) => gen_body_ret_type(ty, funcdefs, env, ret_expr)
    Let(_, _, body) => gen_body_ret_type(ty, funcdefs, env, body)
    CallClosure(name, _) =>
      match funcdefs.search_by(fn(f) { f.name.0 == name.name.unwrap() }) {
        Some(index) =>
          match funcdefs.get(index) {
            Some(f) => f.ty
            None =>
              @util.die(
                "gen_body_ret_type: r " + name.name.unwrap() + " not found",
              )
          }
        None =>
          match env.get(name) {
            Some(ty) =>
              match ty {
                ClosureFn(_, ret_ty) | DirectFn(_, ret_ty) => ret_ty
                _ =>
                  @util.die(
                    "gen_body_ret_type var1: " +
                    name.name.unwrap() +
                    " not a function type",
                  )
              }
            None =>
              @util.die(
                "gen_body_ret_type var2: " + name.name.unwrap() + " not found",
              )
          }
      }
    CallDirect(name, _) =>
      match funcdefs.search_by(fn(f) { f.name.0 == name.0 }) {
        Some(index) =>
          match funcdefs.get(index) {
            Some(f) =>
              match f.ty {
                ClosureFn(_, ret_ty) | DirectFn(_, ret_ty) => ret_ty
                _ =>
                  @util.die("gen_body_ret_type dir: " + name.0 + " not a function type")
              }
            None =>
              @util.die("gen_body_ret_type dir1: " + name.0 + " not found")
          }
        None => ty_to_low_type(ty)
      }
    Var(name) =>
      match funcdefs.search_by(fn(f) { f.old_name == name }) {
        Some(index) =>
          match funcdefs.get(index) {
            Some(f) => f.ty
            None => ty_to_low_type(ty)
          }
        None => ty_to_low_type(ty)
      }
    ArrayGet(arr, _) =>
      match env.get(arr) {
        Some(ty) =>
          match ty {
            Array(ty) => ty
            _ =>
              @util.die(
                "gen_body_ret_type arr: " + arr.name.unwrap() + " not found",
              )
          }
        None =>
          @util.die(
            "gen_body_ret_type arr1: " + arr.name.unwrap() + " not found",
          )
      }
    _ => ty_to_low_type(ty)
  }
}

///|
fn ty_to_low_type(ty : Type, is_closure? : Bool = false) -> LowType {
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
      if is_closure {
        ClosureFn(
          args_ty.map(ty => ty_to_low_type(ty)),
          ty_to_low_type(ret_ty),
        )
      } else {
        DirectFn(
          args_ty.map(ty => ty_to_low_type(ty)),
          ty_to_low_type(ret_ty),
        )
      }
  }
}

