///| Preprocesses the syntax tree, extracting the contents of functions `main` and `init` to top-level.
pub fn KnfEnv::syntax_preprocess(
  self : KnfEnv,
  s : @types.Syntax
) -> @types.Syntax {
  match s {
    LetRec(fundef, rest) =>
      match fundef.name.0 {
        "main" | "init" => fundef.body
        _ => LetRec(fundef, syntax_preprocess(self, rest))
      }
    Let((str, ty), s1, s2) => Let((str, ty), s1, syntax_preprocess(self, s2))
    _ => panic()
  }
}
