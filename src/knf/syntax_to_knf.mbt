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

pub fn KnfEnv::to_knf(self : KnfEnv, s : @types.Syntax) -> Knf!KnfErr { // !Failure
  match s {
    Unit => Unit
    Int(i) => Int(i)
    Double(d) => Double(d)
    Var(name) => Var(@types.name_only(name))
    Bool(b) => if b { Int(1) } else { Int(0) }
    Not(syn) => to_knf!(self, syn)
    If(syn1, syn2, syn3) =>
      match syn1 {
        Bool(b) => if b { to_knf!(self, syn2) } else { to_knf!(self, syn3) }
        _ => raise KnfErr("Unknown type")
      }
    Neg(syn, ~kind) =>
      match kind {
        Some(Int) => {
          let temp = new_temp(self)
          let knf = to_knf!(self, syn)
          Knf::Let((temp, Int), knf, Neg(temp))
        }
        Some(Double) => {
          let temp = new_temp(self)
          let knf = to_knf!(self, syn)
          Knf::Let((temp, Int), knf, FNeg(temp))
        }
        _ => raise KnfErr("Unknown type")
      }
    Prim(lsyn, rsyn, op, ~kind) => {
      let l = to_knf!(self, lsyn)
      let r = to_knf!(self, rsyn)
      let l_name = new_temp(self)
      let r_name = new_temp(self)
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
        _ => raise KnfErr("Unknown type")
      }
    }
    Eq(syn1, syn2) => {
      let name1 = new_temp(self)
      let name2 = new_temp(self)
      let knf1 = to_knf!(self, syn1)
      let knf2 = to_knf!(self, syn2)
      IfEq(name1, name2, knf1, knf2)
    }
    LE(syn1, syn2) => {
      let name1 = new_temp(self)
      let name2 = new_temp(self)
      let knf1 = to_knf!(self, syn1)
      let knf2 = to_knf!(self, syn2)
      IfLe(name1, name2, knf1, knf2)
    }
    Let((name, ty), syn, knf) => {
      let new_env = self.externals.add(name, ty)
      let new_knf = KnfEnv::new(new_env)
      let knf_val = to_knf!(self, syn)
      let rest = to_knf!(new_knf, knf)

      let name = @types.from_string?(name).unwrap()
      Knf::Let((name, ty), knf_val, rest)
    }
    LetRec(defs, knf) => {
      println("LetRec- defs: " + defs.to_string() + ",knf: " + knf.to_string())
      let name = @types.from_string?(defs.name.0).unwrap()
      let ty = defs.name.1
      let args = defs.args.map(
        fn (arg) {
          (@types.from_string?(arg.0).unwrap(), arg.1)
        }
      )
      let knf_body = to_knf!(self, defs.body)
      println("LetRec- knf_body: " + knf_body.to_string())
      let rest = to_knf!(self, knf)
      println("LetRec- rest: " + rest.to_string())
      LetRec({ name, ty, args, body: knf_body }, rest)
    }
    App(syn, args) => {
      let knf_name = new_temp(self)
      let knf_val = to_knf!(self, syn)
      let knf_args = Array::new()
      for arg in args {
        knf_args.push(to_knf!(self, arg))
      }
      Apply(knf_name, [])
    }
    Tuple(syns) => {
      let names = Array::new()
      for syn in syns {
        let knf = to_knf!(self, syn)
        let name = new_temp(self)
        names.push(name)
        let x = Knf::Let((name, Unit), knf, Unit)

      }
      Tuple(names)
    }
    LetTuple(args, syn, knf) => {
      let knf_name = new_temp(self)
      let knf_val = to_knf!(self, syn)
      let knf_args = Array::new()
      // for arg in args {
      //   knf_args.push(to_knf!(self, arg))
      // }
      LetTuple([], knf_name, knf_val)
    }
    Get(name, index) => {
      let knf_name = @types.name_only(name.to_string())
      Get(knf_name, knf_name)
    }
    Put(syn1, syn2, syn3) => {
      let knf_name1 = new_temp(self)
      let knf_val1 = to_knf!(self, syn1)
      let knf_name2 = new_temp(self)
      let knf_val2 = to_knf!(self, syn2)
      let knf_name3 = new_temp(self)
      let knf_val3 = to_knf!(self, syn3)
      Put(knf_name1, knf_name2, knf_name3)
    }
    Array(size, syn) => {
      let knf_name = new_temp(self)
      let knf_val = to_knf!(self, syn)
      // ExternalArray(name)
      ExternalFunctionApplication("", [])
    }
  }
}

type! KnfErr String derive(ToJson)

test {
  let test2 =
    #| let x: Int = 1;
  let parse = @parser.parse_from_string(test2)
  println(parse)
  let knf = to_knf!(KnfEnv::new(@immut/hashmap.new()), parse)
  println(knf)
}
