///| The stage to be run next.
enum Stages {
  Parse
  Typecheck
  Knf
  KnfOpt
  Closure
  Ssa
  Asm
  Finished
} derive(Show, Eq, Compare)

///|
fn Stages::from_string(s : String) -> Stages? {
  match s {
    "parse" => Some(Stages::Parse)
    "typecheck" => Some(Stages::Typecheck)
    "knf" => Some(Stages::Knf)
    "knf-opt" => Some(Stages::KnfOpt)
    "closure" => Some(Stages::Closure)
    "ssa" => Some(Stages::Ssa)
    "riscv" => Some(Stages::Asm)
    "finished" => Some(Stages::Finished)
    _ => None
  }
}

///|
fn Stages::next(self : Stages) -> Stages {
  match self {
    Stages::Parse => Stages::Typecheck
    Stages::Typecheck => Stages::Knf
    Stages::Knf => Stages::KnfOpt
    Stages::KnfOpt => Stages::Closure
    Stages::Closure => Stages::Asm
    Stages::Ssa => Stages::Asm
    Stages::Asm => Stages::Finished
    Stages::Finished => Stages::Finished
  }
}

///|
struct CompileStatus {
  mut curr_stage : Stages
  end_stage : Stages
  mut source_code : String?
  mut ast : @types.Syntax?
  mut typechecked : @types.Syntax?
  knf_env : @knf.KnfEnv
  mut knf : @knf.Knf?
  mut opt_knf : @knf.Knf?
  mut closure_ir : @closure.Program?
  mut ssa : @ssa.Ssa?
  mut llvmir : @llvmir.LLVMIR?
  mut asm : Array[@riscv.AssemblyFunction]?
  mut js : String?
  mut wasm : String?
}

///|
fn CompileStatus::initialize(
  start_stage : Stages,
  end_stage : Stages,
  file : String
) -> CompileStatus! {
  let v = CompileStatus::{
    curr_stage: start_stage,
    end_stage,
    source_code: None,
    ast: None,
    typechecked: None,
    knf_env: @knf.KnfEnv::new(externals()),
    knf: None,
    opt_knf: None,
    closure_ir: None,
    ssa: None,
    llvmir: None,
    asm: None,
    js: None,
    wasm: None,
  }
  match start_stage {
    Parse => v.source_code = Some(file)
    Typecheck => v.ast = Some(@types.Syntax::from_json!(@json.parse!(file)))
    Knf => v.typechecked = Some(@types.Syntax::from_json!(@json.parse!(file)))
    KnfOpt => {
      v.knf = Some(@knf.Knf::from_json!(@json.parse!(file)))
      v.knf_env.init_counter_from_existing(v.knf.unwrap())
    }
    Closure => {
      v.opt_knf = Some(@knf.Knf::from_json!(@json.parse!(file)))
      v.knf_env.init_counter_from_existing(v.opt_knf.unwrap())
    }
    Ssa => v.closure_ir = Some(@closure.Program::from_json!(@json.parse!(file)))
    _ => fail!("invalid start stage")
  }
  v
}

///| Run the next stage of compilation. Returns true if the compilation is finished.
fn CompileStatus::step(self : CompileStatus, backend : Backend) -> Bool {
  if self.curr_stage >= self.end_stage {
    return true
  }
  match self.curr_stage {
    Parse => {
      let source_code = self.source_code.unwrap()
      let parsed = @parser.parse_from_string(source_code)
      self.ast = Some(parsed)
    }
    Typecheck => {
      let typechecked = @typing.typing?(self.ast.unwrap())
      self.typechecked = Some(typechecked.unwrap())
    }
    Knf => {
      let pre = @knf.KnfEnv::syntax_preprocess(self.knf_env, self.typechecked.unwrap())
      let knf = self.knf_env.to_knf?(pre)
      self.knf = Some(knf.unwrap())
    }
    KnfOpt => {
      let knf = self.knf.unwrap()
      // TODO: optimize
      self.opt_knf = Some(knf)
    }
    Closure => {
      let closure_ir = @closure.knf_program_to_closure(
        self.opt_knf.unwrap(),
        Map::from_iter(externals().iter()),
      )
      self.closure_ir = Some(closure_ir)
    }
    Ssa => {
      let ssa = @ssa.to_ssa(self.closure_ir.unwrap())
      self.ssa = Some(ssa)
    }
    Asm =>
      match backend {
        JS => {
          let js_code = @js.emit(self.closure_ir.unwrap())
          self.js = Some(js_code)
        }
        WASM => {
          let wasm_code = @wasm.emit(self.closure_ir.unwrap())
          self.wasm = Some(wasm_code)
        }
        LLVMIR => {
          let llvmir = @llvmir.to_llvmir(self.closure_ir.unwrap())
          self.llvmir = Some(llvmir)
        }
        RISCV => {
          let real_asm = @riscv.emit(self.closure_ir.unwrap())
          self.asm = Some(real_asm)
        }
      }
    Finished => ()
  }
  self.curr_stage = self.curr_stage.next()
  self.curr_stage >= self.end_stage
}

///|
fn CompileStatus::output(
  self : CompileStatus,
  json : Bool,
  outTy : Backend
) -> String {
  if json {
    match self.curr_stage {
      Parse => self.source_code.unwrap()
      Typecheck => @json.stringify(self.ast.unwrap().to_json())
      Knf => @json.stringify(self.typechecked.unwrap().to_json())
      KnfOpt => @json.stringify(self.knf.unwrap().to_json())
      Closure => @json.stringify(self.opt_knf.unwrap().to_json())
      Ssa => @json.stringify(self.closure_ir.unwrap().to_json())
      Asm => @json.stringify(self.closure_ir.unwrap().to_json())
      Finished => @riscv.print_functions(self.asm.unwrap())
    }
  } else {
    match self.curr_stage {
      Parse => self.source_code.unwrap()
      Typecheck => self.ast.unwrap().to_string()
      Knf => self.typechecked.unwrap().to_string()
      KnfOpt => self.knf.unwrap().to_string()
      Closure => self.opt_knf.unwrap().to_string()
      Ssa => self.closure_ir.unwrap().to_string()
      Asm => self.closure_ir.unwrap().to_string()
      Finished =>
        match outTy {
          JS => self.js.unwrap()
          WASM => self.wasm.unwrap()
          LLVMIR => @llvmir.print_functions(self.llvmir.unwrap())
          RISCV => @riscv.print_functions(self.asm.unwrap())
        }
    }
  }
}

///|
fn main {
  let argv = @sys.get_cli_args()
  // println(argv)
  let mut file = None
  let knf_opt_iters = Ref::new(10)
  let knf_opt_inline_threshold = Ref::new(10)

  // Testing directives
  let json = Ref::new(false)
  let start_stage = Ref::new(Stages::Parse)
  let end_stage = Ref::new(Stages::Finished)
  let knf_interpreter = Ref::new(false)
  let closure_interpreter = Ref::new(false)
  let ssa_interpreter = Ref::new(false)
  let out_file = Ref::new("-")
  let print = Ref::new([])
  let js = Ref::new(false)
  let wasm = Ref::new(false)
  let llvmir = Ref::new(false)
  // 
  @ArgParser.parse(
    [
      (
        "--start-stage",
        "",
        @ArgParser.String(
          fn(s) {
            match Stages::from_string(s) {
              Some(stage) => start_stage.val = stage
              None => @util.die("Invalid stage")
            }
          },
        ),
        "Start stage",
      ),
      (
        "--end-stage",
        "",
        @ArgParser.String(
          fn(s) {
            match Stages::from_string(s) {
              Some(stage) => end_stage.val = stage
              None => @util.die("Invalid stage")
            }
          },
        ),
        "End stage",
      ),
      (
        "--knf-interpreter",
        "",
        @ArgParser.Set(knf_interpreter),
        "Run with KNF interpreter",
      ),
      (
        "--closure-interpreter",
        "",
        @ArgParser.Set(closure_interpreter),
        "Run with closure interpreter",
      ),
      (
        "--ssa-interpreter",
        "",
        @ArgParser.Set(ssa_interpreter),
        "Run with Ssa interpreter",
      ),
      (
        "--out-file",
        "-o",
        @ArgParser.String(fn(s) { out_file.val = s }),
        "Output file",
      ),
      ("--json", "", @ArgParser.Set(json), "Print results as JSON"),

      // Regular directives
      (
        "--print",
        "",
        @ArgParser.String(fn(s) { print.val = s.split(",").collect() }),
        "",
      ),
      (
        "--knf-opt-iters",
        "N",
        @ArgParser.String(
          fn(s) {
            let i = @strconv.parse_int?(s)
            match i {
              Ok(i) => knf_opt_iters.val = i
              Err(_) => @util.die("Invalid number")
            }
          },
        ),
        "Number of optimization iterations",
      ),
      (
        "--knf-opt-inline-threshold",
        "N",
        @ArgParser.String(
          fn(s) {
            let i = @strconv.parse_int?(s)
            match i {
              Ok(i) => knf_opt_inline_threshold.val = i
              Err(_) => @util.die("Invalid number")
            }
          },
        ),
        "Inline threshold for KNF optimization",
      ),
      ("--js", "", @ArgParser.Set(js), "Generate JavaScript code"),
      ("--wasm", "", @ArgParser.Set(wasm), "Generate WebAssembly code"),
      ("--llvmir", "", @ArgParser.Set(llvmir), "Generate llvmir"),
    ],
    fn(s) {
      if not(file.is_empty()) {
        @util.die("multiple files are given")
      }
      file = Some(s)
    },
    "",
    argv.split_at(2).1,
  )

  // Configure pipeline
  if knf_interpreter.val {
    end_stage.val = Stages::Knf
  }
  if closure_interpreter.val {
    end_stage.val = Stages::Closure
  }
  if ssa_interpreter.val {
    end_stage.val = Stages::Ssa
  }
  let stages_to_print = print.val.map(
    fn(s) {
      match Stages::from_string(s) {
        Some(stage) => stage
        None => @util.die("Invalid stage to print: \{s}")
      }
    },
  )

  // Input
  let file = if file.is_empty() {
    @util.die("no input file provided")
  } else {
    file.unwrap()
  }
  let contents = @fs.read_file_to_string?(path=file).unwrap()

  // Compilation
  let status = match
    CompileStatus::initialize?(start_stage.val, end_stage.val.next(), contents) {
    Ok(status) => status
    Err(e) => {
      println(e)
      @util.die("Initialization error")
    }
  }
  // Run stages
  while true {
    let stg = status.curr_stage
    let ty = if js.val {
        JS
      } else if wasm.val {
        WASM
      } else if llvmir.val {
        LLVMIR
      } else {
        RISCV
      }
    let stop = status.step(ty)
    if stages_to_print.contains(stg) {
      println("Stage: \{stg}")
      println(status.output(json.val, ty))
    }
    if stop {
      break
    }
  }

  // Output
  if knf_interpreter.val {
    let knfi = @knf_eval.KnfInterpreter::new()
    add_interpreter_fns(knfi)
    match knfi.eval_full?(status.knf.unwrap()) {
      Ok(_) => ()
      Err(Failure(e)) => {
        println(e)
        @util.die("KNF interpreter error")
      }
    }
  } else if closure_interpreter.val {
    let clsi = @closure_eval.ClosureInterpreter::new()
    add_closure_interpreter_fns(clsi)
    match clsi.eval_full?(status.closure_ir.unwrap()) {
      Ok(_) => ()
      Err(Failure(e)) => {
        println(e)
        @util.die("Closure interpreter error")
      }
    }
  } else if ssa_interpreter.val {
    println(status.ssa.unwrap())
  } else {
    let ty = if js.val {
      JS
    } else if wasm.val {
      WASM
    } else if llvmir.val {
      LLVMIR
    } else {
      RISCV
    }
    let out_string = status.output(json.val, ty)
    if out_file.val == "-" {
      println(out_string)
    } else {
      @fs.write_string_to_file(path=out_file.val, content=out_string)
    }
  }
}

///|
enum Backend {
  JS
  WASM
  LLVMIR
  RISCV
}
