///|
pub type LocalEnv = @immut/hashmap.HashMap[Name, LowType]

///|
pub fn knf_program_to_closure(
  prog : @knf.Knf,
  extern_env : Map[String, Type],
) -> Program {
  // println("knf ir: " + prog.to_json().stringify())
  // println("extern_env: " + extern_env.to_string())
  let fundefs : Array[FuncDef] = []
  let static_arrays : Array[StaticArrayData] = []
  extern_env.each(fn(name, ty) {
    let mut low_type : LowType = Unit
    match ty {
      Fun(_, ty) => low_type = ty_to_low_type(ty)
      _ => @util.die("LetRec: " + ty.to_string())
    }
    fundefs.push({
      name: name.to_string(),
      old_name: (try? @types.Name::from_string(name)).unwrap(),
      is_closure: false,
      ty: low_type,
      args: [],
      formal_free_vars: [],
      body: Unit,
    })
  })
  let body : Expr = knf_to_closure(
    fundefs,
    LocalEnv::new(),
    static_arrays,
    [],
    prog,
  )
  { fundefs, static_arrays, body }
}

///|
fn knf_to_closure(
  funcdefs : Array[FuncDef],
  env : LocalEnv,
  static_arrays : Array[StaticArrayData],
  func_stack : Array[@types.Name],
  e : @knf.Knf,
) -> Expr {
  // println("knf_to_closure: " + e.to_string())
  match e {
    Int(i) => Int(i)
    Int64(i) => Int64(i)
    Unit => Unit
    Double(d) => Double(d)
    Bool(b) => Bool(b)
    Add(a, b) => Add(a, b)
    Sub(a, b) => Sub(a, b)
    Mul(a, b) => Mul(a, b)
    Div(a, b) => Div(a, b)
    Mod(a, b) => Mod(a, b)
    Neg(x) => Neg(x)
    FNeg(x) => FNeg(x)
    FAdd(a, b) => FAdd(a, b)
    FSub(a, b) => FSub(a, b)
    FMul(a, b) => FMul(a, b)
    FDiv(a, b) => FDiv(a, b)
    FMod(a, b) => FMod(a, b)
    IfEq(a, b, ka, kb) =>
      IfEq(
        a,
        b,
        knf_to_closure(funcdefs, env, static_arrays, func_stack, ka),
        knf_to_closure(funcdefs, env, static_arrays, func_stack, kb),
      )
    IfLe(a, b, ka, kb) =>
      IfLe(
        a,
        b,
        knf_to_closure(funcdefs, env, static_arrays, func_stack, ka),
        knf_to_closure(funcdefs, env, static_arrays, func_stack, kb),
      )
    IfLt(a, b, ka, kb) =>
      IfLt(
        a,
        b,
        knf_to_closure(funcdefs, env, static_arrays, func_stack, ka),
        knf_to_closure(funcdefs, env, static_arrays, func_stack, kb),
      )
    Let((x, ty), e, cont) => {
      match ty {
        // Fun(_, _) => {
        //   let closure = {
        //     name: Label(x.to_string()),
        //     actual_free_vars: [],
        //   }
        //   MakeClosure((x, ty_to_low_type(ty, is_closure = true)), closure, knf_to_closure(funcdefs, env, static_arrays, e))
        // }
        _ => {
          let body = knf_to_closure(funcdefs, env, static_arrays, func_stack, e)
          // @util.logger("name: " + (x, ty).to_string())
          let ty = match ty {
            // Fun(args_ty, ret_ty) =>
            // ClosureFn(args_ty.map(ty_to_low_type), ty_to_low_type(ret_ty))
            Fun(_) => gen_body_ret_type(ty, funcdefs, env, body)
            _ => ty_to_low_type(ty)
          }
          let env = env.add(x, ty)
          // @util.logger("let: " + (x, ty).to_string())
          // @util.logger("env: " + env.to_string())
          Let((x, ty), body, knf_to_closure(funcdefs, env, static_arrays, func_stack, cont))
        }
      }
    }
    LetRec({ name, ty, args, body }, cont) => {
      let free_vars = fv(env, body).difference(
        @hashset.from_array(
          funcdefs.map(fn(def) { new_fv(def.old_name, def.ty) }),
        ),
      )
      let mut env = env
      for arg in args {
        free_vars.remove(new_fv(arg.0, Unit))
        env = env.add(arg.0, ty_to_low_type(arg.1, is_closure = true))
      }
      free_vars.remove(new_fv(name, Unit))
      let is_closure = not(free_vars.is_empty())
      // @util.logger("letrec: " + name.to_string() + " env: " + env.to_string())

      // 生成限定名称
      let qualified_name = if func_stack.length() > 0 {
        let parent_name = func_stack[func_stack.length() - 1]
        parent_name.to_string() + "$" + name.to_string()
      } else {
        name.to_string()
      }

      // 处理函数体
      let make_def = fn(body : Expr) -> FuncDef {
        {
          name: if is_closure { qualified_name } else { name.to_string() },
          old_name: name,
          is_closure,
          ty: gen_func_type(ty, is_closure, funcdefs, env, body),
          args: args.map(name_ty => (name_ty.0, {
            match ty_to_low_type(name_ty.1) {
              DirectFn(arg_tys, ret_ty) => ClosureFn(arg_tys, ret_ty)
              ty => ty
            }
          })),
          formal_free_vars: fv_to_array(free_vars),
          body,
        }
      }
      funcdefs.push(make_def(Unit))

      // 将当前函数名压入栈中，用于处理嵌套函数
      let new_func_stack = []
      for item in func_stack {
        new_func_stack.push(item)
      }
      new_func_stack.push(name)
      let body = knf_to_closure(funcdefs, env, static_arrays, new_func_stack, body)

      let def = make_def(body)
      let index = funcdefs.search_by(fn(def) { def.old_name == name }).unwrap()
      let _ = funcdefs.remove(index)
      funcdefs.push(def)
      match is_closure {
        true => {
          let free_var_names = fv_to_array(free_vars).map(fv => fv.0)
          let closure = {
            name: qualified_name,
            actual_free_vars: free_var_names,
          }
          MakeClosure((name, def.ty),
            closure,
            knf_to_closure(funcdefs, env, static_arrays, func_stack, cont),
          )
        }
        false => knf_to_closure(funcdefs, env, static_arrays, func_stack, cont)
      }
    }
    Apply(name, args_name) => {
      // 获取被调用函数的定义，以确定参数类型
      let caller_def = match funcdefs.search_by(fn(def) { def.old_name == name }) {
        None => None // 外部函数
        Some(index) => funcdefs.get(index)
      }

      // 检查被调用函数是否是闭包
      let is_closure_func = match caller_def {
        Some(def) => def.is_closure
        None => false
      }
      let is_closure_var = match env.get(name) {
        Some(ty) =>
          match ty {
            ClosureFn(_, _) => true
            DirectFn(_, _) => false // 非函数类型参数
            _ => false // 非函数类型参数
          }
        None => false
      }

      let mut result = match is_closure_func || is_closure_var {
        true => CallClosure(name, args_name)
        false => CallDirect(name.to_string(), args_name)
      }

      result = match funcdefs.search_by(fn(def) { def.old_name == name }) {
        Some(index) => {
          let def = funcdefs.get(index).unwrap()
          if def.is_closure {
            let free_var_names = def.formal_free_vars.map(fv => fv.0)
            let closure = {
              name: def.name,
              actual_free_vars: free_var_names,
            }
            MakeClosure((def.old_name, def.ty), closure, result)
          } else {
            result
          }
        }
        None => result
      }

      // 为函数参数创建闭包（从右到左处理，以保持正确的变量绑定顺序）
      let mut i = args_name.length() - 1
      while i >= 0 {
        let arg_name = args_name[i]
        match funcdefs.search_by(fn(def) { def.old_name == arg_name }) {
          Some(index) => {
            let def = funcdefs.get(index).unwrap()

            // 为所有函数生成闭包，包括没有自由变量的函数
            let closure_name = if def.is_closure {
              def.name
            } else {
              // 为非闭包函数生成 $closure 包装函数
              let wrapper_name = def.name.0 + "$closure"
              generate_closure_wrapper(funcdefs, def, wrapper_name)
              wrapper_name
            }

            let free_var_names = def.formal_free_vars.map(fv => fv.0)
            let closure = {
              name: closure_name,
              actual_free_vars: free_var_names,
            }
            result = MakeClosure((def.old_name, def.ty), closure, result)
            // @util.logger("make closure: " + result.to_string())
          }
          None => () // 不是函数定义，无需处理
        }
        i = i - 1
      }
      result
    }
    Var(n) => Var(n)
    Tuple(arr_name) => MakeTuple(arr_name)
    LetTuple(arr_name_ty, name, cont) => {
      let arr_name = arr_name_ty.map(name_ty => (
        name_ty.0,
        ty_to_low_type(name_ty.1),
      ))
      LetTuple(
        arr_name,
        name,
        knf_to_closure(funcdefs, env, static_arrays, func_stack, cont),
      )
    }
    Put(name, name1, name2) => ArrayPut(name, name1, name2)
    Get(name, name1) => ArrayGet(name, name1)
    ExternalArray(name) => ExternalArray(name)
    ExternalFunctionApplication(name, arr_name) => CallDirect(name, arr_name)
    While(cond, body) =>
      While(
        knf_to_closure(funcdefs, env, static_arrays, func_stack, cond),
        knf_to_closure(funcdefs, env, static_arrays, func_stack, body),
      )
    Assign(x, y) => Assign(x, y)
    FieldAccess(x, ty, y) => TupleGet(x, ty_to_low_type(ty), y)
    ArrayData(label, datas) => {
      let name = Label(label)
      fn gen_static_array_data(datas : Array[@knf.Knf]) -> Array[LowTypeValue] {
        let result = []
        for data in datas {
          match data {
            Int(i) => result.push(IntValue(i))
            Double(d) => result.push(DoubleValue(d))
            ArrayData(_, arr) =>
              result.push(PtrValue(gen_static_array_data(arr)))
            _ => @util.die("gen_static_array_data: " + data.to_string())
          }
        }
        result
      }

      static_arrays.push({ label: name, elements: gen_static_array_data(datas) })
      ExternalArray(name)
    }
  }
}

///|
fn generate_closure_wrapper(
  funcdefs : Array[FuncDef],
  def : FuncDef,
  wrapper_name : String,
) -> Unit {
  // 检查是否已经生成了包装函数
  if funcdefs.search_by(fn(d) { d.name.0 == wrapper_name }) is None {
    match def.ty {
      DirectFn(arg_tys, ret_ty) => {
        // 生成闭包包装函数
        let wrapper_def = {
          name: wrapper_name,
          old_name: Name::name_only(wrapper_name),
          is_closure: true,
          ty: ClosureFn(arg_tys, ret_ty),
          args: def.args, // 使用原始参数
          formal_free_vars: [],
          body: CallDirect(def.name, def.args.map(fn(arg) { arg.0 })),
        }
        funcdefs.push(wrapper_def)
      }
      _ => () // 已经是闭包函数，无需包装
    }
  }
}

///|
fn fv_to_array(
  fv : @hashset.HashSet[FreeVarWithType],
) -> Array[(@types.Name, LowType)] {
  let res = []
  fv.each(fn(fv) { res.push((fv.name, fv.ty)) })
  res
}

///|
pub(all) struct FreeVarWithType {
  name : @types.Name
  ty : LowType
} derive(Show)

///|
impl Hash for FreeVarWithType with hash_combine(self, state) {
    self.name.hash_combine(state)
}

///|
impl Hash for FreeVarWithType with hash(self) {
  let hasher = Hasher::new()
  hasher.combine(self.name)
  hasher.finalize()
}

///|
pub impl Compare for FreeVarWithType with compare(self, other) {
  self.name.compare(other.name)
}

///|
impl Eq for FreeVarWithType with equal(
  self : FreeVarWithType,
  other : FreeVarWithType,
) {
  self.name == other.name
}

///|
fn new_fv(name : @types.Name, ty : LowType) -> FreeVarWithType {
  { name, ty }
}

///|
fn fv(env : LocalEnv, e : @knf.Knf) -> @hashset.HashSet[FreeVarWithType] {
  match e {
    Unit => @hashset.new()
    Int(_) => @hashset.new()
    Int64(_) => @hashset.new()
    Double(_) => @hashset.new()
    Bool(_) => @hashset.new()
    Neg(x) => @hashset.from_array([new_fv(x, Int)])
    Add(a, b) => @hashset.from_array([new_fv(a, Int), new_fv(b, Int)])
    Sub(a, b) => @hashset.from_array([new_fv(a, Int), new_fv(b, Int)])
    Mul(a, b) => @hashset.from_array([new_fv(a, Int), new_fv(b, Int)])
    Div(a, b) => @hashset.from_array([new_fv(a, Int), new_fv(b, Int)])
    Mod(a, b) => @hashset.from_array([new_fv(a, Int), new_fv(b, Int)])
    FNeg(x) => @hashset.from_array([new_fv(x, Double)])
    FAdd(a, b) => @hashset.from_array([new_fv(a, Double), new_fv(b, Double)])
    FSub(a, b) => @hashset.from_array([new_fv(a, Double), new_fv(b, Double)])
    FMul(a, b) => @hashset.from_array([new_fv(a, Double), new_fv(b, Double)])
    FDiv(a, b) => @hashset.from_array([new_fv(a, Double), new_fv(b, Double)])
    FMod(a, b) => @hashset.from_array([new_fv(a, Double), new_fv(b, Double)])
    IfEq(a, b, ka, kb) =>
      @hashset.from_array([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(env, ka))
      .union(fv(env, kb))
    IfLe(a, b, ka, kb) =>
      @hashset.from_array([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(env, ka))
      .union(fv(env, kb))
    IfLt(a, b, ka, kb) =>
      @hashset.from_array([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(env, ka))
      .union(fv(env, kb))
    Let((x, _), e, cont) => {
      let r = fv(env, cont)
      r.remove(new_fv(x, Unit))
      let fve = fv(env, e)
      // fve.remove(new_fv(x, Unit))
      fve.union(r)
    }
    Var(x) => {
      // 获取变量的实际类型，而不是默认为Unit
      // @util.logger("fv: " + x.to_string()   + ", env: " + env.to_string())
      let ty = match env.get(x) {
        Some(t) => t
        None => Unit
      }
      @hashset.from_array([new_fv(x, ty)])
    }
    LetRec({ name, ty: _, args, body }, cont) => {
      let x = fv(env, body)
      for i in args {
        x.remove(new_fv(i.0, Unit))
      }
      let result = fv(env, cont).union(x)
      result.remove(new_fv(name, Unit))
      result
    }
    Apply(f, a) => {
      let ty = match env.get(f) {
        Some(ty) => ty
        None => Unit
      }
      @hashset.from_array([new_fv(f, ty)]).union(
        @hashset.from_array(a.map(name => new_fv(name, Unit))),
      )
    }
    Tuple(arr_name) => {
      // 获取元组的实际类型信息
      let tuple_fvs = []
      for name in arr_name {
        let ty = match env.get(name) {
          Some(t) => t
          None => Ptr  // 默认为Ptr，但优先使用环境中的类型
        }
        tuple_fvs.push(new_fv(name, ty))
      }
      @hashset.from_array(tuple_fvs)
    }
    LetTuple(arr_name_ty, name, cont) => {
      let result = fv(env, cont)
      for _, name_ty in arr_name_ty {
        result.remove(new_fv(name_ty.0, Ptr))
      }
      let name_ty = match env.get(name) {
        Some(t) => t
        None => Ptr  // 默认为Ptr，但优先使用环境中的类型
      }
      result.union(@hashset.from_array([new_fv(name, name_ty)]))
    }
    Get(a, b) => {
      // 获取数组/元组的实际类型
      let a_ty = match env.get(a) {
        Some(t) => t
        None => Ptr  // 默认为Ptr，但优先使用环境中的类型
      }
      @hashset.from_array([new_fv(a, a_ty), new_fv(b, Int)])
    }
    Put(a, b, c) => {
      let a_ty = match env.get(a) {
        Some(ty) => ty
        None => Unit
      }
      let b_ty = match env.get(b) {
        Some(ty) => ty
        None => Int
      }
      let c_ty = match env.get(c) {
        Some(ty) => ty
        None => Ptr
      }
      @hashset.from_array([new_fv(a, a_ty), new_fv(b, b_ty), new_fv(c, c_ty)])
    }
    ExternalArray(_) => @hashset.new()
    ExternalFunctionApplication(_, arr_name) =>
      @hashset.from_array(arr_name.map(name => new_fv(name, Ptr)))
    While(_, body) => fv(env, body)
    Assign(_x, _y) => @hashset.new()
    FieldAccess(_, _, _) => @hashset.new()
    ArrayData(_) => @hashset.new()
  }
}

///|
test {
  let _test2 = (try? @fs.read_file_to_string(
    "contest-2025-data/test_cases/mbt/conv_pool.mbt",
  )).unwrap()
  let parse = @parser.parse_from_string(_test2)
  println("parse: " + parse.to_json().stringify() + "\n")
  try {
    let typed = @typing.typing(parse)
    println("typed: " + typed.to_json().stringify() + "\n")
    let env = @knf.KnfEnv::new(@immut/hashmap.new())
    let pre = @knf.KnfEnv::syntax_preprocess(env, typed)
    println("pre: " + pre.to_json().stringify() + "\n")
    let knf = @knf.KnfEnv::to_knf(env, pre)
    println("knf: ")
    println(knf.to_json().stringify() + "\n")
    let closure = knf_program_to_closure(
      knf,
      Map::from_iter(@immut/hashmap.new().iter()),
    )
    // println("closure: " + closure.to_string() + "\n")
    println("closure: ")
    println(closure.to_json().stringify())
  } catch {
    @typing.TyErr(s) => {
      println("typing error")
      println(s)
    }
    @knf.KnfErr(s) => {
      println("knf error")
      println(s)
    }
    _ => println("unknown error")
  }
}
