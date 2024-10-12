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

fn KnfEnv::get_knf(self : KnfEnv, syn : @types.Syntax) -> (Name, Knf)!KnfErr {
  match syn {
    Var(name) => {
      let name = @types.from_string?(name).unwrap()
      (name, Var(name))
    }
    _ => {
      let name = self.new_temp()
      (name, to_knf!(self, syn))
    }
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
      //     Eq(Syntax, Syntax) // _==_
      // LE(Syntax, Syntax) // _<=_
      //   Not(Syntax) // not(_)
      match syn1 {
        Bool(b) => if b { to_knf!(self, syn2) } else { to_knf!(self, syn3) }
        Eq(lhs, rhs) => {
          let (l_name, lt) = get_knf!(self, lhs)
          let (r_name, rt) = get_knf!(self, rhs)
          Let(
            (l_name, Unit),
            lt,
            Let(
              (r_name, Unit),
              rt,
              IfEq(l_name, r_name, to_knf!(self, syn2), to_knf!(self, syn3)),
            ),
          )
        }
        LE(lhs, rhs) => {
          let (l_name, lt) = get_knf!(self, lhs)
          let (r_name, rt) = get_knf!(self, rhs)
          Let(
            (l_name, Unit),
            lt,
            Let(
              (r_name, Unit),
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
      let (l_name, l) = get_knf!(self, lsyn)
      let (r_name, r) = get_knf!(self, rsyn)
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
      let new_env = KnfEnv::new(self.externals.add(name, ty))
      let name = @types.from_string?(name).unwrap()
      Let((name, ty), to_knf!(self, syn), to_knf!(new_env, rest))
    }
    LetRec(defs, rest) => {
      let name = @types.from_string?(defs.name.0).unwrap()
      let ty = defs.name.1
      let args = defs.args.map(
        fn(arg) { (@types.from_string?(arg.0).unwrap(), arg.1) },
      )
      let knf_body = to_knf!(self, defs.body)
      let rest = to_knf!(self, rest)
      LetRec({ name, ty, args, body: knf_body }, rest)
    }
    App(syn, args) =>
      match syn {
        Var(name) => {
          let name = @types.from_string?(name).unwrap()
          let knf_args = Array::new()
          let knf_args_names = Array::new()
          for arg in args {
            match arg {
              Var(name) => {
                let name = @types.from_string?(name).unwrap()
                knf_args.push(Var(name))
                knf_args_names.push(name)
              }
              _ => {
                let knf = to_knf!(self, arg)
                knf_args.push(knf)
              }
            }
          }
          Apply(name, knf_args_names)
        }
        _ => raise KnfErr("TODO")
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
      let (name1, knf1) = get_knf!(self, e1)
      let (name2, knf2) = get_knf!(self, e2)
      Let((name1, Unit), knf1, Let((name2, Unit), knf2, Get(name1, name2)))
    }
    Put(syn1, syn2, syn3) => {
      let (name1, knf1) = get_knf!(self, syn1)
      let (name2, knf2) = get_knf!(self, syn2)
      let (name3, knf3) = get_knf!(self, syn3)
      Let((name1, Unit), knf1, Let((name2, Unit), knf2, Let((name3, Unit), knf3, Put(name1, name2, name3))))
    }
    Array(e1, e2) => {
      let (name1, knf1) = get_knf!(self, e1)
      let (name2, knf2) = get_knf!(self, e2)
      Let((name1, Unit),  knf1, Let((name2, Unit), knf2, ExternalArray(name1)))
    }
  }
}

type! KnfErr String derive(ToJson)

test {
  let test2 =
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
  let parse = @parser.parse_from_string(test2)
  println(parse)
  try {
    let typed = @typing.typing!(parse)
    println(typed)
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
