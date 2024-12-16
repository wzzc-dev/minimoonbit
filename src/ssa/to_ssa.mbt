///|
pub fn to_ssa(input : @closure.Program) -> Ssa {
  let mut result = "";
  for fundef in input.fundefs {
    if not(@util.extenv.contains(fundef.old_name.to_string())) {
      println("fundef: " + fundef.to_string()) 
      result += fundef.to_string()
    }
  }
  println("minimbt_main: " + input.body.to_string())
  result += input.body.to_string()
  { ssa: result }
}