///| Preprocesses the syntax tree, extracting the contents of functions `main` and `init` to top-level.
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
          LetRec({ name: fundef.name, args: fundef.args, body: body }, KnfEnv::syntax_preprocess(self, rest))
        }
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
    Put(arr, idx, v, rest) => {
      Put(arr, idx, v, KnfEnv::syntax_preprocess(self, rest))
    }
    StructConstruct(_, fields) => {
      let result = fields.map(fn(field) {
        match field {
          (_, value) => value
        }
      })
      Tuple(result)
    }
    Struct(name, _, fields, rest) => {
      let env_fun = self.externals.add(name, UserDefineType(name, {val: fields}))
      KnfEnv::syntax_preprocess({ counter: self.counter, externals: env_fun }, rest)
    }
    Enum(name, _, variants, cont) => {
      let variants = variants.map(fn(variant) {
        match variant {
          (name, ty) => (name, @types.Type::Tuple(ty))
        }
      })
      let env_fun = self.externals.add(name, UserDefineType(name, {val: variants}))
      KnfEnv::syntax_preprocess({ counter: self.counter, externals: env_fun }, cont)
    }
    // EnumConstruct(_name, variant) => {
    //   Tuple(variant)
    // }
    If(cond, then, else_) => {
      let cond = match cond {
        Eq(s1, s2) => @types.Syntax::Eq(KnfEnv::syntax_preprocess(self, s1), KnfEnv::syntax_preprocess(self, s2))
        _ => cond
      }
      If(cond, KnfEnv::syntax_preprocess(self, then), KnfEnv::syntax_preprocess(self, else_))
    }
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
    // Wrap the previous result with this Put operation
    result = Put(Var(str), Int(i), elems[i], result)
  }
  fn get_array_ty(ty : @types.Type) -> @types.Type {
    match ty {
      Array(ty) => get_array_ty(ty)
      _ => ty
    }
  }
  let ty = get_array_ty(ty)
  
  Let((str, Array(ty)), array_make, result)
}

///| Process multidimensional array by flattening to 1D array
fn KnfEnv::process_multidimensional_array(
  self : KnfEnv,
  str : String,
  ty : @types.Type,
  elems : Array[@types.Syntax],
  s2 : @types.Syntax,
) -> @types.Syntax {
  // Flatten the multidimensional array to 1D
  let (flattened_elements, _dims) = KnfEnv::flatten_multidimensional_array(elems)
  // Process as a 1D array
  KnfEnv::process_1d_array(self, str, ty, flattened_elements, s2)
}

///| Flatten multidimensional array to 1D array
fn KnfEnv::flatten_multidimensional_array(
  elems : Array[@types.Syntax]
) -> (Array[@types.Syntax], Array[Int]) {
  let result : Array[@types.Syntax] = []
  let dims : Array[Int] = []
  dims.push(elems.length())
  for elem in elems {
    match elem {
      ArrayExpr(sub_elems) => {
        // Recursively flatten sub-arrays
        let (flattened_sub, sub_dims) = KnfEnv::flatten_multidimensional_array(sub_elems)
        for sub_elem in flattened_sub {
          result.push(sub_elem)
        }
        dims.append(sub_dims)
      }
      _ => {
        // Add non-array elements directly
        result.push(elem)
      }
    }
  }
  (result, dims)
}