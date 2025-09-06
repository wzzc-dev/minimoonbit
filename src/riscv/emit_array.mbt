///|
fn emit_array_get(
  array : @typing.Name,
  index : @typing.Name,
  instrs : Array[RvAsm],
  env : Env,
) -> Unit {
  // 1. 加载数组基地址
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, array) }))
  @util.logger("emit_array_get: " + array.to_string()+ ", env: " +  env.vars.to_string())
  // 2. 加载索引值并根据类型计算偏移
  instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, index) }))
  instrs.push(Slli(T1, T1, 3)) // 8字节
  // 3. 计算最终地址
  instrs.push(Add(T0, T0, T1))
  // 4. 根据数组元素类型选择加载指令
  match get_array_element_type(array, env) {
    Double => instrs.push(Fld(freg_ret, { base: T0, offset: 0 }))
    Int => instrs.push(Lw(reg_ret, { base: T0, offset: 0 }))
    DirectFn(_, _) | ClosureFn(_, _) | Ptr => instrs.push(Mv(reg_ret, T0)) // 函数指针用 Mv
    _ => instrs.push(Ld(reg_ret, { base: T0, offset: 0 })) // 其他类型默认用 Ld
  }
}

///|
fn emit_array_put(
  array : @typing.Name,
  index : @typing.Name,
  value : @typing.Name,
  instrs : Array[RvAsm],
  env : Env
) -> Unit {
  instrs.push(Comment("emit_array_put:" + array.to_string() + " " + index.to_string() + " " + value.to_string()))
  // 1. 加载数组基地址
  instrs.push(Ld(T0, { base: Fp, offset: Env::varOffset(env, array) }))
  // 2. 加载并计算索引偏移
  instrs.push(Ld(T1, { base: Fp, offset: Env::varOffset(env, index) }))
  instrs.push(Slli(T1, T1, 3))
  // 3. 安全地计算目标地址
  instrs.push(Add(T0, T0, T1))
  // 4. 加载并存储值
  let value_offset = env.vars.get(value.to_string()).unwrap().0
  match get_array_element_type(array, env) {
    Double => {
      instrs.push(Fld(Ft0, { base: Fp, offset: value_offset }))
      instrs.push(Fsd(Ft0, { base: T0, offset: 0 }))
    }
    Int => {
      instrs.push(Lw(T2, { base: Fp, offset: value_offset }))
      instrs.push(Sw(T2, { base: T0, offset: 0 }))
    }
    _ => {
      instrs.push(Ld(T2, { base: Fp, offset: value_offset }))
      instrs.push(Sd(T2, { base: T0, offset: 0 }))
    }
  }
  instrs.push(Comment("emit_array_put end"))


}

// 添加一个辅助函数来获取数组元素类型
///|
fn get_array_element_type(array : @typing.Name, env : Env) -> @closure.LowType {
  match env.find_type(array.to_string()) {
    Array(elem_type) => elem_type
    Ptr => Ptr
    _ =>
      @util.die(
        "get array element type error " +
        array.to_string() +
        "\n " +
        env.find_type(array.to_string()).to_string(),
      )
  }
}
