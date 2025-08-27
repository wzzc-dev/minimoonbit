///|
pub(all) suberror TyErr String derive(ToJson(style="flat"))

///|
fn unify(t1 : @types.Type, t2 : @types.Type) -> Unit raise TyErr {
  // println("unify:" + t1.to_string() + " t2: " + t2.to_string())
  let t1 = t1.repr()
  let t2 = t2.repr()
  if physical_equal(t1, t2) {
    return
  }
  match (t1, t2) {
    (Int, Int)
    | (Bool, Bool)
    | (Double, Double)
    | (Unit, Unit)
    | (Int, Bool)
    | (Bool, Int) => ()
    (Var(t), ty) | (ty, Var(t)) =>
      match t.val {
        None => t.val = Some(ty)
        _ => {
          println("unify: t.val: " + t.val.to_string())
          ()
        }
      }
    // handle the array type 
    (Array(t1), Array(t2)) => unify(t1, t2)
    // handle the tuple
    (Tuple(tys1), Tuple(tys2)) =>
      for i, ty in tys1 {
        unify(ty, tys2[i])
      }
    // handle the function
    (Fun(tys1, ty1), Fun(tys2, ty2)) => {
      for i, ty in tys1 {
        unify(ty, tys2[i])
      }
      unify(ty1, ty2)
    }
    _ =>
      raise TyErr("type unify error: " + t1.to_string() + " " + t2.to_string())
  }
}

///|
fn check_occur(t1 : @types.Type, t2 : @types.Type) -> Unit raise TyErr {
  // println("check_occur:" + t1.to_string() + " t2: " + t2.to_string())
  match (t1, t2) {
    (Var(ty1), Var(ty2)) => {
      if physical_equal(t1, t2) {
        raise TyErr(
          "occurs check error, t1" + t1.to_string() + ", t2:" + t2.to_string(),
        )
      }
      match (ty1.val, ty2.val) {
        (Some(val1), Some(val2)) => check_occur(val1, val2)
        _ => raise TyErr("Unexpected None value in type variable")
      }
    }
    (Var(ty1), Array(Var(ty))) | (Array(Var(ty)), Var(ty1)) => {
      if physical_equal(t1, t2) {
        raise TyErr(
          "occurs check error, t1" + t1.to_string() + ", t2:" + t2.to_string(),
        )
      }
      match (ty1.val, ty.val) {
        (Some(val1), Some(val2)) => check_occur(val1, val2)
        _ => raise TyErr("Unexpected None value in type variable")
      }
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
              match ty1.val {
                Some(val) => check_occur(val, ty)
                None => raise TyErr("Unexpected None value in type variable")
              }
            }
          _ => ()
        }
      }
    (Fun(tys, Var(ty)), Var(t1)) | (Var(t1), Fun(tys, Var(ty))) => {
      for t in tys {
        match t1.val {
          Some(val) => {
            if physical_equal(t, val) {
              raise TyErr("The type of function should not be a type variable")
            }
            check_occur(val, t)
          }
          None => raise TyErr("Unexpected None value in type variable")
        }
      }
      if physical_equal(ty, t1) {
        raise TyErr("The type of function should not be a type variable")
      } else {
        match (t1.val, ty.val) {
          (Some(val1), Some(val2)) => check_occur(val1, val2)
          _ => raise TyErr("Unexpected None value in type variable")
        }
      }
    }
    _ => ()
  }
}

///|
struct LocalCtx(@immut/sorted_map.T[String, @types.Type])

///|
pub fn infer(ctx : LocalCtx, e : @types.Syntax) -> @types.Type raise TyErr {
  // println("infer: " + e.to_string())
  match e {
    Unit => Unit
    Bool(_) => Bool
    Int(_) => Int
    Int64(_) => Int
    Double(_) => Double
    // eg.
    Var(x) =>{
      // if x == "_arr" {
      //   @util.logger("infer: Var(x) =>" + x + "\n  ctx.inner().get(x): " + ctx.inner().get(x).to_string())
      // }
      // println("infer var: " + x)
      match ctx.inner().get(x) {
        Some(t) =>
          // println("infer: " + x + " is " + t.to_string())
          t.repr()
        None =>
          match extenv.get(x) {
            Some(t) => t.repr()
            None => {
              let t = @types.Type::new_tvar()
              extenv[x] = t
              // println("infer: " + x + " is " + t.to_string())
              t
            }
          }
      }}
    Tuple(tys) => {
      let result = []
      for ty in tys {
        result.push(infer(ctx, ty))
      }
      Tuple(result)
    }
    Not(syn) =>
      match infer(ctx, syn) {
        Bool => Bool
        _ => raise TyErr("The operand of Not is not a bool value")
      }
    Array(n, syn) => {
      // @util.logger("infer: Array: " + syn.to_string() + " \n")
      match infer(ctx, n) {
        Int => Array(infer(ctx, syn))
        _ => raise TyErr("The operand of Array is not a int value\n" + 
          "n = " + n.to_string() + "\n" +
          "syn = " + syn.to_string() + "\n"
        )
      }
    }
      
    Neg(syn, ..) as neg =>
      match infer(ctx, syn) {
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
      let f_ty = infer(ctx, f)
      let args_ty = []
      for a in args {
        // println("a: " + a.to_string())
        args_ty.push(infer(ctx, a))
      }
      // println("f_ty: " + f_ty.to_string())
      // println("args_ty: " + args_ty.to_string())
      // println("ret_ty: " + ret_ty.to_string())
      unify(f_ty, Fun(args_ty, ret_ty))
      // println("ret_ty: {}" + ret_ty.to_string())
      ret_ty.repr()
    }
    Get(arr, index) =>
      match infer(ctx, index) {
        Int =>
          match infer(ctx, arr) {
            Array(t) => t
            _ => raise TyErr("The operand of Get should have Type Array, but got: " + arr.to_string())
          }
        _ => raise TyErr("The index of Get should have Type Int")
      }
    If(condition, b1, b2) =>
      match infer(ctx, condition) {
        Bool =>
          if infer(ctx, b1) == infer(ctx, b2) {
            return infer(ctx, b1)
          } else {
            let b1_ty = infer(ctx, b1)
            let b2_ty = infer(ctx, b2)
            raise TyErr(
              "The branchs of If should have same type: b1 " +
              b1.to_string() +
              " b2 " +
              b2.to_string() +
              " but got: b1 ty: " +
              b1_ty.to_string() +
              " b2 ty:" +
              b2_ty.to_string(),
            )
          }
        _ => raise TyErr("The condition of If should have Type Bool")
      }
    Prim(l, r, _, ..) as prim =>
      match (infer(ctx, l), infer(ctx, r)) {
        (Int, Int) => {
          prim.kind = Some(Int)
          Int
        }
        (Double, Double) => {
          prim.kind = Some(Double)
          Double
        }
        (Var(t), Int) | (Int, Var(t)) => {
          t.val = Some(Int)
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
    And(l, r)
    | Or(l, r)
    | Eq(l, r)
    | LE(l, r)
    | LT(l, r)
    | GT(l, r)
    | NE(l, r)
    | GE(l, r) =>
      match (infer(ctx, l), infer(ctx, r)) {
        (Int, Int) | (Double, Double) => Bool
        (Var(t), Int) | (Int, Var(t)) => {
          t.val = Some(Int)
          Bool
        }
        (Var(t), Double) | (Double, Var(t)) => {
          t.val = Some(Double)
          Bool
        }
        (Bool, Bool) => Bool
        _ =>
          raise TyErr(
            "The operands of " + e.to_string() + " should have same type",
          )
      }
    Let((name, ty), value, s1) => {
      // @util.logger("Let: " + name + " " + ty.to_string() + " " + value.to_string())
      match ty {
        Var({ val: None }) => {
          let t = infer(ctx, value)
          unify(ty, t)
          let newctx = ctx.inner().add(name, t)
          infer(newctx, s1)
        }
        Array(_) => {
          let t = infer(ctx, value)
          unify(ty, t)
          let newctx = ctx.inner().add(name, t)
          infer(newctx, s1)
        }
        _ => {
          let t = infer(ctx, value)
          // @util.logger("let: " + name.to_string() + " t: " + t.to_string() + " value: " + value.to_string())
          // println("T: before")
          // println("TY: " + ty.repr().to_string());
          // println("after")
          if t == ty.repr() {
            let newctx = ctx.inner().add(name, t)
            infer(newctx, s1)
          } else {
            raise TyErr(
              "The value and expression types in Let are different" +
              " in name: " +
              name.to_string() +
              "\n\tvalue: " +
              value.to_string() +
              "\n\tt: " +
              t.to_string() +
              "\n\tty: " +
              ty.to_string(),
            )
          }
        }
      }
    }
      
    LetRec({ name: (f, t), args: params, body }, rest) => {
      let env_with_f = ctx.inner().add(f, t)
      let params_ty = params.map(t => t.1.repr())
      let mut env_with_params = env_with_f
      for p in params {
        env_with_params = env_with_params.add(p.0, p.1)
      }
      let body_ty = infer(env_with_params, body)
      unify(t, Fun(params_ty, body_ty))
      infer(env_with_f, rest)
    }
    LetTuple(arr, s1, s2) =>
      match arr[0].1 {
        Var({ val: None }) =>
          match s1 {
            Tuple(arr_tup) => {
              let mut newctx = ctx
              for i, value in arr {
                let t = infer(newctx, arr_tup[i])
                unify(value.1, t)
                newctx = newctx.inner().add(value.0, t)
              }
              infer(newctx, s2)
            }
            Var(_) => {
              let t = infer(ctx, s1)
              match t {
                Tuple(arr_tup) => {
                  for i, value in arr {
                    // println("unifying " + value.1.to_string() + " with " + arr_tup[i].to_string())
                    unify(value.1, arr_tup[i])
                  }
                  infer(ctx, s2)
                }
                _ => raise TyErr("Tuple expected, found {}")
              }
            }
            _ =>
              raise TyErr(
                "The first operand of LetTuple should be tuple, but got: " +
                s1.to_string() +
                " with type: " +
                infer(ctx, s1).to_string(),
              )
          }
        _ =>
          match s1 {
            Tuple(arr_tup) => {
              let mut newctx = ctx
              for i, value in arr {
                let t = infer(ctx, arr_tup[i])
                if value.1 == t {
                  newctx = ctx.inner().add(value.0, t)
                } else {
                  raise TyErr("The types of tuple and array are different")
                }
              }
              infer(newctx, s2)
            }
            _ => raise TyErr("The first operand of LetTuple should be tuple")
          }
      }
    Put(name, n, value) =>
      match infer(ctx, n) {
        Int =>
          match infer(ctx, name) {
            Array(t) =>
              if t == infer(ctx, value) {
                Unit
              } else {
                raise TyErr(
                  "The operand of Put should have same type: " +
                  "\n e: " + e.to_string() +
                  "\n (name, n, value): " +
                  (name, n, value).to_string() +
                  "\n infer(ctx, name): " +
                  infer(ctx, name).to_string() +
                  "\n infer(ctx, n): " +
                  infer(ctx, n).to_string() +
                  "\n infer(ctx, value): " +
                  infer(ctx, value).to_string() +
                  "\n t: " +
                  t.to_string(),
                )
              }
            _ =>
              raise TyErr(
                "The type of name should be Array, but got: " +
                infer(ctx, name).to_string(),
              )
          }
        _ =>
          raise TyErr(
            "The operand of Put Index should be Int" +
            "\n n: " +
            n.to_string() +
            "\n infer!(ctx, n): " +
            infer(ctx, n).to_string(),
          )
      }
    ArrayExpr(es) => {
      let ty = infer(ctx, es[0])
      let tys = es.map(e => infer(ctx, e))

      for t in tys {
        @util.logger("unify: " + t.to_string() + " with " + ty.to_string())
        unify(t, ty)
      }
      Array(tys[0])
    }
    Struct(_, _, _) => Unit
    StructConstruct(_, _) => Unit
    FieldAccess(e, _) => infer(ctx, e)
    Enum(_, _) => Unit
    While(cond, body) => {
      let cond_ty = infer(ctx, cond)
      unify(cond_ty, Bool)
      ignore(infer(ctx, body))
      Unit
    }
    Return(r) => {
      match r {
        Some(e) => {
          let e_ty = infer(ctx, e)
          e_ty
        }
        None => Unit
      }
    }
    Assign(name, value) => {
      let name_ty = infer(ctx, name)
      let value_ty = infer(ctx, value)
      unify(name_ty, value_ty)
      Unit
    }
    // _ => @util.die("infer: unknown syntax: " + e.to_string())

  }
}

///|
fn deref_type(t : @types.Type) -> @types.Type {
  match t {
    Fun(params, result) =>
      Fun(params.map(t => deref_type(t)), deref_type(result))
    Tuple(types) => Tuple(types.map(t => deref_type(t)))
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

///|
fn deref_term(syntax : @types.Syntax) -> @types.Syntax {
  match syntax {
    FieldAccess(e, name) => FieldAccess(deref_term(e), name)
    Unit => Unit
    Bool(b) => Bool(b)
    Int(i) => Int(i)
    Double(d) => Double(d)
    Var(x) => Var(x)
    Tuple(tys) => Tuple(tys.map(t => deref_term(t)))
    Not(e) => Not(deref_term(e))
    Array(e1, e2) => Array(deref_term(e1), deref_term(e2))
    Neg(e1, kind~) => Neg(deref_term(e1), kind~)
    App(f, args) => App(deref_term(f), args.map(t => deref_term(t)))
    Get(e1, e2) => Get(deref_term(e1), deref_term(e2))
    If(e1, e2, e3) => If(deref_term(e1), deref_term(e2), deref_term(e3))
    Prim(e1, e2, op, kind~) => Prim(deref_term(e1), deref_term(e2), op, kind~)
    Eq(e1, e2) => Eq(deref_term(e1), deref_term(e2))
    LE(e1, e2) => LE(deref_term(e1), deref_term(e2))
    LT(e1, e2) => LT(deref_term(e1), deref_term(e2))
    GT(e1, e2) => GT(deref_term(e1), deref_term(e2))
    NE(e1, e2) => NE(deref_term(e1), deref_term(e2))
    GE(e1, e2) => GE(deref_term(e1), deref_term(e2))
    And(e1, e2) => And(deref_term(e1), deref_term(e2))
    Or(e1, e2) => Or(deref_term(e1), deref_term(e2))
    Let((name, t), value, other) =>
      Let((name, deref_type(t)), deref_term(value), deref_term(other))
    LetRec({ name: (f, t), args, body }, rest) =>
      LetRec(
        {
          name: (f, deref_type(t)),
          args: args.map(s_t => (s_t.0, deref_type(s_t.1))),
          body: deref_term(body),
        },
        deref_term(rest),
      )
    LetTuple(vars_types, e1, e2) =>
      LetTuple(
        vars_types.map(s_t => (s_t.0, deref_type(s_t.1))),
        deref_term(e1),
        deref_term(e2),
      )
    Put(name, t, value) =>
      Put(deref_term(name), deref_term(t), deref_term(value))
    While(e1, e2) => While(deref_term(e1), deref_term(e2))
    Return(e) =>
      match e {
        None => Unit
        Some(e) => deref_term(e)
      }
    ArrayExpr(es) => ArrayExpr(es.map(e => deref_term(e)))
    Struct(name, generic, es) => Struct(name, generic, es)
    StructConstruct(name, arr) => StructConstruct(name, arr) 
    Enum(name, e) => Enum(name, e)
    Int64(i) => Int64(i)
    Assign(name, value) => Assign(deref_term(name), deref_term(value))
    // _ => @util.die("deref_term: unknown syntax: " + syntax.to_string())
  }
}

///|
pub let extenv : Map[String, @types.Type] = {
  "read_int": Fun([], Unit),
  "print_int": Fun([Int], Unit),
  "read_char": Fun([], Int),
  "print_char": Fun([Int], Unit),
  "print_newline": Fun([], Unit),
  "print_endline": Fun([], Unit),
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

///|
pub fn typing(e : @types.Syntax) -> @types.Syntax raise TyErr {
  unify(Unit, infer(@immut/sorted_map.new(), e))
  // println("type check ok")
  // println("extenv: " + extenv.to_string())
  // println("typed program: " + e.to_string())
  for ext_f, ext_t in extenv {
    extenv[ext_f] = deref_type(ext_t)
  }
  deref_term(e)
}

///|
pub fn get_type(
  m : @immut/hashmap.T[String, @types.Type],
  e : @types.Syntax,
) -> @types.Type raise TyErr {
  let mut sort_map : LocalCtx = @immut/sorted_map.new()
  m.each((k, v) => sort_map = sort_map.inner().add(k, v))
  // @util.logger("get_type: " + e.to_string())
  // @util.logger("m: " + m.to_string())
  infer(sort_map, e)
}

///|
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
    #|  fn main {
    #|    fn f(x) {
    #|      x + 1
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
    try {
      let result = typing(ast)
      println(result)
    } catch {
      TyErr(s) => {
        println("typing error")
        println(s)
      }
    }
    // println(result.unwrap())
  }
}

///|
test {
  // let x = Array::make(10, 0);
  let _test2 = @fs.read_file_to_string(
    "contest-2025-data/test_cases/mbt/mbts",
  )
  let parse = @parser.parse_from_string(_test2)
  
  println("parse: " + parse.to_string() + "\n")
  try {
    let typed = typing(parse)
    println("typed: " + typed.to_string())
  } catch {
    TyErr(s) => {
      println("typing error")
      @util.logger(s)
    }
  }
}

///|
test {
  let list = @fs.read_dir("contest-2025-data/test_cases/mbt")
  println(list)
  for file in list {
    println(file)
    guard file.has_suffix(".mbt") else {
      println("not mbt file")
      continue
    }
    // guard file.starts_with("matmul-flat") else {
    //   println("matmul-flat mbt file")
    //   continue
    // }
    let _test2 = (try? @fs.read_file_to_string(
      "contest-2025-data/test_cases/mbt/" + file,
    )).unwrap()
    let parse = @parser.parse_from_string(_test2)
    try {
      let typed = typing(parse)
      println(typed)
    } catch {
      TyErr(s) => {
        println("typing error")
        println(s)
      }
    }
  }
}
