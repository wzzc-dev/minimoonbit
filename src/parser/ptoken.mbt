///|
let ptoken_array : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::ARRAY => true
    _ => false
  }
})

///|
let ptoken_make : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::IDENTIFIER("make") => true
    _ => false
  }
})

///|
let ptoken_not : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::NOT => true
    _ => false
  }
})

///|
let ptoken_number : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::NUMBER(_) => true
    @lex.Token::BIG_NUMBER(_) => true
    _ => false
  }
})

///|
let ptoken_float_number : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::FLOAT_NUMBER(_) => true
    _ => false
  }
})

///|
let ptoken_fn : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::FN => true
    _ => false
  }
})

///|
let ptoken_let : Parser[@lex.Token] = ptoken(fn(token) {
  // @util.logger("ptoken_let token: " + token.to_string())
  match token {
    @lex.Token::LET => true
    _ => false
  }
})

///|
let dot : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::DOT => true
    _ => false
  }
})

///|
let ptoken_assign : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::ASSIGN => true
    _ => false
  }
})

///|
let ptoken_colon : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::COLON => true
    _ => false
  }
})

///|
let ptoken_comma : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::COMMA => true
    _ => false
  }
})

///|
let lparen : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::LPAREN => true
    _ => false
  }
})

///|
let rparen : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::RPAREN => true
    _ => false
  }
})

///|
let lbracket : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::LBRACKET => true
    _ => false
  }
})

///|
let rbracket : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::RBRACKET => true
    _ => false
  }
})

///|
let lcurlybracket : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::LCURLYBRACKET => true
    _ => false
  }
})

///|
let rcurlybracket : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::RCURLYBRACKET => true
    _ => false
  }
})

///|
let identifier : Parser[@lex.Token] = ptoken(fn(token) {
  // @util.logger("identifier token: " + token.to_string())
  match token {
    @lex.Token::IDENTIFIER(_) => true
    _ => false
  }
})

///|
let upperIdentifier : Parser[@lex.Token] = ptoken(fn(token) {
  // @util.logger("identifier token: " + token.to_string())
  match token {
    @lex.Token::UPPER_IDENTIFIER(_) => true
    _ => false
  }
})

///|
let semicolon : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    SEMICOLON => true
    _ => false
  }
})

///|
let ptoken_while : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::WHILE => true
    _ => false
  }
})

///|
let ptoken_return : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::RETURN => true
    _ => false
  }
})

///|
let ptoken_struct : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::STRUCT => true
    _ => false
  }
})
// let ptoken_lbracket : Parser[@lex.Token] = ptoken(fn(token) {
//   match token {
//     @lex.Token::LBRACKET => true
//     _ => false
//   }
// })
// let ptoken_rbracket : Parser[@lex.Token] = ptoken(fn(token) {
//   match token {
//     @lex.Token::RBRACKET => true
//     _ => false
//   }
// })

///|
let ptoken_plus : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::ADD => true
    _ => false
  }
})

///|
let ptoken_minus : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::SUB => true
    _ => false
  }
})

///|
let ptoken_and : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::AND => true
    _ => false
  }
})

///|
let ptoken_or : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::OR => true
    _ => false
  }
})

///|
let ptoken_mod : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::MOD => true
    _ => false
  }
})

///|
let ptoken_star : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::MUL => true
    _ => false
  }
})

///|
let ptoken_if : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::IF => true
    _ => false
  }
})

///|
let ptoken_else : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::ELSE => true
    _ => false
  }
})

///|
let ptoken_slash : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::DIV => true
    _ => false
  }
})

///|
let ptoken_mut : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::MUT => true
    _ => false
  }
})

///|
let ptoken_cmp_operator : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::CMP_OPERATOR(_) => true
    _ => false
  }
})

let ptoken_enum : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::ENUM => true
    _ => false
  }
})

let ptoken_match : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::MATCH => true
    _ => false
  }
})

let ptoken_true : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::TRUE => true
    _ => false
  }
})

let ptoken_false : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::FALSE => true
    _ => false
  }
})

let ptoken_wildcard : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::WILDCARD => true
    _ => false
  }
})


let ptoken_gt : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::CMP_OPERATOR(">") => true
    _ => false
  }
})