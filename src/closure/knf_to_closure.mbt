pub typealias LocalEnv = @immut/hashmap.T[Name, LowType]

pub fn knf_program_to_closure(
  prog : @knf.Knf,
  extern_env : Map[String, Type]
) -> Program {
  // println("knf ir: " + prog.to_string())
  // println("extern_env: " + extern_env.to_string())
  let fundefs : Array[FuncDef] = []
  extern_env.each(
    fn(name, ty) {
      let mut low_type : LowType = Unit
      let args_low_ty = []
      match ty {
        Fun(args_ty, ty) => {
          low_type = ty_to_low_type(ty, false)
          for ty in args_ty {
            args_low_ty.push(ty_to_low_type(ty, false))
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
  // println("==========================")
  // println("closure ir:")
  // for i in fundefs {
  //   if not(extern_env.contains(i.old_name.to_string())) {
  //     println("fundef: " + i.to_string())
  //   }
  // }
  // println("body: " + body.to_string())
  // println("==========================")
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
      let (args, is_func, _) = match ty {
        Fun(args, return_ty) => (args, true, return_ty)
        _ => ([], false, Unit)
      }

      // 如果是闭包类型，将变量添加到环境中
      if is_func {
        let _args = args.map(
          fn { ty => (gen_name(), ty_to_low_type(ty, false)) },
        )
        let fv = fv(e).difference(@hashset.from_array(
          env.map(fn(def) { new_fv(def.old_name, Unit) })
        ))
        let free_vars = fv_to_array(fv)
        // println("free_vars: " + free_vars.to_string())
        let is_closure = not(free_vars.is_empty())
        // let def : FuncDef = {
        //   name: x.to_string(),
        //   old_name: x,
        //   is_closure,
        //   ty: ty_to_low_type(ty, is_closure),
        //   args: [],
        //   formal_free_vars: free_vars,
        //   body: knf_to_closure(env, e),
        // }
        // env.push(def)
        // let closure : Closure = {
        //   name: x.to_string(),
        //   actual_free_vars: free_vars.map(fn { fv => fv.0 }),
        // }
        // println("free_vars: " + free_vars.to_string())
        Let(
          (x, ty_to_low_type(ty, is_closure)),
          knf_to_closure(env, e),
          knf_to_closure(env, cont),
        )
      } else {
        Let(
          (x, ty_to_low_type(ty, false)),
          knf_to_closure(env, e),
          knf_to_closure(env, cont),
        )
      }
    }
    LetRec({ name, ty, args, body }, cont) => {
      let mut return_ty : Type = Unit
      match ty {
        Fun(_, ty) => return_ty = ty
        _ => @util.die("LetRec: " + ty.to_string())
      }
      let free_vars = fv(body).difference(@hashset.from_array(
        env.map(fn(def) { new_fv(def.old_name, Unit) })
      ))
      for arg in args {
        free_vars.remove(new_fv(arg.0, Unit))
      }
      free_vars.remove(new_fv(name, Unit))
      let is_closure = not(free_vars.is_empty())
      
      // 创建函数定义的通用部分
      let make_def = fn(body : Expr) -> FuncDef {
        {
          name: name.to_string(),
          old_name: name,
          is_closure,
          ty: ty_to_low_type(ty, is_closure),
          args: args.map(fn { (name, ty) => (name, ty_to_low_type(ty, false)) }),
          formal_free_vars: fv_to_array(free_vars),
          body,
        }
      }
      
      // 先将函数定义添加到环境中，这样在处理函数体时可以引用到该函数
      env.push(make_def(Unit))
      
      // 处理函数体
      let def = make_def(knf_to_closure(env, body))
      let index = env.search_by(fn(def) { def.old_name == name }).unwrap()
      let _ = env.remove(index)
      env.push(def)
      
      // 处理后续代码
      if is_closure {
        let closure : Closure = {
          name: name.to_string(),
          actual_free_vars: fv_to_array(free_vars).map(fn { fv => fv.0 }),
        }
        MakeClosure(
          (name, ty_to_low_type(ty, true)),
          closure,
          knf_to_closure(env, cont),
        )
      } else {
        knf_to_closure(env, cont)
      }
    }
    Apply(name, arr_name) => {
      // 参数是函数类型
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
      // 检查是否是函数定义中的函数
      let closure = match env.search_by(fn(def) { def.old_name == name }) {
        None => true
        Some(index) =>
          match env.get(index) {
            Some(def) => def.is_closure
            None => false
          }
      }
      match closure || is_capture {
        true => CallClosure(name, arr_name)
        false => CallDirect(name.to_string(), arr_name)
      }
    }
    Var(n) =>
      match env.search_by(fn(def) { def.old_name == n }) {
        Some(index) => {
          let def = env.get(index).unwrap()
          // match def.is_closure {
          //   true => {
              // 如果变量引用的是一个闭包函数，需要创建闭包对象
              let closure : Closure = {
                name: def.name,
                actual_free_vars: def.formal_free_vars.map(fn { fv => fv.0 }),
              }
              MakeClosure(
                (def.old_name, def.ty),
                closure,
                Var(n)
              )
            // }
            // false => Var(n) // 如果不是闭包，调用 CallDirect
          // }
        }
        None => Var(n)  // 如果在环境中找不到，直接返回变量引用
      }
    Tuple(arr_name) => MakeTuple(arr_name)
    LetTuple(arr_name_ty, name, cont) => {
      let arr_name = arr_name_ty.map(
        fn { (name, ty) => (name, ty_to_low_type(ty, false)) },
      )
      LetTuple(arr_name, name, knf_to_closure(env, cont))
    }
    Put(name, name1, name2) => ArrayPut(name, name1, name2)
    Get(name, name1) => ArrayGet(name, name1)
    ExternalArray(name) => ExternalArray(name.name.to_string())
    ExternalFunctionApplication(name, arr_name) => CallDirect(name, arr_name)
  }
}

fn fv(e : @knf.Knf) -> @hashset.T[FreeVarWithType] {
  fv_with_type(e)
}

fn fv_to_array(
  fv : @hashset.T[FreeVarWithType]
) -> Array[(@types.Name, LowType)] {
  let res = []
  fv.each(fn(fv) { res.push((fv.name, fv.ty)) })
  res
}

fn ty_to_low_type(ty : Type, is_closure : Bool) -> LowType {
  match ty {
    Unit => Unit
    Bool => Bool
    Int => Int
    Double => Double
    Fun(arr_ty, ty) => {
      // println("Fun: " + (arr_ty, ty).to_string())
      let arr_low_ty = arr_ty.map(fn { ty => ty_to_low_type(ty, is_closure) })
      match is_closure {
        true => ClosureFn(arr_low_ty, ty_to_low_type(ty, is_closure))
        false => DirectFn(arr_low_ty, ty_to_low_type(ty, is_closure))
      }
    }
    Tuple(arr_ty) =>
      Tuple(arr_ty.map(fn { ty => ty_to_low_type(ty, is_closure) }))
    Array(ty) => Array(ty_to_low_type(ty, is_closure))
    Var(ty) => @util.die("ty_to_low_type: Var" + ty.to_string())
    Ptr => Ptr
  }
}

let _default_counter : Ref[Int] = { val: 0 }

fn gen_name(~counter : Ref[Int] = _default_counter) -> Name {
  counter.val = counter.val + 1
  Name::from_string?("_" + counter.val.to_string() + "_closure").unwrap()
  // Name::from_string?("x").unwrap()

}

pub struct FreeVarWithType {
  name : @types.Name
  ty : LowType
} derive(Show)

impl Hash for FreeVarWithType with hash_combine(_self, _state) {
  fn _hash_combine(self : FreeVarWithType, state : Hasher) -> Unit {
    self.name.hash_combine(state)
  }


}

impl Hash for FreeVarWithType with hash(self) {
  let hasher = Hasher::new()
  hasher.combine(self.name)
  hasher.finalize()
}

impl Compare for FreeVarWithType with compare(self, other) {
  self.name.compare(other.name)
}

impl Eq for FreeVarWithType with op_equal(
  self : FreeVarWithType,
  other : FreeVarWithType
) {
  self.name == other.name
}

fn new_fv(name : @types.Name, ty : LowType) -> FreeVarWithType {
  { name, ty }
}

fn fv_with_type(e : @knf.Knf) -> @hashset.T[FreeVarWithType] {
  match e {
    Unit => @hashset.new()
    Int(_) => @hashset.new()
    Double(_) => @hashset.new()
    Neg(x) => @hashset.of([new_fv(x, Int)])
    Add(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Sub(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Mul(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    Div(a, b) => @hashset.of([new_fv(a, Int), new_fv(b, Int)])
    FNeg(x) => @hashset.of([new_fv(x, Double)])
    FAdd(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FSub(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FMul(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    FDiv(a, b) => @hashset.of([new_fv(a, Double), new_fv(b, Double)])
    IfEq(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv_with_type(ka))
      .union(fv_with_type(kb))
    IfLe(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv_with_type(ka))
      .union(fv_with_type(kb))
    Let((x, _), e, cont) => {
      let r = fv_with_type(cont)
      r.remove(new_fv(x, Unit))
      fv_with_type(e).union(r)
    }
    Var(x) => @hashset.of([new_fv(x, Unit)])
    // Var(_) => @hashset.new()
    LetRec({ name, ty: _, args, body }, cont) => {
      let x = fv_with_type(body)
      for i in args {
        x.remove(new_fv(i.0, Unit))
      }
      let result = fv_with_type(cont).union(x)
      result.remove(new_fv(name, Unit))
      result
    }
    Apply(f, a) =>
      @hashset.of([new_fv(f, DirectFn([], Unit))]).union(
        @hashset.from_array(a.map(fn { name => new_fv(name, Unit) })),
      )
    Tuple(arr_name) =>
      @hashset.from_array(arr_name.map(fn { name => new_fv(name, Ptr) }))
    LetTuple(arr_name_ty, name, cont) => {
      let result = fv_with_type(cont)
      for _, name_ty in arr_name_ty {
        result.remove(new_fv(name_ty.0, Ptr))
      }
      result.union(@hashset.of([new_fv(name, Ptr)]))
    }
    Get(a, b) => @hashset.of([new_fv(a, Ptr), new_fv(b, Ptr)])
    Put(a, b, c) =>
      @hashset.of([new_fv(a, Ptr), new_fv(b, Ptr), new_fv(c, Ptr)])
    ExternalArray(a) => @hashset.of([new_fv(a, Ptr)])
    ExternalFunctionApplication(_, arr_name) =>
      @hashset.from_array(arr_name.map(fn { name => new_fv(name, Ptr) }))
  }
}
