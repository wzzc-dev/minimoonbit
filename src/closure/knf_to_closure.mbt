///|
pub typealias @immut/hashmap.HashMap[Name, LowType] as LocalEnv

///|
pub fn knf_program_to_closure(
  prog : @knf.Knf,
  extern_env : Map[String, Type],
) -> Program {
  // println("knf ir: " + prog.to_string())
  // println("extern_env: " + extern_env.to_string())
  let fundefs : Array[FuncDef] = []
  let static_arrays : Array[StaticArrayData] = []
  extern_env.each(fn(name, ty) {
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
  let body : Expr = knf_to_closure(fundefs, static_arrays, prog)
  // println("==========================")
  // println("closure ir:")
  // for i in fundefs {
  //   if not(extern_env.contains(i.old_name.to_string())) {
  //     println("fundef: " + i.to_string())
  //   }
  // }
  // println("body: " + body.to_string())
  // println("==========================")
  // println("static_arrays: " + static_arrays.to_string())
  { fundefs, static_arrays, body }
}

///|
fn knf_to_closure(
  env : Array[FuncDef],
  static_arrays : Array[StaticArrayData],
  e : @knf.Knf,
) -> Expr {
  // println("knf_to_closure: " + e.to_string())
  match e {
    Int(i) => Int(i)
    Int64(i) => Int64(i)
    Unit => Unit
    Double(d) => Double(d)
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
        knf_to_closure(env, static_arrays, ka),
        knf_to_closure(env, static_arrays, kb),
      )
    IfLe(a, b, ka, kb) =>
      IfLe(
        a,
        b,
        knf_to_closure(env, static_arrays, ka),
        knf_to_closure(env, static_arrays, kb),
      )
    IfLt(a, b, ka, kb) =>
      IfLt(
        a,
        b,
        knf_to_closure(env, static_arrays, ka),
        knf_to_closure(env, static_arrays, kb),
      )
    Let((x, ty), e, cont) =>
      Let(
        (x, ty_to_low_type(ty, false)),
        knf_to_closure(env, static_arrays, e),
        knf_to_closure(env, static_arrays, cont),
      )
    LetRec({ name, ty, args, body }, cont) => {
      let free_vars = fv(body).difference(
        @hashset.from_array(env.map(fn(def) { new_fv(def.old_name, Unit) })),
      )
      for arg in args {
        free_vars.remove(new_fv(arg.0, Unit))
      }
      free_vars.remove(new_fv(name, Unit))
      let is_closure = not(free_vars.is_empty())
      let make_def = fn(body : Expr) -> FuncDef {
        {
          name: name.to_string(),
          old_name: name,
          is_closure,
          ty: ty_to_low_type(ty, is_closure),
          args: args.map(name_ty => (
            name_ty.0,
            ty_to_low_type(name_ty.1, false),
          )),
          formal_free_vars: fv_to_array(free_vars),
          body,
        }
      }
      env.push(make_def(Unit))

      // 处理函数体
      let def = make_def(knf_to_closure(env, static_arrays, body))
      let index = env.search_by(fn(def) { def.old_name == name }).unwrap()
      let _ = env.remove(index)
      env.push(def)
      let closure : Closure = {
        name: name.to_string(),
        actual_free_vars: fv_to_array(free_vars).map(fv => fv.0),
      }
      MakeClosure(
        (name, ty_to_low_type(ty, is_closure)),
        closure,
        knf_to_closure(env, static_arrays, cont),
      )
    }
    Apply(name, arr_name) => {
      // 参数是函数类型
      let is_capture = match
        env.filter(fn(def) {
          // println("def: " + def.to_string())
          match def.args.search_by(fn(var_ty) { var_ty.0 == name }) {
            Some(_) => true
            None => false
          }
        }) {
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
      // 检查是否是闭包调用
      // println("closure: " + closure.to_string())
      // println("is_capture: " + is_capture.to_string())
      match closure || is_capture {
        true => CallClosure(name, arr_name)
        false => CallDirect(name.to_string(), arr_name)
      }
    }
    Var(n) =>
      match env.search_by(fn(def) { def.old_name == n }) {
        Some(index) => {
          let def = env.get(index).unwrap()
          let closure : Closure = {
            name: def.name,
            actual_free_vars: def.formal_free_vars.map(fv => fv.0),
          }
          MakeClosure((def.old_name, def.ty), closure, Var(n))
        }
        None => Var(n) // 如果在环境中找不到，直接返回变量引用
      }
    // Var(n) => Var(n)
    Tuple(arr_name) => MakeTuple(arr_name)
    LetTuple(arr_name_ty, name, cont) => {
      let arr_name = arr_name_ty.map(name_ty => (
        name_ty.0,
        ty_to_low_type(name_ty.1, false),
      ))
      LetTuple(arr_name, name, knf_to_closure(env, static_arrays, cont))
    }
    Put(name, name1, name2) => ArrayPut(name, name1, name2)
    Get(name, name1) => ArrayGet(name, name1)
    ExternalArray(name) => ExternalArray(name)
    ExternalFunctionApplication(name, arr_name) =>
      ExternalFunctionApplication(name, arr_name)
    While(cond, body) =>
      While(
        knf_to_closure(env, static_arrays, cond),
        knf_to_closure(env, static_arrays, body),
      )
    Assign(x, y) => Assign(x, y)
    FieldAccess(x, ty, y) => TupleGet(x, ty_to_low_type(ty, false), y)
    EnumConstructor(_) =>
      @util.die("EnumConstructor not supported")
    ArrayData(label, datas) => {
      let name = Label(label)
      fn gen_static_array_data(datas : Array[@knf.Knf]) -> Array[LowTypeValue] {
        let result = []
        for data in datas {
          match data {
            Int(i) => result.push(IntValue(i))
            Double(d) => result.push(DoubleValue(d))
            ArrayData(_, arr) => result.push(PtrValue(gen_static_array_data(arr)))
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
fn ty_to_low_type(ty : Type, is_closure : Bool) -> LowType {
  match ty {
    None => Unit
    Unit => Unit
    Bool => Bool
    Int => Int
    Double => Double
    Fun(arr_ty, ty) => {
      let arr_low_ty = arr_ty.map(ty => ty_to_low_type(ty, is_closure))
      match is_closure {
        true => ClosureFn(arr_low_ty, ty_to_low_type(ty, is_closure))
        false => DirectFn(arr_low_ty, ty_to_low_type(ty, is_closure))
      }
    }
    Tuple(arr_ty) => Tuple(arr_ty.map(ty => ty_to_low_type(ty, is_closure)))
    Array(ty) => Array(ty_to_low_type(ty, is_closure))
    Var(ty) =>
      match ty.val {
        Some(UserDefineType(_, fields)) => {
          let fields_ty = fields.val.map(field => ty_to_low_type(
            field.1,
            is_closure,
          ))
          Tuple(fields_ty)
        }
        Some(ty) =>
          // println("ty: " + ty.to_string())
          // println("ty_to_low_type(ty, is_closure): " + ty_to_low_type(ty, is_closure).to_string())
          ty_to_low_type(ty, is_closure)
        _ => @util.die("ty_to_low_type: Var" + ty.to_string())
      }
    Ptr => Ptr
    Enum(_name, _) | Struct(_name, _) =>
      @util.die("ty_to_low_type: Enum or Struct" + ty.to_string())
    UserDefineType(_, fields) => {
      let fields_ty = fields.val.map(field => ty_to_low_type(
        field.1,
        is_closure,
      ))
      Tuple(fields_ty)
    }
    ArrayData(_) => @util.die("ty_to_low_type: ArrayData" + ty.to_string())
  }
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
fn fv(e : @knf.Knf) -> @hashset.HashSet[FreeVarWithType] {
  match e {
    Unit => @hashset.new()
    Int(_) => @hashset.new()
    Int64(_) => @hashset.new()
    Double(_) => @hashset.new()
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
      .union(fv(ka))
      .union(fv(kb))
    IfLe(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(ka))
      .union(fv(kb))
    IfLt(a, b, ka, kb) =>
      @hashset.of([new_fv(a, Unit), new_fv(b, Unit)])
      .union(fv(ka))
      .union(fv(kb))
    Let((x, _), e, cont) => {
      let r = fv(cont)
      r.remove(new_fv(x, Unit))
      let fve = fv(e)
      // fve.remove(new_fv(x, Unit))
      fve.union(r)
    }
    Var(x) => @hashset.of([new_fv(x, Unit)])
    LetRec({ name, ty: _, args, body }, cont) => {
      let x = fv(body)
      for i in args {
        x.remove(new_fv(i.0, Unit))
      }
      let result = fv(cont).union(x)
      result.remove(new_fv(name, Unit))
      result
    }
    Apply(f, a) =>
      @hashset.of([new_fv(f, DirectFn([], Unit))]).union(
        @hashset.from_array(a.map(name => new_fv(name, Unit))),
      )
    Tuple(arr_name) =>
      @hashset.from_array(arr_name.map(name => new_fv(name, Ptr)))
    LetTuple(arr_name_ty, name, cont) => {
      let result = fv(cont)
      for _, name_ty in arr_name_ty {
        result.remove(new_fv(name_ty.0, Ptr))
      }
      result.union(@hashset.of([new_fv(name, Ptr)]))
    }
    Get(a, b) => @hashset.of([new_fv(a, Ptr), new_fv(b, Int)])
    Put(a, b, c) =>
      @hashset.of([new_fv(a, Ptr), new_fv(b, Int), new_fv(c, Ptr)])
    ExternalArray(_) => @hashset.new()
    ExternalFunctionApplication(_, arr_name) =>
      @hashset.from_array(arr_name.map(name => new_fv(name, Ptr)))
    While(_, body) => fv(body)
    Assign(_x, _y) => @hashset.new()
    FieldAccess(_, _, _) => @hashset.new()
    EnumConstructor(_, _, _) => @hashset.new()
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
