
///|
pub fn Ssa::to_json(self : Ssa) -> Json {
  {
    "ssa": self.ssa.to_json(),
  }
}

///|
pub fn Ssa::from_json(json : Json) -> Ssa! {
  match json {
    { "ssa": ssa, ..} => {
      
      { ssa: ssa.to_string() }
    }
    _ => fail!("invalid json")
  }
}
