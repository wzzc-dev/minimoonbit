pub typealias LocalEnv = @immut/hashmap.T[String, Type]

struct KnfEnv {
  mut counter : Int
  externals : @immut/hashmap.T[String, Type]
}

pub fn KnfEnv::new(externals : @immut/hashmap.T[String, Type]) -> KnfEnv {
  { counter: 1, externals }
}

pub fn KnfEnv::init_counter_from_existing(
  self : KnfEnv,
  existing : Knf
) -> Unit {
  self.counter = knf_max_counter(existing) + 1
}

fn KnfEnv::new_temp(self : KnfEnv) -> Name {
  let temp = Name::slot_only(self.counter)
  self.counter += 1
  temp
}

fn KnfEnv::new_named_temp(self : KnfEnv, name : Name) -> Name {
  let counter = self.counter
  self.counter += 1
  { ..name, slot: counter }
}

fn KnfEnv::get_knf(
  self : KnfEnv,
  syn : @types.Syntax
) -> (Name, Type, Knf)!KnfErr {
  let ty = get_type!(self.externals, syn)
  match syn {
    Var(name) => {
      let name = @types.from_string?(name).unwrap()
      (name, ty, Var(name))
    }
    _ => {
      let name = self.new_temp()
      (name, ty, to_knf!(self, syn))
    }
  }
}

fn KnfEnv::get_type(env : LocalEnv, syn : @types.Syntax) -> @types.Type!KnfErr {
  try {
    @typing.get_type!(env, syn)
  } catch {
    TyErr(x) => raise KnfErr(x)
  }
}

pub fn KnfEnv::to_knf(self : KnfEnv, s : @types.Syntax) -> Knf!KnfErr { // !Failure
  match s {
    Unit => Unit
    Int(i) => Int(i)
    Double(d) => Double(d)
    Var(name) => Var(@types.from_string?(name).unwrap())
    Bool(b) => if b { Int(1) } else { Int(0) }
    Not(syn) => to_knf!(self, If(syn, Int(0), Int(1)))
    If(syn1, syn2, syn3) =>
      // println("if: " + syn1.to_string())
      match syn1 {
        Eq(lhs, rhs) => {
          let (l_name, l_ty, lknf) = get_knf!(self, lhs)
          let (r_name, r_ty, rknf) = get_knf!(self, rhs)
          match lhs {
            Var(_) =>
              match rhs {
                Var(_) =>
                  IfEq(l_name, r_name, to_knf!(self, syn2), to_knf!(self, syn3))
                _ =>
                  Let(
                    (r_name, r_ty),
                    rknf,
                    IfEq(
                      l_name,
                      r_name,
                      to_knf!(self, syn2),
                      to_knf!(self, syn3),
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
                      to_knf!(self, syn2),
                      to_knf!(self, syn3),
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
                        to_knf!(self, syn2),
                        to_knf!(self, syn3),
                      ),
                    ),
                  )
              }
          }
        }
        LE(lhs, rhs) => {
          let (l_name, l_ty, lknf) = get_knf!(self, lhs)
          let (r_name, r_ty, rknf) = get_knf!(self, rhs)
          // println("LE: " + (l_name, l_ty, lknf).to_string())
          // println("LE: " + (r_name, r_ty, rknf).to_string())
          match lhs {
            Var(_) =>
              match rhs {
                Var(_) =>
                  IfLe(l_name, r_name, to_knf!(self, syn2), to_knf!(self, syn3))
                _ =>
                  // println("LE: rhs is  a variable" + r_name.to_string())
                  Let(
                    (r_name, r_ty),
                    rknf,
                    IfLe(
                      l_name,
                      r_name,
                      to_knf!(self, syn2),
                      to_knf!(self, syn3),
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
                      to_knf!(self, syn2),
                      to_knf!(self, syn3),
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
                        to_knf!(self, syn2),
                        to_knf!(self, syn3),
                      ),
                    ),
                  )
              }
          }
        }
        // let (r_name, r_ty, rt) = get_knf!(self, rhs)

        // Let(
        //   (l_name, l_ty),
        //   lt,
        //   Let(
        //     (r_name, r_ty),
        //     rt,
        //     IfLe(l_name, r_name, to_knf!(self, syn2), to_knf!(self, syn3)),
        //   ),
        // )
        Not(b) => to_knf!(self, If(b, syn3, syn2))
        Bool(b) => if b { to_knf!(self, syn2) } else { to_knf!(self, syn3) }
        _ => to_knf!(self, If(Eq(syn1, Bool(false)), syn3, syn2))
      }
    Neg(syn, ~kind) =>
      // let knf = get_knf!(self, syn)
      match kind {
        Some(Int) =>
          // Knf::Let((knf.0, Int), knf.1, Neg(knf.0))
          match syn {
            Var(str) => {
              let name = @types.from_string?(str).unwrap()
              Neg(name)
            }
            _ => {
              let name = self.new_temp()
              let k = to_knf!(self, syn)
              Let((name, Int), k, Neg(name))
            }
          }
        Some(Double) =>
          match syn {
            Var(str) => {
              let name = @types.from_string?(str).unwrap()
              FNeg(name)
            }
            _ => {
              let name = self.new_temp()
              let k = to_knf!(self, syn)
              Let((name, Double), k, FNeg(name))
            }
          }
        _ => raise KnfErr("the type of negation is unknown")
      }
    Prim(lsyn, rsyn, op, ~kind) => {
      let (l_name, _, l) = get_knf!(self, lsyn)
      let (r_name, _, r) = get_knf!(self, rsyn)
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
        _ => raise KnfErr("the type of prim is unknown")
      }
    }
    Eq(syn1, syn2) => to_knf!(self, If(Eq(syn1, syn2), Bool(true), Bool(false)))
    LE(syn1, syn2) => to_knf!(self, If(LE(syn1, syn2), Bool(true), Bool(false)))
    Let((name, ty), syn, rest) => {
      let knf = to_knf!(self, syn)
      let new_env = {
        counter: self.counter,
        externals: self.externals.add(name, ty),
      }
      let rest_knf = to_knf!(new_env, rest)
      let name = @types.name_only(name)
      Let((name, ty), knf, rest_knf)
    }
    LetRec({ name: (name, ty), args, body }, rest) => {
      let fun_name = @types.from_string?(name).unwrap()
      let mut env_body = self.externals.add(name, ty)
      let env_fun = self.externals.add(name, ty)
      let fun_args = args.map(
        fn {
          t => {
            env_body = env_body.add(t.0, t.1)
            let x = @types.from_string?(t.0).unwrap()
            (x, t.1)
          }
        },
      )
      let fun_body = to_knf!(
        { counter: self.counter, externals: env_body },
        body,
      )
      let rest = to_knf!({ counter: self.counter, externals: env_fun }, rest)
      LetRec({ name: fun_name, ty, args: fun_args, body: fun_body }, rest)
    }
    App(syn, args_syns) => {
      // println("app: syn: " + syn.to_string())
      // println("app: args: " + args.to_string())
      // let args_names = Array::new()

      // fn let_app(self : KnfEnv, args : Array[@types.Syntax]) -> Knf!KnfErr {
      //   match args.pop() {
      //     None => {
      //       let app_name = match syn {
      //         Var(name) => name
      //         _ => raise KnfErr("app: expected a variable")
      //       }
      //       if @typing.extenv.contains(app_name.to_string()) {
      //         ExternalFunctionApplication(
      //           "minimbt_" + app_name.to_string(),
      //           args_names.rev(),
      //         )
      //       } else {
      //         Apply(@types.from_string?(app_name).unwrap(), args_names.rev())
      //       }
      //     }
      //     Some(arg) =>
      //       match arg {
      //         Var(s_name) => {
      //           let name = @types.from_string?(s_name).unwrap()
      //           args_names.push(name)
      //           let_app!(self, args)
      //         }
      //         _ => {
      //           let (arg_name, arg_ty, arg_knf) = get_knf!(self, arg)
      //           args_names.push(arg_name)
      //           Let((arg_name, arg_ty), arg_knf, let_app!(self, args))
      //         }
      //       }
      //   }
      // }
      // let_app!(self, args)
      fn let_app(
        self : KnfEnv,
        f : Name,
        args_names : Array[Name],
        s : Array[@types.Syntax]
      ) -> Knf!KnfErr {
        let ss = s.pop()
        match ss {
          None =>
            // println(f)
            // println(f.name)
            // println(f.name.to_string())
            if not(f.name.is_empty()) &&
              @typing.extenv.contains(f.name.unwrap()) {
              // println("external")
              ExternalFunctionApplication("minimbt_" + f.name.unwrap(), args_names)
            } else {
              // println("app")
              Apply(f, args_names)
            }
          Some(ss) => {
            let ty = get_type!(self.externals, ss)
            match ss {
              Var(str) => {
                let x = @types.from_string?(str).unwrap()
                args_names.insert(0, x)
                let_app!(self, f, args_names, s)
              }
              _ => {
                let x = self.new_temp()
                let k = to_knf!(self, ss)
                args_names.insert(0, x)
                Let((x, ty), k, let_app!(self, f, args_names, s))
              }
            }
          }
        }
      }

      fn let_args(
        self : KnfEnv,
        syn : @types.Syntax,
        syns : Array[@types.Syntax]
      ) -> Knf!KnfErr {
        let ty_s = get_type!(self.externals, syn)
        match syn {
          Var(str) => {
            let x = @types.from_string?(str).unwrap()
            let_app!(self, x, [], syns)
          }
          _ => {
            let x = self.new_temp()
            let k = to_knf!(self, syn)
            Let((x, ty_s), k, let_app!(self, x, [], syns))
          }
        }
      }

      match syn {
        Var(f) =>
          if @typing.extenv.contains(f) {
            let_app!(self, @types.from_string?(f).unwrap(), [], args_syns)
          } else {
            let_args!(self, syn, args_syns)
          }
        _ => let_args!(self, syn, args_syns)
      }
    }
    Tuple(syns) => {
      let syns_names = Array::new()
      fn let_tuple(syns : Array[@types.Syntax]) -> Knf!KnfErr {
        match syns.pop() {
          None => Tuple(syns_names)
          Some(syn) => {
            let (name, ty, knf) = get_knf!(self, syn)
            match syn {
              Var(_) => {
                syns_names.push(name)
                let_tuple!(syns)
              }
              _ => {
                syns_names.push(name)
                Let((name, ty), knf, let_tuple!(syns))
              }
            }
          }
        }
      }

      let_tuple!(syns)
    }
    LetTuple(args, syn, rest) => {
      //println("Enter LetTuple")
      let mut env_tuple = self.externals
      for i in args {
        env_tuple = env_tuple.add(i.0, i.1)
      }
      let after = to_knf!({ counter: self.counter, externals: env_tuple }, rest)
      let arr_nm_ty = args.map(
        fn {
          t => {
            let nm = @types.name_only(t.0)
            (nm, t.1)
          }
        },
      )
      match syn {
        Var(str) => {
          let x = @types.from_string?(str).unwrap()
          LetTuple(arr_nm_ty, x, after)
        }
        _ => {
          let x = self.new_temp()
          let k = to_knf!(self, s)
          Let((x, Unit), k, LetTuple(arr_nm_ty, x, after))
        }
      }
    }
    Get(e1, e2) => {
      let (name1, e1_ty, knf1) = get_knf!(self, e1)
      let (name2, e2_ty, knf2) = get_knf!(self, e2)
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
      // println("Put: ")
      // println(syn1)
      // println(syn2)
      // println(syn3) 
      let (name1, s1_ty, knf1) = get_knf!(self, syn1)
      let (name2, s2_ty, knf2) = get_knf!(self, syn2)
      let (name3, s3_ty, knf3) = get_knf!(self, syn3)
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
    Array(e1, e2) => {
      let (name1, e1_ty, knf1) = get_knf!(self, e1)
      let (name2, e2_ty, knf2) = get_knf!(self, e2)
      fn genArray(name1 : Name, name2 : Name) {
        match e2_ty {
          Int =>
            ExternalFunctionApplication("minimbt_create_array", [name1, name2])
          Double =>
            ExternalFunctionApplication(
              "minimbt_create_float_array",
              [name1, name2],
            )
          _ =>
            ExternalFunctionApplication(
              "minimbt_create_ptr_array",
              [name1, name2],
            )
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
  }
}

type! KnfErr String derive(ToJson)

test {
  let list = @fs.read_dir!(path="test/test_src")
  println(list)
  for file in list {
    println(file)
    guard file.ends_with(".mbt") else {
      println("not mbt file")
      continue
    }
    // guard file.starts_with("matmul-flat") else {
    //   println("matmul-flat mbt file")
    //   continue
    // }
    let _test2 = @fs.read_file_to_string?(path="test/test_src/" + file).unwrap()
    let parse = @parser.parse_from_string(_test2)
    try {
      let typed = @typing.typing!(parse)
      // println(typed)
      let knf = to_knf!(new(@immut/hashmap.new()), typed)
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

test {
  let _test2 = @fs.read_file_to_string?(path="test/test_src/matmul.mbt").unwrap() //cls-reg-bug.mbt
  let parse = @parser.parse_from_string(_test2)
  println(parse)
  try {
    let typed = @typing.typing!(parse)
    println(typed)
    
    let env = KnfEnv::new(@immut/hashmap.new())
    let pre = syntax_preprocess(env, typed)
    println(pre)
    let knf = to_knf!(env, pre)
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
