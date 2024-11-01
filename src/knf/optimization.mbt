pub fn KnfEnv::opt_pass(self : KnfEnv, knf : Knf) -> Knf {
  alpha_conversion(self, [], knf)
}
fn alpha_conversion(self : KnfEnv, existing : Array[Name], knf : Knf) -> Knf {
  match knf {
    Let((n, ty), e1, e2) => {
      if existing.contains(n) {
        self.opt_pass(e2)
      } else {
        existing.push(n)
        Let((n, ty), self.alpha_conversion(existing, e1), self.alpha_conversion(existing, e2))
      }
    }
    _ => knf
  }
}