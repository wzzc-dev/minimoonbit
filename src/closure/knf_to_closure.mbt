///|
pub typealias @immut/hashmap.HashMap[Name, LowType] as LocalEnv

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
      free_vars: [],
      body: Unit,
    })
  })
  let body : Expr = knf_to_closure(
    fundefs,
    LocalEnv::new(),
    static_arrays,
    prog,
  )
  { fundefs, static_arrays, body }
}

///|
fn knf_to_closure(
  funcdefs : Array[FuncDef],
  env : LocalEnv,
  static_arrays : Array[StaticArrayData],
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
        knf_to_closure(funcdefs, env, static_arrays, ka),
        knf_to_closure(funcdefs, env, static_arrays, kb),
      )
    IfLe(a, b, ka, kb) =>
      IfLe(
        a,
        b,
        knf_to_closure(funcdefs, env, static_arrays, ka),
        knf_to_closure(funcdefs, env, static_arrays, kb),
      )
    IfLt(a, b, ka, kb) =>
      IfLt(
        a,
        b,
        knf_to_closure(funcdefs, env, static_arrays, ka),
        knf_to_closure(funcdefs, env, static_arrays, kb),
      )
    Let((x, ty), e, cont) => {
      let body = knf_to_closure(funcdefs, env, static_arrays, e)
      // @util.logger("name: " + (x, ty).to_string())
      let ty = match ty {
        // Fun(args_ty, ret_ty) =>
        // ClosureFn(args_ty.map(ty_to_low_type), ty_to_low_type(ret_ty))
        Fun(_, ty) => gen_body_ret_type(ty, funcdefs, env, body)
        _ => ty_to_low_type(ty)
      }
      let env = env.add(x, ty)
      // @util.logger("let: " + (x, ty).to_string())
      // @util.logger("env: " + env.to_string())
      Let((x, ty), body, knf_to_closure(funcdefs, env, static_arrays, cont))
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
        env = env.add(arg.0, ty_to_low_type(arg.1))
      }
      free_vars.remove(new_fv(name, Unit))
      let is_closure = not(free_vars.is_empty())
      // @util.logger("letrec: " + name.to_string() + " env: " + env.to_string())
      // 处理函数体
      let make_def = fn(body : Expr) -> FuncDef {
        {
          name: name.to_string(),
          old_name: name,
          is_closure,
          ty: gen_func_type(ty, is_closure, funcdefs, env, body),
          args: args.map(name_ty => (name_ty.0, ty_to_low_type(name_ty.1))),
          free_vars: fv_to_array(free_vars),
          body,
        }
      }
      funcdefs.push(make_def(Unit))
      let body = knf_to_closure(funcdefs, env, static_arrays, body)
      let def = make_def(body)
      let index = funcdefs.search_by(fn(def) { def.old_name == name }).unwrap()
      let _ = funcdefs.remove(index)
      funcdefs.push(def)
      match is_closure {
        true => {
          let free_var_names = fv_to_array(free_vars).map(fv => fv.0)
          MakeClosure(
            name.to_string(),
            free_var_names,
            knf_to_closure(funcdefs, env, static_arrays, cont),
          )
        }
        false => knf_to_closure(funcdefs, env, static_arrays, cont)
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
          match ty.function_type() {
            Some((_, _, is_closure)) => is_closure
            None => false
          }
        None => false
      }

      let mut result = match is_closure_func || is_closure_var {
        true => CallClosure(name, args_name)
        false => CallDirect(name.to_string(), args_name)
      }

      // 为函数参数创建闭包（从右到左处理，以保持正确的变量绑定顺序）
      let mut i = args_name.length() - 1
      while i >= 0 {
        let arg_name = args_name[i]
        match funcdefs.search_by(fn(def) { def.old_name == arg_name }) {
          Some(index) => {
            let def = funcdefs.get(index).unwrap()
            // 检查被调用函数对应位置的参数类型
            let should_create_closure = match caller_def {
              Some(caller) => {
                if i < caller.args.length() {
                  let param_type = caller.args[i].1
                  match param_type.function_type() {
                    Some((_, _, is_closure)) => is_closure
                    None => false // 非函数类型参数
                  }
                } else {
                  false // 参数数量不匹配
                }
              }
              None => false // 外部函数假设不需要闭包
            }

            // 只有在参数类型期望闭包时才创建闭包
            if should_create_closure && def.is_closure {
              let free_var_names = def.free_vars.map(fv => fv.0)
              result = MakeClosure(def.old_name.to_string(), free_var_names, result)
            }
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
        knf_to_closure(funcdefs, env, static_arrays, cont),
      )
    }
    Put(name, name1, name2) => ArrayPut(name, name1, name2)
    Get(name, name1) => ArrayGet(name, name1)
    ExternalArray(name) => ExternalArray(name)
    ExternalFunctionApplication(name, arr_name) => CallDirect(name, arr_name)
    While(cond, body) =>
      While(
        knf_to_closure(funcdefs, env, static_arrays, cond),
        knf_to_closure(funcdefs, env, static_arrays, body),
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
impl Hash for FreeVarWithType with hash_combine(_self, _state) {
  fn _hash_combine(self : FreeVarWithType, state : Hasher) -> Unit {
    self.name.hash_combine(state)
  }


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
    Neg(x) => @hashset.of([new_fv(x, Int)])
    Add(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Sub(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Mul(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Div(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Mod(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    FNeg(x) => @hashset.of([new_fv(x, Double)])
    FAdd(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FSub(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FMul(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FDiv(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FMod(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    IfEq(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(env, ka))
      .union(fv(env, kb))
    IfLe(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(env, ka))
      .union(fv(env, kb))
    IfLt(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
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
      @hashset.of([new_fv(x, ty)])
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
      @hashset.of([new_fv(f, ty)]).union(
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
      result.union(@hashset.of([new_fv(name, name_ty)]))
    }
    Get(a, b) => {
      // 获取数组/元组的实际类型
      let a_ty = match env.get(a) {
        Some(t) => t
        None => Ptr  // 默认为Ptr，但优先使用环境中的类型
      }
      @hashset.of([new_fv(a, a_ty), new_fv(b, Int)])
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
      @hashset.of([new_fv(a, a_ty), new_fv(b, b_ty), new_fv(c, c_ty)])
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
