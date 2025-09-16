///|
/// Preprocesses the syntax tree, extracting the contents of functions `main` and `init` to top-level.
pub fn KnfEnv::syntax_preprocess(
  self : KnfEnv,
  s : @types.Syntax,
) -> @types.Syntax {
  // println("Syntax preprocessing...: " + s.to_string());
  match s {
    LetRec(fundef, rest) =>
      match fundef.name.0 {
        "main" => KnfEnv::syntax_preprocess(self, fundef.body)
        _ => {
          let body = KnfEnv::syntax_preprocess(self, fundef.body)
          LetRec(
            { name: fundef.name, args: fundef.args, body },
            KnfEnv::syntax_preprocess(self, rest),
          )
        }
      }
    Let((str, ty), s1, s2) =>
      match s1 {
        ArrayExpr(elems) => {
          // Check if this is a static array (all elements are constants)
          if KnfEnv::is_static_array(elems) {
            // Generate a unique label for this static array
            
            // Add the array data to the environment
            let array_data = KnfEnv::extract_array_data(elems)
           
            // Create ExternalArray reference
            Let(
              (str, ty),
              ArrayData(str, array_data),
              KnfEnv::syntax_preprocess({
                counter: self.counter,
                externals: self.externals,
              }, s2),
            )
          } else {
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
        }
        Array(len, ArrayExpr(elems)) => {
          let elems_len = elems.length()
          // Create Array::make(len, default_value) where default_value is based on first expr
          let array_make_sub = @types.Syntax::Array(Int(elems_len), elems[0])
          let array_make = @types.Syntax::Array(len, array_make_sub)

          // Process elements in reverse order to build nested Let expressions
          let mut sub_result = array_make
          for i = elems_len - 1; i >= 0; i = i - 1 {
            // Wrap the previous result with this Put operation
            sub_result = Let(("_", Unit), Put(Var(str + "_sub"), Int(i), elems[i]), sub_result)
          }

          
          let sub_ty = match elems[0] {
            Int(_) => @types.Type::Int
            Double(_) => @types.Type::Double
            _ => Ptr
          }
          let sub = @types.Syntax::Let((str + "_sub", Array(sub_ty)), array_make_sub, sub_result)

          Let(
            (str, ty),
            sub,
            KnfEnv::syntax_preprocess(self, s2),
          )
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
    StructConstruct(_, fields) => {
      let result = fields.map(fn(field) {
        match field {
          (_, value) => value
        }
      })
      Tuple(result)
    }
    Struct(name, _, fields, rest) => {
      let env_fun = self.externals.add(
        name,
        UserDefineType(name, { val: fields }),
      )
      KnfEnv::syntax_preprocess(
        { counter: self.counter, externals: env_fun },
        rest,
      )
    }
    Enum(name, _, variants, cont) =>
      Enum(name, "", variants, KnfEnv::syntax_preprocess(self, cont))
    ExternalArray(label) => ExternalArray(label)
    _ => s
  }
}

///|
/// Check if an array is static (all elements are constants)
fn KnfEnv::is_static_array(elems : Array[@types.Syntax]) -> Bool {
  for elem in elems {
    match elem {
      Int(_) | Double(_) | Bool(_) | Neg(_, ..) => ()  // These are constants
      ArrayExpr(sub_elems) => {
        // Recursively check if nested array is static
        if not(KnfEnv::is_static_array(sub_elems)) {
          return false
        }
      }
      _ => return false  // Not a constant
    }
  }
  true
}

///|
/// Extract array data for static arrays
fn KnfEnv::extract_array_data(elems : Array[@types.Syntax]) -> Array[@types.Syntax] {
  elems
}

///|
/// Process 1D array (original logic)
fn KnfEnv::process_1d_array(
  self : KnfEnv,
  str : String,
  ty : @types.Type,
  elems : Array[@types.Syntax],
  s2 : @types.Syntax,
) -> @types.Syntax {
  let len = elems.length()
  // Create Array::make(len, default_value) where default_value is based on first expr
  let array_make = @types.Syntax::Array(Int(len), elems[0])

  // Build the nested structure from inside out
  // Start with the innermost expression
  let mut result = KnfEnv::syntax_preprocess(self, s2)

  // Process elements in reverse order to build nested Let expressions
  for i = len - 1; i >= 0; i = i - 1 {
    // Wrap the previous result with this Put operation
    result = Let(("_", Unit), Put(Var(str), Int(i), elems[i]), result)
  }
  Let((str, ty), array_make, result)
}

///|
/// Process multidimensional array
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
    let (sub_array_ty, temp_var_name) = match ty {
      Array(inner_ty) =>
        (inner_ty, @types.Syntax::Var(str + "_sub_" + i.to_string()))
      _ => (ty, sub_elem)
    }
    let processed_sub_array = match sub_elem {
      ArrayExpr(sub_elems) =>
        KnfEnv::process_multidimensional_array(
          self,
          str + "_sub_" + i.to_string(),
          sub_array_ty,
          sub_elems,
          temp_var_name,
        )
      _ => sub_elem
    }
    // Wrap the result with the sub-array processing and Put operation
    result = match processed_sub_array {
      Let((temp_name, temp_ty), temp_init, _) =>
        // Replace the placeholder with Put operation
        Let(
          (temp_name, temp_ty),
          temp_init,
          Let(("_", Unit), Put(Var(str), Int(i), processed_sub_array), result),
        )
      _ => Let(("_", Unit), Put(Var(str), Int(i), processed_sub_array), result)
    }
  }
  let first_subarray_expr = match elems[0] {
    ArrayExpr(sub_elems) => {
      let sub_len = sub_elems.length()
      @types.Syntax::Array(@types.Syntax::Int(sub_len), sub_elems[0])
    }
    _ => elems[0]
  }
  let len_expr = @types.Syntax::Int(len)
  let outer_array_make = @types.Syntax::Array(len_expr, first_subarray_expr)
  Let((str, ty), outer_array_make, result)
}
