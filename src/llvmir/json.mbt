///|
pub fn LLVMIR::to_json(self : LLVMIR) -> Json {
  { "name": self.name.to_json() }
}

///|
pub fn LLVMIR::from_json(json : Json) -> LLVMIR!Error {
  match json {
    {
      "name": name,
      "globals": Array(globals),
      "functions": Array(functions),
      "types": types,
      "metadata": metadata,
      ..
    } =>
      {
        name: name.to_string(),
        globals: {
          let mut result = []
          for global in globals {
            result += [Global::from_json!(global)]
          }
          result
        },
        functions: {
          let mut result = []
          for function in functions {
            result += [Function::from_json!(function)]
          }
          result
        },
        types: {
          let mut result = []
          result += [Type::from_json!(types)]
          result
        },
        metadata: [],
      }
    _ => fail!("invalid json")
  }
}

///|
fn Global::to_json(self : Global) -> Json {
  { "name": self.name.to_json() }
}

///|
fn Global::from_json(json : Json) -> Global!Error {
  match json {
    { "name": name, .. } =>
      {
        name: name.to_string(),
        ty: Type::Void,
        initializer: None,
        is_constant: false,
      }
    _ => fail!("invalid json")
  }
}

///|
fn Function::to_json(self : Function) -> Json {
  { "name": self.name.to_json() }
}

///|
fn Function::from_json(json : Json) -> Function!Error {
  match json {
    { "name": name, .. } =>
      {
        name: name.to_string(),
        return_type: Type::Void,
        parameters: [],
        basic_blocks: [],
      }
    _ => fail!("invalid json")
  }
}

fn Metadata::to_json(self : Metadata) -> Json {
  { "name": self.to_json() }
}

fn Metadata::from_json(json : Json) -> Metadata!Error {
  match json {
    
    _ => fail!("invalid json")
  }
}

fn Type::to_json(self : Type) -> Json {
  { "name": self.to_json() }
}

fn Type::from_json(json : Json) -> Type!Error {
  match json {
    "void" => Type::Void
    _ => fail!("invalid json")
  }
}