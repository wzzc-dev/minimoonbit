///|
pub(all) struct Context {
  str : String
  mut offset : Int
  array : Array[Token]
}

///|
pub fn julex(context : Context) -> Unit {
  let { str, offset, array } = context
  // println("lex: " + str)
  // println("offset: " + offset.to_string())
  // println("array: " + array.to_string())
  if offset >= str.length() {
    return
  }
  match str[offset] {
    '.' => {
      array.push(DOT)
      context.offset += 1
    }
    '+' => {
      array.push(ADD)
      context.offset += 1
    }
    '-' =>
      if str[offset + 1] == '>' {
        array.push(ARROW)
        context.offset += 2
      } else {
        array.push(SUB)
        context.offset += 1
      }
    '*' => {
      array.push(MUL)
      context.offset += 1
    }
    '/' => {
      array.push(DIV)
      context.offset += 1
    }
    '%' => {
      array.push(MOD)
      context.offset += 1
    }
    '=' =>
      if str[context.offset + 1] == '=' {
        array.push(CMP_OPERATOR("=="))
        context.offset += 2
      } else {
        array.push(ASSIGN)
        context.offset += 1
      }
    '!' => {
      if str[context.offset + 1] == '=' {
        array.push(CMP_OPERATOR("!="))
        context.offset += 2
      } else {
        array.push(NOT)
        context.offset += 1
      }
    }
    '>' => {
      if str[context.offset + 1] == '=' {
        array.push(CMP_OPERATOR(">="))
        context.offset += 2
      } else {
        array.push(CMP_OPERATOR(">"))
        context.offset += 1
      }
    }
    '<' =>
      if str[context.offset + 1] == '=' {
        array.push(CMP_OPERATOR("<="))
        context.offset += 2
      } else {
        array.push(CMP_OPERATOR("<"))
        context.offset += 1
      }
    '&' => {
      if str[context.offset + 1] == '&' {
        array.push(AND)
        context.offset += 2
      } else {
        @util.die("Invalid character: " + str[context.offset + 1].to_string())
      }
    }
    '|' => {
      if str[context.offset + 1] == '|' {
        array.push(OR)
        context.offset += 2
      } else {
        @util.die("Invalid character: " + str[context.offset + 1].to_string())
      }
    }
    '(' => {
      array.push(LPAREN)
      context.offset += 1
    }
    ')' => {
      array.push(RPAREN)
      context.offset += 1
    }
    '[' => {
      array.push(LBRACKET)
      context.offset += 1
    }
    ']' => {
      array.push(RBRACKET)
      context.offset += 1
    }
    '{' => {
      array.push(LCURLYBRACKET)
      context.offset += 1
    }
    '}' => {
      array.push(RCURLYBRACKET)
      context.offset += 1
    }
    ':' => {
      array.push(COLON)
      context.offset += 1
    }
    ',' => {
      array.push(COMMA)
      context.offset += 1
    }
    ';' => {
      array.push(SEMICOLON)
      context.offset += 1
    }
    '_' => {
      array.push(WILDCARD)
      context.offset += 1
    }
    ' ' | '\n' | '\t' | '\r' | '\\' => context.offset += 1
    ch =>
      if ch >= '0' && ch <= '9' {
        let number = str.get_char(offset).unwrap()
        context.offset += 1
        lex_number_rest(context, number.to_string())
      } else {
        let ch = str.get_char(offset).unwrap()
        context.offset += 1
        lex_other_rest(context, ch.to_string())
      }
  }
  julex(context)
}

///|
fn lex_number_rest(context : Context, number : String) -> Unit {
  // println("lex_number_rest: " + number)
  let { offset, str, array } = context
  let number_ = (try? @strconv.parse_int64(number)).unwrap()
  
  if offset >= str.length() {
    if number_ > 0x7fffffff {
      array.push(BIG_NUMBER(number_))
    } else {
      array.push(NUMBER(number_.to_int()))
    }
    return
  }
  let ch = str.get_char(offset).unwrap()
  if ch >= '0' && ch <= '9' {
    context.offset += 1
    lex_number_rest(context, number + ch.to_string())
  } else {
    if number_ > 0x7fffffff {
      array.push(BIG_NUMBER(number_))
    } else {
      array.push(NUMBER(number_.to_int()))
    }
  }
}

///|
fn lex_other_rest(context : Context, ident : String) -> Unit {
  let { str, offset, array } = context
  if offset >= str.length() {
    array.push(matchIdentifier(ident))
    return
  }
  let ch = str.get_char(offset).unwrap()
  if (ch >= 'a' && ch <= 'z') ||
    (ch >= 'A' && ch <= 'Z') ||
    (ch >= '0' && ch <= '9') ||
    ch == '_' ||
    ch == '\"' {
    context.offset += 1
    lex_other_rest(context, ident + ch.to_string())
  } else {
    array.push(matchIdentifier(ident))
  }
}

///|
fn matchIdentifier(ident : String) -> Token {
  match ident {
    "true" => TRUE
    "false" => FALSE
    "Unit" => UNIT
    "Bool" => BOOL
    "Int" => INT
    "Double" => DOUBLE
    "Array" => ARRAY
    "not" => NOT
    "if" => IF
    "else" => ELSE
    "fn" => FN
    "let" => LET
    "struct" => STRUCT
    "enum" => ENUM
    "match" => MATCH
    "mut" => MUT
    "while" => WHILE
    "return" => RETURN
    _ => {
      // if ident[0] >= 'A' && ident[0] <= 'Z' {
      //   UPPER_IDENTIFIER(ident)
      // } else {
        IDENTIFIER(ident)
      // }
    }
  }
}

///|
pub(all) enum Token {
  TRUE
  FALSE
  UNIT
  BOOL
  INT
  DOUBLE
  ARRAY
  NOT
  IF
  ELSE
  FN
  LET
  NUMBER(Int)
  BIG_NUMBER(Int64)
  IDENTIFIER(String)
  UPPER_IDENTIFIER(String)
  WILDCARD
  CMP_OPERATOR(String)
  AND
  OR
  DOT
  ADD
  SUB
  MUL
  DIV
  MOD
  ASSIGN
  LE
  LPAREN
  RPAREN
  LBRACKET
  RBRACKET
  LCURLYBRACKET
  RCURLYBRACKET
  ARROW
  COLON
  SEMICOLON
  COMMA
  WS
  COMMENT
  STRUCT
  ENUM
  MATCH
  MUT
  WHILE
  RETURN
} derive(Show)

test {
  let tokens = []
  let source = #| fn main() {
               #|    let hello = "world"
               #|    println(hello)
               #| }
  println(source)
  julex(
    {
      str: source,
      offset: 0,
      array: tokens,
    },
  )
  println(tokens)

  // let (prog, _) = parseType(tokens[:]).unwrap()
  // println(prog)  

}
test {
  let tokens = []
  julex(
    {
      str: "let x = x",
      offset: 0,
      array: tokens,
    },
  )
  println(tokens)

  // let (prog, _) = parseType(tokens[:]).unwrap()
  // println(prog)  
}
test {
  let tokens = []
  let _test2 = @fs.read_file_to_string("contest-2025-data/test_cases/mbt/clamp.mbt")
  println(_test2)
  julex(
    {
      str: _test2,
      offset: 0,
      array: tokens,
    },
  )
  println(tokens)
  
}
