///|
pub typealias @immut/hashmap.HashMap[String, Type] as LocalEnv

///|
pub struct KnfEnv {
  mut counter : Int
  mut externals : @immut/hashmap.HashMap[String, Type]
}

///|
pub fn KnfEnv::new(externals : @immut/hashmap.HashMap[String, Type]) -> KnfEnv {
  { counter: 1, externals }
}

///|
pub fn KnfEnv::init_counter_from_existing(
  self : KnfEnv,
  existing : Knf,
) -> Unit {
  self.counter = knf_max_counter(existing) + 1
}

///|
fn KnfEnv::new_temp(self : KnfEnv) -> Name {
  let temp = Name::slot_only(self.counter)
  self.counter += 1
  temp
}

///|
fn KnfEnv::new_name(self : KnfEnv, name : String) -> Name {
  let temp = Name::name_and_slot(name, self.counter)
  self.counter += 1
  temp
}

///|
pub fn KnfEnv::get_knf(
  self : KnfEnv,
  syn : @types.Syntax,
) -> (Name, Type, Knf) raise KnfErr {
  // println("externals: " + self.externals.to_string())
  // println("syn: " + syn.to_string())
  let ty = KnfEnv::get_type(self.externals, syn) catch {
    KnfErr(s) => raise KnfErr("KNF get_knf error: " + s)
  }
  match syn {
    Var(name) => {
      let name = (try? @types.Name::from_string(name)).unwrap()
      (name, ty, Var(name))
    }
    _ => {
      let name = self.new_temp()
      (name, ty, KnfEnv::to_knf(self, syn))
    }
  }
}

///|
fn KnfEnv::get_type(
  env : LocalEnv,
  syn : @types.Syntax,
) -> @types.Type raise KnfErr {
  @typing.get_type(env, syn) catch {
    @typing.TyErr(s) =>
      raise KnfErr(
        "KNF get_type TyErr error: " +
        s +
        "\n" +
        "syn: " +
        syn.to_string() +
        "\n" +
        "env: " +
        env.to_string(),
      )
  }
}

///|
pub fn KnfEnv::to_knf(self : KnfEnv, s : @types.Syntax) -> Knf raise KnfErr { // !Failure
  match s {
    Unit => Unit
    Int(i) => Int(i)
    Int64(i) => Int64(i)
    Double(d) => Double(d)
    Var(name) =>
      // @util.logger("var: " + name)
      Var((try? @types.Name::from_string(name)).unwrap())
    Bool(b) => if b { Int(1) } else { Int(0) }
    Not(syn) => KnfEnv::to_knf(self, If(syn, Int(0), Int(1)))
    If(syn1, syn2, syn3) =>
      // println("if: " + syn1.to_string())
      match syn1 {
        Eq(lhs, rhs) => {
          let (l_name, l_ty, lknf) = KnfEnv::get_knf(self, lhs)
          match l_ty {
            UserDefineType(_, fields) =>
              for field in fields.val {
                self.externals = self.externals.add(field.0, l_ty)
              }
            _ => ()
          }
          let (r_name, r_ty, rknf) = KnfEnv::get_knf(self, rhs)
          match lhs {
            Var(_) =>
              match rhs {
                Var(_) =>
                  IfEq(
                    l_name,
                    r_name,
                    KnfEnv::to_knf(self, syn2),
                    KnfEnv::to_knf(self, syn3),
                  )
                _ =>
                  Let(
                    (r_name, r_ty),
                    rknf,
                    IfEq(
                      l_name,
                      r_name,
                      KnfEnv::to_knf(self, syn2),
                      KnfEnv::to_knf(self, syn3),
                    ),
                  )
              }
            _ =>
              match rhs {
                Var(_) =>
                  Let(
                    (l_name, l_ty),
                    lknf,
                    IfEq(
                      l_name,
                      r_name,
                      KnfEnv::to_knf(self, syn2),
                      KnfEnv::to_knf(self, syn3),
                    ),
                  )
                _ =>
                  Let(
                    (l_name, l_ty),
                    lknf,
                    Let(
                      (r_name, r_ty),
                      rknf,
                      IfEq(
                        l_name,
                        r_name,
                        KnfEnv::to_knf(self, syn2),
                        KnfEnv::to_knf(self, syn3),
                      ),
                    ),
                  )
              }
          }
        }
        LE(lhs, rhs) => {
          let (l_name, l_ty, lknf) = KnfEnv::get_knf(self, lhs)
          let (r_name, r_ty, rknf) = KnfEnv::get_knf(self, rhs)
          // println("LE: " + (l_name, l_ty, lknf).to_string())
          // println("LE: " + (r_name, r_ty, rknf).to_string())
          match lhs {
            Var(_) =>
              match rhs {
                Var(_) =>
                  IfLe(
                    l_name,
                    r_name,
                    KnfEnv::to_knf(self, syn2),
                    KnfEnv::to_knf(self, syn3),
                  )
                _ =>
                  // println("LE: rhs is  a variable" + r_name.to_string())
                  Let(
                    (r_name, r_ty),
                    rknf,
                    IfLe(
                      l_name,
                      r_name,
                      KnfEnv::to_knf(self, syn2),
                      KnfEnv::to_knf(self, syn3),
                    ),
                  )
              }
            _ =>
              match rhs {
                Var(_) =>
                  Let(
                    (l_name, l_ty),
                    lknf,
                    IfLe(
                      l_name,
                      r_name,
                      KnfEnv::to_knf(self, syn2),
                      KnfEnv::to_knf(self, syn3),
                    ),
                  )
                _ =>
                  Let(
                    (l_name, l_ty),
                    lknf,
                    Let(
                      (r_name, r_ty),
                      rknf,
                      IfLe(
                        l_name,
                        r_name,
                        KnfEnv::to_knf(self, syn2),
                        KnfEnv::to_knf(self, syn3),
                      ),
                    ),
                  )
              }
          }
        }
        LT(lhs, rhs) => {
          let (l_name, l_ty, lknf) = KnfEnv::get_knf(self, lhs)
          let (r_name, r_ty, rknf) = KnfEnv::get_knf(self, rhs)
          // println("LE: " + (l_name, l_ty, lknf).to_string())
          // println("LE: " + (r_name, r_ty, rknf).to_string())
          match lhs {
            Var(_) =>
              match rhs {
                Var(_) =>
                  IfLt(
                    l_name,
                    r_name,
                    KnfEnv::to_knf(self, syn2),
                    KnfEnv::to_knf(self, syn3),
                  )
                _ =>
                  // println("LE: rhs is  a variable" + r_name.to_string())
                  Let(
                    (r_name, r_ty),
                    rknf,
                    IfLt(
                      l_name,
                      r_name,
                      KnfEnv::to_knf(self, syn2),
                      KnfEnv::to_knf(self, syn3),
                    ),
                  )
              }
            _ =>
              match rhs {
                Var(_) =>
                  Let(
                    (l_name, l_ty),
                    lknf,
                    IfLt(
                      l_name,
                      r_name,
                      KnfEnv::to_knf(self, syn2),
                      KnfEnv::to_knf(self, syn3),
                    ),
                  )
                _ =>
                  Let(
                    (l_name, l_ty),
                    lknf,
                    Let(
                      (r_name, r_ty),
                      rknf,
                      IfLt(
                        l_name,
                        r_name,
                        KnfEnv::to_knf(self, syn2),
                        KnfEnv::to_knf(self, syn3),
                      ),
                    ),
                  )
              }
          }
        }
        Not(b) => KnfEnv::to_knf(self, If(b, syn3, syn2))
        Bool(b) =>
          if b {
            KnfEnv::to_knf(self, syn2)
          } else {
            KnfEnv::to_knf(self, syn3)
          }
        _ => KnfEnv::to_knf(self, If(Eq(syn1, Bool(false)), syn3, syn2))
      }
    Neg(syn, kind~) =>
      // let knf = KnfEnv::get_knf!(self, syn)
      match kind {
        Some(Int) =>
          // Knf::Let((knf.0, Int), knf.1, Neg(knf.0))
          match syn {
            Var(str) => {
              let name = (try? @types.Name::from_string(str)).unwrap()
              Neg(name)
            }
            _ => {
              let name = self.new_temp()
              let k = KnfEnv::to_knf(self, syn)
              Let((name, Int), k, Neg(name))
            }
          }
        Some(Double) =>
          match syn {
            Var(str) => {
              let name = (try? @types.Name::from_string(str)).unwrap()
              FNeg(name)
            }
            _ => {
              let name = self.new_temp()
              let k = KnfEnv::to_knf(self, syn)
              Let((name, Double), k, FNeg(name))
            }
          }
        _ => raise KnfErr("the type of negation is unknown")
      }
    Prim(lsyn, rsyn, op, kind~) => {
      let (l_name, _, l) = KnfEnv::get_knf(self, lsyn)
      let (r_name, _, r) = KnfEnv::get_knf(self, rsyn)
      // println("l_name = " + l_name.to_string())
      // println("r_name = " + r_name.to_string())
      // println("lsyn = " + lsyn.to_string())
      // println("rsyn = " + rsyn.to_string())
      let mut opty : Knf = Unit
      match kind {
        Some(Int) => {
          match op {
            Add => opty = Add(l_name, r_name)
            Sub => opty = Sub(l_name, r_name)
            Mul => opty = Mul(l_name, r_name)
            Div => opty = Div(l_name, r_name)
            Mod => opty = Mod(l_name, r_name)
          }
          match lsyn {
            Var(_) =>
              match rsyn {
                Var(_) => opty
                _ => Let((r_name, Int), r, opty)
              }
            _ =>
              match rsyn {
                Var(_) => Let((l_name, Int), l, opty)
                _ => Let((l_name, Int), l, Let((r_name, Int), r, opty))
              }
          }
        }
        Some(Double) => {
          match op {
            Add => opty = FAdd(l_name, r_name)
            Sub => opty = FSub(l_name, r_name)
            Mul => opty = FMul(l_name, r_name)
            Div => opty = FDiv(l_name, r_name)
            Mod => opty = FMod(l_name, r_name)
          }
          match lsyn {
            Var(_) =>
              match rsyn {
                Var(_) => opty
                _ => Let((r_name, Double), r, opty)
              }
            _ =>
              match rsyn {
                Var(_) => Let((l_name, Double), l, opty)
                _ => Let((l_name, Double), l, Let((r_name, Double), r, opty))
              }
          }
        }
        _ =>
          raise KnfErr(
            "the type of prim is unknown, s: " +
            s.to_string() +
            ", \n\t kind: " +
            kind.to_string(),
          )
      }
    }
    Eq(syn1, syn2) =>
      KnfEnv::to_knf(self, If(Eq(syn1, syn2), Bool(true), Bool(false)))
    LE(syn1, syn2) =>
      KnfEnv::to_knf(self, If(LE(syn1, syn2), Bool(true), Bool(false)))
    LT(syn1, syn2) =>
      KnfEnv::to_knf(self, If(LT(syn1, syn2), Bool(true), Bool(false)))
    GT(syn1, syn2) =>
      KnfEnv::to_knf(self, If(LE(syn1, syn2), Bool(false), Bool(true)))
    GE(syn1, syn2) =>
      KnfEnv::to_knf(self, If(LT(syn1, syn2), Bool(false), Bool(true)))
    Let((name, ty), syn, rest) => {
      let mut env = self.externals
      match ty.repr() {
        UserDefineType(_, fields) =>
          for field in fields.val {
            env = env.add(field.0, ty)
          }
        _ => ()
      }
      let knf = KnfEnv::to_knf({ counter: self.counter, externals: env }, syn)
      let new_env = {
        counter: self.counter,
        externals: self.externals.add(name, ty),
      }
      let rest_knf = KnfEnv::to_knf(new_env, rest)
      let name = @types.Name::name_only(name)
      Let((name, ty), knf, rest_knf)
    }
    LetRec({ name: (name, ty), args, body }, rest) => {
      // @util.logger("let_rec: name = " + name.to_string())
      // @util.logger("let_rec: type " + @typing.extenv.to_string())
      let fun_name = (try? @types.Name::from_string(name)).unwrap()
      let mut env_body = self.externals.add(name, ty)
      let fun_args = args.map(t => {
        env_body = env_body.add(t.0, t.1)
        let x = (try? @types.Name::from_string(t.0)).unwrap()
        (x, t.1)
      })
      let fun_body = KnfEnv::to_knf(
        { counter: self.counter, externals: env_body },
        body,
      )
      let env_fun = self.externals.add(name, ty)
      let rest = KnfEnv::to_knf(
        { counter: self.counter, externals: env_fun },
        rest,
      )
      LetRec({ name: fun_name, ty, args: fun_args, body: fun_body }, rest)
    }
    App(syn, args_syns) => {
      // @util.logger("app: syn = " + syn.to_string() + "; args_syns= " + args_syns.to_string())
      fn let_app(
        self : KnfEnv,
        f : Name,
        args_names : Array[Name],
        s : Array[@types.Syntax],
      ) -> Knf raise KnfErr {
        let ss = s.pop()
        // @util.logger("let_app: ss = " + ss.to_string())
        match ss {
          None =>
            // println(f)
            // println(f.name)
            // println(f.name.to_string())
            if not(f.name.is_empty()) && @util.extenv.contains(f.name.unwrap()) {
              // @util.logger("@types: " + @typing.extenv.to_string())
              // @util.logger("let_app: ExternalFunctionApplication(f, args_names) f = " + f.name.to_string())
              if @typing.extenv.contains(f.name.unwrap()) {
                // @util.logger("let_app: ExternalFunctionApplication(f, args_names) f = " + f.name.to_string())
                ExternalFunctionApplication(
                  "minimbt_" + f.name.unwrap(),
                  args_names,
                )
              } else {
                // @util.logger("let_app: FunctionApplication(f, args_names) f = " + f.to_string())
                Apply(f, args_names)
              }
            } else {
              // println("app")
              // @util.logger("let_app: Apply(f, args_names) f = " + f.name.to_string())
              Apply(f, args_names)
            }
          Some(ss) => {
            // @util.logger("let_app: ss = Some(ss): " + ss.to_string())
            let ty = KnfEnv::get_type(self.externals, ss)
            match ss {
              Var(str) => {
                let x = (try? @types.Name::from_string(str)).unwrap()
                args_names.insert(0, x)
                let_app(self, f, args_names, s)
              }
              _ => {
                let x = self.new_temp()
                let k = KnfEnv::to_knf(self, ss)
                args_names.insert(0, x)
                Let((x, ty), k, let_app(self, f, args_names, s))
              }
            }
          }
        }
      }

      fn let_args(
        self : KnfEnv,
        syn : @types.Syntax,
        syns : Array[@types.Syntax],
      ) -> Knf raise KnfErr {
        let ty_s = KnfEnv::get_type(self.externals, syn)
        match syn {
          Var(str) => {
            let x = (try? @types.Name::from_string(str)).unwrap()
            let_app(self, x, [], syns)
          }
          _ => {
            let x = self.new_temp()
            let k = KnfEnv::to_knf(self, syn)
            Let((x, ty_s), k, let_app(self, x, [], syns))
          }
        }
      }

      match syn {
        Var(f) =>
          if @typing.extenv.contains(f) {
            let_app(
              self,
              (try? @types.Name::from_string(f)).unwrap(),
              [],
              args_syns,
            )
          } else {
            let_args(self, syn, args_syns)
          }
        _ => let_args(self, syn, args_syns)
      }
    }
    Tuple(syns) => make_tuple(self, syns)
    LetTuple(args, syn, rest) => {
      // println("Enter LetTuple")
      let mut env_tuple = self.externals
      for i in args {
        env_tuple = env_tuple.add(i.0, i.1)
      }
      let after = KnfEnv::to_knf(
        { counter: self.counter, externals: env_tuple },
        rest,
      )
      let arr_nm_ty = args.map(t => {
        let nm = @types.Name::name_only(t.0)
        (nm, t.1.repr())
      })
      match syn {
        Var(str) => {
          let x = (try? @types.Name::from_string(str)).unwrap()
          LetTuple(arr_nm_ty, x, after)
        }
        _ => {
          let k = KnfEnv::get_knf(self, syn)
          Let((k.0, k.1), k.2, LetTuple(arr_nm_ty, k.0, after))
        }
      }
    }
    Get(e1, e2) => {
      let (name1, e1_ty, knf1) = KnfEnv::get_knf(self, e1)
      let (name2, e2_ty, knf2) = KnfEnv::get_knf(self, e2)
      match e1 {
        Var(_) =>
          match e2 {
            Var(_) => Get(name1, name2)
            _ => Let((name2, e2_ty), knf2, Get(name1, name2))
          }
        _ =>
          match e2 {
            Var(_) => Let((name1, e1_ty), knf1, Get(name1, name2))
            _ =>
              Let(
                (name1, e1_ty),
                knf1,
                Let((name2, e2_ty), knf2, Get(name1, name2)),
              )
          }
      }
    }
    Put(syn1, syn2, syn3) => {
      let (name1, s1_ty, knf1) = KnfEnv::get_knf(self, syn1)
      let (name2, s2_ty, knf2) = KnfEnv::get_knf(self, syn2)
      let (name3, s3_ty, knf3) = KnfEnv::get_knf(self, syn3)
      match syn1 {
        Var(_) =>
          Let(
            (name2, s2_ty),
            knf2,
            Let((name3, s3_ty), knf3, Put(name1, name2, name3)),
          )
        _ =>
          Let(
            (name1, s1_ty),
            knf1,
            Let(
              (name2, s2_ty),
              knf2,
              Let((name3, s3_ty), knf3, Put(name1, name2, name3)),
            ),
          )
      }
    }
    Array(e1, e2) => {
      let (name1, e1_ty, knf1) = KnfEnv::get_knf(self, e1)
      let (name2, e2_ty, knf2) = KnfEnv::get_knf(self, e2)
      fn genArray(name1 : Name, name2 : Name) {
        match e2_ty {
          Int =>
            ExternalFunctionApplication("minimbt_create_array", [name1, name2])
          Double =>
            ExternalFunctionApplication("minimbt_create_float_array", [
              name1, name2,
            ])
          _ =>
            ExternalFunctionApplication("minimbt_create_ptr_array", [
              name1, name2,
            ])
        }
      }

      match e1 {
        Var(_) =>
          match e2 {
            Var(_) => genArray(name1, name2)
            _ => Let((name2, e2_ty), knf2, genArray(name1, name2))
          }
        _ =>
          match e2 {
            Var(_) => Let((name1, e1_ty), knf1, genArray(name1, name2))
            _ =>
              Let(
                (name1, e1_ty),
                knf1,
                Let((name2, e2_ty), knf2, genArray(name1, name2)),
              )
          }
      }
    }
    While(e1, e2) =>
      // Process the array of syntax elements into a single KNF expression

      While(KnfEnv::to_knf(self, e1), KnfEnv::to_knf(self, e2))
    Assign(e1, e2) => {
      let (name1, e1_ty, knf1) = KnfEnv::get_knf(self, e1)
      let (name2, e2_ty, knf2) = KnfEnv::get_knf(self, e2)
      match e1 {
        Var(_) =>
          match e2 {
            Var(_) => Assign(name1, name2)
            _ => Let((name2, e2_ty), knf2, Assign(name1, name2))
          }
        _ =>
          match e2 {
            Var(_) => Let((name1, e1_ty), knf1, Assign(name1, name2))
            _ =>
              Let(
                (name1, e1_ty),
                knf1,
                Let((name2, e2_ty), knf2, Assign(name1, name2)),
              )
          }
      }
    }
    And(e1, e2) => KnfEnv::to_knf(self, If(e1, e2, Bool(false)))
    // Struct(name, _, fields, rest) => {
    //   let env_fun = self.externals.add(name, UserDefineType(name, fields))
    //   KnfEnv::to_knf({ counter: self.counter, externals: env_fun }, rest)
    // }
    FieldAccess(e, field) => {
      let (name, e_ty, knf) = KnfEnv::get_knf(self, e)
      // @util.logger("(name, e_ty, knf)"  + (name, e_ty, knf).to_string())
      let index = match e_ty {
        UserDefineType(_, fields) => {
          let index = fields.val.search_by(fn(f) { f.0 == field })
          index.unwrap()
        }
        _ => @util.die("not support field access")
      }
      // let index_name = (try? @types.Name::from_string(name.name.unwrap() + "_" + field + "_index")).unwrap()
      // let let_index = Let((index_name, Int), index, FieldAccess(name, index_name))
      Let((name, e_ty), knf, FieldAccess(name, e_ty, index))
    }
    Enum(name, _, variants, cont) => {
      let variants = variants.map(fn(variant) {
        match variant {
          (name, ty) => (name, @types.Type::Tuple(ty))
        }
      })
      let mut env_fun = self.externals.add(
        name,
        UserDefineType(name, { val: variants }),
      )
      for variant in variants {
        let (name, _) = variant
        env_fun = env_fun.add(name, UserDefineType(name, { val: variants }))
      }
      // @util.logger("Enum name: " + name.to_string())
      KnfEnv::to_knf(
        { counter: self.counter, externals: env_fun },
        cont,
      )
    }
    EnumConstruct(name, variant) => {
      // @util.logger("env: " + self.counter.to_string())
      let ty = self.externals.get(name).unwrap()
      let index = match ty.repr() {
        UserDefineType(_, fields) => {
          let index = fields.val.search_by(fn(f) { f.0 == name })
          index.unwrap()
        }
        _ => @util.die("not support enum construct: " + ty.to_string())
      }
      let i = KnfEnv::get_knf(self, Int(index))
      let result = [i.0]
      let x = variant.fold(init=Tuple(result), (acc, variant) => {
        let (name, variant_ty, knf) = KnfEnv::get_knf(self, variant)
        result.push(name)
        // @util.logger("EnumConstruct acc: " + acc.to_string())
        Let((name, variant_ty), knf, acc)
      })
      // @util.logger("EnumConstruct x: " + x.to_string())
      // @util.logger("EnumConstruct i: " + Let((i.0, i.1), i.2, x).to_string())
      Let((i.0, i.1), i.2, x)
    }
    Match(expr, arms) => {
      // @util.logger("Match expr: " + expr.to_string())
      // @util.logger("Match e'nüenü: " + self.externals.to_string())
      let tag = KnfEnv::new_name(self, "match_tag")
      let (name, _expr_ty, _knf) = KnfEnv::get_knf(self, expr)
      // @util.logger("Match expr: " + expr.to_string() + " name:" + name.to_string() + " expr_ty:" + _expr_ty.to_string())
      // @util.logger("arms: " + arms.to_string())
      fn gen_match(arm : (@types.Pattern, @types.Syntax)) raise KnfErr {
        let (pat, body) = arm
        // @util.logger("Match arm: " + pat.to_string())
        let index = match pat {
          PEnumVariant(name, _) => {
            // @util.logger("PEnumVariant self.externals: " + self.externals.to_string())
            let ty = self.externals.get(name).unwrap()
            let index = match ty.repr() {
              UserDefineType(_, fields) => {
                // @util.logger("EnumConstruct name: " + name.to_string())
                let index = fields.val.search_by(fn(f) { f.0 == name })
                // @util.logger("EnumConstruct index: " + index.to_string())
                match index {
                  Some(index) => (index, fields.val[index])
                  None =>
                    @util.die(
                      "not support enum construct: " +
                      ty.to_string() +
                      "search by name: " +
                      name.to_string(),
                    )
                }
              }
              _ => @util.die("not support enum construct: " + ty.to_string())
            }
            index
          }
          _ => @util.die("not support match pattern: " + pat.to_string())
        }
        let body = KnfEnv::get_knf(self, body)
        // IfEq(tag, is_expr.0, body.2, acc)
        match index.1 {
          (_, Tuple(patterns_ty)) =>
            if patterns_ty.length() == 0 {
              body.2
            } else {
              let names = match pat {
                PEnumVariant(_, patts) =>
                  patts.map(fn(pat) {
                    match pat {
                      PVar(name) => Name::name_only(name)
                      _ =>
                        @util.die(
                          "not support match pattern: " + pat.to_string(),
                        )
                    }
                  })
                _ => @util.die("not support match pattern: " + pat.to_string())
              }
              let result = body.2
              patterns_ty.foldi(init=result, (i, acc, pat_ty) => Let(
                (names[names.length() - i - 1], pat_ty),
                FieldAccess(name, pat_ty, names.length() - i),
                acc,
              ))
            }
          _ => @util.die("not support match pattern: " + pat.to_string())
        }
      }

      let arms_knf = arms[1:].rev_fold(init=gen_match(arms[0]), (acc, arm) => {
        let (pat, _) = arm
        // @util.logger("Match arm: " + pat.to_string())
        let index = match pat {
          PEnumVariant(name, _) => {
            // @util.logger("PEnumVariant self.externals: " + self.externals.to_string())
            let ty = self.externals.get(name).unwrap()
            let index = match ty.repr() {
              UserDefineType(_, fields) => {
                // @util.logger("EnumConstruct name: " + name.to_string())
                let index = fields.val.search_by(fn(f) { f.0 == name })
                // @util.logger("EnumConstruct index: " + index.to_string())
                match index {
                  Some(index) => (index, fields.val[index])
                  None =>
                    @util.die(
                      "not support enum construct: " +
                      ty.to_string() +
                      "search by name: " +
                      name.to_string(),
                    )
                }
              }
              _ => @util.die("not support enum construct: " + ty.to_string())
            }
            index
          }
          _ => @util.die("not support match pattern: " + pat.to_string())
        }
        let is_expr = KnfEnv::get_knf(self, Int(index.0))
        let pattern_body = gen_match(arm)

        // @util.logger("Match acc  acc: " + acc.to_string())
        Let(
          (is_expr.0, is_expr.1),
          is_expr.2,
          IfEq(tag, is_expr.0, pattern_body, acc),
        )
      })
      // @util.logger("Match : " + Let((name, _expr_ty), _knf, Let((tag, Int), FieldAccess(name, _expr_ty, 0), arms_knf)).to_string())
      Let(
        (name, _expr_ty),
        _knf,
        Let((tag, Int), FieldAccess(name, _expr_ty, 0), arms_knf),
      )
      // @util.die("not support match: expr: " + expr.to_string() + "; arms: " + arms.to_string())
    }
    ExternalArray(label) => ExternalArray(label)
    ArrayData(label, data) =>
      ArrayData(
        label,
        data.mapi(fn(i, d) {
          match d {
            Int(i) => Int(i)
            Double(d) => Double(d)
            Neg(Double(d), ..) => Double(-d)
            Neg(Int(d), ..) => Int(-d)

            ArrayData(label, data) => KnfEnv::to_knf(self, ArrayData(label+"_"+i.to_string(), data))
            ArrayExpr(data) => KnfEnv::to_knf(self, ArrayData(label+"_"+i.to_string(), data))
            _ =>
              raise KnfErr("not supported syntax ArrayData: " + d.to_string())
          }
        }),
      )
    _ => raise KnfErr("not supported syntax " + s.to_string())
  }
}

///|
fn make_tuple(env : KnfEnv, syns : Array[@types.Syntax]) -> Knf raise KnfErr {
  let syns_names = Array::new()
  let lets = Array::new()

  // Process all syntax elements first
  for syn in syns {
    let (name, ty, knf) = KnfEnv::get_knf(env, syn)
    syns_names.push(name)
    match syn {
      Var(_) => () // No Let needed for variables
      _ => lets.push((name, ty, knf))
    }
  }

  // Build the result by nesting Let expressions from inside out
  let mut result = Tuple(syns_names)
  for i = lets.length() - 1; i >= 0; i = i - 1 {
    let (name, ty, knf) = lets[i]
    result = Let((name, ty), knf, result)
  }
  result
}

///|
pub(all) suberror KnfErr String derive(ToJson(style="flat"))

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
      let typed = @typing.typing(parse)
      // println(typed)
      let pre = KnfEnv::syntax_preprocess(
        KnfEnv::new(@immut/hashmap.new()),
        typed,
      )
      // println(pre)
      let knf = KnfEnv::to_knf(KnfEnv::new(@immut/hashmap.new()), pre)
      println(knf)
    } catch {
      @typing.TyErr(s) => {
        println("typing error")
        println(s)
      }
      KnfErr(s) => {
        println("knf error")
        println(s)
      }
      _ => println("unknown error")
    }
  }
}

///|
test {
  let _test2 = (try? @fs.read_file_to_string(
    "contest-2025-data/test_cases/mbt/enum2.mbt",
  )).unwrap() //cls-reg-bug.mbt
  let parse = @parser.parse_from_string(_test2)
  println("parse: " + parse.to_json().stringify())
  try {
    let typed = @typing.typing(parse)
    // println("typed: " + typed.to_json().stringify())
    let env = KnfEnv::new(@immut/hashmap.new())
    let pre = KnfEnv::syntax_preprocess(env, typed)
    // println("pre: " + pre.to_json().stringify())
    // @util.logger("env: " + env.externals.to_string())
    let _knf = KnfEnv::to_knf(env, pre)
    println("knf: " + _knf.to_json().stringify())
  } catch {
    @typing.TyErr(s) => {
      println("typing error")
      println(s)
    }
    KnfErr(s) => {
      println("knf error")
      println(s)
    }
    _ => println("unknown error")
  }
}
