///|
/// Generate fresh name for alpha conversion
fn KnfEnv::generate_fresh_name(
  self : KnfEnv,
  rho : @immut/hashmap.HashMap[Name, Name],
  original_name : Name,
) -> Name {
  // Check if original name is already mapped in rho
  if !rho.contains(original_name) {
    return original_name
  }
  // Generate fresh name by appending suffix to original name
  match original_name.name {
    Some(_) => self.new_name("alpha_" + original_name.to_string())
    None => self.new_temp()
  }
}

///|
/// Enhanced KNF optimization with multiple passes
pub fn KnfEnv::opt_pass(self : KnfEnv, knf : Knf) -> Knf {
  // Apply optimizations in sequence
  let optimized = knf
  let optimized = self.alpha_conversion(
    @immut/hashmap.HashMap::new(),
    optimized,
  )
  // β-Reduction
  let optimized = self.beta_reduction(optimized)
  let optimized = self.nested_let_reduction(optimized)
  let optimized = self.let_inlining(optimized)
  let optimized = self.constant_folding_and_unused_variable_elimination_with_env(
    @immut/hashmap.HashMap::new(),
    optimized,
  )
  optimized
}

///|
/// α-conversion: rename bound variables to avoid name conflicts
/// ρ: mapping from old names to fresh names
fn KnfEnv::alpha_conversion(
  self : KnfEnv,
  rho : @immut/hashmap.HashMap[Name, Name],
  knf : Knf,
) -> Knf {
  match knf {
    // Constants - no variables to rename
    Unit => Unit
    Int(_) => knf
    Int64(_) => knf
    Double(_) => knf
    Bool(_) => knf

    // Unary operations
    Neg(x) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      Neg(new_x)
    }
    FNeg(x) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      FNeg(new_x)
    }

    // Binary operations
    Add(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      Add(new_x, new_y)
    }
    Sub(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      Sub(new_x, new_y)
    }
    Mul(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      Mul(new_x, new_y)
    }
    Div(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      Div(new_x, new_y)
    }
    Mod(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      Mod(new_x, new_y)
    }
    FAdd(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      FAdd(new_x, new_y)
    }
    FSub(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      FSub(new_x, new_y)
    }
    FMul(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      FMul(new_x, new_y)
    }
    FDiv(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      FDiv(new_x, new_y)
    }
    FMod(x, y) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      FMod(new_x, new_y)
    }

    // Variable reference - core of alpha conversion
    Var(x) => if rho.contains(x) { Var(rho.get(x).unwrap()) } else { knf }

    // Conditional expressions
    IfEq(x, y, then_branch, else_branch) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      let new_then = self.alpha_conversion(rho, then_branch)
      let new_else = self.alpha_conversion(rho, else_branch)
      IfEq(new_x, new_y, new_then, new_else)
    }
    IfLe(x, y, then_branch, else_branch) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      let new_then = self.alpha_conversion(rho, then_branch)
      let new_else = self.alpha_conversion(rho, else_branch)
      IfLe(new_x, new_y, new_then, new_else)
    }
    IfLt(x, y, then_branch, else_branch) => {
      let new_x = if rho.contains(x) { rho.get(x).unwrap() } else { x }
      let new_y = if rho.contains(y) { rho.get(y).unwrap() } else { y }
      let new_then = self.alpha_conversion(rho, then_branch)
      let new_else = self.alpha_conversion(rho, else_branch)
      IfLt(new_x, new_y, new_then, new_else)
    }

    // Let binding - introduce new mapping
    Let((x, x_ty), e, m) => {
      // Generate fresh name for bound variable x
      let fresh_x = self.generate_fresh_name(rho, x)
      // Extend mapping: old name x -> fresh name fresh_x
      let extended_rho = rho.add(x, fresh_x)
      // Convert expression e with extended mapping (x is in scope)
      let new_e = self.alpha_conversion(rho, e)
      // Convert body m with original mapping (x is not in scope)
      let new_m = self.alpha_conversion(extended_rho, m)
      Let((fresh_x, x_ty), new_e, new_m)
    }

    // Recursive function binding
    LetRec(func, m) => {
      // For simplicity, keep original args but build parameter mapping
      let new_args = []
      let mut param_rho = rho
      for name_ty in func.args {
        let (param_name, param_ty) = name_ty
        let fresh_param_name = self.generate_fresh_name(rho, param_name)
        new_args.push((fresh_param_name, param_ty))
        param_rho = param_rho.add(param_name, fresh_param_name)
      }
      // For simplicity, we'll use the same approach as original code
      // but with fresh names for parameters
      let new_body = self.alpha_conversion(param_rho, func.body)
      // Create new function definition
      let new_func = {
        name: func.name,
        ty: func.ty,
        args: new_args,
        body: new_body,
      }
      // Convert the rest of the program with function name in scope
      let extended_rho = rho.add(func.name, func.name)
      let new_m = self.alpha_conversion(extended_rho, m)
      LetRec(new_func, new_m)
    }
    LetTuple(xs, tuple_expr, m) => {
      // For simplicity, keep original xs but build tuple mapping
      let new_xs = []
      let mut tuple_rho = rho
      for name_ty in xs {
        let (x, ty) = name_ty
        let fresh_x = self.generate_fresh_name(rho, x)
        new_xs.push((fresh_x, ty))
        tuple_rho = tuple_rho.add(x, fresh_x)
      }

      // Convert tuple expression with original mapping
      let new_tuple_expr = if rho.contains(tuple_expr) {
        rho.get(tuple_expr).unwrap()
      } else {
        tuple_expr
      }

      // Convert body m with tuple variables in scope
      // For simplicity, just use tuple_rho for now
      let new_m = self.alpha_conversion(tuple_rho, m)
      LetTuple(new_xs, new_tuple_expr, new_m)
    }
    // Function application
    Apply(f, args) => {
      let new_f = if rho.contains(f) { rho.get(f).unwrap() } else { f }
      let new_args = args.map(arg => if rho.contains(arg) {
        rho.get(arg).unwrap()
      } else {
        arg
      })
      Apply(new_f, new_args)
    }

    // Tuple operations
    Tuple(xs) => {
      let new_xs = xs.map(x => if rho.contains(x) {
        rho.get(x).unwrap()
      } else {
        x
      })
      Tuple(new_xs)
    }

    // Field access and array operations
    FieldAccess(obj, field_ty, field_idx) => {
      let new_obj = if rho.contains(obj) { rho.get(obj).unwrap() } else { obj }
      FieldAccess(new_obj, field_ty, field_idx)
    }
    Get(array, index) => {
      let new_array = if rho.contains(array) {
        rho.get(array).unwrap()
      } else {
        array
      }
      let new_index = if rho.contains(index) {
        rho.get(index).unwrap()
      } else {
        index
      }
      Get(new_array, new_index)
    }
    Put(array, index, value) => {
      let new_array = if rho.contains(array) {
        rho.get(array).unwrap()
      } else {
        array
      }
      let new_index = if rho.contains(index) {
        rho.get(index).unwrap()
      } else {
        index
      }
      let new_value = if rho.contains(value) {
        rho.get(value).unwrap()
      } else {
        value
      }
      Put(new_array, new_index, new_value)
    }

    // External operations
    ExternalArray(_) => knf
    ExternalFunctionApplication(name, args) => {
      let new_args = args.map(arg => if rho.contains(arg) {
        rho.get(arg).unwrap()
      } else {
        arg
      })
      ExternalFunctionApplication(name, new_args)
    }
    ArrayData(name, elements) => {
      let new_elements = elements.map(elem => self.alpha_conversion(rho, elem))
      ArrayData(name, new_elements)
    }

    // While loop
    While(condition, body) => {
      let new_condition = self.alpha_conversion(rho, condition)
      let new_body = self.alpha_conversion(rho, body)
      While(new_condition, new_body)
    }

    // Assignment
    Assign(lhs, rhs) => {
      let new_lhs = if rho.contains(lhs) { rho.get(lhs).unwrap() } else { lhs }
      let new_rhs = if rho.contains(rhs) { rho.get(rhs).unwrap() } else { rhs }
      Assign(new_lhs, new_rhs)
    }
  }
}

///|
/// Simple substitution: replace all occurrences of old_name with new_name
fn KnfEnv::substitute_simple(
  self : KnfEnv,
  new_name : Name,
  old_name : Name,
  knf : Knf,
) -> Knf {
  match knf {
    // Constants - no substitution needed
    Unit => Unit
    Int(_) => knf
    Int64(_) => knf
    Double(_) => knf
    Bool(_) => knf
    ExternalArray(_) => knf

    // Variable reference - substitute if matches old_name
    Var(x) => if x.name == old_name.name { Var(new_name) } else { knf }

    // Unary operations - substitute in operands (x is a Name)
    Neg(x) => Neg(if x.name == old_name.name { new_name } else { x })
    FNeg(x) => FNeg(if x.name == old_name.name { new_name } else { x })

    // Binary operations - substitute in operands
    Add(x, y) =>
      Add(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    Sub(x, y) =>
      Sub(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    Mul(x, y) =>
      Mul(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    Div(x, y) =>
      Div(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    Mod(x, y) =>
      Mod(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    FAdd(x, y) =>
      FAdd(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    FSub(x, y) =>
      FSub(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    FMul(x, y) =>
      FMul(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    FDiv(x, y) =>
      FDiv(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )
    FMod(x, y) =>
      FMod(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
      )

    // Conditional expressions - substitute in operands and recurse in branches
    IfEq(x, y, then_branch, else_branch) =>
      IfEq(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
        self.substitute_simple(new_name, old_name, then_branch),
        self.substitute_simple(new_name, old_name, else_branch),
      )
    IfLe(x, y, then_branch, else_branch) =>
      IfLe(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
        self.substitute_simple(new_name, old_name, then_branch),
        self.substitute_simple(new_name, old_name, else_branch),
      )
    IfLt(x, y, then_branch, else_branch) =>
      IfLt(
        if x.name == old_name.name {
          new_name
        } else {
          x
        },
        if y.name == old_name.name {
          new_name
        } else {
          y
        },
        self.substitute_simple(new_name, old_name, then_branch),
        self.substitute_simple(new_name, old_name, else_branch),
      )

    // Let bindings - substitute in expression and body (but skip bound variable)
    Let((x, x_ty), e, body) => {
      let new_e = self.substitute_simple(new_name, old_name, e)
      let new_body = if x.name == old_name.name {
        // Don't substitute in body if x is the variable being replaced (capture avoiding)
        body
      } else {
        self.substitute_simple(new_name, old_name, body)
      }
      Let((x, x_ty), new_e, new_body)
    }

    // Function applications
    Apply(f, args) => {
      let new_f = if f.name == old_name.name { new_name } else { f }
      let new_args = args.map(arg => if arg.name == old_name.name {
        new_name
      } else {
        arg
      })
      Apply(new_f, new_args)
    }

    // Tuple operations
    Tuple(xs) =>
      Tuple(xs.map(x => if x.name == old_name.name { new_name } else { x }))
    Get(array, index) =>
      Get(
        if array.name == old_name.name {
          new_name
        } else {
          array
        },
        if index.name == old_name.name {
          new_name
        } else {
          index
        },
      )
    Put(array, index, value) =>
      Put(
        if array.name == old_name.name {
          new_name
        } else {
          array
        },
        if index.name == old_name.name {
          new_name
        } else {
          index
        },
        if value.name == old_name.name {
          new_name
        } else {
          value
        },
      )

    // Other operations
    FieldAccess(obj, field_ty, field_idx) =>
      FieldAccess(
        if obj.name == old_name.name {
          new_name
        } else {
          obj
        },
        field_ty,
        field_idx,
      )
    ExternalFunctionApplication(name, args) =>
      ExternalFunctionApplication(
        name,
        args.map(arg => if arg.name == old_name.name { new_name } else { arg }),
      )
    ArrayData(name, elements) =>
      ArrayData(
        name,
        elements.map(elem => self.substitute_simple(new_name, old_name, elem)),
      )
    While(condition, body) =>
      While(
        self.substitute_simple(new_name, old_name, condition),
        self.substitute_simple(new_name, old_name, body),
      )
    Assign(lhs, rhs) =>
      Assign(
        if lhs.name == old_name.name {
          new_name
        } else {
          lhs
        },
        if rhs.name == old_name.name {
          new_name
        } else {
          rhs
        },
      )

    // Complex cases - handle recursively where appropriate
    LetRec(func, m) => {
      let new_m = self.substitute_simple(new_name, old_name, m)
      LetRec(func, new_m)
    }
    LetTuple(xs, tuple_expr, m) => {
      let new_m = self.substitute_simple(new_name, old_name, m)
      LetTuple(xs, tuple_expr, new_m)
    }
  }
}

///|
/// β-Reduction: perform function application and constant folding
fn KnfEnv::beta_reduction(self : KnfEnv, knf : Knf) -> Knf {
  match knf {

    // let x = y in M ⇒ [y/x]M (if y is a variable and x is used once)
    Let((x, x_ty), e, body) => {
      let reduced_e = self.beta_reduction(e)
      let reduced_body = self.beta_reduction(body)

      // Simple implementation: if e is a variable different from x, substitute it
      match reduced_e {
        Var(y) =>
          // Don't substitute if x and y are the same
          if x.name != y.name && !(x_ty is Fun(_)) {
            // Simple substitution - replace all occurrences of x with y in body
            self.substitute_simple(y, x, reduced_body)
          } else {
            Let((x, x_ty), reduced_e, reduced_body)
          }
        _ => Let((x, x_ty), reduced_e, reduced_body)
      }
    }
    While(condition, body) =>
      While(self.beta_reduction(condition), self.beta_reduction(body))

    // Recursive function binding
    LetRec(func, m) => {
      let reduced_body = self.beta_reduction(func.body)
      let reduced_m = self.beta_reduction(m)
      let new_func = {
        name: func.name,
        ty: func.ty,
        args: func.args,
        body: reduced_body,
      }
      LetRec(new_func, reduced_m)
    }
    IfEq(a, b, then_branch, else_branch) =>
      IfEq(
        a,
        b,
        self.beta_reduction(then_branch),
        self.beta_reduction(else_branch),
      )
    IfLe(a, b, then_branch, else_branch) =>
      IfLe(
        a,
        b,
        self.beta_reduction(then_branch),
        self.beta_reduction(else_branch),
      )
    IfLt(a, b, then_branch, else_branch) =>
      IfLt(
        a,
        b,
        self.beta_reduction(then_branch),
        self.beta_reduction(else_branch),
      )
    _ => knf
  }
}

///|
/// Nested "Let" Reduction
fn KnfEnv::nested_let_reduction(self : KnfEnv, knf : Knf) -> Knf {
  match knf {
    // Main optimization: flatten nested Let bindings
    Let((y, y_ty), Let((x, x_ty), m1, m2), m3) =>
      self.nested_let_reduction(
        Let(
          (x, x_ty),
          self.nested_let_reduction(m1),
          Let(
            (y, y_ty),
            self.nested_let_reduction(m2),
            self.nested_let_reduction(m3),
          ),
        ),
      )

    // Conditional expressions - need recursive processing
    IfEq(a, b, then_branch, else_branch) =>
      IfEq(
        a,
        b,
        self.nested_let_reduction(then_branch),
        self.nested_let_reduction(else_branch),
      )
    IfLe(a, b, then_branch, else_branch) =>
      IfLe(
        a,
        b,
        self.nested_let_reduction(then_branch),
        self.nested_let_reduction(else_branch),
      )
    IfLt(a, b, then_branch, else_branch) =>
      IfLt(
        a,
        b,
        self.nested_let_reduction(then_branch),
        self.nested_let_reduction(else_branch),
      )

    // Let binding - recursive processing of subexpressions
    Let((x, x_ty), e, m) => {
      let new_e = self.nested_let_reduction(e)
      let new_m = self.nested_let_reduction(m)
      Let((x, x_ty), new_e, new_m)
    }

    // Recursive function binding
    LetRec(func, m) => {
      let new_body = self.nested_let_reduction(func.body)
      let new_func = {
        name: func.name,
        ty: func.ty,
        args: func.args,
        body: new_body,
      }
      let new_m = self.nested_let_reduction(m)
      LetRec(new_func, new_m)
    }
    LetTuple(xs, tuple_expr, m) => {
      let new_m = self.nested_let_reduction(m)
      LetTuple(xs, tuple_expr, new_m)
    }
    ArrayData(name, elements) => {
      let new_elements = elements.map(elem => self.nested_let_reduction(elem))
      ArrayData(name, new_elements)
    }
    // While loop
    While(condition, body) => {
      let new_condition = self.nested_let_reduction(condition)
      let new_body = self.nested_let_reduction(body)
      While(new_condition, new_body)
    }

    // Constants - no recursive processing needed
    Unit => Unit
    Int(_) => knf
    Int64(_) => knf
    Double(_) => knf
    Bool(_) => knf

    // Unary operations - leaf nodes
    Neg(_) => knf
    FNeg(_) => knf

    // Binary operations - leaf nodes
    Add(_, _) => knf
    Sub(_, _) => knf
    Mul(_, _) => knf
    Div(_, _) => knf
    Mod(_, _) => knf
    FAdd(_, _) => knf
    FSub(_, _) => knf
    FMul(_, _) => knf
    FDiv(_, _) => knf
    FMod(_, _) => knf

    // Variable reference - leaf node
    Var(_) => knf

    // Function application - leaf node (arguments are variables, not expressions)
    Apply(_, _) => knf

    // Tuple operations
    Tuple(_) => knf // tuple elements are variables

    // Field access and array operations - leaf nodes
    FieldAccess(_, _, _) => knf
    Get(_, _) => knf
    Put(_, _, _) => knf

    // External operations
    ExternalArray(_) => knf
    ExternalFunctionApplication(_, _) => knf

    // Assignment - leaf node
    Assign(_, _) => knf
  }
}

///|
/// Check if an expression is simple enough to be inlined
fn is_simple_for_inlining(expr : Knf) -> Bool {
  match expr {
    Var(_) => true
    Unit | Int(_) | Int64(_) | Double(_) | Bool(_) => true
    Neg(_) | FNeg(_) => true
    Add(_, _) | Sub(_, _) | Mul(_, _) | Div(_, _) | Mod(_) => true
    FAdd(_, _) | FSub(_, _) | FMul(_, _) | FDiv(_, _) | FMod(_, _) => true
    Tuple(_) => true
    _ => false  // Too complex for safe inlining
  }
}

///|
/// Estimate expression complexity for inlining decisions
fn expr_inline_complexity(expr : Knf) -> Int {
  match expr {
    Var(_) | Unit | Int(_) | Int64(_) | Double(_) | Bool(_) => 1
    Neg(_) | FNeg(_) => 2
    Add(_, _) | Sub(_, _) | Mul(_, _) | Div(_, _) | Mod(_) => 3
    FAdd(_, _) | FSub(_, _) | FMul(_, _) | FDiv(_, _) | FMod(_, _) => 3
    Tuple(xs) => 1 + Array::length(xs)
    _ => 10  // Complex expressions get high complexity
  }
}

///|
fn KnfEnv::let_inlining(self : KnfEnv, knf : Knf) -> Knf {
  match knf {
    // Constants - no inlining needed
    Unit => Unit
    Int(_) => knf
    Int64(_) => knf
    Double(_) => knf
    Bool(_) => knf

    // Unary operations
    Neg(x) => Neg(x)
    FNeg(x) => FNeg(x)

    // Binary operations
    Add(x, y) => Add(x, y)
    Sub(x, y) => Sub(x, y)
    Mul(x, y) => Mul(x, y)
    Div(x, y) => Div(x, y)
    Mod(x, y) => Mod(x, y)
    FAdd(x, y) => FAdd(x, y)
    FSub(x, y) => FSub(x, y)
    FMul(x, y) => FMul(x, y)
    FDiv(x, y) => FDiv(x, y)
    FMod(x, y) => FMod(x, y)

    // Variable reference
    Var(x) => Var(x)

    // Conditional expressions
    IfEq(a, b, then_branch, else_branch) =>
      IfEq(a, b, self.let_inlining(then_branch), self.let_inlining(else_branch))
    IfLe(a, b, then_branch, else_branch) =>
      IfLe(a, b, self.let_inlining(then_branch), self.let_inlining(else_branch))
    IfLt(a, b, then_branch, else_branch) =>
      IfLt(a, b, self.let_inlining(then_branch), self.let_inlining(else_branch))

    // Let binding - implement inlining optimization
    Let((x, x_ty), e, m) => {
      let optimized_e = self.let_inlining(e)
      let optimized_m = self.let_inlining(m)

      // Check inlining conditions
      let usage_count = self.count_var_usage(x, optimized_m)
      let expr_complexity = expr_inline_complexity(optimized_e)
      let is_simple = is_simple_for_inlining(optimized_e)
      let no_side_effects = !self.has_side_effects(optimized_e)

      // Inline conditions:
      // 1. Simple expression used once (always inline)
      // 2. Very simple expression (constant/var) used multiple times
      // 3. No side effects, low complexity
      if (is_simple && usage_count == 1 && no_side_effects) ||
         (is_simple_for_inlining(optimized_e) && usage_count <= 3) ||
         (no_side_effects && expr_complexity <= 5) {

        // Perform substitution based on expression type
        match optimized_e {
          Var(y) => {
            if x_ty is Fun(_, _) {
              // Function type - don't inline variables
              Let((x, x_ty), optimized_e, optimized_m)
            } else {
              // Simple variable substitution
              self.substitute_simple(y, x, optimized_m)
            }
          }
          Unit | Int(_) | Int64(_) | Double(_) | Bool(_) => {
            // For constants, use the existing constant folding mechanism
            // Don't inline here, let constant folding handle it
            Let((x, x_ty), optimized_e, optimized_m)
          }
          _ => {
            // Complex expression - be conservative and don't inline to avoid capture issues
            Let((x, x_ty), optimized_e, optimized_m)
          }
        }
      } else {
        // Don't inline, keep the let binding
        Let((x, x_ty), optimized_e, optimized_m)
      }
    }

    // Recursive function binding
    LetRec(func, m) => {
      let new_body = self.let_inlining(func.body)
      let new_func = {
        name: func.name,
        ty: func.ty,
        args: func.args,
        body: new_body,
      }
      let new_m = self.let_inlining(m)
      LetRec(new_func, new_m)
    }

    // Function application
    Apply(f, args) => Apply(f, args)

    // Tuple operations
    Tuple(xs) => Tuple(xs)
    LetTuple(xs, tuple_expr, m) => {
      let new_m = self.let_inlining(m)
      LetTuple(xs, tuple_expr, new_m)
    }

    // Field access and array operations
    FieldAccess(obj, field_ty, field_idx) =>
      FieldAccess(obj, field_ty, field_idx)
    Get(array, index) => Get(array, index)
    Put(array, index, value) => Put(array, index, value)

    // External operations
    ExternalArray(_) => knf
    ExternalFunctionApplication(name, args) =>
      ExternalFunctionApplication(name, args)
    ArrayData(name, elements) => {
      let new_elements = elements.map(elem => self.let_inlining(elem))
      ArrayData(name, new_elements)
    }

    // While loop
    While(condition, body) => {
      let new_condition = self.let_inlining(condition)
      let new_body = self.let_inlining(body)
      While(new_condition, new_body)
    }

    // Assignment
    Assign(lhs, rhs) => Assign(lhs, rhs)
  }
}

///|
/// Check if a KNF expression is a constant and extract its value if possible
fn is_constant_expr(expr : Knf) -> Knf? {
  match expr {
    Unit => Some(Unit)
    Int(i) => Some(Int(i))
    Int64(i) => Some(Int64(i))
    Double(d) => Some(Double(d))
    Bool(b) => Some(Bool(b))
    _ => None
  }
}

///|
/// Check if a variable is bound to a constant in the current environment
fn lookup_constant(
  env : @immut/hashmap.HashMap[Name, Knf],
  var_name : Name,
) -> Knf? {
  env.get(var_name)
}

///|
/// Evaluate binary operation on constants
fn KnfEnv::eval_binary_op(
  self : KnfEnv,
  op : String,
  left : Knf,
  right : Knf,
) -> Knf {
  match (op, left, right) {
    // Integer operations
    ("add", Int(l), Int(r)) => Int(l + r)
    ("sub", Int(l), Int(r)) => Int(l - r)
    ("mul", Int(l), Int(r)) => Int(l * r)
    ("div", Int(l), Int(r)) =>
      if r != 0 {
        Int(l / r)
      } else {
        Div(self.new_temp(), self.new_temp())
      } // Keep original if division by zero
    ("mod", Int(l), Int(r)) =>
      if r != 0 {
        Int(l % r)
      } else {
        Mod(self.new_temp(), self.new_temp())
      }

    // Int64 operations
    ("add", Int64(l), Int64(r)) => Int64(l + r)
    ("sub", Int64(l), Int64(r)) => Int64(l - r)
    ("mul", Int64(l), Int64(r)) => Int64(l * r)
    ("div", Int64(l), Int64(r)) =>
      if r != 0L {
        Int64(l / r)
      } else {
        Div(self.new_temp(), self.new_temp())
      }
    ("mod", Int64(l), Int64(r)) =>
      if r != 0L {
        Int64(l % r)
      } else {
        Mod(self.new_temp(), self.new_temp())
      }

    // Float operations
    ("fadd", Double(l), Double(r)) => Double(l + r)
    ("fsub", Double(l), Double(r)) => Double(l - r)
    ("fmul", Double(l), Double(r)) => Double(l * r)
    ("fdiv", Double(l), Double(r)) => Double(l / r)
    ("fmod", Double(l), Double(r)) => Double(l % r)

    // Fallback - return original operation
    (_, _, _) =>
      match op {
        "add" => Add(self.new_temp(), self.new_temp())
        "sub" => Sub(self.new_temp(), self.new_temp())
        "mul" => Mul(self.new_temp(), self.new_temp())
        "div" => Div(self.new_temp(), self.new_temp())
        "mod" => Mod(self.new_temp(), self.new_temp())
        "fadd" => FAdd(self.new_temp(), self.new_temp())
        "fsub" => FSub(self.new_temp(), self.new_temp())
        "fmul" => FMul(self.new_temp(), self.new_temp())
        "fdiv" => FDiv(self.new_temp(), self.new_temp())
        "fmod" => FMod(self.new_temp(), self.new_temp())
        _ => Unit // fallback
      }
  }
}

///|
/// Evaluate unary operation on constants
fn KnfEnv::eval_unary_op(self : KnfEnv, op : String, operand : Knf) -> Knf {
  match (op, operand) {
    ("neg", Int(i)) => Int(-i)
    ("neg", Int64(i)) => Int64(-i)
    ("fneg", Double(d)) => Double(-d)
    _ =>
      match op {
        "neg" => Neg(self.new_temp())
        "fneg" => FNeg(self.new_temp())
        _ => Unit // fallback
      }
  }
}

///|
/// Evaluate conditional expression on constants
fn KnfEnv::eval_conditional(
  self : KnfEnv,
  left : Knf,
  right : Knf,
  then_branch : Knf,
  else_branch : Knf,
  op : String,
) -> Knf {
  match (op, left, right) {
    ("ifeq", Int(l), Int(r)) => if l == r { then_branch } else { else_branch }
    ("ifeq", Int64(l), Int64(r)) =>
      if l == r {
        then_branch
      } else {
        else_branch
      }
    ("ifeq", Double(l), Double(r)) =>
      if l == r {
        then_branch
      } else {
        else_branch
      }
    ("ifeq", Bool(l), Bool(r)) => if l == r { then_branch } else { else_branch }
    ("ifle", Int(l), Int(r)) => if l <= r { then_branch } else { else_branch }
    ("ifle", Int64(l), Int64(r)) =>
      if l <= r {
        then_branch
      } else {
        else_branch
      }
    ("ifle", Double(l), Double(r)) =>
      if l <= r {
        then_branch
      } else {
        else_branch
      }
    ("ifle", Bool(l), Bool(r)) =>
      if !l || r {
        then_branch
      } else {
        else_branch
      } // logical implication
    ("iflt", Int(l), Int(r)) => if l < r { then_branch } else { else_branch }
    ("iflt", Int64(l), Int64(r)) =>
      if l < r {
        then_branch
      } else {
        else_branch
      }
    ("iflt", Double(l), Double(r)) =>
      if l < r {
        then_branch
      } else {
        else_branch
      }
    _ =>
      match op {
        "ifeq" =>
          IfEq(self.new_temp(), self.new_temp(), then_branch, else_branch)
        "ifle" =>
          IfLe(self.new_temp(), self.new_temp(), then_branch, else_branch)
        "iflt" =>
          IfLt(self.new_temp(), self.new_temp(), then_branch, else_branch)
        _ => Unit // fallback
      }
  }
}

///|
/// Check if a variable is assigned to within a KNF expression
fn KnfEnv::is_var_assigned(self : KnfEnv, var_name : Name, expr : Knf) -> Bool {
  match expr {
    Unit | Int(_) | Int64(_) | Double(_) | Bool(_) => false
    Var(_) => false
    Neg(_) | FNeg(_) => false
    Add(_, _) | Sub(_, _) | Mul(_, _) | Div(_, _) | Mod(_, _) => false
    FAdd(_, _) | FSub(_, _) | FMul(_, _) | FDiv(_, _) | FMod(_, _) => false
    FieldAccess(_, _, _) => false
    Get(_, _) => false
    Put(_, _, _) => false
    ExternalArray(_) => false
    ExternalFunctionApplication(_, _) => false

    Assign(lhs, _) => lhs == var_name

    IfEq(_, _, then_branch, else_branch) =>
      self.is_var_assigned(var_name, then_branch) || self.is_var_assigned(var_name, else_branch)
    IfLe(_, _, then_branch, else_branch) =>
      self.is_var_assigned(var_name, then_branch) || self.is_var_assigned(var_name, else_branch)
    IfLt(_, _, then_branch, else_branch) =>
      self.is_var_assigned(var_name, then_branch) || self.is_var_assigned(var_name, else_branch)

    Let((x, _), e, body) => {
      let e_assigned = self.is_var_assigned(var_name, e)
      let body_assigned = if x == var_name {
        // Don't look in body if this binding shadows our variable
        false
      } else {
        self.is_var_assigned(var_name, body)
      }
      e_assigned || body_assigned
    }

    LetRec(func, m) =>
      self.is_var_assigned(var_name, func.body) || self.is_var_assigned(var_name, m)
    Apply(_, _) => false
    Tuple(_) => false
    LetTuple(_, _, m) => self.is_var_assigned(var_name, m)
    ArrayData(_, elements) => {
      for elem in elements {
        if self.is_var_assigned(var_name, elem) {
          return true
        }
      }
      false
    }
    While(condition, body) =>
      self.is_var_assigned(var_name, condition) || self.is_var_assigned(var_name, body)
  }
}
///|
/// Count variable usage in a KNF expression
fn KnfEnv::count_var_usage(self : KnfEnv, var_name : Name, expr : Knf) -> Int {
  match expr {
    Unit => 0
    Int(_) => 0
    Int64(_) => 0
    Double(_) => 0
    Bool(_) => 0
    Neg(x) => if x == var_name { 1 } else { 0 }
    FNeg(x) => if x == var_name { 1 } else { 0 }
    Add(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    Sub(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    Mul(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    Div(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    Mod(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    FAdd(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    FSub(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    FMul(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    FDiv(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    FMod(x, y) =>
      (if x == var_name { 1 } else { 0 }) + (if y == var_name { 1 } else { 0 })
    Var(x) => if x == var_name { 1 } else { 0 }
    IfEq(x, y, then_branch, else_branch) =>
      (if x == var_name { 1 } else { 0 }) +
      (if y == var_name { 1 } else { 0 }) +
      self.count_var_usage(var_name, then_branch) +
      self.count_var_usage(var_name, else_branch)
    IfLe(x, y, then_branch, else_branch) =>
      (if x == var_name { 1 } else { 0 }) +
      (if y == var_name { 1 } else { 0 }) +
      self.count_var_usage(var_name, then_branch) +
      self.count_var_usage(var_name, else_branch)
    IfLt(x, y, then_branch, else_branch) =>
      (if x == var_name { 1 } else { 0 }) +
      (if y == var_name { 1 } else { 0 }) +
      self.count_var_usage(var_name, then_branch) +
      self.count_var_usage(var_name, else_branch)
    Let((x, _), e, body) => {
      let usage_in_e = self.count_var_usage(var_name, e)
      let usage_in_body = if x == var_name {
        0 // Don't count usage in body if it shadows our variable
      } else {
        self.count_var_usage(var_name, body)
      }
      usage_in_e + usage_in_body
    }
    LetRec(func, m) => {
      let usage_in_body = self.count_var_usage(var_name, func.body)
      let usage_in_m = self.count_var_usage(var_name, m)
      usage_in_body + usage_in_m
    }
    Apply(f, args) => {
      let mut count = if f == var_name { 1 } else { 0 }
      for arg in args {
        if arg == var_name {
          count = count + 1
        }
      }
      count
    }
    Tuple(xs) => {
      let mut count = 0
      for x in xs {
        if x == var_name {
          count = count + 1
        }
      }
      count
    }
    LetTuple(xs, tuple_expr, m) => {
      let usage_in_m = self.count_var_usage(var_name, m)
      let usage_in_tuple = if tuple_expr == var_name { 1 } else { 0 }
      let mut usage_in_xs = 0
      for elem in xs {
        let (x, _) = elem
        if x == var_name {
          usage_in_xs = usage_in_xs + 1
        }
      }
      usage_in_m + usage_in_tuple + usage_in_xs
    }
    FieldAccess(obj, _, _) => if obj == var_name { 1 } else { 0 }
    Get(array, index) =>
      (if array == var_name { 1 } else { 0 }) +
      (if index == var_name { 1 } else { 0 })
    Put(array, index, value) =>
      (if array == var_name { 1 } else { 0 }) +
      (if index == var_name { 1 } else { 0 }) +
      (if value == var_name { 1 } else { 0 })
    ExternalArray(_) => 0
    ExternalFunctionApplication(_, args) => {
      let mut count = 0
      for arg in args {
        if arg == var_name {
          count = count + 1
        }
      }
      count
    }
    ArrayData(_, elements) => {
      let mut count = 0
      for elem in elements {
        count = count + self.count_var_usage(var_name, elem)
      }
      count
    }
    While(condition, body) =>
      self.count_var_usage(var_name, condition) +
      self.count_var_usage(var_name, body)
    Assign(lhs, rhs) =>
      (if lhs == var_name { 1 } else { 0 }) +
      (if rhs == var_name { 1 } else { 0 })
  }
}

///|
/// Internal version with constant propagation environment
fn KnfEnv::constant_folding_and_unused_variable_elimination_with_env(
  self : KnfEnv,
  env : @immut/hashmap.HashMap[Name, Knf],
  knf : Knf,
) -> Knf {
  match knf {
    // Variable reference - check if it's a known constant
    Var(x) =>
      match lookup_constant(env, x) {
        Some(const_val) => const_val
        None => Var(x)
      }
    // Let binding - check for unused variable elimination and constant propagation
    Let((x, x_ty), e, body) => {
      let optimized_e = self.constant_folding_and_unused_variable_elimination_with_env(
        env, e,
      )
      // Check if e is a constant and x is not used elsewhere
      match is_constant_expr(optimized_e) {
        Some(const_val) => {
          // Only treat x as constant if it's never assigned to in the body
          let is_assigned = self.is_var_assigned(x, body)
          if !is_assigned {
            // Add x to constant environment
            let extended_env = env.add(x, const_val)
            let usage_count = self.count_var_usage(x, body)
            if usage_count == 0 {
              // x is unused and bound to constant, can eliminate binding
              self.constant_folding_and_unused_variable_elimination_with_env(
                extended_env, body,
              )
            } else {
              // x is used, keep binding but propagate constant
              let optimized_body = self.constant_folding_and_unused_variable_elimination_with_env(
                extended_env, body,
              )
              Let((x, x_ty), optimized_e, optimized_body)
            }
          } else {
            // x is assigned to in body, don't treat as constant
            let optimized_body = self.constant_folding_and_unused_variable_elimination_with_env(
              env, body,
            )
            Let((x, x_ty), optimized_e, optimized_body)
          }
        }
        None => {
          // e is not a constant, optimize body without adding to constant env
          let optimized_body = self.constant_folding_and_unused_variable_elimination_with_env(
            env, body,
          )
          let usage_count = self.count_var_usage(x, body)
          if usage_count == 0 && !self.has_side_effects(optimized_e) {
            // x is unused and e has no side effects, eliminate binding
            optimized_body
          } else {
            // Keep binding
            Let((x, x_ty), optimized_e, optimized_body)
          }
        }
      }
    }

    // Constants - return as-is
    Unit => Unit
    Int(_) => knf
    Int64(_) => knf
    Double(_) => knf
    Bool(_) => knf
    ExternalArray(_) => knf


    // Unary operations - try constant folding
    Neg(x) =>
      match lookup_constant(env, x) {
        Some(const_val) => self.eval_unary_op("neg", const_val)
        None => Neg(x)
      }
    FNeg(x) =>
      match lookup_constant(env, x) {
        Some(const_val) => self.eval_unary_op("fneg", const_val)
        None => FNeg(x)
      }

    // Binary operations - try constant folding
    Add(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("add", left_const, right_const)
        (Some(_), None) => Add(x, y) // left is constant, keep right (keep original Name)
        (None, Some(_)) => Add(x, y) // right is constant, keep left (keep original Name)
        (None, None) => Add(x, y) // neither is constant
      }
    Sub(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("sub", left_const, right_const)
        (Some(_), None) => Sub(x, y)
        (None, Some(_)) => Sub(x, y)
        (None, None) => Sub(x, y)
      }
    Mul(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("mul", left_const, right_const)
        (Some(_), None) => Mul(x, y)
        (None, Some(_)) => Mul(x, y)
        (None, None) => Mul(x, y)
      }
    Div(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("div", left_const, right_const)
        (Some(_), None) => Div(x, y)
        (None, Some(_)) => Div(x, y)
        (None, None) => Div(x, y)
      }
    Mod(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("mod", left_const, right_const)
        (Some(_), None) => Mod(x, y)
        (None, Some(_)) => Mod(x, y)
        (None, None) => Mod(x, y)
      }
    FAdd(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("fadd", left_const, right_const)
        (Some(_), None) => FAdd(x, y)
        (None, Some(_)) => FAdd(x, y)
        (None, None) => FAdd(x, y)
      }
    FSub(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("fsub", left_const, right_const)
        (Some(_), None) => FSub(x, y)
        (None, Some(_)) => FSub(x, y)
        (None, None) => FSub(x, y)
      }
    FMul(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("fmul", left_const, right_const)
        (Some(_), None) => FMul(x, y)
        (None, Some(_)) => FMul(x, y)
        (None, None) => FMul(x, y)
      }
    FDiv(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("fdiv", left_const, right_const)
        (Some(_), None) => FDiv(x, y)
        (None, Some(_)) => FDiv(x, y)
        (None, None) => FDiv(x, y)
      }
    FMod(x, y) =>
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_binary_op("fmod", left_const, right_const)
        (Some(_), None) => FMod(x, y)
        (None, Some(_)) => FMod(x, y)
        (None, None) => FMod(x, y)
      }

    // Conditional expressions - try constant folding
    IfEq(x, y, then_branch, else_branch) => {
      let optimized_then = self.constant_folding_and_unused_variable_elimination_with_env(
        env, then_branch,
      )
      let optimized_else = self.constant_folding_and_unused_variable_elimination_with_env(
        env, else_branch,
      )
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_conditional(
            left_const, right_const, optimized_then, optimized_else, "ifeq",
          )
        (Some(_), None) => IfEq(x, y, optimized_then, optimized_else)
        (None, Some(_)) => IfEq(x, y, optimized_then, optimized_else)
        (None, None) => IfEq(x, y, optimized_then, optimized_else)
      }
    }
    IfLe(x, y, then_branch, else_branch) => {
      let optimized_then = self.constant_folding_and_unused_variable_elimination_with_env(
        env, then_branch,
      )
      let optimized_else = self.constant_folding_and_unused_variable_elimination_with_env(
        env, else_branch,
      )
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_conditional(
            left_const, right_const, optimized_then, optimized_else, "ifle",
          )
        (Some(_), None) => IfLe(x, y, optimized_then, optimized_else)
        (None, Some(_)) => IfLe(x, y, optimized_then, optimized_else)
        (None, None) => IfLe(x, y, optimized_then, optimized_else)
      }
    }
    IfLt(x, y, then_branch, else_branch) => {
      let optimized_then = self.constant_folding_and_unused_variable_elimination_with_env(
        env, then_branch,
      )
      let optimized_else = self.constant_folding_and_unused_variable_elimination_with_env(
        env, else_branch,
      )
      match (lookup_constant(env, x), lookup_constant(env, y)) {
        (Some(left_const), Some(right_const)) =>
          self.eval_conditional(
            left_const, right_const, optimized_then, optimized_else, "iflt",
          )
        (Some(_), None) => IfLt(x, y, optimized_then, optimized_else)
        (None, Some(_)) => IfLt(x, y, optimized_then, optimized_else)
        (None, None) => IfLt(x, y, optimized_then, optimized_else)
      }
    }

    
    // Recursive function binding
    LetRec(func, m) => {
      let optimized_body = self.constant_folding_and_unused_variable_elimination_with_env(
        env,
        func.body,
      )
      let optimized_m = self.constant_folding_and_unused_variable_elimination_with_env(
        env, m,
      )
      let new_func = {
        name: func.name,
        ty: func.ty,
        args: func.args,
        body: optimized_body,
      }
      LetRec(new_func, optimized_m)
    }

    // Function application
    Apply(f, args) => Apply(f, args)

    // Tuple operations
    Tuple(xs) => Tuple(xs)
    LetTuple(xs, tuple_expr, m) => {
      let optimized_m = self.constant_folding_and_unused_variable_elimination_with_env(
        env, m,
      )
      LetTuple(xs, tuple_expr, optimized_m)
    }

    // Field access and array operations
    FieldAccess(obj, field_ty, field_idx) =>
      FieldAccess(obj, field_ty, field_idx)
    Get(array, index) => Get(array, index)
    Put(array, index, value) => Put(array, index, value)

    // External function application
    ExternalFunctionApplication(name, args) =>
      ExternalFunctionApplication(name, args)
    ArrayData(name, elements) => {
      let optimized_elements = Array::new()
      for elem in elements {
        optimized_elements.push(
          self.constant_folding_and_unused_variable_elimination_with_env(
            env, elem,
          ),
        )
      }
      ArrayData(name, optimized_elements)
    }

    // While loop
    While(condition, body) => {
      let optimized_condition = self.constant_folding_and_unused_variable_elimination_with_env(
        env, condition,
      )
      let optimized_body = self.constant_folding_and_unused_variable_elimination_with_env(
        env, body,
      )
      While(optimized_condition, optimized_body)
    }

    // Assignment
    Assign(lhs, rhs) => Assign(lhs, rhs)
  }
}

///|
/// Check if an expression has side effects
fn KnfEnv::has_side_effects(self : KnfEnv, expr : Knf) -> Bool {
  match expr {
    Unit | Int(_) | Int64(_) | Double(_) | Bool(_) => false
    Var(_) => false
    Neg(_)
    | FNeg(_)
    | Add(_, _)
    | Sub(_, _)
    | Mul(_, _)
    | Div(_, _)
    | Mod(_, _)
    | FAdd(_, _)
    | FSub(_, _)
    | FMul(_, _)
    | FDiv(_, _)
    | FMod(_, _) => false
    FieldAccess(_, _, _) => false
    Get(_, _) => false
    Put(_, _, _) => true // array assignment has side effects
    ExternalArray(_) => false
    ExternalFunctionApplication(_, _) => true // external function calls have side effects
    ArrayData(_, elements) => {
      for elem in elements {
        if self.has_side_effects(elem) {
          return true
        }
      }
      false
    }
    While(_, _) => true // loops have side effects
    Assign(_, _) => true // assignment has side effects
    IfEq(_, _, then_branch, else_branch)
    | IfLe(_, _, then_branch, else_branch)
    | IfLt(_, _, then_branch, else_branch) =>
      self.has_side_effects(then_branch) || self.has_side_effects(else_branch)
    Let((_, _), e, body) =>
      self.has_side_effects(e) || self.has_side_effects(body)
    LetRec(func, m) =>
      self.has_side_effects(func.body) || self.has_side_effects(m)
    Apply(_, _) => true // function calls may have side effects
    Tuple(_) => false
    LetTuple(_, _, m) => self.has_side_effects(m)
  }
}
