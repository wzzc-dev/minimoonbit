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

pub fn KnfEnv::to_knf(self : KnfEnv, s : @types.Syntax) -> Knf { // !Failure
  match s {
    Var(x) => Knf::Var(@types.from_string?(x).unwrap())
    // Add(a, b, ty) => {
    //   let a_name = generate_name()                  //_1
    //   let b_name = generate_name()                  //_2
    //   KnfLet(a_name, ty, expr_to_knf(env, a),    // let _1 = <a>
    //     KnfLet(b_name, ty, expr_to_knf(env, b),   //let _2 = <b>
    //       KnfAdd(a_name, b_name)))                //_1 + _2
    // }
    // Let((x, t), expr, cont) => {
    //   let new_env = env.add(x, t)
    //   Let((x, t), expr_to_knf(env, expr),     //   let x: T = <expr> in
    //     expr_to_knf(new_env, cont))             //    <cont>
    // }
    _ => Knf::Unit
  }
}
