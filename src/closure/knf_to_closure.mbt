pub typealias LocalEnv = @immut/hashmap.T[Name, LowType]

pub fn knf_program_to_closure(
  prog : @knf.Knf,
  extern_env : Map[String, Type]
) -> Program {
  // println("knf_program_to_closure: " + prog.to_string())
  // println("extern_env: " + extern_env.to_string())
  let fundefs : Array[FuncDef] = []
  extern_env.each(
    fn(name, ty) {
      let mut low_type : LowType = Unit
      let args_low_ty = []
      match ty {
        Fun(args_ty, ty) => {
          low_type = ty_to_low_type(ty)
          for ty in args_ty {
            args_low_ty.push(ty_to_low_type(ty))
          }
        }
        _ => @util.die("LetRec: " + ty.to_string())
      }
      fundefs.push(
        {
          name: name.to_string(),
          old_name: @types.Name::from_string?(name).unwrap(),
          is_closure: false,
          ty: low_type,
          args: [],
          formal_free_vars: [],
          body: Unit,
        },
      )
    },
  )
  let body : Expr = knf_to_closure(fundefs, prog)
  // for i in fundefs {
  //   if not(extern_env.contains(i.old_name.to_string())) {
  //     println("fundef: " + i.to_string())
  //   }
  // }
  // println("==========================")
  // println("body: " + body.to_string())
  { fundefs, body }
}

fn knf_to_closure(env : Array[FuncDef], e : @knf.Knf) -> Expr {
  // println("knf_to_closure: " + e.to_string())
  match e {
    Int(i) => Int(i)
    Unit => Unit
    Double(d) => Double(d)
    Add(a, b) => Add(a, b)
    Sub(a, b) => Sub(a, b)
    Mul(a, b) => Mul(a, b)
    Div(a, b) => Div(a, b)
    Neg(x) => Neg(x)
    FNeg(x) => FNeg(x)
    FAdd(a, b) => FAdd(a, b)
    FSub(a, b) => FSub(a, b)
    FMul(a, b) => FMul(a, b)
    FDiv(a, b) => FDiv(a, b)
    IfEq(a, b, ka, kb) =>
      IfEq(a, b, knf_to_closure(env, ka), knf_to_closure(env, kb))
    IfLe(a, b, ka, kb) =>
      IfLe(a, b, knf_to_closure(env, ka), knf_to_closure(env, kb))
    Let((x, ty), e, cont) => {
      // 记录变量的类型信息
      let low_ty = ty_to_low_type(ty)

      // 检查是否是闭包类型
      let is_closure = match ty {
        Fun(_, _) => true
        _ => false
      }

      // 如果是闭包类型，将变量添加到环境中
      if is_closure {
        env.push(
          {
            name: x.to_string(),
            old_name: x,
            is_closure: true,
            ty: low_ty,
            args: [],
            formal_free_vars: [],
            body: Unit,
          },
        )
      }
      Let((x, low_ty), knf_to_closure(env, e), knf_to_closure(env, cont))
    }
    LetRec({ name, ty, args, body }, cont) => {
      // println("LetRec: " + e.to_string())
      // let mut args_ty = []
      let mut return_ty : Type = Unit
      match ty {
        Fun(_, ty) =>
          // args_ty = arr_ty
          return_ty = ty
        _ => @util.die("LetRec: " + ty.to_string())
      }

      // println("LetRec: " + name.to_string())
      let free_vars = fv(body)
      for arg in args {
        free_vars.remove(arg.0)
      }
      // println("LetRec: " + name.to_string() + " , free_vars: " + free_vars.to_string())
      free_vars.remove(name)
      // println("LetRec: " + name.to_string() + " , free_vars: " + free_vars.to_string())
      let closure = if free_vars.is_empty() { false } else { true }
      // println("args: " + args.to_string())
      // println("free_vars: " + free_vars.to_string())

      let initial_def : FuncDef = {
        name: name.to_string(),
        old_name: name,
        is_closure: closure,
        ty: ty_to_low_type(return_ty),
        args: args.map(fn { (name, ty) => (name, ty_to_low_type(ty)) }),
        formal_free_vars: [],
        body: Unit, // 临时设置为 Unit
      }
      env.push(initial_def)
      let free_vars = fv(body)
      for arg in args {
        free_vars.remove(arg.0)
      }
      // println("LetRec: " + name.to_string() + " , free_vars: " + free_vars.to_string())
      free_vars.remove(name)
      // println("LetRec: " + name.to_string() + " , free_vars: " + free_vars.to_string())
      let closure = if free_vars.is_empty() { false } else { true }
      let def : FuncDef = {
        name: name.to_string(),
        old_name: name,
        is_closure: closure,
        ty: ty_to_low_type(return_ty),
        args: args.map(fn { (name, ty) => (name, ty_to_low_type(ty)) }),
        formal_free_vars: to_array(free_vars).map(fn { name => (name, Int) }),
        body: knf_to_closure(env, body),
      }
      let index = env.search_by(fn(def) { def.old_name == name }).unwrap()
      let _ = env.remove(index)
      env.push(def)
      // println("LetRec: " + name.to_string() + " , def: " + def.to_string())
      let closure : Closure = {
        name: name.to_string(),
        actual_free_vars: to_array(free_vars),
      }
      // if closure.actual_free_vars.is_empty() {
      //   knf_to_closure(env, cont)
      // } else {
      MakeClosure(
        (name, ty_to_low_type(ty)),
        closure,
        knf_to_closure(env, cont),
      )
      // }
    }
    Apply(name, arr_name) => {
      // println("Apply: " + name.to_string() + " , arr_name: " + arr_name.to_string())
      // for i in env {
      //   println("env: " + i.name.to_string())
      // }
      let is_capture = match
        env.filter(
          fn(def) {
            // println("def: " + def.to_string())
            match def.args.search_by(fn(var) { var.0 == name }) {
              Some(_) => true
              None => false
            }
          },
        ) {
        [] => false
        _ => true
      }
      // println("is_capture: " + is_capture.to_string())
      // 检查是否是函数定义中的函数
      let closure = match
        env.search_by(
          fn(def) {
            // println("def.old_name: " + def.old_name.to_string() +
            // " , name: " + def.name.to_string() +
            // " , def.is_closure: " + def.is_closure.to_string())
            def.old_name == name && def.is_closure
          },
        ) {
        None => false
        Some(_) => true
      }
      match closure && is_capture {
        true => CallDirect(name.to_string(), arr_name)
        false => CallClosure(name, arr_name)
      }
    }
    Var(n) => Var(n)
    Tuple(arr_name) => MakeTuple(arr_name)
    LetTuple(arr_name_ty, name, cont) => {
      let arr_name = arr_name_ty.map(
        fn { (name, ty) => (name, ty_to_low_type(ty)) },
      )
      LetTuple(arr_name, name, knf_to_closure(env, cont))
    }
    Put(name, name1, name2) => ArrayPut(name, name1, name2)
    Get(name, name1) => ArrayGet(name, name1)
    ExternalArray(name) => ExternalArray(name.name.to_string())
    ExternalFunctionApplication(name, arr_name) =>
      // println(
      //   "ExternalFunctionApplication: " +
      //   name +
      //   " , arr_name: " +
      //   arr_name.to_string(),
      // )
      // let label = env.get(name).unwrap()
      CallDirect(name, arr_name)
  }
}

fn to_array[T](set : @hashset.T[T]) -> @moonbitlang/core/builtin.Array[T] {
  let result = Array::new()
  set.each(fn(x : T) -> Unit { result.push(x) })
  result
}

fn fv(e : @knf.Knf) -> @hashset.T[@types.Name] {
  match e {
    Unit => @hashset.new()
    Int(_) => @hashset.new()
    Double(_) => @hashset.new()
    Neg(x) => @hashset.of([x])
    Add(a, b) => @hashset.of([a, b])
    Sub(a, b) => @hashset.of([a, b])
    Mul(a, b) => @hashset.of([a, b])
    Div(a, b) => @hashset.of([a, b])
    FNeg(x) => @hashset.of([x])
    FAdd(a, b) => @hashset.of([a, b])
    FSub(a, b) => @hashset.of([a, b])
    FMul(a, b) => @hashset.of([a, b])
    FDiv(a, b) => @hashset.of([a, b])
    IfEq(a, b, ka, kb) => @hashset.of([a, b]).union(fv(ka)).union(fv(kb))
    IfLe(a, b, ka, kb) => @hashset.of([a, b]).union(fv(ka)).union(fv(kb))
    Let((x, _), e, cont) => {
      let r = fv(cont)
      r.remove(x)
      fv(e).union(r)
    }
    Var(x) => @hashset.of([x])
    LetRec({ name, ty: _, args, body }, cont) => {
      let x = fv(body)
      for i in args {
        x.remove(i.0)
      }
      let result = fv(cont).union(x)
      result.remove(name)
      result
    }
    Apply(f, a) => @hashset.of([f]).union(@hashset.from_array(a))
    Tuple(arr_name) => @hashset.from_array(arr_name)
    LetTuple(arr_name_ty, name, cont) => {
      let result = fv(cont)
      for _, name_ty in arr_name_ty {
        result.remove(name_ty.0)
      }
      result.union(@hashset.of([name]))
    }
    Get(a, b) => @hashset.of([a, b])
    Put(a, b, c) => @hashset.of([a, b, c])
    ExternalArray(a) => @hashset.of([a])
    ExternalFunctionApplication(_, arr_name) => @hashset.from_array(arr_name)
  }
}

fn ty_to_low_type(ty : Type) -> LowType {
  match ty {
    Unit => Unit
    Bool => Bool
    Int => Int
    Double => Double
    Fun(arr_ty, ty) => {
      // println("Fun: " + (arr_ty, ty).to_string())
      let arr_low_ty = arr_ty.map(fn { ty => ty_to_low_type(ty) })
      ClosureFn(arr_low_ty, ty_to_low_type(ty))
    }
    Tuple(arr_ty) => Tuple(arr_ty.map(fn { ty => ty_to_low_type(ty) }))
    Array(ty) => Array(ty_to_low_type(ty))
    Var(ty) => @util.die("ty_to_low_type: Var" + ty.to_string())
    Ptr => Ptr
  }
}
