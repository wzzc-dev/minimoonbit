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
          // Check if this is a multidimensional array by examining first element
          let is_multidimensional = match elems[0] {
            ArrayExpr(_) => true
            _ => false
          }
          if is_multidimensional {
            // Handle multidimensional array
            KnfEnv::process_multidimensional_array(self, str, ty, elems, s2)
          } else {
            // Handle 1D array (original logic)
            KnfEnv::process_1d_array(self, str, ty, elems, s2)
          }
        }
        _ =>
          Let(
            (str, ty),
            KnfEnv::syntax_preprocess(self, s1),
            KnfEnv::syntax_preprocess(self, s2),
          )
      }
    LetTuple(arr, s1, s2) =>
      LetTuple(
        arr,
        KnfEnv::syntax_preprocess(self, s1),
        KnfEnv::syntax_preprocess(self, s2),
      )
    _ => s
  }
}

///| Process 1D array (original logic)
fn KnfEnv::process_1d_array(
  self : KnfEnv,
  str : String,
  ty : @types.Type,
  elems : Array[@types.Syntax],
  s2 : @types.Syntax,
) -> @types.Syntax {
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
    let put_expr = @types.Syntax::Put(@types.Syntax::Var(str), index_expr, elem)

    // Wrap the previous result with this Put operation
    result = Let(("_", Unit), put_expr, result)
  }
  Let((str, ty), array_make, result)
}

///| Process multidimensional array
fn KnfEnv::process_multidimensional_array(
  self : KnfEnv,
  str : String,
  ty : @types.Type,
  elems : Array[@types.Syntax],
  s2 : @types.Syntax,
) -> @types.Syntax {
  let len = elems.length()
  
  let mut result = KnfEnv::syntax_preprocess(self, s2)

  for i = len - 1; i >= 0; i = i - 1 {
    let sub_elem = elems[i]

    let (sub_array_ty,temp_var_name) = match ty {
      Array(inner_ty) => (inner_ty, @types.Syntax::Var(str + "_sub_" + i.to_string()))
      _ => (ty,sub_elem)
    }

    let processed_sub_array = match sub_elem {
      ArrayExpr(sub_elems) => {
        KnfEnv::process_multidimensional_array(
          self,
          str + "_sub_" + i.to_string(),
          sub_array_ty,
          sub_elems,
          temp_var_name,
        )
      }
      _ => sub_elem
    }
    // Create index expression: i
    let index_expr = @types.Syntax::Int(i)

    // Create Put expression: Put(outer_array, i, temp_var)
    let put_expr = @types.Syntax::Put(
      @types.Syntax::Var(str),
      index_expr,
      processed_sub_array,
    )
    // Wrap the result with the sub-array processing and Put operation
    result = match processed_sub_array {
      Let((temp_name, temp_ty), temp_init, _) =>
        // Replace the placeholder with Put operation
        Let((temp_name, temp_ty), temp_init, Let(("_", Unit), put_expr, result))
      _ => Let(("_", Unit), put_expr, result)
    }
  }

  let first_subarray_expr = match elems[0] {
    ArrayExpr(sub_elems) => {
      let sub_len = sub_elems.length()
      @types.Syntax::Array(@types.Syntax::Int(sub_len), sub_elems[0])
    }
    _ => {
      elems[0]
    }
  }

  let len_expr = @types.Syntax::Int(len)
  let outer_array_make = @types.Syntax::Array(len_expr, first_subarray_expr)

  Let((str, ty), outer_array_make, result)
}
