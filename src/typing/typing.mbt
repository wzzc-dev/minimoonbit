type! TyErr String

fn unify(t1 : @types.Type, t2 : @types.Type) -> Unit!TyErr {
  println("unify:" + t1.to_string() + " t2: " + t2.to_string())
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
          println("match (t1, t2) {  t1: " + t1.to_string() + " ty: " + ty.to_string())
          check_occur!(t1, ty)
          t.val = Some(ty)
        }
        _ => ()
      }
    (Array(t1), Array(t2)) => unify!(t1, t2)
    (Tuple(tys1), Tuple(tys2)) =>
      for i, ty in tys1 {
        unify!(ty, tys2[i])
      }
    (Fun(tys1, ty1), Fun(tys2, ty2)) => {
      for i, ty in tys1 {
        unify!(ty, tys2[i])
      }
      unify!(ty1, ty2)
    }
    //  .. // handle the function, tuple, and array type  
    _ => raise TyErr("type unify error: " + t1.to_string() + " " + t2.to_string())
  }
}

fn check_occur(t1 : @types.Type, t2 : @types.Type) -> Unit!TyErr {
  match (t1, t2) {
    (Var(ty1), Var(ty2)) => {
      if(physical_equal(t1, t2)) {
        raise TyErr("occurs check error")
      }
      check_occur!(ty1.val.unwrap(), ty2.val.unwrap())
    }
    (Var(ty1), Array(Var(ty))) | (Array(Var(ty)), Var(ty1)) =>{
      if (physical_equal(t1, t2)) {
        raise TyErr("occurs check error")
      }
      check_occur!(ty1.val.unwrap(), ty.val.unwrap())}
    (Tuple(tys), Var(ty1)) | (Var(ty1), Tuple(tys)) =>
      for ty in tys {
        if (physical_equal(t1, ty)) {
          raise TyErr("occurs check error")
        }
        check_occur!(ty1.val.unwrap(), ty)
      }
    (Fun(tys, Var(ty)), Var(t1)) | (Var(t1), Fun(tys, Var(ty))) => {
      for t in tys {
        if (physical_equal(t, t1.val.unwrap())) {
          raise TyErr("occurs check error")
        }
        check_occur!(Var(t1), t)
      }
      check_occur!(t1.val.unwrap(), ty.val.unwrap())
    }
    _ => ()
  }
}

type LocalCtx @immut/sorted_map.T[String, @types.Type]

fn infer(ctx : LocalCtx, e : @types.Syntax) -> @types.Type!TyErr {
  println("infer:" + e.to_string())
  match e {
    Unit => Unit
    Bool(_) => Bool
    Int(_) => Int
    Double(_) => Double
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
    Not(e) =>
      match infer!(ctx, e) {
        Bool => Bool
        _ => raise TyErr("not type error")
      }
    Array(e1, e2) => {
      let t1 = infer!(ctx, e1)
      if t1 != Int {
        raise TyErr("array type error")
      }
      Array(infer!(ctx, e2))
    }
    Neg(e1, ..) as neg => {
      let r = infer!(ctx, e1)
      match r {
        Int => {
          neg.kind = Some(@types.Kind::Int)
          Int
        }
        Double => {
          neg.kind = Some(@types.Kind::Double)
          Double
        }
        _ => raise TyErr("neg type error")
      }
    }
    App(f, args) => {
      let ret_ty = @types.Type::new_tvar()
      let f_ty = infer!(ctx, f)
      let args_ty = []
      for a in args {
        args_ty.push(infer!(ctx, a))
      }
      unify!(f_ty, Fun(args_ty, ret_ty))
      ret_ty
    }
    Get(e1, e2) => {
      let t2 = infer!(ctx, e2)
      if t2 != Array(Int) {
        raise TyErr("get type error")
      }
      let t1 = infer!(ctx, e1)
      unify!(t1, Array(t2))
      t1
    }
    If(e1, e2, e3) => {
      let t1 = infer!(ctx, e1)
      if t1 != Bool {
        raise TyErr("if type error")
      }
      let t2 = infer!(ctx, e2)
      let t3 = infer!(ctx, e3)
      if t2 != t3 {
        raise TyErr("if type error")
      }
      t2
    }
    Prim(e1, e2, _, ..) as prim => {
      let t1 = infer!(ctx, e1)
      let t2 = infer!(ctx, e2)
      match (t1, t2) {
        (Int, Int) => {
          prim.kind = Some(@types.Kind::Int)
          Int
        }
        (Double, Double) => {
          prim.kind = Some(@types.Kind::Double)
          Double
        }
        (Var(t1), Var(t2)) =>
          match (t1.val.unwrap(), t2.val.unwrap()) {
            (Int, Int) => Int
            (Double, Double) => Double
            _ => raise TyErr("prim type error")
          }
        _ => raise TyErr("prim type error")
      }
    }
    Eq(e1, e2) => {
      let t1 = infer!(ctx, e1)
      let t2 = infer!(ctx, e2)
      match (t1, t2) {
        (Int, Int) | (Double, Double) => Bool
        (Var(t1), Int) | (Int, Var(t1)) => {
          t1.val = Some(Int)
          Bool
        }
        (Var(t1), Double) | (Double, Var(t1)) => {
          t1.val = Some(Double)
          Bool
        }
        (Var(t1), Var(t2)) =>
          match (t1.val.unwrap(), t2.val.unwrap()) {
            (Int, Int) | (Double, Double) => Bool
            _ => raise TyErr("eq type error")
          }
        _ => raise TyErr("eq type error")
      }
    }
    LE(e1, e2) => {
      let t1 = infer!(ctx, e1)
      let t2 = infer!(ctx, e2)
      match (t1, t2) {
        (Int, Int) | (Double, Double) => Bool
        (Var(t1), Int) | (Int, Var(t1)) => {
          t1.val = Some(Int)
          Bool
        }
        (Var(t1), Double) | (Double, Var(t1)) => {
          t1.val = Some(Int)
          Bool
        }
        (Var(t1), Var(t2)) =>
          match (t1.val.unwrap(), t2.val.unwrap()) {
            (Int, Int) | (Double, Double) => Bool
            _ => raise TyErr("le type error")
          }
        _ => raise TyErr("le type error")
      }
    }
    Let((name, ty), e1, e2) =>
      match ty {
        Var({ val: None }) => {
          let t = infer!(ctx, e1)
          unify!(ty, t)
          let ctx_with_name = ctx._.insert(name, t)
          infer!(ctx_with_name, e1)
        }
        _ => {
          let t = infer!(ctx, e1)
          if t == ty {
            let newctx = ctx._.insert(name, t)
            infer!(newctx, e2)
          } else {
            raise TyErr("let type error")
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
    LetTuple(vars_types, e1, e2) => {
      let tys = vars_types.map(fn { (_, t) => deref_type(t) })
      match e1 {
        Tuple(tys1) => {
          if tys.length() != tys1.length() {
            raise TyErr("let tuple type error")
          }
          let mut new_ctx = ctx
          for i, ty1 in tys {
            let t = infer!(ctx, tys1[i])
            unify!(ty1, t)
            new_ctx = ctx._.insert(vars_types[i].0, ty1)
          }
          infer!(new_ctx, e2)
        }
        _ => raise TyErr("let tuple type error")
      }
    }
    Put(name, _, value) =>
      match name {
        Var(_) => infer!(ctx, value)
        _ => raise TyErr("put type error")
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

pub fn typing(e : @types.Syntax) -> @types.Syntax {
  // println("program: " + e.to_string())
  try {
    unify!(Unit, infer!(@immut/sorted_map.empty(), e))
    println("type check ok")
    // println("extenv: " + extenv.to_string())
    // println("typed program: " + e.to_string())
    for ext_f, ext_t in extenv {
      extenv[ext_f] = deref_type(ext_t)
    }
    deref_term(e)
  } catch {
    TyErr(s) => {
      println("type error: " + s)
      return e
    }
  }
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
    #| fn main {
    #|    fn f(x) -> (Int, Int) {
    #|      (x, x)
    #|    };
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
  // println(tokens)
  let ast = @parser.parse_from_string(test2)
  println(ast)
  println(typing(ast))
}
