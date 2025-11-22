///|
pub(all) suberror TyErr String derive(ToJson)

///|
fn unify(t1 : @types.Type, t2 : @types.Type) -> Unit raise TyErr {
  // @util.logger("unify:" + t1.to_string() + " t2: " + t2.to_string())
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
        None => {
          check_occur(t1, ty)
          t.val = Some(ty)
        }
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
    (UserDefineType(name1, fields1), UserDefineType(name2, fields2)) =>
      // @util.logger("user define type unify: " + name1 + " " + name2)
      // @util.logger("fields1: " + fields1.to_string())
      // @util.logger("fields2: " + fields2.to_string())
      if name1 == name2 {
        if fields1.val.length() == 0 {
          fields1.val = fields2.val
        }
        if fields2.val.length() == 0 {
          fields2.val = fields1.val
        }
      } else {
        raise TyErr(
          "type unify error 1: " + t1.to_string() + " " + t2.to_string(),
        )
      }
    _ =>
      raise TyErr(
        "type unify error 2: t1: " +
        t1.to_string() +
        "\n\t t2: " +
        t2.to_string(),
      )
  }
}

///|
fn check_occur(t1 : @types.Type, t2 : @types.Type) -> Unit raise TyErr {
  // @util.logger("check_occur:" + t1.to_string() + " t2: " + t2.to_string())
  match (t1, t2) {
    (Var(ty1), Var(ty2)) => {
      if physical_equal(t1, t2) {
        raise TyErr(
          "occurs check error, t1" + t1.to_string() + ", t2:" + t2.to_string(),
        )
      }
      match (ty1.val, ty2.val) {
        (Some(val1), Some(val2)) => check_occur(val1, val2)
        (None, None) => ()
        _ =>
          raise TyErr(
            "Unexpected None value in type variable: " +
            t1.to_string() +
            " t2: " +
            t2.to_string(),
          )
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
        _ =>
          raise TyErr(
            "The type of array element should not be a type variable: " +
            t1.to_string() +
            " t2: " +
            t2.to_string(),
          )
      }
    }
    (Tuple(tys), Var(ty1)) | (Var(ty1), Tuple(tys)) =>
      for ty in tys {
        match ty {
          Var(t) =>
            if physical_equal(t, ty1) {
              raise TyErr(
                "The type of tuple element should not be a type variable: " +
                t.to_string(),
              )
            } else {
              match ty1.val {
                Some(val) => check_occur(val, ty)
                None =>
                  raise TyErr(
                    "The type of tuple Unexpected None value in type variable: " +
                    t.to_string(),
                  )
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
              raise TyErr(
                "The type of function should not be a type variable: " +
                t.to_string(),
              )
            }
            check_occur(val, t)
          }
          None => ()
        }
      }
      if physical_equal(ty, t1) {
        raise TyErr(
          "The type of function should not be a type variable: " +
          ty.to_string(),
        )
      } else {
        match (t1.val, ty.val) {
          (Some(val1), Some(val2)) => check_occur(val1, val2)
          _ => ()
        }
      }
    }
    (UserDefineType(name1, _), UserDefineType(name2, _)) =>
      if name1 != name2 {
        raise TyErr(
          "type unify error: " + t1.to_string() + " " + t2.to_string(),
        )
      }
    _ => ()
  }
}

///|
struct LocalCtx(@immut/sorted_map.SortedMap[String, @types.Type])

///|
pub fn infer(ctx : LocalCtx, e : @types.Syntax) -> @types.Type raise TyErr {
  // println("infer: " + e.to_string())
  // println("extenv: " + ctx.0.to_string())
  match e {
    Unit => Unit
    Bool(_) => Bool
    Int(_) => Int
    Int64(_) => Int
    Double(_) => Double
    Struct(name, _, fields, rest) => {
      let ty = @types.Type::UserDefineType(name, { val: fields })
      let newctx = ctx.0.add(name, ty)
      infer(newctx, rest)
    }
    StructConstruct(name, fields) => {
      let types = fields.map(fn(field) {
        let (name, syn) = field
        let ty = infer(ctx, syn)
        (name, ty)
      })
      UserDefineType(name, { val: types })
    }
    Enum(enum_name, _, enum_variant_list, cont) => {
      let mut newctx = ctx
      let enum_variant_list_ty = enum_variant_list.map(fn(variant) {
        let (name, fields) = variant
        (name, @types.Type::Tuple(fields))
      })
      let ty = @types.Type::UserDefineType(enum_name, {
        val: enum_variant_list_ty,
      })
      for variant in enum_variant_list_ty {
        let (name, _) = variant
        newctx = newctx.0.add(name, ty)
      }
      // @util.logger("Enum: " + enum_name + " " + ty.to_string())
      let newctx = newctx.0.add(enum_name, ty)
      // @util.logger("Enum: " + enum_name + " " + ty.to_string() + "; newctx: " + newctx.to_string())
      infer(newctx, cont)
    }
    EnumConstruct(enum_name, _arr) =>
      match ctx.0.get(enum_name) {
        Some(ty) => ty
        None =>
          raise TyErr(
            "enum not found " +
            enum_name +
            " \n" +
            "ctx: " +
            ctx.0.to_string(),
          )
      }
    FieldAccess(e, name) => {
      let t = infer(ctx, e)
      match t {
        UserDefineType(struct_name, fields) => {
          for field in fields.val {
            let (name2, ty) = field
            if name2 == name {
              return ty
            }
          }
          let struct_ty = ctx.0.get(struct_name)
          match struct_ty {
            Some(UserDefineType(_, fields)) =>
              for field in fields.val {
                let (name2, ty) = field
                if name2 == name {
                  return ty
                }
              }
            _ =>
              raise TyErr(
                "struct not found " +
                struct_name +
                " in " +
                t.to_string() +
                "\n struct_ty: " +
                struct_ty.to_string() +
                "\n name: " +
                name,
              )
          }
          raise TyErr("field not found " + name + " in " + t.to_string())
        }
        _ => raise TyErr("type unify error: " + t.to_string())
      }
    }
    Var(x) =>
      // if x == "_arr" {
      //   @util.logger("infer: Var(x) =>" + x + "\n  ctx.0.get(x): " + ctx.0.get(x).to_string())
      // }
      // println("infer var: " + x)
      match ctx.0.get(x) {
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
      }
    Tuple(tys) => Tuple(tys.map(fn(ty) { infer(ctx, ty) }))
    Not(syn) =>
      match infer(ctx, syn) {
        Bool => Bool
        _ => raise TyErr("The operand of Not is not a bool value")
      }
    Array(n, syn) =>
      // @util.logger("infer: Array: " + syn.to_string() + " \n")
      match infer(ctx, n) {
        Int => Array(infer(ctx, syn))
        _ =>
          raise TyErr(
            "The operand of Array is not a int value\n" +
            "n = " +
            n.to_string() +
            "\n" +
            "syn = " +
            syn.to_string() +
            "\n",
          )
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
            _ =>
              raise TyErr(
                "The operand of Get should have Type Array, but got: " +
                arr.to_string(),
              )
          }
        _ => raise TyErr("The index of Get should have Type Int")
      }
    If(condition, b1, b2) => {
      guard infer(ctx, condition) == Bool else {
        raise TyErr(
          "The condition of If should have Type Bool; " + condition.to_string(),
        )
      }
      let ctx_ty = get_ctx_ty(ctx, condition)
      let b1ty = infer(ctx_ty, b1)
      let b2ty = infer(ctx, b2)
      match (b1ty, b2ty) {
        (Tuple(t1), Tuple(t2)) => {
          for index = 0; index < t1.length(); index = index + 1 {
            let ty1 = t1[index]
            let ty2 = t2[index]
            match (ty1, ty2) {
              (_, Var(_)) => unify(ty1, ty2)
              (Var(_), _) => unify(ty2, ty1)
              _ => ()
            }
          }
          Tuple(t1.map(fn(ty) { ty.repr() }))
        }
        (ty1, ty2) =>
          if ty1 == ty2 {
            ty1
          } else {
            raise TyErr(
              "The branchs of If should have same type: b1 " +
              b1.to_string() +
              " b2 " +
              b2.to_string() +
              " but got: b1 ty: " +
              ty1.to_string() +
              " b2 ty:" +
              ty2.to_string(),
            )
          }
      }
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
        (t1, t2) =>
          // @util.logger("ctx: " + ctx.0.to_string())
          raise TyErr(
            "The operands of Prim should have same type: " +
            l.to_string() +
            " " +
            r.to_string() +
            "\n but got: " +
            t1.to_string() +
            " " +
            t2.to_string(),
          )
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
        (Var(t), Bool) | (Bool, Var(t)) => {
          t.val = Some(Bool)
          Bool
        }
        (Var(t), UserDefineType(name, fields))
        | (UserDefineType(name, fields), Var(t)) => {
          // @util.logger("Eq: " + t.to_string() + " " + name.to_string())
          t.val = Some(UserDefineType(name, fields))
          Bool
        }
        (UserDefineType(name1, fields1), UserDefineType(name2, fields2)) => {
          if name1 != name2 {
            raise TyErr(
              "The operands of 1: " +
              e.to_string() +
              " should have same type; name1: " +
              name1.to_string() +
              ", name2: " +
              name2.to_string() +
              ", fields1: " +
              fields1.to_string() +
              ", fields2: " +
              fields2.to_string(),
            )
          }
          Bool
        }
        (Tuple(fields1), Tuple(fields2)) => {
          if fields1.length() != fields2.length() {
            raise TyErr(
              "The operands of " +
              e.to_string() +
              " should have same type; fields1: " +
              fields1.to_string() +
              ", fields2: " +
              fields2.to_string(),
            )
          }
          Bool
        }
        _ =>
          raise TyErr(
            "The operands of " +
            e.to_string() +
            " should have same type" +
            " l: " +
            l.to_string() +
            " r: " +
            r.to_string() +
            " l infer: " +
            infer(ctx, l).to_string() +
            " r infer: " +
            infer(ctx, r).to_string(),
          )
      }
    Let((name, ty), value, s1) =>
      // @util.logger("Let: " + name + " " + ty.to_string() + " " + value.to_string())
      match ty {
        Var({ val: None }) => {
          let t = infer(ctx, value)
          unify(ty, t)
          let newctx = ctx.0.add(name, t)
          infer(newctx, s1)
        }
        Array(_) => {
          let t = infer(ctx, value)
          unify(ty, t)
          let newctx = ctx.0.add(name, t)
          infer(newctx, s1)
        }
        UserDefineType(name, _fields) => {
          let t = infer(ctx, value)
          unify(ty, t)
          let newctx = ctx.0.add(name, t)
          infer(newctx, s1)
        }
        _ => {
          let t = infer(ctx, value)
          // @util.logger("let: " + name.to_string() + " t: " + t.to_string() + " value: " + value.to_string())
          // println("T: before")
          // println("TY: " + ty.repr().to_string());
          // println("after")
          if t == ty.repr() {
            let newctx = ctx.0.add(name, t)
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
    LetRec({ name: (f, t), args: params, body }, rest) => {
      let mut env_with_f = ctx.0.add(f, t)
      // let params_ty = params.map(t => t.1.repr())
      let params_ty = params.map(t => t.1.repr())
      for p in params {
        env_with_f = env_with_f.add(p.0, p.1)
      }
      // @util.logger("env_with_f:" + env_with_f.to_json().stringify())
      let body_ty = infer(env_with_f, body)
      unify(t, Fun(params_ty, body_ty))
      infer(env_with_f, rest)
    }
    LetTuple(arr, s1, s2) => {
      let t = infer(ctx, s1)
      // @util.logger("let tuple: arr:" + arr.to_string() + "; \n\ts1: " + s1.to_string() +
      //    "; \n\t t: " + t.to_string())
      // @util.logger("let tuple: t: " + t.to_string())
      match t {
        Tuple(arr_tup) => {
          let mut newctx = ctx
          for i, value in arr {
            unify(value.1, arr_tup[i])
            // @util.logger("unify: name: " + value.0 + " with " + value.1.to_string() + " with " + arr_tup[i].to_string())
            newctx = newctx.0.add(value.0, arr_tup[i])
          }
          infer(newctx, s2)
        }
        _ => raise TyErr("Tuple expected, found {}")
      }
    }
    Put(name, n, value) => {
      match infer(ctx, n) {
        Int =>
          match infer(ctx, name) {
            Array(t) =>
              if t != infer(ctx, value) {
                raise TyErr(
                  "The operand of Put should have same type: " +
                  "\n e: " +
                  e.to_string() +
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
      Unit
    }
    ArrayExpr(es) => {
      let ty = infer(ctx, es[0])
      let tys = es.map(e => infer(ctx, e))
      for t in tys {
        unify(t, ty)
      }
      Array(tys[0])
    }
    While(cond, body) => {
      let cond_ty = infer(ctx, cond)
      unify(cond_ty, Bool)
      ignore(infer(ctx, body))
      Unit
    }
    Return(r) =>
      match r {
        Some(e) => {
          let e_ty = infer(ctx, e)
          e_ty
        }
        None => Unit
      }
    Assign(name, value) => {
      let name_ty = infer(ctx, name)
      let value_ty = infer(ctx, value)
      unify(name_ty, value_ty)
      Unit
    }
    Match(_, arms) => {
      let mut body_ty = @types.Type::Unit
      let (pat, body) = arms[0]
      // @util.logger("match: pat: " + pat.to_string())
      // @util.logger("match: ctx: " + ctx.0.to_string())
      let mut ctx = ctx
      match pat {
        PEnumVariant(name, patts) => {
          let index = match ctx.0.get(name) {
            Some(UserDefineType(_, fields)) =>
              fields.val.search_by(fn(input) { input.0 == name })
            _ => @util.die("match: not found var: " + name.to_string())
          }
          let arr = match ctx.0.get(name) {
            Some(UserDefineType(_, fields)) =>
              fields.val.get(index.unwrap()).unwrap().1
            _ => @util.die("match: not found var: " + name.to_string())
          }
          let arr = match arr {
            Tuple(arr) => arr
            _ =>
              @util.die(
                "match: not found var: " +
                name.to_string() +
                " in " +
                arr.to_string(),
              )
          }
          let _ = patts.mapi(fn(i, pat) {
            match pat {
              PVar(name) => ctx = ctx.0.add(name, arr[i])
              _ => @util.die("not support match pattern 6: " + pat.to_string())
            }
          })

        }
        PBool(_) => ()
        _ => @util.die("not support match pattern 7: " + pat.to_string())
      }
      // @util.logger("match: pat_ty: " + ctx.0.to_string())
      body_ty = infer(ctx, body)
      // @util.logger("match: body_ty: " + body_ty.to_string())
      body_ty
    }
    // _ => @util.die("infer: unknown syntax: " + e.to_string())
    ExternalArray(_) => Array(@types.Type::Unit)
    ArrayData(_) => Array(@types.Type::Unit)
  }
}

///|
fn get_ctx_ty(
  ctx : LocalCtx,
  condition : @types.Syntax,
) -> LocalCtx raise TyErr {
  match condition {
    Eq(e1, e2) => {
      let e1t = infer(ctx, e1)
      let e2t = infer(ctx, e2)
      match (e1t, e2t) {
        (UserDefineType(_), UserDefineType(_, fields)) => {
          // @util.logger("unify e2t: " + e2t.to_string())
          // @util.logger("unify e2: " + e2.to_string())
          let (e2_name, field_names) = match e2 {
            EnumConstruct(name, fields) =>
              (
                name,
                fields.map(fn(field) {
                  match field {
                    Var(x) => x
                    _ =>
                      @util.die(
                        "EnumConstruct field not Var: " + e2.to_string(),
                      )
                  }
                }),
              )
            _ => @util.die("unify e2: " + e2.to_string())
          }
          let e2_ty_index = fields.val
            .search_by(fn(field) { field.0 == e2_name })
            .unwrap()
          let e2_ty = fields.val[e2_ty_index].1
          match e2_ty {
            Tuple(tys) => {
              let mut newctx = ctx
              for i, t in tys {
                unify(t, tys[i])
                newctx = newctx.0.add(field_names[i], t)
              }
              newctx
            }
            _ => ctx
          }
        }
        _ => ctx
      }
    }
    _ => ctx
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
    ExternalArray(name) => ExternalArray(name)
    ArrayData(label, name) => ArrayData(label, name)
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
    Struct(name, generic, es, rest) => Struct(name, generic, es, rest)
    StructConstruct(name, arr) => StructConstruct(name, arr)
    Enum(name, generic, e, rest) => Enum(name, generic, e, rest)
    Int64(i) => Int64(i)
    Assign(name, value) => Assign(deref_term(name), deref_term(value))
    EnumConstruct(name, e) => EnumConstruct(name, e)
    Match(expr, arms) =>
      Match(
        deref_term(expr),
        arms.map(fn(input) { (input.0, deref_term(input.1)) }),
      )
    // _ => @util.die("deref_term: unknown syntax: " + syntax.to_string())
  }
}

///|
pub let extenv : Map[String, @types.Type] = {
  "read_int": Fun([], Int),
  "print_int": Fun([Int], Unit),
  "print_float": Fun([Double], Unit),
  "read_char": Fun([], Int),
  "print_char": Fun([Int], Unit),
  "print_newline": Fun([], Unit),
  "print_endline": Fun([], Unit),
  "int_of_float": Fun([Double], Int),
  "float_of_int": Fun([Int], Double),
  "create_array": Fun([Int, Int], @types.Type::Array(Int)),
  "create_float_array": Fun([Int, Double], @types.Type::Array(Double)),
  "create_ptr_array": Fun([Int, Ptr], @types.Type::Array(Ptr)),
  "truncate": Fun([Double], Int),
  "abs_float": Fun([Double], Double),
  "sqrt": Fun([Double], Double),
  "sin": Fun([Double], Double),
  "cos": Fun([Double], Double),
  "atan": Fun([Double], Double),
}

///|
pub fn typing(e : @types.Syntax) -> @types.Syntax raise TyErr {
  // @util.logger("before typing: " + e.to_json().stringify())
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
  m : @immut/hashmap.HashMap[String, @types.Type],
  e : @types.Syntax,
) -> @types.Type raise TyErr {
  let mut sort_map : LocalCtx = @immut/sorted_map.new()
  m.each((k, v) => sort_map = sort_map.0.add(k, v))
  // @util.logger("get_type: " + e.to_string())
  // @util.logger("sort_map: " + sort_map.0.to_string())
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
    "contest-2025-data/test_cases/mbt/enum1.mbt",
  )
  let parse = @parser.parse_from_string(_test2)
  println("parse: " + parse.to_json().stringify() + "\n")
  try {
    let typed = typing(parse)
    println("typed: " + typed.to_json().stringify() + "\n")
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
