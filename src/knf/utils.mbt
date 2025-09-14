///|
pub fn knf_max_counter(knf : Knf) -> Int {
  match knf {
    Unit => 0
    Int(_) => 0
    Int64(_) => 0
    Double(_) => 0
    Neg(x) => x.slot
    Add(x, y) => @cmp.maximum(x.slot, y.slot)
    Sub(x, y) => @cmp.maximum(x.slot, y.slot)
    Mul(x, y) => @cmp.maximum(x.slot, y.slot)
    Div(x, y) => @cmp.maximum(x.slot, y.slot)
    Mod(x, y) => @cmp.maximum(x.slot, y.slot)
    FNeg(x) => x.slot
    FAdd(x, y) => @cmp.maximum(x.slot, y.slot)
    FSub(x, y) => @cmp.maximum(x.slot, y.slot)
    FMul(x, y) => @cmp.maximum(x.slot, y.slot)
    FDiv(x, y) => @cmp.maximum(x.slot, y.slot)  
    FMod(x, y) => @cmp.maximum(x.slot, y.slot)
    IfEq(x, y, e1, e2) =>
      @cmp.maximum(
        x.slot,
        @cmp.maximum(
          y.slot,
          @cmp.maximum(knf_max_counter(e1), knf_max_counter(e2)),
        ),
      )
    IfLe(x, y, e1, e2) =>
      @cmp.maximum(
        x.slot,
        @cmp.maximum( 
          y.slot,
          @cmp.maximum(knf_max_counter(e1), knf_max_counter(e2)),
        ),
      )
    IfLt(x, y, e1, e2) =>
      @cmp.maximum(
        x.slot,
        @cmp.maximum( 
          y.slot,
          @cmp.maximum(knf_max_counter(e1), knf_max_counter(e2)),
        ),
      )
    Let((n, _), e1, e2) =>
      @cmp.maximum(
        n.slot,
        @cmp.maximum(knf_max_counter(e1), knf_max_counter(e2)),   
      )
    Var(x) => x.slot
    LetRec(f, e) =>
      @cmp.maximum(
        f.name.slot,
        @cmp.maximum(knf_max_counter(f.body), knf_max_counter(e)),
      )
    Apply(x, xs) =>
      @cmp.maximum(
        x.slot,
        xs.map(fn(x) { x.slot }).fold(init=0, fn(a, b) { @cmp.maximum(a, b) }),
      )
    Tuple(xs) =>
      xs.map(fn(x) { x.slot }).fold(init=0, fn(a, b) { @cmp.maximum(a, b) })
    LetTuple(xts, n, e) =>
      @cmp.maximum(
        n.slot,
        @cmp.maximum(
          xts
          .map(fn(x) { x.0.slot })
          .fold(init=0, fn(a, b) { @cmp.maximum(a, b) }),
          knf_max_counter(e),
        ),
      )
    Get(x, y) => @cmp.maximum(x.slot, y.slot)
    Put(x, y, z) => @cmp.maximum(x.slot, @cmp.maximum(y.slot, z.slot))
    ExternalFunctionApplication(_, xs) =>
      xs.map(fn(x) { x.slot }).fold(init=0, fn(a, b) { @cmp.maximum(a, b) })
    ExternalArray(_) => 0
    While(cond, body) =>
      @cmp.maximum(knf_max_counter(cond), knf_max_counter(body))
    Assign(x, y) => @cmp.maximum(x.slot, y.slot)
    FieldAccess(x, _t, y) => @cmp.maximum(x.slot, y)
    EnumConstructor(_, index, variant) => @cmp.maximum(index, variant.map(fn(x) { x.slot }).fold(init=0, fn(a, b) { @cmp.maximum(a, b) }))
  }
}
