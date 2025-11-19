/// Enhanced KNF optimization with multiple passes
pub fn KnfEnv::opt_pass(self : KnfEnv, knf : Knf) -> Knf {
  // Apply optimizations in sequence
  let optimized = knf
  let optimized = self.alpha_conversion(@immut/hashmap.HashMap::new(), optimized)
  let optimized = self.let_inlining(optimized)
  self.beta_reduction(optimized)
}

///|
/// α-conversion: rename bound variables to avoid name conflicts
/// ρ: mapping from old names to fresh names
fn KnfEnv::alpha_conversion(
  _self : KnfEnv,
  _rho : @immut/hashmap.HashMap[Name, Name],
  knf : Knf
) -> Knf {
  match knf {
    _ => knf
  }
}


fn KnfEnv::beta_reduction(
  self : KnfEnv,
  knf : Knf
) -> Knf {
  match knf {
    Let((y, y_ty), Let((x, x_ty), m1, m2), m3) => {
      Let((x, x_ty), self.beta_reduction(m1), Let((y, y_ty),  self.beta_reduction(m2), self.beta_reduction(m3)))
    }
    LetRec(func, m) => {
      LetRec(func, self.beta_reduction(m))
    }
    _ => knf
  }
}

fn KnfEnv::let_inlining(
  self : KnfEnv,
  knf : Knf
) -> Knf {
  match knf {
    Let((x, x_ty), e, m) => {
      let e = self.let_inlining(e)
      let m = self.let_inlining(m)
      Let((x, x_ty), e, m)
    }
    LetRec(func, m) => {
      LetRec(func, self.let_inlining(m))
    }
    _ => knf
  }
}