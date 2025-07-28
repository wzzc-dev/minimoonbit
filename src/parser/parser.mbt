///|
fn program(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(topLevel).parse(tokens)
}

///|
fn topLevel(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("topLevel: " + tokens.to_string())
  Parser(toplevelFnDecl).or(topLetDecl).parse(tokens)
}

///|
fn topLetDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("topLetDecl: " + tokens.to_string())
  ptoken(fn(token) {
    match token {
      @lex.Token::LET => true
      _ => false
    }
  })
  .parser_and(identifier)
  .parser_and(ptoken_colon)
  .parser_and(parseType)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .zeroOrOnce(topLevel)
  .map(fn(input) {
    match input {
      (
        ((((((_, @lex.Token::IDENTIFIER(id)), _), _type), _), expr), _),
        Some(topLevel),
      ) => @types.Syntax::Let((id, _type), expr, topLevel)
      (((((((_, @lex.Token::IDENTIFIER(id)), _), _type), _), expr), _), None) =>
        @types.Syntax::Let((id, _type), expr, Unit)
      (((((((_, ident), _), _type), _), expr), _), _) => {
        println(
          "Invalid top let decl declaration" +
          tokens.to_string() +
          "expr: " +
          expr.to_string() +
          "ident: " +
          ident.to_string(),
        )
        panic()
      }
      // _ => {
      //   println("Invalid top let decl declaration" + tokens.to_string())
      //   panic()
      // }
    }
  })
  .parse(tokens)
}

///|
fn toplevelFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(mainFnDecl)
  .or(topFnDecl)
  .parser_and(semicolon)
  .zeroOrOnce(topLevel)
  .map(fn(input) {
    match input {
      (((name, args, body), _), Some(topLevel)) =>
        // println("top_let_decl: name" + name.to_string())
        @types.Syntax::LetRec({ name, args, body }, topLevel)
      (((name, args, body), _), None) =>
        // println("top_let_decl: name None" + name.to_string())
        @types.Syntax::LetRec({ name, args, body }, @types.Syntax::Unit)
    }
  })
  .parse(tokens)
}

///|
fn mainFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (
  ((String, @types.Type), Array[(String, @types.Type)], @types.Syntax),
  ArrayView[@lex.Token],
)? {
  // println("main_fn_decl: " + tokens.to_string())
  ptoken(fn(token) {
    match token {
      @lex.Token::FN => true
      _ => false
    }
  })
  .parser_and(
    ptoken(fn(token) {
      match token {
        @lex.Token::IDENTIFIER("main") => true
        @lex.Token::IDENTIFIER("init") => true
        _ => false
      }
    }),
  )
  .parser_and(fnBody)
  .map(fn(input) {
    match input {
      ((_, _), fnBody) => (("main", @types.Type::Fun([], @types.Type::Unit)), [], fnBody)
    }
  })
  .parse(tokens)
}

// top_fn_decl:
// 	'fn' IDENTIFIER '(' param_list? ')' '->' type fn_body;

///|
fn topFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (
  ((String, @types.Type), Array[(String, @types.Type)], @types.Syntax),
  ArrayView[@lex.Token],
)? {
  // println("top_fn_decl: " + tokens.to_string())
  ptoken_fn
  .parser_and(identifier)
  .parser_and(lparen)
  .zeroOrOnce(paramList)
  .parser_and(rparen)
  .parser_and(arrow)
  .parser_and(parseType)
  .parser_and(fnBody)
  .map(fn(input) {
    // println("top_fn_decl input : " + input.to_string())
    match input {
      (
        (
          (((((_, @lex.Token::IDENTIFIER(id)), _), Some(param_list)), _), _),
          type_,
        ),
        fnBody,
      ) => {
        let fun_type = param_list.map(fn(input) {
          match input {
            (_, type_) => type_
          }
        })
        ((id, @types.Fun(fun_type, type_)), param_list, fnBody)
      }
      (((((((_, @lex.Token::IDENTIFIER(id)), _), None), _), _), type_), fnBody) =>
        ((id, @types.Fun([], type_)), [], fnBody)
      (((((((_, ident), _), _), _), _), type_), fnBody) => {
        println("Invalid top fn decl declaration" + tokens.to_string())
        println(
          "ident: " +
          ident.to_string() +
          " type: " +
          type_.to_string() +
          " fnBody: " +
          fnBody.to_string(),
        )
        panic()
      }
    }
  })
  .parse(tokens)
}

// param_list: param (',' param)*;

///|
fn paramList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, @types.Type)], ArrayView[@lex.Token])? {
  Parser(param)
  .parser_and(comma.parser_and(param).many())
  .map(fn(input) {
    match input {
      (param, param_list) => {
        // println("param_list")
        let params = [param]
        for x in param_list {
          let (_, x) = x
          params.push(x)
        }
        params
      }
    }
  })
  .parse(tokens)
}

// param: IDENTIFIER type_annotation;

///|
fn param(
  tokens : ArrayView[@lex.Token],
) -> ((String, @types.Type), ArrayView[@lex.Token])? {
  identifier
  .parser_and(typeAnnotation)
  .map(fn(input) {
    match input {
      (@lex.Token::IDENTIFIER(i), t) => (i, t)
      _ =>
        // println("Invalid param")
        panic()
    }
  })
  .parse(tokens)
}

// fn_body: '{' stmt '}';

///|
fn fnBody(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("fnBody: " + tokens.to_string())
  lcurlybracket
  .parser_and(stmt)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    match input {
      ((_, stmt), _) => stmt
      // {
      // println("fnBody: stmt :" + stmt.to_string())

      // }
    }
  })
  .parse(tokens)
}

// nontop_fn_decl:
// 	'fn' IDENTIFIER '(' nontop_param_list? ')' (
// 		'->' type
// 	)? fn_body;

///|
fn nontopFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (
  ((String, @types.Type), Array[(String, @types.Type)], @types.Syntax),
  ArrayView[@lex.Token],
)? {
  // println("nontop_fn_decl: " + tokens.to_string())
  ptoken_fn
  .parser_and(identifier)
  .parser_and(lparen)
  .zeroOrOnce(nonTopParamList)
  .parser_and(rparen)
  .zeroOrOnce(arrow.parser_and(parseType))
  .parser_and(fnBody)
  .map(fn(input) {
    match input {
      ((((((_, @lex.Token::IDENTIFIER(id)), _), param_list), _), type_), fnBody) => {
        // println("nontop_fn_decl")
        // println("nontop_fn_decl: id: " + id.to_string())
        // println("nontop_fn_decl: param_list: " + param_list.to_string())
        // println("nontop_fn_decl: type_: " + type_.to_string())

        let params = match param_list {
          Some(type_) => type_
          None => []
        }
        let fun_type = params.map(fn(input) {
          match input {
            (_, type_) => type_
          }
        })
        let type_ = match type_ {
          Some((_, type_)) => @types.Type::Fun(fun_type, type_)
          None => @types.Type::Fun(fun_type, Var({ val: None }))
        }
        // println("nontop_fn_decl: params: " + params.to_string() + ": " + ((id, type_), params, fnBody).to_string())
        ((id, type_), params, fnBody)
      }
      _ as result => {
        println("nontop_fn_decl: --- token: " + tokens.to_string())
        println("nontop_fn_decl: --- result: " + result.to_string())
        println("Invalid non top level declaration")
        panic()
      }
    }
  })
  .parse(tokens)
}
// nontop_param_list:
// 	nontop_param (',' nontop_param)*;

///|
fn nonTopParamList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, @types.Type)], ArrayView[@lex.Token])? {
  Parser(nonTopParam)
  .parser_and(comma.parser_and(nonTopParam).many())
  .map(fn(input) {
    match input {
      (first, param_list) => {
        let param_list = param_list.map(fn(input) {
          match input {
            (_, x) => x
          }
        })
        [first, ..param_list]
      }
    }
  })
  .parse(tokens)
}

// nontop_param: IDENTIFIER type_annotation?;

///|
fn nonTopParam(
  tokens : ArrayView[@lex.Token],
) -> ((String, @types.Type), ArrayView[@lex.Token])? {
  identifier
  .zeroOrOnce(typeAnnotation)
  .map(fn(input) {
    match input {
      (@lex.Token::IDENTIFIER(id), type_annotation) =>
        match type_annotation {
          Some(type_annotation) => (id, type_annotation)
          None => (id, Var({ val: None }))
        }
      _ =>
        // println("Invalid non top level declaration")
        panic()
    }
  })
  .parse(tokens)
}

///|
fn stmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("stmt: " + tokens.to_string())
  Parser(letTupleStmt)
  .or(letStmt)
  .or(fnDeclStmt)
  .or(assignStmt)
  .or(exprStmt)
  .parse(tokens)
}

///|
fn letTupleStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("letTupleStmt: " + tokens.to_string())
  ptoken_let
  .parser_and(lparen)
  .parser_and(identifier)
  .parser_and(comma.parser_and(identifier).many())
  .parser_and(rparen)
  .zeroOrOnce(typeAnnotation)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .parser_and(stmt)
  .map(fn(input) {
    match input {
      (
        (
          (
            (
              (
                (((_, @lex.Token::IDENTIFIER(identifier)), identifiers), _),
                type_annotation,
              ),
              _,
            ),
            expr,
          ),
          _,
        ),
        stmt,
      ) => {
        let ids = [(identifier, @types.Type::Var({ val: None }))]
        for x in identifiers {
          match x {
            (_, @lex.Token::IDENTIFIER(i)) =>
              ids.push((i, @types.Type::Var({ val: None })))
            (_, ident) => {
              println("let tuple ident: " + ident.to_string())
              panic()
            }
          }
        }
        // let mut ids = identifiers.map(
        //   fn {
        //     (@lex.Token::IDENTIFIER(i), _) => (i, @types.Type::Var({ val: None }))
        //     _ => panic()
        //   }
        // )
        // ids = [(identifier, @types.Type::Unit), ..ids]
        match type_annotation {
          Some(type_) => {
            match type_ {
              Tuple(typeTuple) =>
                for i, e in typeTuple {
                  ids[i] = (ids[i].0, e)
                }
              _ => {
                println("type_annotation is not a tuple")
                panic()
              }
            }
            @types.Syntax::LetTuple(ids, expr, stmt)
          }
          None => @types.Syntax::LetTuple(ids, expr, stmt)
        }
      }
      _ => {
        println("Invalid let statement")
        panic()
      }
    }
  })
  .parse(tokens)
}
// let_stmt:
// 	'let' IDENTIFIER type_annotation? '=' expr ';' stmt;

///|
fn letStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("letStmt: " + tokens.to_string())
  ptoken_let
  .parser_and(identifier)
  .zeroOrOnce(typeAnnotation)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .parser_and(stmt)
  .map(fn(input) {
    match input {
      (
        (
          ((((_, @lex.Token::IDENTIFIER(id)), Some(type_annotation)), _), expr),
          _,
        ),
        stmt,
      ) =>
        // println("letStmt: " + ((id, type_annotation), expr, stmt).to_string())
        @types.Syntax::Let((id, type_annotation), expr, stmt)
      ((((((_, @lex.Token::IDENTIFIER(id)), None), _), expr), _), stmt) =>
        // println("letStmt: None" + (id, expr, stmt).to_string())
        @types.Syntax::Let((id, @types.Type::Var({ val: None })), expr, stmt)
      _ =>
        // println("Invalid let statement")
        panic()
    }
  })
  .parse(tokens)
}



// type_annotation: COLON type;

///|
fn typeAnnotation(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  ptoken_colon.parser_and(parseType).map(fn(input) {
    match input {
      (_, t) => t
    }
  }).parse(tokens)
}

// fn_decl_stmt: nontop_fn_decl ';' stmt;

///|
fn fnDeclStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("fnDeclStmt: " + tokens.to_string())
  Parser(nontopFnDecl)
  .parser_and(semicolon)
  .parser_and(stmt)
  .map(fn(input) {
    match input {
      (((name, args, body), _), stmt) =>
        // println("fnDeclStmt: " + ((name, args, body), stmt).to_string())
        @types.Syntax::LetRec({ name, args, body }, stmt)
    }
  })
  .parse(tokens)
}

// // x[y] = z;
// assign_stmt: get_expr '=' expr ';' stmt;

///|
fn assignStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("assignStmt: " + tokens.to_string())
  Parser(getOrApplyLevelExpr)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .parser_and(stmt)
  .map(fn(input) {
    match input {
      ((((get_expr, _), expr), _), stmt) =>
        match get_expr {
          Get(arr, idx) =>
            @types.Syntax::Let(("_", Unit), Put(arr, idx, expr), stmt)
          _ => {
            println("Invalid assign statement")
            @types.Syntax::Let(("_", Var({ val: None })), get_expr, stmt)
          }
        }
    }
  })
  .parse(tokens)
}

// expr_stmt: expr;

///|
fn exprStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("exprStmt: " + tokens.to_string())
  Parser(expr).parse(tokens)
}

///|
fn expr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("expr: " + tokens.to_string())
  Parser(exprEq).or(exprLe).or(addSubLevelExpr).parse(tokens)
}



///|
fn exprEq(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(addSubLevelExpr)
  .parser_and(ptoken_eq)
  .parser_and(expr)
  .map(fn(input) {
    match input {
      ((expr, _), expr2) => @types.Syntax::Eq(expr, expr2)
    }
  })
  .parse(tokens)
}

///|
let ptoken_le : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::LE => true
    _ => false
  }
})




///|
fn exprLe(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("exprLe: " + tokens.to_string())
  Parser(addSubLevelExpr)
  .parser_and(ptoken_le)
  .parser_and(expr)
  .map(fn(input) {
    match input {
      ((expr, _), expr2) => @types.Syntax::LE(expr, expr2)
    }
  })
  .parse(tokens)
}




///|
fn addSubLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(mulDivLevelExpr)
  .parser_and(ptoken_plus.or(ptoken_minus).parser_and(mulDivLevelExpr).many())
  .map(fn(input) {
    match input {
      (e, list) => {
        if list.is_empty() {
          return e
        }
        let result = list.fold(init=e, fn(e, input) {
          match input {
            (Add, expr) => Prim(e, expr, Add, kind=None)
            (Sub, expr) => Prim(e, expr, Sub, kind=None)
            (t, _) => {
              println(" Add or Sub not " + t.to_string())
              panic()
            }
          }
        })
        result
      }
    }
  })
  .parse(tokens)
}



///|
let ptoken_plus : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::Add => true
    _ => false
  }
})

///|
let ptoken_minus : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::Sub => true
    _ => false
  }
})

// mul_div_level_expr:
//  if_level_expr
//  | if_level_expr '*' mul_div_level_expr
//  | if_level_expr '/' mul_div_level_expr;



fn mulDivLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(ifLevelExpr)
 .zeroOrOnce(
    ptoken_star.parser_and(mulDivLevelExpr).or(ptoken_slash.parser_and(mulDivLevelExpr)),
  )
  .map(
    fn(input){
      match input {
        (expr, None) => expr
        (expr, Some((t, expr2))) => {
          match t {
            @lex.Token::Mul => Prim(expr, expr2, Mul, kind=None)
            @lex.Token::Div => Prim(expr, expr2, Div, kind=None)
            _ => {
              println(" Mul or Div not " + t.to_string())
              panic()
            }
          }
        }
      }
    }
  )
  .parse(tokens)
}
///|
let ptoken_star : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::Mul => true
    _ => false
  }
})

///|
let ptoken_slash : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::Div => true
    _ => false
  }
})

///|
fn ifLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("ifLevelExpr: " + tokens.to_string())
  Parser(getOrApplyLevelExpr).or(ifExpr).parse(tokens)
}

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
fn ifExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("ifExpr: " + tokens.to_string())
  ptoken_if
  .parser_and(expr)
  .parser_and(blockExpr)
  .zeroOrOnce(ptoken_else.parser_and(blockExpr))
  .map(fn(input) {
    match input {
      (((_, expr), block_expr), Some((_, block_expr2))) =>
        @types.Syntax::If(expr, block_expr, block_expr2)
      (((_, expr), block_expr), None) =>
        @types.Syntax::If(expr, block_expr, Unit)
    }
  })
  .parse(tokens)
}

///|
fn getOrApplyLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("getOrApplyLevelExpr: " + tokens.to_string())
  // Parser(getExpr).or(applyExpr).or(valueExpr).parse(tokens)
  Parser(valueExpr)
  .parser_and(
    lbracket
    .or(lparen)
    .zeroOrOnce(Parser(expr).parser_and(comma.parser_and(expr).many()))
    .parser_and(rbracket.or(rparen))
    .many(),
    // )
  )
  .map(fn(input) {
    match input {
      (expr, list) => {
        if list.is_empty() {
          return expr
        }
        let result = list.fold(init=expr, fn(acc, item) {
          match (acc, item) {
            (e, ((l, None), _)) =>
              match l {
                LBRACKET => {
                  println(
                    "getExpr LBRACKET not empty - token :" + tokens.to_string(),
                  )
                  panic()
                }
                LPAREN => App(e, [])
                _ => {
                  println("Invalid getExpr need [ or (")
                  panic()
                }
              }
            (e, ((l, Some((expr1, list))), _)) => {
              let tails = list.map(e2 => e2.1)
              // println("applyExpr tails: " + tails.to_string())
              // println("applyExpr l: " + l.to_string())
              match l {
                LBRACKET =>
                  if list.is_empty() {
                    Get(e, expr1)
                  } else {
                    println(
                      "getExpr LBRACKET is not empty - token :" +
                      tokens.to_string(),
                    )
                    panic()
                  }
                LPAREN => App(e, [expr1, ..tails])
                _ => panic()
              }
            }
          }
        })
        result
      }
    }
  })
  .parse(tokens)
}
// fn getExpr(
//   tokens : ArrayView[@lex.Token]
// ) -> (@types.Syntax, ArrayView[@lex.Token])? {
//   // println("getExpr: " + tokens.to_string())
//   // Parser(valueExpr)
//   // .and(lbracket)
//   // .and(expr)
//   // .and(rbracket)
//   // .map(
//   //   fn { (((value_expr, _), expr), _) => @types.Syntax::Get(value_expr, expr) },
//   // )
//   // .parse(tokens)
//   Parser(valueExpr)
//   .and(lbracket.and(expr).and(rbracket).many())
//   .map(
//     fn {
//       (e, list) => {
//         let result = list.fold(init=e, fn { e, ((_, expr), _) => Get(e, expr) })
//         result
//       }
//     },
//   )
//   .parse(tokens)
// }

// fn applyExpr(
//   tokens : ArrayView[@lex.Token]
// ) -> (@types.Syntax, ArrayView[@lex.Token])? {
//   // println("applyExpr: " + tokens.to_string())
//   // Parser(noEmptyApplyExpr).or(emptyApplyExpr).parse(tokens)
//   Parser(valueExpr)
//   .and(
//     lparen
//     .zeroOrOnce(Parser(expr).zeroOrOnce(comma.and(expr).many()))
//     .and(rparen)
//     .many(),
//   )
//   .map(
//     fn {
//       (e, list) => {
//         let result = list.fold(
//           init=e,
//           fn {
//             e, ((_, None), _) => App(e, [])
//             e, ((_, Some((expr1, None))), _) => App(e, [expr1])
//             e, ((_, Some((expr1, Some(arr)))), _) => {
//               let arr_t = arr.map(fn { (_, t) => t })
//               App(e, [expr1, ..arr_t])
//             }
//           },
//         )
//         result
//       }
//     },
//   )
//   .parse(tokens)
// }

// fn emptyApplyExpr(
//   tokens : ArrayView[@lex.Token]
// ) -> (@types.Syntax, ArrayView[@lex.Token])? {
//   // println("emptyApplyExpr: " + tokens.to_string())
//   Parser(valueExpr)
//   .and(lparen)
//   .and(rparen)
//   .map(
//     fn {
//       ((valueExpr, _), _) =>
//         // println("emptyApplyExpr: ")
//         @types.Syntax::App(valueExpr, [])
//     },
//   )
//   .parse(tokens)
// }

// // fn noEmptyApplyExpr(
// //   tokens : ArrayView[@lex.Token]
// // ) -> (@types.Syntax, ArrayView[@lex.Token])? {
// //   // println("noEmptyApplyExpr: " + tokens.to_string())
// //   Parser(valueExpr)
// //   .and(
// //     lparen
// //     .zeroOrOnce(Parser(expr).zeroOrOnce(comma.and(expr).many()))
// //     .and(rparen)
// //     .many(),
// //   )
// //   .map(
// //     fn {
// //       (e, list) => {
// //         let result = list.fold(
// //           init=e,
// //           fn {
// //             e, (((_, None), _)) => App(e, [])
// //             e, (((_, Some((expr, None))), _)) => {
// //               App(e, [expr])
// //             }
// //             e, (((_, Some((expr, Some(arr)))), _)) => {
// //               let arr = arr.map(
// //                 fn {
// //                   (_, expr) => expr
// //                 },
// //               )
// //               App(e, [expr, ..arr])
// //             }
// //           },
// //         )
// //         result
// //       }
// //     },
// //   )
// //   .parse(tokens)
// // }

// fn noEmptyApplyExpr(
//   tokens : ArrayView[@lex.Token]
// ) -> (@types.Syntax, ArrayView[@lex.Token])? {
//   // println("noEmptyApplyExpr: " + tokens.to_string())
//   Parser(valueExpr)
//   .and(lparen)
//   .and(expr)
//   .zeroOrOnce(comma.and(expr).many())
//   .and(rparen)
//   .map(
//     fn {
//       ((((valueExpr, _), expr), Some(arr)), _) => {
//         // println("noEmptyApplyExpr: tokens: " + tokens.to_string())
//         let arr_t = arr.map(fn { (_, t) => t })

//         // println("noEmptyApplyExpr: @types.Syntax::App(valueExpr, [expr, ..arr_t]): " + (valueExpr, [expr, ..arr_t]).to_string())

//         @types.Syntax::App(valueExpr, [expr, ..arr_t])
//       }
//       ((((valueExpr, _), expr), None), _) =>
//         // println("noEmptyApplyExpr: None")
//         @types.Syntax::App(valueExpr, [expr])
//     },
//   )
//   .parse(tokens)
// }

// // Value expressions
// value_expr:
// 	unit_expr
// 	| tuple_expr
// 	| bool_expr
// 	| identifier_expr
// 	| block_expr
// 	| neg_expr
// 	| floating_point_expr
// 	| int_expr
// 	| not_expr
// 	| array_make_expr;

///|
fn valueExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("valueExpr: " + tokens.to_string())
  Parser(unitExpr)
  .or(groupExpr)
  .or(tupleExpr)
  .or(boolExpr)
  .or(identifierExpr)
  .or(blockExpr)
  .or(negExpr)
  .or(floatingPointExpr)
  .or(intExpr)
  .or(notExpr)
  .or(arrayMakeExpr)
  .parse(tokens)
}

// unit_expr: '(' ')'; // ()

///|
fn unitExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  lparen
  .parser_and(rparen)
  .map(fn(input) {
    match input {
      _ => @types.Syntax::Unit
    }
  })
  .parse(tokens)
}

///|
fn groupExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  lparen.parser_and(expr).parser_and(rparen).map(expr => expr.0.1).parse(tokens)
}
// tuple_expr: '(' expr (',' expr)* ')'; // (x, y)

///|
fn tupleExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  lparen
  .parser_and(expr)
  .parser_and(
    ptoken(fn(input) {
      match input {
        @lex.Token::COMMA => true
        _ => false
      }
    })
    .parser_and(expr)
    .many(),
  )
  .parser_and(rparen)
  .map(fn(input) {
    match input {
      (((_, first), arr), _) => {
        // println("tuple_expr: " + arr.to_string())
        if arr.is_empty() {
          return first
        }
        let expr = arr.map(fn(input) {
          match input {
            (_, expr) => expr
          }
        })
        @types.Syntax::Tuple([first, ..expr])
      }
    }
  })
  .parse(tokens)
}

// block_expr: '{' stmt '}'; // { blah; blah; }

///|
fn blockExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("blockExpr: " + tokens.to_string())
  lcurlybracket
  .parser_and(stmt)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    match input {
      ((_, stmts), _) => stmts
    }
  })
  .parse(tokens)
}

// bool_expr: 'true' | 'false';

///|
fn boolExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken(fn(input) {
    match input {
      @lex.Token::TRUE => true
      @lex.Token::FALSE => true
      _ => false
    }
  })
  .map(fn(input) {
    match input {
      TRUE => @types.Syntax::Bool(true)
      FALSE => @types.Syntax::Bool(false)
      _ => panic()
    }
  })
  .parse(tokens)
}

// neg_expr: '-' value_expr;

///|
fn negExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken_minus
  .parser_and(valueExpr)
  .map(fn(input) {
    match input {
      (_, expr) => @types.Syntax::Neg(expr, kind=None)
    }
  })
  .parse(tokens)
}

// floating_point_expr: NUMBER '.' NUMBER?; // 1.0 | 1.

///|
fn floatingPointExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("floatingPointExpr: " + tokens.to_string())
  ptoken_number
  .parser_and(dot)
  .zeroOrOnce(ptoken_number)
  .map(fn(input) {
    match input {
      ((NUMBER(num1), _), Some(NUMBER(num2))) => {
        let d = try? @strconv.parse_double(
            num1.to_string() + "." + num2.to_string(),
          )
        @types.Syntax::Double(d.unwrap())
      }
      ((NUMBER(num1), _), None) => {
        let d = try? @strconv.parse_double(
            num1.to_string() + "." + "0".to_string(),
          )
        @types.Syntax::Double(d.unwrap())
      }
      _ =>
        // println("floatingPointExpr: not handled, input: " + tokens.to_string())
        panic()
    }
  })
  .parse(tokens)
}

// int_expr: NUMBER; // 1

///|
fn intExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("intExpr: " + tokens.to_string())
  ptoken(fn(input) {
    match input {
      @lex.Token::NUMBER(_) => true
      _ => false
    }
  })
  .map(fn(input) {
    match input {
      NUMBER(num) =>
        // println("intExpr: " + num.to_string())
        @types.Syntax::Int(num)
      _ =>
        // println("intExpr: not handled, input: " + tokens.to_string())
        panic()
    }
  })
  .parse(tokens)
}

// not_expr: 'not' '(' expr ')'; // not(x)

///|
fn notExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken_not
  .parser_and(lparen)
  .parser_and(expr)
  .parser_and(rparen)
  .map(fn(input) {
    match input {
      ((_, expr), _) => @types.Syntax::Not(expr)
    }
  })
  .parse(tokens)
}
// array_make_expr:
// 	'Array' ':' ':' 'make' '(' expr ',' expr ')'; // Array::make(x, y)

///|
fn arrayMakeExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken_array
  .parser_and(ptoken_colon)
  .parser_and(ptoken_colon)
  .parser_and(ptoken_make)
  .parser_and(lparen)
  .parser_and(expr)
  .parser_and(comma)
  .parser_and(expr)
  .parser_and(rparen)
  .map(fn(input) {
    match input {
      ((((_, expr1), _), expr2), _) => @types.Syntax::Array(expr1, expr2)
    }
  })
  .parse(tokens)
}
// identifier_expr: IDENTIFIER;

///|
fn identifierExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken(fn(input) {
    match input {
      @lex.Token::IDENTIFIER(_) => true
      _ => false
    }
  })
  .map(fn(input) {
    match input {
      @lex.Token::IDENTIFIER(id) => @types.Syntax::Var(id)
      _ =>
        // println("identifierExpr: not handled")
        panic()
    }
  })
  .parse(tokens)
}

///|
fn parseType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  // println("parseType:" + tokens.to_string())
  ptoken(fn(input) {
    match input {
      @lex.Token::UNIT => true
      @lex.Token::BOOL => true
      @lex.Token::INT => true
      @lex.Token::DOUBLE => true
      _ => false
    }
  })
  .map(fn(input) {
    match input {
      UNIT => @types.Type::Unit
      BOOL => @types.Type::Bool
      INT => @types.Type::Int
      DOUBLE => @types.Type::Double
      _ => panic()
    }
  })
  .or(arrayType)
  .or(functionType)
  .or(tupleType)
  .parse(tokens)
}

///|
fn arrayType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  // println("arrayType: " + tokens.to_string())
  ptoken_array
  .parser_and(lbracket)
  .parser_and(parseType)
  .parser_and(rbracket)
  .map(fn(input) {
    match input {
      ((_, type_), _) =>
        // println("arrayType type_: " + type_.to_string())
        @types.Type::Array(type_)
    }
  })
  .parse(tokens)
}

// tuple_type: '(' type (',' type)* ')'; // (Int, Bool)

///|
fn tupleType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  // println("tupleType: " + tokens.to_string())
  lparen
  .parser_and(parseType)
  .parser_and(
    ptoken(fn(input) {
      match input {
        @lex.Token::COMMA => true
        _ => false
      }
    })
    .parser_and(parseType)
    .many(),
  )
  .parser_and(rparen)
  .map(fn(input) {
    match input {
      (((_, t), arr_t), _) => {
        // println("tupleType: t: " + t.to_string())
        // println("tupleType: arr_t: " + arr_t.to_string())
        let r_arr = arr_t.map(fn(input) {
          match input {
            (_, t) => t
          }
        })
        // println("tupleType: [t, ..r_arr]: " + [t, ..r_arr].to_string())
        @types.Type::Tuple([t, ..r_arr])
      }
    }
  })
  .parse(tokens)
}
// function_type:
// 	'(' type (',' type)* ')' '->' type; // (Int, Bool) -> Int

///|
let arrow : Parser[@lex.Token] = ptoken(fn(input) {
  match input {
    @lex.Token::ARROW => true
    _ => false
  }
})

///|
fn functionType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  // println("functionType: " + tokens.to_string())
  lparen
  .parser_and(parseType)
  .parser_and(
    ptoken(fn(input) {
      match input {
        @lex.Token::COMMA => true
        _ => false
      }
    })
    .parser_and(parseType)
    .many(),
  )
  .parser_and(rparen)
  .parser_and(arrow)
  .parser_and(parseType)
  .map(fn(input) {
    match input {
      (((((_, type_), arr), _), _), type2) => {
        let arr_t = arr.map(t => t.1)
        @types.Type::Fun([type_, ..arr_t], type2)
      }
    }
  })
  .parse(tokens)
}

///|
fn ptoken(predicate : (@lex.Token) -> Bool) -> Parser[@lex.Token] {
  fn(input) {
    match input {
      [hd, .. tl] => if predicate(hd) { Some((hd, tl)) } else { None }
      [] => None
    }
  }
}

///|
fn[I, O] map(self : Parser[I], f : (I) -> O) -> Parser[O] {
  fn(input) {
    match self.parse(input) {
      Some((token, rest)) => Some((f(token), rest))
      None => None
    }
  }
}

///|
// fn and[V1, V2](self : Parser[V1], parser2 : Parser[V2]) -> Parser[(V1, V2)] {
//   fn(input) {
//     self
//     .parse(input)
//     .bind(
//       fn {
//         (value, rest) =>
//           parser2
//           .parse(rest)
//           .map(fn { (value2, rest2) => ((value, value2), rest2) })
//       },
//     )
//   }
// }

fn[V1, V2] parser_and(self : Parser[V1], parser2 : Parser[V2]) -> Parser[(V1, V2)] {
  fn(input) {
    self
    .parse(input)
    .bind(value_rest => parser2
      .parse(value_rest.1)
      .map(value2_rest2 => ((value_rest.0, value2_rest2.0), value2_rest2.1)))
  }
}

///|
fn[V] or(self : Parser[V], parser2 : Parser[V]) -> Parser[V] {
  fn(input) {
    match self.parse(input) {
      None => parser2.parse(input)
      Some(_) as result => result
    }
  }
}

///|
fn[Value] many(self : Parser[Value]) -> Parser[Array[Value]] {
  fn(input) {
    let cumul = []
    let mut rest = input
    loop self.parse(input) {
      None => Some((cumul, rest))
      Some((v, rest_)) => {
        cumul.push(v)
        rest = rest_
        continue self.parse(rest_)
      }
    }
  }
}

///|
fn[V1, V2] zeroOrOnce(
  self : Parser[V1],
  parser2 : Parser[V2],
) -> Parser[(V1, V2?)] {
  fn(input) {
    self
    .parse(input)
    .bind(v1_rest => match parser2.parse(v1_rest.1) {
      None => Some(((v1_rest.0, None), v1_rest.1))
      Some((v2, rest2)) => Some(((v1_rest.0, Some(v2)), rest2))
    })
    // match self.parse(input) {
    //   Some((v1, rest)) =>
    //     match parser2.parse(rest) {
    //       None => Some(((v1, None), rest))
    //       Some((v2, rest2)) => Some(((v1, Some(v2)), rest2))
    //     }
    //   None => None
    // }
  }
}
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
let ptoken_eq : Parser[@lex.Token] = ptoken(fn(token) {
  match token {
    @lex.Token::EQ => true
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
let comma : Parser[@lex.Token] = ptoken(fn(token) {
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
  match token {
    @lex.Token::IDENTIFIER(_) => true
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
pub type Parser[V] (ArrayView[@lex.Token]) -> (V, ArrayView[@lex.Token])?

///|
fn[V] parse(
  self : Parser[V],
  tokens : ArrayView[@lex.Token],
) -> (V, ArrayView[@lex.Token])? {
  println("parsing: " + tokens.to_string())
  self.inner()(tokens)
}

///|
let parser : Parser[@types.Syntax] = Parser(program)

///|
pub(all) suberror ParserErr String derive(ToJson)

///|
pub fn parse_from_string(str : String) -> @types.Syntax {
  // println("parsing: \n" + str)
  let tokens = []
  @lex.lex({ str, offset: 0, array: tokens })
  // println(tokens)
  let (prog, _) = parser.parse(tokens[:]).unwrap()
  prog
}

///|
test {
  let tokens = []
  let test1 =
    #| fn main {
    // #|  let x = c[i][j];
    #|    let (x, _, _) = v;
    // #|let _ = print_int(truncate(c[0][1]));
    // #| let _ = print_endline();
    // #| let _ = print_int(truncate(c[1][0]));
    // #| let _ = print_endline();
    // #| let _ = print_int(truncate(c[1][1]));
    // #|  let _ = print_int(truncate(c[0][0]));

    // #| + b[o] * c[u];
    // #|  c[i][j] = c[i][j] + a[i][k] * b[k][j];
    #|  ()
    // #|  println(x)
    #| };
  @lex.lex({ str: test1, offset: 0, array: tokens })
  // println(tokens)
  let (prog, _) = parser.parse(tokens[:]).unwrap()
  println(prog)
}

///|
test {
  let tokens = []
  let _test2 = @fs.read_file_to_string("test/test_src/adder.mbt")
  // println(_test2)
  @lex.lex({ str: _test2, offset: 0, array: tokens })
  // println(tokens)
  let (prog, _) = parser.parse(tokens[:]).unwrap()
  println(prog)
}

///|
test {
  let x = ["1", "2", "3", "4"]
  let res = x.fold(init="0", (n, i) => "F(" + n + "," + i + ")")
  println(res)
}