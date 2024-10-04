fn unify(t1 : @types.Type, t2: @types.Type) -> Unit {
}

type LocalCtx @immut/sorted_map.T[String,@types.Type]
fn infer(ctx: LocalCtx, e: @types.Syntax) -> @types.Type{
  @types.Type::Unit
}

fn deref_type(t: @types.Type) -> @types.Type {
  @types.Type::Unit
}
fn deref_syntax(syntax: @types.Syntax) -> @types.Syntax{
  @types.Syntax::Unit
}
pub let extenv : Map[String,@types.Type] = {
  "read_int" : Fun([],Unit),
  "print_int" : Fun([Int],Unit),
  "read_char" : Fun([],Int),
  "print_char" : Fun([Int],Unit),
  "print_newline" : Fun([],Unit),
  "int_of_float" : Fun([Double],Int),
  "float_of_int" : Fun([Int],Double),
  "truncate" : Fun([Double],Int),
  "floor" : Fun([Double],Double),
  "abs_float" : Fun([Double],Double),
  "sqrt" : Fun([Double],Double),
  "sin" : Fun([Double],Double),
  "cos" : Fun([Double],Double),
  "atan" : Fun([Double],Double),
}
pub fn typing(e: @types.Syntax) -> @types.Syntax {
  unify(Unit, infer(@immut/sorted_map.empty(),e))
  for ext_f,ext_t in extenv {
    extenv[ext_f] = deref_type(ext_t)
  }
  deref_syntax(e)
}