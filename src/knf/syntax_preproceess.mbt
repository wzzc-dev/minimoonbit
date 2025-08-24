///| Preprocesses the syntax tree, extracting the contents of functions `main` and `init` to top-level.
pub fn KnfEnv::syntax_preprocess(
  self : KnfEnv,
  s : @types.Syntax,
) -> @types.Syntax {
  // println("Syntax preprocessing...");
  match s {
    LetRec(fundef, rest) =>
      match fundef.name.0 {
        "main" => KnfEnv::syntax_preprocess(self, fundef.body)
        _ => LetRec(fundef, KnfEnv::syntax_preprocess(self, rest))
      }
    Let((str, ty), s1, s2) =>
      match s1 {
        ArrayExpr(elems) => {
          let len = elems.length()

          // Create Array::make(len, default_value) where default_value is based on first expr
          let len_expr = @types.Syntax::Int(len)
          let arr_ty = elems[0]
          let array_make = @types.Syntax::Array(len_expr, arr_ty)

          // Build the nested structure from inside out
          // Start with the innermost expression
          let mut result = KnfEnv::syntax_preprocess(self, s2)

          // Process elements in reverse order to build nested Let expressions
          for i = len - 1; i >= 0; i = i - 1 {
            let elem = elems[i]

            // Create index expression: i
            let index_expr = @types.Syntax::Int(i)

            // Create Put expression: Put(arr, i, actual_element)
            let put_expr = @types.Syntax::Put(
              @types.Syntax::Var(str),
              index_expr,
              elem,
            )

            // Wrap the previous result with this Put operation
            result = Let(("_", Unit), put_expr, result)
          }
          Let((str, ty), array_make, result)
        }
        _ =>
          Let(
            (str, ty),
            KnfEnv::syntax_preprocess(self, s1),
            KnfEnv::syntax_preprocess(self, s2),
          )
      }
    _ => s
  }
}
