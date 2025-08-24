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
  // @util.logger("Processing multidimensional array...")
  let len = elems.length()

  // For multidimensional arrays, we need to:
  // 1. Create the outer array with appropriate size
  // 2. Process each inner array element recursively
  // 3. Assign each processed inner array to the outer array

  // Get the first sub-array to determine inner array structure
  let first_subarray_expr = match elems[0] {
    ArrayExpr(sub_elems) => {
      let sub_len = sub_elems.length()
      let sub_ty = sub_elems[0] // Type of elements in sub-array
      @types.Syntax::Array(@types.Syntax::Int(sub_len), sub_ty)
    }
    _ => @util.die("Expected ArrayExpr for multidimensional array element")
  }

  // Create the outer array: Array::make(len, default_inner_array)
  let len_expr = @types.Syntax::Int(len)
  let outer_array_make = @types.Syntax::Array(len_expr, first_subarray_expr)

  // Start with the final expression
  let mut result = KnfEnv::syntax_preprocess(self, s2)

  // Process each sub-array in reverse order
  for i = len - 1; i >= 0; i = i - 1 {
    let sub_array = elems[i]

    // Generate a unique temporary variable name for this sub-array
    let temp_var_name = str + "_sub_" + i.to_string()

    // Process the sub-array - it could be 1D or further nested
    let processed_sub_array = match sub_array {
      ArrayExpr(sub_elems) => {
        // Determine the type of the sub-array
        let sub_array_ty = match ty {
          Array(inner_ty) => inner_ty
          _ => @util.die("Expected Array type for multidimensional array")
        }

        // Check if sub-array is also multidimensional
        let is_sub_multidimensional = match sub_elems[0] {
          ArrayExpr(_) => true
          _ => false
        }
        if is_sub_multidimensional {
          // Recursively handle nested multidimensional arrays
          KnfEnv::process_multidimensional_array(
            self,
            temp_var_name,
            sub_array_ty,
            sub_elems,
            @types.Syntax::Var(temp_var_name),
          )
        } else {
          // Handle 1D sub-array
          KnfEnv::process_1d_array(
            self,
            temp_var_name,
            sub_array_ty,
            sub_elems,
            @types.Syntax::Var(temp_var_name),
          )
        }
      }
      _ => @util.die("Expected ArrayExpr for multidimensional array element")
    }

    // Create index expression: i
    let index_expr = @types.Syntax::Int(i)

    // Create Put expression: Put(outer_array, i, temp_var)
    let put_expr = @types.Syntax::Put(
      @types.Syntax::Var(str),
      index_expr,
      @types.Syntax::Var(temp_var_name),
    )

    // Wrap the result with the sub-array processing and Put operation
    result = match processed_sub_array {
      Let((temp_name, temp_ty), temp_init, _) =>
        // Replace the placeholder with Put operation
        Let((temp_name, temp_ty), temp_init, Let(("_", Unit), put_expr, result))
      _ => Let(("_", Unit), put_expr, result)
    }
  }
  Let((str, ty), outer_array_make, result)
}
