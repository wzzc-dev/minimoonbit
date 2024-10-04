pub struct Context {
  str : String
  mut offset : Int
  array : Array[Token]
}

pub fn lex(context : Context) -> Unit {
  let { offset, str, array } = context
  if offset >= str.length() {
    return
  }
  match str[offset] {
    '.' => {
      array.push(DOT)
      context.offset += 1
    }
    '+' => {
      array.push(Add)
      context.offset += 1
    }
    '-' =>
      if str[offset + 1] == '>' {
        array.push(ARROW)
        context.offset += 2
      } else {
        array.push(Sub)
        context.offset += 1
      }
    '*' => {
      array.push(Mul)
      context.offset += 1
    }
    '/' => {
      array.push(Div)
      context.offset += 1
    }
    '=' =>
      if str[context.offset + 1] == '=' {
        array.push(EQ)
        context.offset += 2
      } else {
        array.push(ASSIGN)
        context.offset += 1
      }
    '<' =>
      if str[context.offset + 1] == '=' {
        array.push(LE)
        context.offset += 2
      } else {
        array.push(LE)
        context.offset += 1
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
    ' ' | '\n' | '\t' | '\r' | '\\' => context.offset += 1
    ch =>
      if ch >= '1' && ch <= '9' {
        let number = "\{str[offset]}"
        context.offset += 1
        lex_number_rest(context, number)
      } else {
        let ident = "\{str[offset]}"
        context.offset += 1
        lex_other_rest(context, ident)
      }
  }
  lex(context)
}

fn lex_number_rest(context : Context, number : String) -> Unit {
  let { offset, str, array } = context
  if offset >= str.length() {
    array.push(NUMBER(@strconv.parse_int?(number).unwrap()))
    return
  }
  let ch = str[offset]
  if ch >= '0' && ch <= '9' {
    context.offset += 1
    lex_number_rest(context, number + ch.to_string())
  } else {
    array.push(NUMBER(@strconv.parse_int?(number).unwrap()))
  }
}

fn lex_other_rest(context : Context, ident : String) -> Unit {
  let { offset, str, array } = context
  if offset >= str.length() {
    array.push(matchIdentifier(ident))
    return
  }
  let ch = str[offset]
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
      _ => IDENTIFIER(ident)
    }
}

pub enum Token {
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
  IDENTIFIER(String)
  DOT
  Add
  Sub
  Mul
  Div
  ASSIGN
  EQ
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
  WA
  COMMENT
} derive(Show)

test {
  let tokens = []
  lex(
    {
      str: #| fn main() {
           #|    let hello = "world"
           #|    println(hello)
           #| }
      ,
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
  lex(
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