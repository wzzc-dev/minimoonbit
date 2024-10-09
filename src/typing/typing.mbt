type! TyErr String

fn unify(t1 : @types.Type, t2 : @types.Type) -> Unit!TyErr {
  // println("unify:" + t1.to_string() + " t2: " + t2.to_string())
  let t1 = t1.repr()
  let t2 = t2.repr()
  if physical_equal(t1, t2) {
    return
  }
  match (t1, t2) {
    (Int, Int) | (Bool, Bool) | (Double, Double) | (Unit, Unit) => ()
    (Var(t), ty) | (ty, Var(t)) =>
      match t.val {
        None => {
          // println(
          //   "match (t1, t2) {  t1: " + t1.to_string() + " ty: " + ty.to_string(),
          // )
          check_occur!(t1, ty)
          t.val = Some(ty)
          // println(
          //   "unify! done" +
          //   " t.val: " +
          //   t.val.to_string() +
          //   " Some(ty): " +
          //   Some(ty).to_string() +
          //   "",
          // )
        }
        _ => ()
      }
    // handle the array type 
    (Array(t1), Array(t2)) => unify!(t1, t2)
    // handle the tuple
    (Tuple(tys1), Tuple(tys2)) =>
      for i, ty in tys1 {
        unify!(ty, tys2[i])
      }
    // handle the function
    (Fun(tys1, ty1), Fun(tys2, ty2)) => {
      for i, ty in tys1 {
        unify!(ty, tys2[i])
      }
      unify!(ty1, ty2)
    }
    _ =>
      raise TyErr("type unify error: " + t1.to_string() + " " + t2.to_string())
  }
}

fn check_occur(t1 : @types.Type, t2 : @types.Type) -> Unit!TyErr {
  // println("check_occur:" + t1.to_string() + " t2: " + t2.to_string())
  match (t1, t2) {
    (Var(ty1), Var(ty2)) => {
      if physical_equal(t1, t2) {
        raise TyErr(
          "occurs check error, t1" + t1.to_string() + ", t2:" + t2.to_string(),
        )
      }
      check_occur!(ty1.val.unwrap(), ty2.val.unwrap())
    }
    (Var(ty1), Array(Var(ty))) | (Array(Var(ty)), Var(ty1)) => {
      if physical_equal(t1, t2) {
        raise TyErr(
          "occurs check error, t1" + t1.to_string() + ", t2:" + t2.to_string(),
        )
      }
      check_occur!(ty1.val.unwrap(), ty.val.unwrap())
    }
    (Tuple(tys), Var(ty1)) | (Var(ty1), Tuple(tys)) =>
      for ty in tys {
        match ty {
          Var(t) =>
            if physical_equal(t, ty1) {
              raise TyErr(
                "The type of tuple element should not be a type variable ",
              )
            } else {
              check_occur!(ty1.val.unwrap(), ty)
            }
          _ => ()
        }
      }
    (Fun(tys, Var(ty)), Var(t1)) | (Var(t1), Fun(tys, Var(ty))) => {
      for t in tys {
        if physical_equal(t, t1.val.unwrap()) {
          raise TyErr("The type of function should not be a type variable")
        }
        check_occur!(Var(t1), t)
      }
      match @types.Type::Var(ty) {
        ty =>
          if physical_equal(ty, t1.val.unwrap()) {
            raise TyErr("The type of function should not be a type variable")
          } else {
            check_occur!(t1.val.unwrap(), ty)
          }
      }
    }
    _ => ()
  }
}

type LocalCtx @immut/sorted_map.T[String, @types.Type]

fn infer(ctx : LocalCtx, e : @types.Syntax) -> @types.Type!TyErr {
  // println("infer: " + e.to_string())
  match e {
    Unit => Unit
    Bool(_) => Bool
    Int(_) => Int
    Double(_) => Double
    // eg.
    Var(x) =>
      match ctx._[x] {
        Some(t) => t.repr()
        None =>
          match extenv[x] {
            Some(t) => t.repr()
            None => {
              let t = @types.Type::new_tvar()
              extenv[x] = t
              t
            }
          }
      }
    Tuple(tys) => {
      let result = []
      for ty in tys {
        result.push(infer!(ctx, ty))
      }
      Tuple(result)
    }
    Not(syn) =>
      match infer!(ctx, syn) {
        Bool => Bool
        _ => raise TyErr("The operand of Not is not a bool value")
      }
    Array(n, syn) =>
      match infer!(ctx, n) {
        Int => Array(infer!(ctx, syn))
        _ => raise TyErr("The operand of Array is not a int value")
      }
    Neg(syn, ..) as neg =>
      match infer!(ctx, syn) {
        Int => {
          neg.kind = Some(Int)
          Int
        }
        Double => {
          neg.kind = Some(Double)
          Double
        }
        _ => raise TyErr("The operand of Neg is not a int or double value")
      }
    // eg.
    App(f, args) => {
      // println("App: " + f.to_string() + " args: " + args.to_string())
      let ret_ty = @types.Type::new_tvar()
      let f_ty = infer!(ctx, f)
      let args_ty = []
      for a in args {
        args_ty.push(infer!(ctx, a))
      }
      unify!(f_ty, Fun(args_ty, ret_ty))
      ret_ty
    }
    Get(arr, index) =>
      match infer!(ctx, index) {
        Int =>
          match infer!(ctx, arr) {
            Array(t) => t
            _ => raise TyErr("The operand of Get should have Type Array")
          }
        _ => raise TyErr("The index of Get should have Type Int")
      }
    If(condition, b1, b2) =>
      match infer!(ctx, condition) {
        Bool =>
          if infer!(ctx, b1) == infer!(ctx, b2) {
            return infer!(ctx, b1)
          } else {
            raise TyErr("The branchs of If should have same type")
          }
        _ => raise TyErr("The condition of If should have Type Bool")
      }
    Prim(l, r, _, ..) as prim =>
      match (infer!(ctx, l), infer!(ctx, r)) {
        (Int, Int) => {
          prim.kind = Some(Int)
          Int
        }
        (Double, Double) => {
          prim.kind = Some(Double)
          Double
        }
        (Var(t), Int) | (Int, Var(t)) => {
          t.val = Some(Double)
          prim.kind = Some(Int)
          Int
        }
        (Var(t), Double) | (Double, Var(t)) => {
          t.val = Some(Double)
          prim.kind = Some(Double)
          Double
        }
        (Var(_), Var(_)) => {
          prim.kind = Some(Int)
          Int
        }
        _ => raise TyErr("The operands of Prim should have same type")
      }
    Eq(l, r) =>
      match (infer!(ctx, l), infer!(ctx, r)) {
        (Int, Int) | (Double, Double) => Bool
        (Var(t), Int) | (Int, Var(t)) => {
          t.val = Some(Int)
          Bool
        }
        (Var(t), Double) | (Double, Var(t)) => {
          t.val = Some(Double)
          Bool
        }
        _ => raise TyErr("The operands of Eq should have same type")
      }
    LE(l, r) =>
      match (infer!(ctx, l), infer!(ctx, r)) {
        (Int, Int) | (Double, Double) => Bool
        (Var(t), Int) | (Int, Var(t)) => {
          t.val = Some(Int)
          Bool
        }
        (Var(t), Double) | (Double, Var(t)) => {
          t.val = Some(Double)
          Bool
        }
        _ => raise TyErr("The operands of LE should have same type")
      }
    Let((name, ty), value, s1) =>
      match ty {
        Var({ val: None }) => {
          let t = infer!(ctx, value)
          unify!(ty, t)
          let newctx = ctx._.insert(name, t)
          infer!(newctx, s1)
        }
        _ => {
          let t = infer!(ctx, value)
          if t == ty {
            let newctx = ctx._.insert(name, ty)
            infer!(newctx, s1)
          } else {
            raise TyErr("The value and expression types in Let are different")
          }
        }
      }
    LetRec({ name: (f, t), args: params, body }, rest) => {
      let env_with_f = ctx._.insert(f, t)
      let params_ty = params.map(fn { (_, t) => t.repr() })
      let mut env_with_params = env_with_f
      for p in params {
        env_with_params = env_with_params.insert(p.0, p.1)
      }
      let body_ty = infer!(env_with_params, body)
      unify!(t, Fun(params_ty, body_ty))
      infer!(env_with_f, rest)
    }
    LetTuple(arr, s1, s2) =>
      match arr[0].1 {
        Var({ val: None }) =>
          match s1 {
            Tuple(arr_tup) => {
              let mut newctx = ctx
              for i, value in arr {
                let t = infer!(ctx, arr_tup[i])
                unify!(value.1, t)
                newctx = ctx._.insert(value.0, t)
              }
              infer!(newctx, s2)
            }
            _ => raise TyErr("The first operand of LetTuple should be tuple")
          }
        _ =>
          match s1 {
            Tuple(arr_tup) => {
              let mut newctx = ctx
              for i, value in arr {
                let t = infer!(ctx, arr_tup[i])
                if value.1 == t {
                  newctx = ctx._.insert(value.0, t)
                } else {
                  raise TyErr("The types of tuple and array are different")
                }
              }
              infer!(newctx, s2)
            }
            _ => raise TyErr("The first operand of LetTuple should be tuple")
          }
      }
    Put(name, n, value) =>
      match name {
        Get(_, _) =>
          if infer!(ctx, name) == infer!(ctx, n) {
            infer!(ctx, value)
          } else {
            raise TyErr("The operand of Put should have same type")
          }
        _ => raise TyErr("The operand of Put should be Get")
      }
  }
}

fn deref_type(t : @types.Type) -> @types.Type {
  match t {
    Fun(params, result) =>
      Fun(params.map(fn { t => deref_type(t) }), deref_type(result))
    Tuple(types) => Tuple(types.map(fn { t => deref_type(t) }))
    Array(t) => Array(deref_type(t))
    Var(tvar) =>
      match tvar.val {
        Some(t1) => {
          let typ = deref_type(t1)
          tvar.val = Some(typ)
          typ
        }
        None => {
          tvar.val = Some(Unit)
          Unit
        }
      }
    t => t
  }
}

fn deref_term(syntax : @types.Syntax) -> @types.Syntax {
  match syntax {
    Unit => Unit
    Bool(b) => Bool(b)
    Int(i) => Int(i)
    Double(d) => Double(d)
    Var(x) => Var(x)
    Tuple(tys) => Tuple(tys.map(fn { t => deref_term(t) }))
    Not(e) => Not(deref_term(e))
    Array(e1, e2) => Array(deref_term(e1), deref_term(e2))
    Neg(e1, ~kind) => Neg(deref_term(e1), ~kind)
    App(f, args) => App(deref_term(f), args.map(fn { t => deref_term(t) }))
    Get(e1, e2) => Get(deref_term(e1), deref_term(e2))
    If(e1, e2, e3) => If(deref_term(e1), deref_term(e2), deref_term(e3))
    Prim(e1, e2, op, ~kind) => Prim(deref_term(e1), deref_term(e2), op, ~kind)
    Eq(e1, e2) => Eq(deref_term(e1), deref_term(e2))
    LE(e1, e2) => LE(deref_term(e1), deref_term(e2))
    Let((name, t), value, other) =>
      Let((name, deref_type(t)), deref_term(value), deref_term(other))
    LetRec({ name: (f, t), args, body }, rest) =>
      LetRec(
        {
          name: (f, deref_type(t)),
          args: args.map(fn { (s, t) => (s, deref_type(t)) }),
          body: deref_term(body),
        },
        deref_term(rest),
      )
    LetTuple(vars_types, e1, e2) =>
      LetTuple(
        vars_types.map(fn { (s, t) => (s, deref_type(t)) }),
        deref_term(e1),
        deref_term(e2),
      )
    Put(name, t, value) =>
      Put(deref_term(name), deref_term(t), deref_term(value))
  }
}

pub let extenv : Map[String, @types.Type] = {
  "read_int": Fun([], Unit),
  "print_int": Fun([Int], Unit),
  "read_char": Fun([], Int),
  "print_char": Fun([Int], Unit),
  "print_newline": Fun([], Unit),
  "int_of_float": Fun([Double], Int),
  "float_of_int": Fun([Int], Double),
  "truncate": Fun([Double], Int),
  "floor": Fun([Double], Double),
  "abs_float": Fun([Double], Double),
  "sqrt": Fun([Double], Double),
  "sin": Fun([Double], Double),
  "cos": Fun([Double], Double),
  "atan": Fun([Double], Double),
}

pub fn typing(e : @types.Syntax) -> @types.Syntax!TyErr {
  // println("program: " + e.to_string())
  unify!(Unit, infer!(@immut/sorted_map.empty(), e))
  // println("type check ok")
  // println("extenv: " + extenv.to_string())
  // println("typed program: " + e.to_string())
  for ext_f, ext_t in extenv {
    extenv[ext_f] = deref_type(ext_t)
  }
  deref_term(e)
}

test "typing" {
  // #| let x:Int = 1 + 1;
  let _str =
    #| fn main {
    #|  let x = 1 + 1;
    #|  println(x)
    // #|  println("Hello, world!")
    // #|  ()
    #| };
  let test2 =
    #|  fn test(x: Int) -> Int {
    #|    x + 1 + 1.1
    #|  };
    #|  fn main {
    #|    fn f(x: Int) {
    #|      (x, x)
    #|    };
    #|    let fnx = f(1);
    #|    ()
    //#| fn main {
    // #| let sum:Int = 1 + 1;
    //  #| let foo: (Int, Int) -> Int = 1;
    //  #| let bar: (Int, Double) = (1, 2.0);
    //  #| let foo: (Int, Int) = (1, 2);
    //  #| let foo: Int = 1;
    //  #| let foo: Double = 1;
    //  #| let foo: Bool = 1;
    //  #| let foo: Unit = 1;
    //  #| let foo: Array[Int] = Array::make(x, y);
    //  //  #| let foo: (Int, Int) -> Int = fn(x, y) { x + y }
    //  #| fn bar(x: Int, y: Int) -> Int {
    //  #|   1
    //  #| };
    //  #|    let x: Int = (1 + 1) * (1 / 1);
    #| };
    #|
  let tests = [test2]
  // println(tokens)
  for test_ in tests {
    let ast = @parser.parse_from_string(test_)
    println(ast)
    let result = typing!(ast)
    println(result)
  }
}
