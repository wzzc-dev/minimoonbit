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

fn KnfEnv::app_bind_name(
  self : KnfEnv,
  name : Name,
  e : @types.Syntax,
  args : Array[@types.Syntax],
  args_names : Array[Name]
) -> Knf!KnfErr {
  let all_args = args.copy()
  match args.pop() {
    None => Apply(name, args_names.rev())
    Some(arg) =>
      match arg {
        Var(_) =>
          Apply(
            name,
            all_args.map(
              fn(x) {
                match x {
                  Var(name) => @types.from_string?(name).unwrap()
                  _ => @types.from_string?("").unwrap()
                }
              },
            ),
          )
        _ => {
          let (s_name, s_ty, knf) = get_knf!(self, arg)
          args_names.push(s_name)
          Let(
            (s_name, s_ty),
            knf,
            app_bind_name!(self, name, e, args, args_names),
          )
        }
      }
  }
}

fn KnfEnv::tuple_bind_name(
  self : KnfEnv,
  name : Name,
  args : Array[@types.Syntax],
  args_names : Array[Name]
) -> Knf!KnfErr {
  match args.pop() {
    None => Apply(name, args_names.rev())
    Some(arg) => {
      let (s_name, s_ty, knf) = get_knf!(self, arg)
      args_names.push(s_name)
      Let((s_name, s_ty), knf, tuple_bind_name!(self, name, args, args_names))
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
      match syn1 {
        Bool(b) => if b { to_knf!(self, syn2) } else { to_knf!(self, syn3) }
        Eq(lhs, rhs) => {
          let (l_name, l_ty, lt) = get_knf!(self, lhs)
          let (r_name, r_ty, rt) = get_knf!(self, rhs)
          Let(
            (l_name, l_ty),
            lt,
            Let(
              (r_name, r_ty),
              rt,
              IfEq(l_name, r_name, to_knf!(self, syn2), to_knf!(self, syn3)),
            ),
          )
        }
        LE(lhs, rhs) => {
          let (l_name, l_ty, lt) = get_knf!(self, lhs)
          let (r_name, r_ty, rt) = get_knf!(self, rhs)
          Let(
            (l_name, l_ty),
            lt,
            Let(
              (r_name, r_ty),
              rt,
              IfLe(l_name, r_name, to_knf!(self, syn2), to_knf!(self, syn3)),
            ),
          )
        }
        Not(b) => to_knf!(self, If(b, syn3, syn2))
        _ => to_knf!(self, syn1)
      }
    Neg(syn, ~kind) =>
      // let knf = get_knf!(self, syn)
      match kind {
        Some(Int) =>
          // Knf::Let((knf.0, Int), knf.1, Neg(knf.0))
          match syn {
            Var(name) => {
              let name = @types.from_string?(name).unwrap()
              Neg(name)
            }
            _ => {
              let name = self.new_temp()
              let k = to_knf!(self, s)
              Let((name, Int), k, Neg(name))
            }
          }
        Some(Double) =>
          match syn {
            Var(name) => {
              let name = @types.from_string?(name).unwrap()
              FNeg(name)
            }
            _ => {
              let x = self.new_temp()
              let k = to_knf!(self, s)
              Let((x, Int), k, FNeg(x))
            }
          }
        _ => raise KnfErr("the type of negation is unknown")
      }
    Prim(lsyn, rsyn, op, ~kind) => {
      let (l_name, _, l) = get_knf!(self, lsyn)
      let (r_name, _, r) = get_knf!(self, rsyn)
      let mut opty : Knf = Unit
      match kind {
        Some(Int) => {
          match op {
            Add => opty = Add(l_name, r_name)
            Sub => opty = Sub(l_name, r_name)
            Mul => opty = Mul(l_name, r_name)
            Div => opty = Div(l_name, r_name)
          }
          Knf::Let((l_name, Int), l, Knf::Let((r_name, Int), r, opty))
        }
        Some(Double) => {
          match op {
            Add => opty = FAdd(l_name, r_name)
            Sub => opty = FSub(l_name, r_name)
            Mul => opty = FMul(l_name, r_name)
            Div => opty = FDiv(l_name, r_name)
          }
          Knf::Let((l_name, Double), l, Knf::Let((r_name, Double), r, opty))
        }
        _ => raise KnfErr("the type of prim is unknown")
      }
    }
    Eq(syn1, syn2) => to_knf!(self, If(Eq(syn1, syn2), Int(1), Int(0)))
    LE(syn1, syn2) => to_knf!(self, If(LE(syn1, syn2), Int(1), Int(0)))
    Let((name, ty), syn, rest) => {
      let new_env = {
        counter: self.counter,
        externals: self.externals.add(name, ty),
      }
      let name = @types.name_only(name)
      Let((name, ty), to_knf!(self, syn), to_knf!(new_env, rest))
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
    App(syn, args) => {
      let (name, _, _) = get_knf!(self, syn)
      match syn {
        Var(n) =>
          if @typing.extenv.contains(n) {
            ExternalFunctionApplication(
              "minimbt_" + n,
              args.map(
                fn(x) {
                  match x {
                    Var(name) => @types.from_string?(name).unwrap()
                    _ => @types.from_string?("").unwrap()
                  }
                },
              ),
            )
          } else {
            println(
              "App: syn" + syn.to_string() + ", args: " + args.to_string(),
            )
            app_bind_name!(self, name, syn, args, Array::new())
          }
        _ => app_bind_name!(self, name, syn, args, Array::new())
      }
    }
    Tuple(syns) => {
      // Tuple([name1,name2...])
      let mut result : Knf = Unit
      let arr_names = Array::new()
      for syn in syns {
        match syn {
          Var(name) => {
            let name = @types.from_string?(name).unwrap()
            arr_names.push(name)
            result = Knf::Tuple(arr_names)
          }
          _ => {
            let knf = to_knf!(self, syn)
            let name = new_temp(self)
            arr_names.push(name)
            result = Knf::Let((name, Unit), result, knf)
          }
        }
      }
      result
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
      Let((name1, e1_ty), knf1, Let((name2, e2_ty), knf2, Get(name1, name2)))
    }
    Put(syn1, syn2, syn3) => {
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
      Let((name1, e1_ty), knf1, Let((name2, e2_ty), knf2, ExternalArray(name1)))
    }
  }
}

type! KnfErr String derive(ToJson)

test {
  let _test2 =
    #|  fn main {
    #|    fn f(x) {
    #|      x + 1
    #|    };
    #|    let fnx = f(1);
    #|    ()
    #|};
  // let test2 =
  //   #|  let x: Int = 1 + 1;
  //   #|  let y: Int = x;
  let _test2 = @fs.read_file_to_string?(path="test/test_src/shuffle.mbt").unwrap()
  let parse = @parser.parse_from_string(_test2)
  // println(parse)
  try {
    let typed = @typing.typing!(parse)
    // println(typed)
    let knf = to_knf!(KnfEnv::new(@immut/hashmap.new()), typed)
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
