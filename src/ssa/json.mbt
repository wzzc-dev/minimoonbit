///|
pub fn Ssa::to_json(self : Ssa) -> Json {
  { "ssa": self.program.to_json() }
}

///|
pub fn Ssa::from_json(json : Json) -> Ssa raise {
  match json {
    { "ssa": program, .. } => Ssa::{ program: Program::from_json(program) }
    _ => fail("invalid json")
  }
}
