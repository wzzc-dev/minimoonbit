///|
pub typealias @immut/hashmap.HashMap[String, Type] as LocalEnv

///|
pub struct KnfEnv {
  mut counter : Int
  mut externals : @immut/hashmap.HashMap[String, Type]
}

///|
pub fn KnfEnv::new(externals : @immut/hashmap.HashMap[String, Type]) -> KnfEnv {
  { counter: 1, externals }
}

///|
pub fn KnfEnv::init_counter_from_existing(
  self : KnfEnv,
  existing : Knf,
) -> Unit {
  self.counter = knf_max_counter(existing) + 1
}

///|
fn KnfEnv::new_temp(self : KnfEnv) -> Name {
  let temp = Name::slot_only(self.counter)
  self.counter += 1
  temp
}

///|
fn KnfEnv::new_name(self : KnfEnv, name : String) -> Name {
  let temp = Name::name_and_slot(name, self.counter)
  self.counter += 1
  temp
}

pub fn gen_name_from_string(name : String) -> Name  raise KnfErr {
  try @types.Name::from_string(name) catch {
    InvalidSlotNumber(name, slot) => raise KnfErr("KNF gen_name_from_string error: invalid slot number for name " + name + " slot " + slot.to_string())
  }
}
///|
pub fn KnfEnv::get_knf(
  self : KnfEnv,
  syn : @types.Syntax,
) -> (Name, Type, Knf) raise KnfErr {
  let ty = KnfEnv::get_type(self.externals, syn)
  match syn {
    Var(name) => {
      let name = gen_name_from_string(name)
      (name, ty, Var(name))
    }
    _ => {
      let name = self.new_temp()
      (name, ty, KnfEnv::to_knf(self, syn))
    }
  }
}

///|
fn KnfEnv::get_type(
  env : LocalEnv,
  syn : @types.Syntax,
) -> @types.Type raise KnfErr {
  @typing.get_type(env, syn) catch {
    @typing.TyErr(s) =>
      raise KnfErr(
        "KNF get_type TyErr error: " +
        s +
        "\n" +
        "syn: " +
        syn.to_string() +
        "\n" +
        "env: " +
        env.to_string(),
      )
  }
}


// Helper function to process comparison operations with consistent pattern
fn process_comparison(
  env : KnfEnv,
  left_expr : @types.Syntax,
  right_expr : @types.Syntax,
  then_expr : @types.Syntax,
  else_expr : @types.Syntax,
  comparison_fn : (Name, Name, Knf, Knf) -> Knf,
) -> Knf raise KnfErr {
  let (left_name, left_ty, left_knf) = KnfEnv::get_knf(env, left_expr)

  // Add fields to externals for user-defined types
  match left_ty {
    UserDefineType(_, fields) =>
      for field in fields.val {
        env.externals = env.externals.add(field.0, left_ty)
      }
    _ => ()
  }

  let (right_name, right_ty, right_knf) = KnfEnv::get_knf(env, right_expr)
  let then_knf = KnfEnv::to_knf(env, then_expr)
  let else_knf = KnfEnv::to_knf(env, else_expr)

  let body = comparison_fn(left_name, right_name, then_knf, else_knf)

  match (left_expr, right_expr) {
    (Var(_), Var(_)) => body
    (Var(_), _) => Let((right_name, right_ty), right_knf, body)
    (_, Var(_)) => Let((left_name, left_ty), left_knf, body)
    (_, _) => Let((left_name, left_ty), left_knf,
                  Let((right_name, right_ty), right_knf, body))
  }
}

// Helper function to process arithmetic operations
fn process_arithmetic(
  env : KnfEnv,
  left_expr : @types.Syntax,
  right_expr : @types.Syntax,
  op : @types.Op,
  kind : Type,
) -> Knf raise KnfErr {
  let (left_name, _, left_knf) = KnfEnv::get_knf(env, left_expr)
  let (right_name, _, right_knf) = KnfEnv::get_knf(env, right_expr)

  let operation = match kind {
    Int => {
      match op {
        Add => Add(left_name, right_name)
        Sub => Sub(left_name, right_name)
        Mul => Mul(left_name, right_name)
        Div => Div(left_name, right_name)
        Mod => Mod(left_name, right_name)
      }
    }
    Double => {
      match op {
        Add => FAdd(left_name, right_name)
        Sub => FSub(left_name, right_name)
        Mul => FMul(left_name, right_name)
        Div => FDiv(left_name, right_name)
        Mod => FMod(left_name, right_name)
      }
    }
    _ => raise KnfErr(
      "Unsupported arithmetic type: " + kind.to_string() +
      ", expression: " + left_expr.to_string()
    )
  }

  match (left_expr, right_expr) {
    (Var(_), Var(_)) => operation
    (Var(_), _) => Let((right_name, kind), right_knf, operation)
    (_, Var(_)) => Let((left_name, kind), left_knf, operation)
    (_, _) => Let((left_name, kind), left_knf,
                  Let((right_name, kind), right_knf, operation))
  }
}

// Helper function to process negation operations
fn process_negation(
  env : KnfEnv,
  expr : @types.Syntax,
  kind : Type,
) -> Knf raise KnfErr {
  match expr {
    Var(name_str) => {
      let name = gen_name_from_string(name_str)
      match kind {
        Int => Neg(name)
        Double => FNeg(name)
        _ => raise KnfErr("Unsupported negation type: " + kind.to_string())
      }
    }
    _ => {
      let temp_name = env.new_temp()
      let expr_knf = KnfEnv::to_knf(env, expr)
      match kind {
        Int => Let((temp_name, Int), expr_knf, Neg(temp_name))
        Double => Let((temp_name, Double), expr_knf, FNeg(temp_name))
        _ => raise KnfErr("Unsupported negation type: " + kind.to_string())
      }
    }
  }
}

///|
pub fn KnfEnv::to_knf(self : KnfEnv, s : @types.Syntax) -> Knf raise KnfErr { // !Failure
  match s {
    Unit => Unit
    Int(i) => Int(i)
    Int64(i) => Int64(i)
    Double(d) => Double(d)
    Var(name) => Var(gen_name_from_string(name))
    Bool(b) => if b { Bool(true) } else { Bool(false) }
    Not(syn) => KnfEnv::to_knf(self, If(syn, Bool(false), Bool(true)))
    If(condition_expr, then_expr, else_expr) => {
      match condition_expr {
        Eq(lhs, rhs) =>
          process_comparison(self, lhs, rhs, then_expr, else_expr,
                            (l_name, r_name, then_knf, else_knf) =>
                             IfEq(l_name, r_name, then_knf, else_knf))
        LE(lhs, rhs) =>
          process_comparison(self, lhs, rhs, then_expr, else_expr,
                           (l_name, r_name, then_knf, else_knf) =>
                             IfLe(l_name, r_name, then_knf, else_knf))
        GE(lhs, rhs) =>
          process_comparison(self, lhs, rhs, then_expr, else_expr,
                           (l_name, r_name, then_knf, else_knf) =>
                             IfLe(r_name, l_name, then_knf, else_knf))
        LT(lhs, rhs) =>
          process_comparison(self, lhs, rhs, then_expr, else_expr,
                           (l_name, r_name, then_knf, else_knf) =>
                             IfLt(l_name, r_name, then_knf, else_knf))
        GT(lhs, rhs) =>
          process_comparison(self, lhs, rhs, then_expr, else_expr,
                           (l_name, r_name, then_knf, else_knf) =>
                             IfLt(r_name, l_name, then_knf, else_knf))
        Not(negated_expr) => 
          process_comparison(self, negated_expr, Bool(false), then_expr, else_expr,
                            (l_name, r_name, then_knf, else_knf) =>
                             IfEq(l_name, r_name, then_knf, else_knf))
        Bool(bool_value) =>
          KnfEnv::to_knf(self, If(Eq(Bool(bool_value), Bool(true)), then_expr, else_expr))
        And(left_expr, right_expr) => {
          let cond = @types.Syntax::If(left_expr, right_expr, Bool(false))
          process_comparison(self, cond, Bool(true), then_expr, else_expr,
                            (l_name, r_name, then_knf, else_knf) =>
                             IfEq(l_name, r_name, then_knf, else_knf))
          
        }
        Or(left_expr, right_expr) => {
          let cond = @types.Syntax::If(left_expr, Bool(true), right_expr)
          process_comparison(self, cond, Bool(true), then_expr, else_expr,
                            (l_name, r_name, then_knf, else_knf) =>
                             IfEq(l_name, r_name, then_knf, else_knf))
        }
        App(_) => {
          process_comparison(self, condition_expr, Bool(true), then_expr, else_expr,
                            (l_name, r_name, then_knf, else_knf) =>
                             IfEq(l_name, r_name, then_knf, else_knf))
        }
        _ => raise KnfErr("Unsupported boolean expression: " + s.to_string())
      }
    }
    Neg(expr, kind~) =>
      match kind {
        Some(Int) => process_negation(self, expr, Int)
        Some(Double) => process_negation(self, expr, Double)
        _ => raise KnfErr("Unsupported negation type: " + kind.to_string())
      }
    Prim(left_expr, right_expr, operation, kind~) => {
      match kind {
        Some(Int) => process_arithmetic(self, left_expr, right_expr, operation, Int)
        Some(Double) => process_arithmetic(self, left_expr, right_expr, operation, Double)
        _ => raise KnfErr(
          "Unsupported arithmetic type: " + kind.to_string() +
          ", expression: " + s.to_string()
        )
      }
    }
    Eq(lhs, rhs) =>
      process_comparison(self, lhs, rhs, Bool(true), Bool(false),
                       (l_name, r_name, _, _) => IfEq(l_name, r_name, Bool(true), Bool(false)))
    LE(lhs, rhs) =>
      process_comparison(self, lhs, rhs, Bool(true), Bool(false),
                       (l_name, r_name, _, _) => IfLe(l_name, r_name, Bool(true), Bool(false)))
    LT(lhs, rhs) =>
      process_comparison(self, lhs, rhs, Bool(true), Bool(false),
                       (l_name, r_name, _, _) => IfLt(l_name, r_name, Bool(true), Bool(false)))
    GT(syn1, syn2) =>
      KnfEnv::to_knf(self, LT(syn2, syn1))
    GE(syn1, syn2) =>
      KnfEnv::to_knf(self, LE(syn2, syn1))
    Let((var_name, var_type), var_expr, rest_expr) => {
      // Create environment with user-defined type fields
      let mut env_with_fields = self.externals
      match var_type.repr() {
        UserDefineType(_, fields) =>
          for field in fields.val {
            env_with_fields = env_with_fields.add(field.0, var_type)
          }
        _ => ()
      }

      // Process the binding expression
      let binding_knf = KnfEnv::to_knf({ counter: self.counter, externals: env_with_fields }, var_expr)

      // Create environment with the bound variable
      let env_with_binding = {
        counter: self.counter,
        externals: self.externals.add(var_name, var_type),
      }

      // Process the rest expression with the new environment
      let rest_knf = KnfEnv::to_knf(env_with_binding, rest_expr)
      let final_name = @types.Name::name_only(var_name)

      Let((final_name, var_type), binding_knf, rest_knf)
    }
    LetRec({ name: (func_name_str, func_type), args: param_list, body: func_body }, rest_expr) => {
      // Convert function name to Name type
      let func_name = gen_name_from_string(func_name_str)

      // Build environment for function body (including function name and parameters)
      let mut func_body_env = self.externals.add(func_name_str, func_type)
      let processed_params = param_list.map(param => {
        // Add parameter to environment for subsequent parameters and body
        func_body_env = func_body_env.add(param.0, param.1)
        // Convert parameter name to Name type
        let param_name = gen_name_from_string(param.0)
        (param_name, param.1)
      })

      // Process function body with function and parameters in scope
      let processed_func_body = KnfEnv::to_knf(
        { counter: self.counter, externals: func_body_env },
        func_body,
      )

      // Build environment for rest expression (function is in scope)
      let rest_env = self.externals.add(func_name_str, func_type)
      let processed_rest = KnfEnv::to_knf(
        { counter: self.counter, externals: rest_env },
        rest_expr,
      )

      LetRec({ name: func_name, ty: func_type, args: processed_params, body: processed_func_body }, processed_rest)
    }
    App(func_expr, arg_exprs) => {
      // Helper function to build function application recursively
      fn build_application(
        env : KnfEnv,
        func_name : Name,
        processed_args : Array[Name],
        remaining_args : Array[@types.Syntax],
      ) -> Knf raise KnfErr {
        match remaining_args.pop() {
          None => {
            // No more arguments to process - create final application
            match func_name.name {
              Some(name_str) if @typing.extenv.contains(name_str) =>
                ExternalFunctionApplication("minimbt_" + name_str, processed_args)
              _ => Apply(func_name, processed_args)
            }
          }
          Some(next_arg) => {
            // Process next argument recursively
            let arg_type = KnfEnv::get_type(env.externals, next_arg)
            match next_arg {
              Var(var_str) => {
                let arg_name = gen_name_from_string(var_str)
                processed_args.insert(0, arg_name)
                build_application(env, func_name, processed_args, remaining_args)
              }
              _ => {
                let temp_name = env.new_temp()
                let arg_knf = KnfEnv::to_knf(env, next_arg)
                processed_args.insert(0, temp_name)
                Let((temp_name, arg_type), arg_knf,
                    build_application(env, func_name, processed_args, remaining_args))
              }
            }
          }
        }
      }

      // Helper function to start processing function and first argument
      fn start_processing(
        env : KnfEnv,
        first_expr : @types.Syntax,
        remaining_exprs : Array[@types.Syntax],
      ) -> Knf raise KnfErr {
        let expr_type = KnfEnv::get_type(env.externals, first_expr)
        match first_expr {
          Var(var_str) => {
            let func_name = gen_name_from_string(var_str)
            build_application(env, func_name, [], remaining_exprs)
          }
          _ => {
            let temp_name = env.new_temp()
            let expr_knf = KnfEnv::to_knf(env, first_expr)
            Let((temp_name, expr_type), expr_knf,
                build_application(env, temp_name, [], remaining_exprs))
          }
        }
      }

      // Handle function expression (may be external function or regular function)
      match func_expr {
        Var(func_name_str) if @typing.extenv.contains(func_name_str) =>
          build_application(self, gen_name_from_string(func_name_str), [], arg_exprs)
        _ => start_processing(self, func_expr, arg_exprs)
      }
    }
    Tuple(syns) => make_tuple(self, syns)
    LetTuple(pattern_vars, tuple_expr, rest_expr) => {
      // Create environment with tuple pattern variables
      let mut pattern_env = self.externals
      for pattern_var in pattern_vars {
        pattern_env = pattern_env.add(pattern_var.0, pattern_var.1)
      }

      // Process rest expression with pattern variables in scope
      let rest_knf = KnfEnv::to_knf(
        { counter: self.counter, externals: pattern_env },
        rest_expr,
      )

      // Convert pattern variables to Name objects with their types
      let name_type_pairs = pattern_vars.map(pattern_var => {
        let var_name = @types.Name::name_only(pattern_var.0)
        (var_name, pattern_var.1.repr())
      })

      // Handle tuple expression (variable vs complex expression)
      match tuple_expr {
        Var(tuple_var_str) => {
          let tuple_name = gen_name_from_string(tuple_var_str)
          LetTuple(name_type_pairs, tuple_name, rest_knf)
        }
        _ => {
          let (temp_name, temp_type, tuple_knf) = KnfEnv::get_knf(self, tuple_expr)
          Let((temp_name, temp_type), tuple_knf,
              LetTuple(name_type_pairs, temp_name, rest_knf))
        }
      }
    }
    Get(array_expr, index_expr) => {
      let (array_name, array_type, array_knf) = KnfEnv::get_knf(self, array_expr)
      let (index_name, index_type, index_knf) = KnfEnv::get_knf(self, index_expr)

      let get_operation = Get(array_name, index_name)
      match (array_expr, index_expr) {
        (Var(_), Var(_)) => get_operation
        (Var(_), _) => Let((index_name, index_type), index_knf, get_operation)
        (_, Var(_)) => Let((array_name, array_type), array_knf, get_operation)
        (_, _) => Let((array_name, array_type), array_knf,
                      Let((index_name, index_type), index_knf, get_operation))
      }
    }
    Put(array_expr, index_expr, value_expr) => {
      let (array_name, array_type, array_knf) = KnfEnv::get_knf(self, array_expr)
      let (index_name, index_type, index_knf) = KnfEnv::get_knf(self, index_expr)
      let (value_name, value_type, value_knf) = KnfEnv::get_knf(self, value_expr)

      let put_operation = Put(array_name, index_name, value_name)
      match array_expr {
        Var(_) =>
          Let((index_name, index_type), index_knf,
              Let((value_name, value_type), value_knf, put_operation))
        _ =>
          Let((array_name, array_type), array_knf,
              Let((index_name, index_type), index_knf,
                  Let((value_name, value_type), value_knf, put_operation)))
      }
    }
    Array(size_expr, init_value_expr) => {
      let (size_name, size_type, size_knf) = KnfEnv::get_knf(self, size_expr)
      let (init_name, init_type, init_knf) = KnfEnv::get_knf(self, init_value_expr)

      // Generate appropriate array creation function based on element type
      fn create_array_operation(size_name : Name, init_name : Name, element_type : Type) -> Knf {
        match element_type {
          Int => ExternalFunctionApplication("minimbt_create_array", [size_name, init_name])
          Double => ExternalFunctionApplication("minimbt_create_float_array", [size_name, init_name])
          _ => ExternalFunctionApplication("minimbt_create_ptr_array", [size_name, init_name])
        }
      }

      let array_operation = create_array_operation(size_name, init_name, init_type)

      // Always use Let bindings for array creation for consistency
      Let((size_name, size_type), size_knf,
          Let((init_name, init_type), init_knf, array_operation))
    }
    While(condition_expr, body_expr) =>
      // Convert while loop to KNF while with processed condition and body
      While(KnfEnv::to_knf(self, condition_expr), KnfEnv::to_knf(self, body_expr))
    Assign(target_expr, value_expr) => {
      let (target_name, target_type, target_knf) = KnfEnv::get_knf(self, target_expr)
      let (value_name, value_type, value_knf) = KnfEnv::get_knf(self, value_expr)

      let assign_operation = Assign(target_name, value_name)
      match (target_expr, value_expr) {
        (Var(_), Var(_)) => assign_operation
        (Var(_), _) => Let((value_name, value_type), value_knf, assign_operation)
        (_, Var(_)) => Let((target_name, target_type), target_knf, assign_operation)
        (_, _) => Let((target_name, target_type), target_knf,
                      Let((value_name, value_type), value_knf, assign_operation))
      }
    }
    And(left_expr, right_expr) =>
      // Convert logical AND to conditional: if left then right else false
      KnfEnv::to_knf(self, If(left_expr, right_expr, Bool(false)))
    
    FieldAccess(struct_expr, field_name) => {
      let (struct_name, struct_type, struct_knf) = KnfEnv::get_knf(self, struct_expr)

      // Find field index in struct type definition
      let field_index = match struct_type {
        UserDefineType(_, fields) => {
          match fields.val.search_by(fn(field) { field.0 == field_name }) {
            Some(index) => index
            None => @util.die("Field '" + field_name + "' not found in struct type: " + struct_type.to_string())
          }
        }
        _ => @util.die("Field access only supported for user-defined types, got: " + struct_type.to_string())
      }

      // Create field access with Let binding for non-variable expressions
      match struct_expr {
        Var(_) => FieldAccess(struct_name, struct_type, field_index)
        _ => Let((struct_name, struct_type), struct_knf, FieldAccess(struct_name, struct_type, field_index))
      }
    }
    Enum(name, _, variants, cont) => {
      let variants = variants.map(fn(variant) {
        match variant {
          (name, ty) => (name, @types.Type::Tuple(ty))
        }
      })
      let mut env_fun = self.externals.add(
        name,
        UserDefineType(name, { val: variants }),
      )
      for variant in variants {
        let (name, _) = variant
        env_fun = env_fun.add(name, UserDefineType(name, { val: variants }))
      }
      // @util.logger("Enum name: " + name.to_string())
      KnfEnv::to_knf({ counter: self.counter, externals: env_fun }, cont)
    }
    EnumConstruct(name, variant) => {
      // @util.logger("env: " + self.counter.to_string())
      let ty = self.externals.get(name).unwrap()
      let index = match ty.repr() {
        UserDefineType(_, fields) => {
          let index = fields.val.search_by(fn(f) { f.0 == name })
          index.unwrap()
        }
        _ => @util.die("not support enum construct: " + ty.to_string())
      }
      let i = KnfEnv::get_knf(self, Int(index))
      let result = [i.0]
      let x = variant.fold(init=Tuple(result), (acc, variant) => {
        let (name, variant_ty, knf) = KnfEnv::get_knf(self, variant)
        result.push(name)
        Let((name, variant_ty), knf, acc)
      })
      Let((i.0, i.1), i.2, x)
    }
    Match(expr, arms) => {
      let tag = KnfEnv::new_name(self, "match_tag")
      let (name, expr_ty, _knf) = KnfEnv::get_knf(self, expr)
      fn gen_match(arm : (@types.Pattern, @types.Syntax)) raise KnfErr {
        let (pat, body) = arm
        // @util.logger("Match arm: " + pat.to_string())
        let index = match pat {
          PEnumVariant(name, _) => {
            // @util.logger("PEnumVariant self.externals: " + self.externals.to_string())
            let ty = self.externals.get(name).unwrap()
            let index = match ty.repr() {
              UserDefineType(_, fields) => {
                // @util.logger("EnumConstruct name: " + name.to_string())
                let index = fields.val.search_by(fn(f) { f.0 == name })
                // @util.logger("EnumConstruct index: " + index.to_string())
                match index {
                  Some(index) => (index, fields.val[index])
                  None =>
                    @util.die(
                      "not support enum construct: " +
                      ty.to_string() +
                      "search by name: " +
                      name.to_string(),
                    )
                }
              }
              _ => @util.die("not support enum construct: " + ty.to_string())
            }
            index
          }
          _ => @util.die("not support match pattern: " + pat.to_string())
        }
        let body = KnfEnv::get_knf(self, body)
        // IfEq(tag, is_expr.0, body.2, acc)
        match index.1 {
          (_, Tuple(patterns_ty)) =>
            if patterns_ty.length() == 0 {
              body.2
            } else {
              let names = match pat {
                PEnumVariant(_, patts) =>
                  patts.map(fn(pat) {
                    match pat {
                      PVar(name) => Name::name_only(name)
                      _ =>
                        @util.die(
                          "not support match pattern: " + pat.to_string(),
                        )
                    }
                  })
                _ => @util.die("not support match pattern: " + pat.to_string())
              }
              let result = body.2
              patterns_ty.foldi(init=result, (i, acc, pat_ty) => Let(
                (names[names.length() - i - 1], pat_ty),
                FieldAccess(name, Tuple(patterns_ty), names.length() - i),
                acc,
              ))
            }
          _ => @util.die("not support match pattern: " + pat.to_string())
        }
      }

      let arms_knf = arms[1:].rev_fold(init=gen_match(arms[0]), (acc, arm) => {
        let (pat, _) = arm
        // @util.logger("Match arm: " + pat.to_string())
        let index = match pat {
          PEnumVariant(name, _) => {
            // @util.logger("PEnumVariant self.externals: " + self.externals.to_string())
            let ty = self.externals.get(name).unwrap()
            let index = match ty.repr() {
              UserDefineType(_, fields) => {
                // @util.logger("EnumConstruct name: " + name.to_string())
                let index = fields.val.search_by(fn(f) { f.0 == name })
                // @util.logger("EnumConstruct index: " + index.to_string())
                match index {
                  Some(index) => (index, fields.val[index])
                  None =>
                    @util.die(
                      "not support enum construct: " +
                      ty.to_string() +
                      "search by name: " +
                      name.to_string(),
                    )
                }
              }
              _ => @util.die("not support enum construct: " + ty.to_string())
            }
            index
          }
          _ => @util.die("not support match pattern: " + pat.to_string())
        }
        let is_expr = KnfEnv::get_knf(self, Int(index.0))
        let pattern_body = gen_match(arm)

        // @util.logger("Match acc  acc: " + acc.to_string())
        Let(
          (is_expr.0, is_expr.1),
          is_expr.2,
          IfEq(tag, is_expr.0, pattern_body, acc),
        )
      })
      // @util.logger("Match : " + Let((name, _expr_ty), _knf, Let((tag, Int), FieldAccess(name, _expr_ty, 0), arms_knf)).to_string())
      Let(
        (name, expr_ty),
        _knf,
        Let((tag, Int), FieldAccess(name, expr_ty, 0), arms_knf),
      )
    }
    ExternalArray(label) => ExternalArray(label)
    ArrayData(label, data) =>
      ArrayData(
        label,
        data.mapi(fn(i, d) {
          match d {
            Int(i) => Int(i)
            Double(d) => Double(d)
            Neg(Double(d), ..) => Double(-d)
            Neg(Int(d), ..) => Int(-d)
            ArrayData(label, data) =>
              KnfEnv::to_knf(self, ArrayData(label + "_" + i.to_string(), data))
            ArrayExpr(data) =>
              KnfEnv::to_knf(self, ArrayData(label + "_" + i.to_string(), data))
            _ =>
              raise KnfErr("not supported syntax ArrayData: " + d.to_string())
          }
        }),
      )
    _ => raise KnfErr("not supported syntax " + s.to_string())
  }
}

///|
fn make_tuple(env : KnfEnv, element_exprs : Array[@types.Syntax]) -> Knf raise KnfErr {
  let element_names = Array::new()
  let non_variable_bindings = Array::new()

  // Process all tuple elements
  for element_expr in element_exprs {
    let (element_name, element_type, element_knf) = KnfEnv::get_knf(env, element_expr)
    element_names.push(element_name)

    // Track non-variable expressions that need Let bindings
    match element_expr {
      Var(_) => () // Variables don't need Let bindings
      _ => non_variable_bindings.push((element_name, element_type, element_knf))
    }
  }

  // Build nested Let expressions from inside out, ending with tuple
  let mut tuple_result = Tuple(element_names)
  for binding_index = non_variable_bindings.length() - 1; binding_index >= 0; binding_index = binding_index - 1 {
    let (name, ty, knf) = non_variable_bindings[binding_index]
    tuple_result = Let((name, ty), knf, tuple_result)
  }

  tuple_result
}

///|
pub(all) suberror KnfErr String derive(ToJson)

///|
test {
  let list = @fs.read_dir("contest-2025-data/test_cases/mbt")
  println(list)
  for file in list {
    println(file)
    guard file.has_suffix(".mbt") else {
      println("not mbt file")
      continue
    }
    // guard file.starts_with("matmul-flat") else {
    //   println("matmul-flat mbt file")
    //   continue
    // }
    let _test2 = (try? @fs.read_file_to_string(
      "contest-2025-data/test_cases/mbt/" + file,
    )).unwrap()
    let parse = @parser.parse_from_string(_test2)
    try {
      let typed = @typing.typing(parse)
      // println(typed)
      let pre = KnfEnv::syntax_preprocess(
        KnfEnv::new(@immut/hashmap.new()),
        typed,
      )
      // println(pre)
      let knf = KnfEnv::to_knf(KnfEnv::new(@immut/hashmap.new()), pre)
      println(knf)
    } catch {
      @typing.TyErr(s) => {
        println("typing error")
        println(s)
      }
      KnfErr(s) => {
        println("knf error")
        println(s)
      }
      _ => println("unknown error")
    }
  }
}

///|
test {
  let _test2 = (try? @fs.read_file_to_string(
    "contest-2025-data/test_cases/mbt/enum2.mbt",
  )).unwrap() //cls-reg-bug.mbt
  let parse = @parser.parse_from_string(_test2)
  println("parse: " + parse.to_json().stringify())
  try {
    let typed = @typing.typing(parse)
    // println("typed: " + typed.to_json().stringify())
    let env = KnfEnv::new(@immut/hashmap.new())
    let pre = KnfEnv::syntax_preprocess(env, typed)
    // println("pre: " + pre.to_json().stringify())
    // @util.logger("env: " + env.externals.to_string())
    let _knf = KnfEnv::to_knf(env, pre)
    println("knf: " + _knf.to_json().stringify())
  } catch {
    @typing.TyErr(s) => {
      println("typing error")
      println(s)
    }
    KnfErr(s) => {
      println("knf error")
      println(s)
    }
    _ => println("unknown error")
  }
}
