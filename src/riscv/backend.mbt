// // This backend spills all the variables to the stack

// typealias Name = @moonbitlang/minimbt.Name

// typealias LowType = @closure.LowType

// typealias Expr = @closure.Expr

// typealias FuncDef = @closure.FuncDef

// typealias Program = @closure.Program

// typealias Value = (LowType, MemAccess[Reg, Int])


// // ------------------- enviroment start -------------------
// struct Env {
//   env : @immut/hashmap.T[String, Value]
// }

// fn Env::new() -> Env {
//   let env = @immut/hashmap.new()
//   Env::{ env, }
// }

// fn add(self : Env, k : Name, t : LowType, a : MemAccess[Reg, Int]) -> Env {
//   let env = self.env.add(k.to_string(), (t, a))
//   Env::{ env, }
// }
// fn find(self : Env, key : Name) -> Value {

//   self.env.find(key.to_string()).unwrap()
// }

// fn find_type(self : Env, key : Name) -> LowType {
//   self.find(key).0
// }

// fn find_addr(self : Env, key : Name) -> MemAccess[Reg, Int] {
//   self.find(key).1
// }
// // ------------------- enviroment end -------------------


// // ------------------- instruction selection -------------------
pub struct Emitter {
  mut stack_sapce : Int
  mut label_counter : Int
  mut func_name : String
}

// fn Emitter::new(func_name : String) -> Emitter {
//   { stack_sapce: 16, label_counter: 0, func_name }
// }

// fn alloc_double_word(self : Emitter) -> MemAccess[Reg, Int] {
//   self.stack_sapce = self.stack_sapce + 8
//   MemAccess::{ base: reg_fp, offset: self.stack_sapce * -1 }
// }

// fn alloc_word(self : Emitter) -> MemAccess[Reg, Int] {
//   self.stack_sapce = self.stack_sapce + 4
//   MemAccess::{ base: reg_fp, offset: self.stack_sapce * -1 }
// }

fn adjust_stack_space(self : Emitter) -> Unit {
  if self.stack_sapce % 16 != 0 {
    self.stack_sapce = self.stack_sapce / 16 * 16 + 16
  }
}

// fn gen_label(self : Emitter, prefix : String) -> String {
//   self.label_counter = self.label_counter + 1
//   self.func_name + prefix + "_" + self.label_counter.to_string()
// }

// fn compute_bytes(env: Env, names: Array[Name]) -> Int {
//   names.fold(~init = 0, fn {acc, name => 
//     if env.find_type(name).is_float_like() {
//       acc + 8
//     } else if env.find_type(name).is_ptr_like() {
//       acc + 8
//     } else {
//       acc + 4
//     }
//   })
// }

// fn emit_exp(self : Emitter, env : Env, expr : Expr, is_tail: Bool) -> Array[RvAsm] {
//   // println("emit_exp: " + expr.to_string())
//   let asm_comment = Comment(expr.to_string())
//   match expr {
//     Unit => {
//       let asm1 = Addi(reg_ret, Zero, 0)
//       [asm_comment, asm1]
//     }
//     Int(i) => {
//       let asm1 = Li(reg_ret, i.to_string())
//       [asm_comment, asm1]
//     }
//     Double(double) => {
//       let u64 = double.reinterpret_as_u64()
//       let left = ((u64 & 0xFFFFFFFF00000000) >> 32).to_string() ;
//       let right = (u64 & 0x00000000FFFFFFFF).to_string()
//       let asm1 = Li(T0, left)
//       let asm2 = Slli(T0, T0, 32)
//       let asm3 = Li(T1, right)
//       let asm4 = Slli(T1, T1, 32)
//       let asm5 = Srli(T1, T1, 32)
//       let asm6 = Or(T0, T0, T1)
//       let asm7 = FmvDX(freg_ret, T0)
//       [asm_comment, asm1, asm2, asm3, asm4, asm5, asm6, asm7]
//     }
//     Neg(var) => {
//       let asm1 = Lw(T0, env.find_addr(var))
//       let asm2 = Neg(reg_ret, T0)
//       [asm_comment, asm1, asm2]
//     }
//     Add(v1, v2) | Sub(v1, v2) | Mul(v1, v2) | Div(v1, v2) => {
//       let asm1 = Lw(T0, env.find_addr(v1))
//       let asm2 = Lw(T1, env.find_addr(v2))
//       let asm3 = match expr {
//         Add(_) => Add(reg_ret, T0, T1)
//         Sub(_) => Sub(reg_ret, T0, T1)
//         Mul(_) => Mulw(reg_ret, T0, T1)
//         Div(_) | _ => Divw(reg_ret, T0, T1)
//       }
//       [asm_comment, asm1, asm2, asm3]
//     }
//     FNeg(v) => {
//       let asm1 = Fld(Ft0, env.find_addr(v))
//       let asm2 = FnegD(freg_ret, Ft0)
//       [asm_comment, asm1, asm2]
//     }
//     FAdd(v1, v2) | FSub(v1, v2) | FMul(v1, v2) | FDiv(v1, v2) => {
//       let asm1 = Fld(Ft0, env.find_addr(v1))
//       let asm2 = Fld(Ft1, env.find_addr(v2))
//       let asm3 = match expr {
//         FAdd(_) => FaddD(freg_ret, Ft0, Ft1)
//         FSub(_) => FsubD(freg_ret, Ft0, Ft1)
//         FMul(_) => FmulD(freg_ret, Ft0, Ft1)
//         FDiv(_) | _ => FdivD(freg_ret, Ft0, Ft1)
//       }
//       [asm_comment, asm1, asm2, asm3]
//     }
//     IfEq(v1, v2, thn, els) | IfLe(v1, v2, thn, els) => {
//       let thn_lbl = self.gen_label("then")
//       let els_lbl = self.gen_label("else")
//       let merge_lbl = self.gen_label("merge")
//       let asms = if env.find_type(v1).is_float_like() {
//         let asm1 = Fld(Ft0, env.find_addr(v1))
//         let asm2 = Fld(Ft1, env.find_addr(v2))
//         let asm3 = match expr {
//           IfEq(_) => FeqD(T0, Ft0, Ft1)
//           IfLe(_) | _ => FleD(T0, Ft0, Ft1)
//         }
//         let asm4 = Bne(T0, Zero, thn_lbl)
//         [asm1, asm2, asm3, asm4]
//       } else {
//         let asm1 = Lw(T0, env.find_addr(v1))
//         let asm2 = Lw(T1, env.find_addr(v2))
//         match expr {
//           IfEq(_) => [asm1, asm2, Beq(T0, T1, thn_lbl)]
//           IfLe(_) | _ => [asm1, asm2, Ble(T0, T1, thn_lbl)]
//         }
//       }
//       asms + [J(els_lbl)] +
//       [RvAsm::Label(thn_lbl)] + self.emit_exp(env, thn, is_tail) + [J(merge_lbl)] +
//       [RvAsm::Label(els_lbl)] + self.emit_exp(env, els, is_tail) + [J(merge_lbl)] +
//       [RvAsm::Label(merge_lbl)]
//     }
//     Let((var, ty), e1, e2) => {
//       let e1_asms = self.emit_exp(env, e1, false)
      
//       if var.to_string() == "_" {
//         let e2_asms = self.emit_exp(env, e2, is_tail)
//         return e1_asms + e2_asms
//       }

//       if ty.is_float_like() {
//           let addr = self.alloc_double_word()
//           let asm1 = Fsd(freg_ret, addr)
//           let e2_asms = self.emit_exp(env.add(var, ty, addr), e2, is_tail)
//           e1_asms + [asm1] + e2_asms
//       } else if ty.is_ptr_like() {
//           let addr = self.alloc_double_word()
//           let asm1 = Sd(reg_ret, addr)
//           let e2_asms = self.emit_exp(env.add(var, ty, addr), e2, is_tail)
//           e1_asms + [asm1] + e2_asms
//       } else {
//           let addr = self.alloc_word()
//           let asm1 = Sw(reg_ret, addr)
//           let e2_asms = self.emit_exp(env.add(var, ty, addr), e2, is_tail)
//           e1_asms + [asm1] + e2_asms
//       }
//     }
//     Var(name) => {
//       let name_type = env.find_type(name)
//       if name_type.is_float_like() {
//         let asm1 = Fld(freg_ret, env.find_addr(name))
//         [asm_comment] + [asm1]
//       } else if name_type.is_ptr_like() {
//         let asm1 = Ld(reg_ret, env.find_addr(name))
//         [asm_comment] + [asm1]
//       } else {
//         let asm1 = Lw(reg_ret, env.find_addr(name))
//         [asm_comment] + [asm1]
//       }
//     }
//     MakeClosure((name, ty), { name: clos, actual_free_vars }, body) => {
//       let free_vars_bytes = compute_bytes(env, actual_free_vars)

//       // call minimbt_malloc to allocate memory
//       let asm1 = Addi(reg_arg_list[0], Zero, free_vars_bytes + 8)
//       let asm2 = Call("minimbt_malloc")

//       // move function pointer into the closure
//       let asm3 = La(T0, clos._)
//       let asm4 = Sd(T0, MemAccess::{ base: reg_ret, offset: 0 })

//       // move free variables into the closure
//       let mut offset = 8
//       let move_fv_asms = actual_free_vars.map(fn {name => 
//         if env.find_type(name).is_float_like() {
//           let asm1 = Fld(Ft0, env.find_addr(name))
//           let asm2 = Fsd(Ft0, MemAccess::{base : reg_ret, offset})
//           offset += 8
//           [asm1, asm2]
//         } else if env.find_type(name).is_ptr_like() {
//           let asm1 = Ld(T0, env.find_addr(name))
//           let asm2 = Sd(T0, MemAccess::{base : reg_ret, offset})
//           offset += 8
//           [asm1, asm2]
//         } else {
//           let asm1 = Lw(T0, env.find_addr(name))
//           let asm2 = Sw(T0, MemAccess::{base : reg_ret, offset})
//           offset += 4
//           [asm1, asm2]
//         }
//       })

//       let addr = self.alloc_double_word()
//       let asm5 = Sd(reg_ret, addr)
//       let body_asms = self.emit_exp(env.add(name, ty, addr), body, is_tail)
//       [asm1, asm2, asm3, asm4] + move_fv_asms.flatten() + [asm5] + body_asms
//     }
//     CallClosure(clos, args) => {
//       let clos_addr = env.find_addr(clos)

//       // pass closure
//       let asm1 = Ld(reg_arg_list[0], clos_addr)

//       // pass arguments
//       let move_args = args.mapi(fn {idx, name => 
//         if env.find_type(name).is_float_like() {
//             let asm1 = Fld(freg_arg_list[idx + 1], env.find_addr(name))
//             asm1
//         } else if env.find_type(name).is_ptr_like() {
//             let asm1 = Ld(reg_arg_list[idx + 1], env.find_addr(name))
//             asm1
//         } else {
//             let asm1 = Lw(reg_arg_list[idx + 1], env.find_addr(name))
//             asm1
//         }
//       })

//       // call closure
//       let asm2 = Ld(T0, clos_addr)
//       let asm3 = Ld(T0, MemAccess::{ base: T0, offset: 0 })
//       let asm4 = if is_tail {
//         TailJalr(T0)
//       } else {
//         Jalr(T0)
//       }
//       [asm1] + move_args + [asm2, asm3, asm4]
//     }
//     CallDirect(f, args) => {
//       // pass arguments
//       let move_args = args.mapi(fn {idx, name => 
//         if env.find_type(name).is_float_like() {
//             let asm1 = Fld(freg_arg_list[idx], env.find_addr(name))
//             asm1
//         } else if env.find_type(name).is_ptr_like() {
//             let asm1 = Ld(reg_arg_list[idx], env.find_addr(name))
//             asm1
//         } else {
//             let asm1 = Lw(reg_arg_list[idx], env.find_addr(name))
//             asm1
//         }
//       })
//       let asm1 = if is_tail {
//         Tail(f._)
//       } else {
//         Call(f._)
//       }
//       move_args + [asm1]
//     }
//     MakeTuple(names) => {
//       let names_bytes = compute_bytes(env, names)

//       // allocate memory
//       let asm1 = Addi(reg_arg_list[0], Zero, names_bytes)
//       let asm2 = Call("minimbt_malloc")

//       // move vars into the allocated memory
//       let mut offset = 0
//       let move_fv_asms = names.map(fn {name => 
//         if env.find_type(name).is_float_like() {
//           let asm1 = Fld(Ft0, env.find_addr(name))
//           let asm2 = Fsd(Ft0, MemAccess::{base : reg_ret, offset})
//           offset += 8
//           [asm1, asm2]
//         } else if env.find_type(name).is_ptr_like() {
//           let asm1 = Ld(T0, env.find_addr(name))
//           let asm2 = Sd(T0, MemAccess::{base : reg_ret, offset})
//           offset += 8
//           [asm1, asm2]
//         } else {
//           let asm1 = Lw(T0, env.find_addr(name))
//           let asm2 = Sw(T0, MemAccess::{base : reg_ret, offset})
//           offset += 4
//           [asm1, asm2]
//         }
//       })

//       [asm1, asm2] + move_fv_asms.flatten()
//     }
//     LetTuple(vars, init_name, body) => {
//       let init_addr = env.find_addr(init_name)
//       let asm1 = Ld(T0, init_addr)
//       let (env, asms, _) = vars.fold(~init = (env, [], 0), fn {(env, asms, offset), (name, name_type) =>
//         if name.to_string() == "_" {
//             if name_type.is_float_like() { 
//               (env, asms, offset + 8)
//             } else if name_type.is_ptr_like() {
//               (env, asms, offset + 8)
//             } else {
//               (env, asms, offset + 4)
//             }
//         } else {
//           if name_type.is_float_like() {
//             let asm2 = Fld(Ft0, MemAccess::{base : T0, offset})
//             let name_addr = self.alloc_double_word()
//             let asm3 = Fsd(Ft0, name_addr)

//             let env = env.add(name, name_type, name_addr)
//             let asms = asms + [asm1, asm2, asm3]
//             let offset = offset + 8
//             (env, asms, offset)
//           } else if name_type.is_ptr_like() {
//             let asm2 = Ld(T0, MemAccess::{base : T0, offset})
//             let name_addr = self.alloc_double_word()
//             let asm3 = Sd(T0, name_addr)

//             let env = env.add(name, name_type, name_addr)
//             let asms = asms + [asm1, asm2, asm3]
//             let offset = offset + 8
//             (env, asms, offset)
//           } else {
//             let asm2 = Lw(T0, MemAccess::{base : T0, offset})
//             let name_addr = self.alloc_word()
//             let asm3 = Sw(T0, name_addr)

//             let env = env.add(name, name_type, name_addr)
//             let asms = asms + [asm1, asm2, asm3]
//             let offset = offset + 4
//             (env, asms, offset)
//           }
//         }
//       })
//       let body_asms = self.emit_exp(env, body, is_tail)
//       asms + body_asms
//     }
//     ArrayGet(array, index) => {
//       let asm1 = Ld(T0, env.find_addr(array))
//       let asm2 = Lw(T1, env.find_addr(index))
//       let inner_type = match env.find_type(array) {
//         Array(inner_type) => inner_type
//         _ => Ptr
//       }
//       if inner_type.is_float_like() {
//         let asm3 = Slli(T1, T1, 3)
//         let asm4 = Add(T0, T0, T1)
//         let asm5 = Fld(freg_ret, MemAccess::{ base: T0, offset: 0 })
//         [asm1, asm2, asm3, asm4, asm5]
//       } else if inner_type.is_ptr_like() {
//         let asm3 = Slli(T1, T1, 3)
//         let asm4 = Add(T0, T0, T1)
//         let asm5 = Ld(reg_ret, MemAccess::{ base: T0, offset: 0 })
//         [asm1, asm2, asm3, asm4, asm5]
//       } else {
//         let asm3 = Slli(T1, T1, 2)
//         let asm4 = Add(T0, T0, T1)
//         let asm5 = Lw(reg_ret, MemAccess::{ base: T0, offset: 0 })
//         [asm1, asm2, asm3, asm4, asm5]
//       }
//     }
//     ArrayPut(array, index, rhs_exp) => {
//       let asm1 = Ld(T0, env.find_addr(array))
//       let asm2 = Lw(T1, env.find_addr(index))
//       let exp_addr = env.find_addr(rhs_exp)
//       let inner_type = match env.find_type(array) {
//         Array(inner_type) => inner_type
//         _ => panic()
//       }
//       if inner_type.is_float_like() {
//         let asm3 = Slli(T1, T1, 3)
//         let asm4 = Add(T0, T0, T1)
//         let asm5 = Fld(Ft1, exp_addr)
//         let asm6 = Fsd(Ft1, MemAccess::{ base: T0, offset: 0 })
//         let asm7 = Addi(reg_ret, Zero, 0)
//         [asm1, asm2, asm3, asm4, asm5, asm6, asm7]
//       } else if inner_type.is_ptr_like() {
//         let asm3 = Slli(T1, T1, 3)
//         let asm4 = Add(T0, T0, T1)
//         let asm5 = Ld(T1, exp_addr)
//         let asm6 = Sd(T1, MemAccess::{ base: T0, offset: 0 })
//         let asm7 = Addi(reg_ret, Zero, 0)
//         [asm1, asm2, asm3, asm4, asm5, asm6, asm7]
//       } else {
//         let asm3 = Slli(T1, T1, 2)
//         let asm4 = Add(T0, T0, T1)
//         let asm5 = Lw(T1, exp_addr)
//         let asm6 = Sw(T1, MemAccess::{ base: T0, offset: 0 })
//         let asm7 = Addi(reg_ret, Zero, 0)
//         [asm1, asm2, asm3, asm4, asm5, asm6, asm7]
//       }
//     }
//     ExternalArray(_) => panic()
//   }
// }

fn emit_prelude_conclusion(self : Emitter) -> (Array[RvAsm], Array[RvAsm]) {
  self.adjust_stack_space()

  let frame_pointer_addr = MemAccess::{ base: Sp, offset: -8 }
  let return_address_addr = MemAccess::{ base: Sp, offset: -16 }

  let prelude1 = Sd(Ra, return_address_addr)     // store return address
  let prelude2 = Sd(Fp, frame_pointer_addr)      // store frame pointer
  let prelude3 = Mv(Fp, Sp)                      // set frame pointer
  let prelude4 = Addi(Sp, Sp, -self.stack_sapce) // allocate stack frame

  let conclusion1 = Mv(Sp, Fp)                  // restore stack pointer
  let conclusion2 = Ld(Fp, frame_pointer_addr)  // restore frame pointer
  let conclusion3 = Ld(Ra, return_address_addr) // restore return address
  let conclusion4 = Ret                         // return to the caller

  let preclude = [prelude1, prelude2, prelude3, prelude4]
  let conclusion = [conclusion1, conclusion2, conclusion3, conclusion4]
  (preclude, conclusion)
}

// fn pass_param(self : Emitter, env: Env, index: Int, param: (Name, LowType)) -> (Env, RvAsm) {
//   if param.1.is_float_like() {
//     let addr = self.alloc_double_word()
//     let asm1 = Fsd(freg_arg_list[index], addr)
//     let env = env.add(param.0, param.1, addr)
//     (env, asm1)
//   } else if param.1.is_ptr_like() {
//     let addr = self.alloc_double_word()
//     let asm1 = Sd(reg_arg_list[index], addr)
//     let env = env.add(param.0, param.1, addr)
//     (env, asm1)
//   } else {
//     let addr = self.alloc_word()
//     let asm1 = Sw(reg_arg_list[index], addr)
//     let env = env.add(param.0, param.1, addr)
//     (env, asm1)
//   }
// }

// fn pass_params(self : Emitter, env : Env, params: Array[(Name, LowType)]) -> (Env, Array[RvAsm]) {
//   params.foldi(~init=(env, []), fn {index, (env, asms), param =>
//     match 0 {
//       _ => {
//         let (env, asm) = self.pass_param(env, index, param)
//         let asms = asms + [asm]
//         (env, asms)
//       }
//     }
//   })
// }

// fn tail_call_opt(conclusion : Array[RvAsm], body_asms: Array[RvAsm]) -> Array[RvAsm] {
//   let _ = conclusion.pop()
//   let new_conclusion = [Comment("pop stack start")] + conclusion + [Comment("pop stack end")]
//   body_asms.rev_fold(~init = [], fn {acc, asm =>
//     match asm {
//       Tail(lbl) => new_conclusion + [J(lbl)] + acc
//       TailJalr(reg) => new_conclusion + [Jr(reg)] + acc
//       asm => [asm] + acc
//     }
//   })
// }

// pub let extenv = [
//   "read_int", "print_int", "read_char", "print_char", "print_newline", "print_endline",
//   "int_of_float", "float_of_int", "truncate", "floor", "abs_float", "sqrt", "sin",
//   "cos", "atan", "create_array", "create_float_array", "create_ptr_array",
// ]

// fn emit_fun(func_decl : FuncDef) -> AssemblyFunction {
//   let env = Env::new()
//   let emitter = Emitter::new(func_decl.name._)

//   // pass parameters
//   let clos_type = LowType::Tuple([LowType::Ptr] + func_decl.formal_free_vars.map(fn { p => p.1 }) )
//   let clos_name = func_decl.old_name
//   let clos = (clos_name, clos_type) // closure parameter
//   let (env, move_param_asms) = emitter.pass_params(env, [clos] + func_decl.args)

//   // emit function body
//   let body = Expr::LetTuple([(Name::name_only("_"), LowType::Ptr)] + func_decl.formal_free_vars, 
//                             clos_name, 
//                             func_decl.body)
//   let body_asms = emitter.emit_exp(env, body, true)

//   // emit prelude and conclusion
//   let (prelude, conclusion) = emitter.emit_prelude_conclusion()

//   // tail call optimization
//   let body_asms = tail_call_opt(conclusion.copy(), body_asms)

//   let body = prelude + [] + move_param_asms + body_asms + conclusion
//   AssemblyFunction::{ name: func_decl.name._, export: false, body }
// }

// pub fn emit(prog : Program) -> Array[AssemblyFunction] {
//   let assem_funcs = prog.fundefs.filter(
//       fn(f){
//         if(not(extenv.contains(f.name._))){
//           println(f)
//         }
//           not(extenv.contains(f.name._))
//       }
//   ).map(emit_fun)

//   // minimbt_main
//   let emitter = Emitter::new("minimbt_main")
//   let body_asms = emitter.emit_exp(Env::new(), prog.body, true)
//   let (prelude, conclusion) = emitter.emit_prelude_conclusion()

//   // tail call optimization
//   let body_asms = tail_call_opt(conclusion.copy(), body_asms)
//   let body = prelude + body_asms + conclusion
  
//   assem_funcs + [AssemblyFunction::{name: "minimbt_main", export: true, body }]
// }