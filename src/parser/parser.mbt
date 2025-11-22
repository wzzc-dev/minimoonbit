// prog: top_level* EOF;

///|
fn program(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("program: " + tokens.to_string())
  Parser(topLevel)
  .many()
  .map(fn(decls) {
    // println("decls: " + decls.to_string())
    // Combine all top-level declarations into a single syntax tree
    decls.rev_fold(init=@types.Syntax::Unit, fn(acc, decl) {
      // println("decl: " + decl.to_string())
      // println("acc: " + acc.to_string())
      // println("")
      match decl {
        @types.Syntax::LetRec(fn_def, _) => @types.Syntax::LetRec(fn_def, acc)
        @types.Syntax::Let(binding, value, _) =>
          @types.Syntax::Let(binding, value, acc)
        @types.Syntax::Struct(name, generic, fields, _) =>
          @types.Syntax::Struct(name, generic, fields, acc)
        @types.Syntax::Enum(name, generic, variants, _) =>
          @types.Syntax::Enum(name, generic, variants, acc)
        _ => acc
      }
    })
  })
  .parse(tokens)
}
// top_level: top_let_decl | toplevel_fn_decl | struct_decl | enum_decl;

///|
fn topLevel(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("topLevel: " + tokens[0:10].to_string())
  Parser(enumDecl)
  .or(structDecl)
  .or(topLetDecl)
  .or(toplevelFnDecl)
  .parse(tokens)
}
// top_let_decl:
//	'let' IDENTIFIER (':' type)? '=' expr ';';

///|
fn topLetDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("topLetDecl: " + tokens.to_string())
  ptoken_let
  .parser_and(identifier)
  .zeroOrOnce(typeAnnotation)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .map(fn(input) {
    // @util.logger("topLetDecl input: " + input.to_string())
    match input {
      (((((_, binding), type_annotation), _), expr), _) => {
        let binding = match binding {
          @lex.Token::IDENTIFIER(id) => id
          @lex.Token::WILDCARD => "_"
          _ => @util.die("Invalid binding: " + binding.to_string())
        }
        let type_ = match type_annotation {
          Some(t) => t
          None => @types.Type::Var({ val: None })
        }
        @types.Syntax::Let((binding, type_), expr, @types.Syntax::Unit)
      }
    }
  })
  .parse(tokens)
}

///|
// toplevel_fn_decl: (main_fn_decl | top_fn_decl);
fn toplevelFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(mainFnDecl).or(topFnDecl).parse(tokens)
}

///|
/// main_fn_decl: 'fn' 'main' fn_body;
fn mainFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("main_fn_decl: " + tokens.to_string())
  ptoken_fn
  .parser_and(
    ptoken(fn(token) {
      // @util.logger("main_fn_decl: " + token.to_string())
      match token {
        @lex.Token::IDENTIFIER("main") => true
        @lex.Token::IDENTIFIER("init") => true
        _ => false
      }
    }),
  )
  .parser_and(fnBody)
  .map(fn(input) {
    // println("main_fn_decl input: " + input.to_string() + "\n")
    match input {
      ((_, _), fnBody) =>
        // (("main", @types.Type::Fun([], @types.Type::Unit)), [], )
        @types.Syntax::LetRec(
          {
            name: ("main", @types.Type::Fun([], @types.Type::Unit)),
            args: [],
            body: fnBody,
          },
          @types.Syntax::Unit,
        )
    }
  })
  .parse(tokens)
}

// top_fn_decl:
// 	'fn' IDENTIFIER '(' param_list? ')' '->' type fn_body;

///|
fn topFnDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
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
        // ((id, @types.Fun(fun_type, type_)), param_list, fnBody)
        @types.Syntax::LetRec(
          {
            name: (id, @types.Fun(fun_type, type_)),
            args: param_list,
            body: fnBody,
          },
          @types.Syntax::Unit,
        )
      }
      (((((((_, @lex.Token::IDENTIFIER(id)), _), None), _), _), type_), fnBody) =>
        @types.Syntax::LetRec(
          { name: (id, @types.Fun([], type_)), args: [], body: fnBody },
          @types.Syntax::Unit,
        )
      (((((((_, ident), _), _), _), _), type_), fnBody) =>
        @util.die(
          "Invalid top fn decl declaration" +
          tokens.to_string() +
          "\n" +
          "ident: " +
          ident.to_string() +
          " type: " +
          type_.to_string() +
          " fnBody: " +
          fnBody.to_string(),
        )
    }
  })
  .parse(tokens)
}

// param_list: param (',' param)*;

///|
fn paramList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, @types.Type)], ArrayView[@lex.Token])? {
  // @util.logger("paramList: " + tokens.to_string())
  Parser(param)
  .parser_and(ptoken_comma.parser_and(param).many())
  .map(fn(input) {
    // @util.logger("paramList input: " + input.to_string())
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
  // @util.logger("param: " + tokens.to_string())
  identifier
  .parser_and(typeAnnotation)
  .map(fn(input) {
    // @util.logger("param input: " + input.to_string())
    match input {
      (@lex.Token::IDENTIFIER(i), t) => (i, t)
      _ => @util.die("Invalid param")
    }
  })
  .parse(tokens)
}

// fn_body: '{' stmt* expr? '}';

///|
fn fnBody(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("fnBody: " + tokens.to_string())
  lcurlybracket
  .parser_and(Parser(stmt).many())
  .zeroOrOnce(expr)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    // println("fnBody input: " + input.to_string() + "\n")
    match input {
      (((_, stmts), final_expr), _) => {
        // Helper function to build nested syntax tree
        let build_nested = fn(
          statements : Array[@types.Syntax],
          last_expr : @types.Syntax,
        ) -> @types.Syntax {
          // println("build_nested statements: " + statements.to_string() + "\n")
          // println("build_nested last_expr: " + last_expr.to_string() + "\n")
          statements.rev_fold(init=last_expr, fn(stmt, acc) {
            // println("build_nested stmt: " + stmt.to_string() + "\n")
            match acc {
              @types.Syntax::Let(binding, value, _) =>
                @types.Syntax::Let(binding, value, stmt)
              @types.Syntax::LetTuple(bindings, value, _) =>
                @types.Syntax::LetTuple(bindings, value, stmt)
              @types.Syntax::LetRec(fn_def, _) =>
                @types.Syntax::LetRec(fn_def, stmt)
              @types.Syntax::While(cond, body) =>
                @types.Syntax::Let(
                  ("_", @types.Type::Unit),
                  @types.Syntax::While(cond, body),
                  stmt,
                )
              @types.Syntax::Put(arr, idx, value) =>
                Let(("_", Unit), @types.Syntax::Put(arr, idx, value), stmt)
              @types.Syntax::Return(ret_expr) => @types.Syntax::Return(ret_expr) // Return should terminate the sequence
              _ =>
                // For other expression statements, treat as side effects
                @types.Syntax::Let(("_", @types.Type::Unit), acc, stmt)
            }
          })
        }
        match final_expr {
          Some(expr) => build_nested(stmts, expr)
          None =>
            match stmts {
              [] => @types.Syntax::Unit
              [single] =>
                // Ensure single statement has proper continuation
                match single {
                  @types.Syntax::Let(binding, value, _) =>
                    @types.Syntax::Let(binding, value, @types.Syntax::Unit)
                  @types.Syntax::LetTuple(bindings, value, _) =>
                    @types.Syntax::LetTuple(
                      bindings,
                      value,
                      @types.Syntax::Unit,
                    )
                  @types.Syntax::LetRec(fn_def, _) =>
                    @types.Syntax::LetRec(fn_def, @types.Syntax::Unit)
                  @types.Syntax::Return(_) => single // Return statements don't need Unit continuation
                  _ => single
                }
              [.. init, last] => build_nested(init.to_array(), last)
            }
        }
      }
    }
  })
  .parse(tokens)
}

// struct_decl:
//	'struct' UPPER_IDENTIFIER ('[' UPPER_IDENTIFIER ']')? '{' struct_field_list? '}';

///|
fn structDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken_struct
  .parser_and(upperIdentifier)
  .zeroOrOnce(lbracket.parser_and(upperIdentifier).parser_and(rbracket))
  .parser_and(lcurlybracket)
  .zeroOrOnce(structFieldList)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    // @util.logger("structDecl: input: " + input.to_string())
    match input {
      (((((_, UPPER_IDENTIFIER(struct_name)), None), _), None), _) =>
        @types.Syntax::Struct(struct_name, "", [], @types.Syntax::Unit)
      (
        ((((_, UPPER_IDENTIFIER(struct_name)), None), _), Some(structFieldList)),
        _,
      ) =>
        @types.Syntax::Struct(
          struct_name,
          "",
          structFieldList,
          @types.Syntax::Unit,
        )
      (
        (
          (
            (
              (_, UPPER_IDENTIFIER(struct_name)),
              Some(((_, UPPER_IDENTIFIER(generic)), _)),
            ),
            _,
          ),
          Some(structFieldList),
        ),
        _,
      ) =>
        @types.Syntax::Struct(
          struct_name,
          generic,
          structFieldList,
          @types.Syntax::Unit,
        )
      _ => @util.die("Invalid struct decl")
    }
  })
  .parse(tokens)
}

// struct_field_list:
// 	struct_field (';' struct_field)* ';'?;

///|
fn structFieldList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, @types.Type)], ArrayView[@lex.Token])? {
  Parser(structField)
  .parser_and(semicolon.parser_and(structField).many())
  .parser_and(semicolon)
  .map(fn(input) {
    match input {
      ((structField, structFieldList), _) => {
        let structFields = [structField]
        for x in structFieldList {
          let (_, x) = x
          structFields.push(x)
        }
        structFields
      }
    }
  })
  .parse(tokens)
}

// struct_field:
// 	IDENTIFIER type_annotation;

///|
fn structField(
  tokens : ArrayView[@lex.Token],
) -> ((String, @types.Type), ArrayView[@lex.Token])? {
  identifier
  .parser_and(typeAnnotation)
  .map(fn(input) {
    match input {
      (@lex.Token::IDENTIFIER(i), t) => (i, t)
      _ => @util.die("Invalid struct field")
    }
  })
  .parse(tokens)
}

// enum_decl:
//  'enum' ('[' UPPER_IDENTIFIER ']')? UPPER_IDENTIFIER '{' enum_variant_list? '}';

///|
fn enumDecl(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken_enum
  .parser_and(upperIdentifier)
  .zeroOrOnce(lbracket.parser_and(upperIdentifier).parser_and(rbracket))
  .parser_and(lcurlybracket)
  .zeroOrOnce(enumVariantList)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    match input {
      (((((_, UPPER_IDENTIFIER(enum_name)), None), _), Some(enumVariantList)), _
      ) =>
        @types.Syntax::Enum(enum_name, "", enumVariantList, @types.Syntax::Unit)
      _ => @util.die("Invalid enum decl")
    }
  })
  .parse(tokens)
}

// enum_variant_list:
// 	enum_variant (';' enum_variant)* ';'?;

///|
fn enumVariantList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, Array[@types.Type])], ArrayView[@lex.Token])? {
  // @util.logger("enumVariantList: tokens: " + tokens.to_string())
  Parser(enumVariant)
  .parser_and(semicolon.parser_and(enumVariant).many())
  .zeroOrOnce(semicolon)
  .map(fn(input) {
    // @util.logger("enumVariantList: input: " + input.to_string())
    match input {
      ((enumVariant, enumVariantList), _) => {
        let enumVariants = [enumVariant]
        for x in enumVariantList {
          let (_, x) = x
          enumVariants.push(x)
        }
        enumVariants
      }
    }
  })
  .parse(tokens)
}
// enum_variant:
//   UPPER_IDENTIFIER ('(' enum_variant_field_list? ')')?;

///|
fn enumVariant(
  tokens : ArrayView[@lex.Token],
) -> ((String, Array[@types.Type]), ArrayView[@lex.Token])? {
  // @util.logger("enumVariant: tokens: " + tokens[:10].to_string())
  upperIdentifier
  .zeroOrOnce(lparen.parser_and(enumVariantFieldList).parser_and(rparen))
  .map(fn(input) {
    // @util.logger("enumVariant: input: " + input.to_string())
    match input {
      (UPPER_IDENTIFIER(id), None) => (id, [])
      (UPPER_IDENTIFIER(id), Some(((_, enumVariantFieldList), _))) =>
        (id, enumVariantFieldList)
      _ => @util.die("Invalid enum variant")
    }
  })
  .parse(tokens)
}
// enum_variant_field_list:
// 	type (',' type)*;

///|
fn enumVariantFieldList(
  tokens : ArrayView[@lex.Token],
) -> (Array[@types.Type], ArrayView[@lex.Token])? {
  Parser(parseType)
  .parser_and(ptoken_comma.parser_and(parseType).many())
  .map(fn(input) {
    match input {
      (type_, typeList) => {
        let types = [type_]
        for x in typeList {
          let (_, x) = x
          types.push(x)
        }
        types
      }
    }
  })
  .parse(tokens)
}

// nontop_fn_decl:
// 	'fn' IDENTIFIER '(' nontop_param_list? ')' (
// 		'->' type
// 	)? fn_body;

///|
/// nontop_fn_decl:
/// 	'fn' IDENTIFIER '(' nontop_param_list? ')' (
/// 		'->' type
/// 	)? fn_body;
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
/// nontop_param_list:
/// 	nontop_param (',' nontop_param)*;
fn nonTopParamList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, @types.Type)], ArrayView[@lex.Token])? {
  Parser(nonTopParam)
  .parser_and(ptoken_comma.parser_and(nonTopParam).many())
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
// stmt:
// 	let_tuple_stmt
// 	| let_stmt
// 	| fn_decl_stmt
// 	| assign_stmt
// 	| while_stmt
// 	| return_stmt
// 	| expr_stmt;
fn stmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("stmt: " + tokens.to_string())
  Parser(letTupleStmt)
  .or(letStmt)
  .or(fnDeclStmt)
  .or(assignStmt)
  .or(whileStmt)
  .or(returnStmt)
  .or(exprStmt)
  // .log()
  .parse(tokens)
}

// binding: IDENTIFIER | WILDCARD ;

///|
fn binding(
  tokens : ArrayView[@lex.Token],
) -> (@lex.Token, ArrayView[@lex.Token])? {
  identifier.or(ptoken_wildcard).parse(tokens)
}

///|
/// let_tuple_stmt:
/// 	'let' '(' IDENTIFIER (',' IDENTIFIER)* ')' type_annotation? '=' expr ';';
fn letTupleStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("letTupleStmt: " + tokens[:10].to_string())
  ptoken_let
  .parser_and(lparen)
  .parser_and(binding)
  .parser_and(ptoken_comma.parser_and(binding).many())
  .parser_and(rparen)
  .zeroOrOnce(typeAnnotation)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .map(fn(input) {
    // @util.logger("letTupleStmt: " + input.to_string())
    match input {
      (((((((_, identifier), identifiers), _), type_annotation), _), expr), _) => {
        let identifier = match identifier {
          @lex.Token::IDENTIFIER(id) => id
          @lex.Token::WILDCARD => "_".to_string()
          _ => {
            println("let tuple ident: " + identifier.to_string())
            panic()
          }
        }
        let ids = [(identifier, @types.Type::Var({ val: None }))]
        for x in identifiers {
          match x {
            (_, @lex.Token::IDENTIFIER(i)) =>
              ids.push((i, @types.Type::Var({ val: None })))
            (_, @lex.Token::WILDCARD) =>
              ids.push(("_".to_string(), @types.Type::Var({ val: None })))
            (_, ident) => {
              println("let tuple ident: " + ident.to_string())
              panic()
            }
          }
        }
        match type_annotation {
          Some(type_) => {
            match type_ {
              Tuple(typeTuple) =>
                for i, e in typeTuple {
                  if i < ids.length() {
                    ids[i] = (ids[i].0, e)
                  }
                }
              _ => @util.die("type_annotation is not a tuple")
            }
            @types.Syntax::LetTuple(ids, expr, @types.Syntax::Unit)
          }
          None => @types.Syntax::LetTuple(ids, expr, @types.Syntax::Unit)
        }
      }
    }
  })
  .parse(tokens)
}

///|
// let_stmt:
// 	'let' 'mut'? IDENTIFIER type_annotation? '=' expr ';';
fn letStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("letStmt token : " + tokens[:10].to_string())
  ptoken_let
  .zeroOrOnce(ptoken_mut)
  .parser_and(binding)
  .zeroOrOnce(typeAnnotation)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .map(fn(input) {
    // @util.logger("letStmt input: " + input.to_string())
    match input {
      (((((_, binding), type_annotation), _), expr), _) => {
        let binding = match binding {
          @lex.Token::IDENTIFIER(id) => id
          @lex.Token::UPPER_IDENTIFIER(id) => id
          @lex.Token::WILDCARD => "_"
          _ => @util.die("Invalid binding: " + binding.to_string())
        }
        let type_ = match type_annotation {
          Some(t) => t
          None => @types.Type::Var({ val: None })
        }
        @types.Syntax::Let((binding, type_), expr, @types.Syntax::Unit)
      }
    }
  })
  .parse(tokens)
}

// type_annotation: COLON type;

///|
fn typeAnnotation(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  ptoken_colon
  .parser_and(parseType)
  .map(fn(input) {
    match input {
      (_, t) => t
    }
  })
  .parse(tokens)
}

// fn_decl_stmt: nontop_fn_decl;

///|
fn fnDeclStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("fnDeclStmt: " + tokens.to_string())
  Parser(nontopFnDecl)
  .map(fn(input) {
    match input {
      (name, args, body) =>
        // println("fnDeclStmt: " + ((name, args, body)).to_string())
        @types.Syntax::LetRec({ name, args, body }, @types.Syntax::Unit)
    }
  })
  .parse(tokens)
}

// // x[y] = z;
// assign_stmt: left_value '=' expr ';';

///|
fn assignStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("assignStmt: " + tokens.to_string())
  Parser(leftValue)
  .parser_and(ptoken_assign)
  .parser_and(expr)
  .parser_and(semicolon)
  .map(fn(input) {
    // @util.logger("assignStmt input: " + input.to_string())
    match input {
      (((get_expr, _), expr), _) =>
        match get_expr {
          Get(arr, idx) => @types.Syntax::Put(arr, idx, expr)
          Var(x) => @types.Syntax::Assign(Var(x), expr)
          _ => @types.Syntax::Let(("_", Var({ val: None })), get_expr, expr)
          // @util.die("Invalid assign statement: left side must be an array access or identifier, but got " + get_expr.to_string())
        }
    }
  })
  .parse(tokens)
}

// // while x { ... }
// while_stmt: 'while' expr '{' stmt* '}';

///|
fn whileStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("whileStmt")
  // @util.logger("whileStmt tokens: " + tokens.to_string())
  ptoken_while
  .parser_and(expr)
  .parser_and(lcurlybracket)
  .parser_and(Parser(stmt).many())
  .parser_and(rcurlybracket)
  .map(fn(input) {
    // @util.logger("whileStmt input: " + tokens.to_string())
    match input {
      ((((_, expr), _), stmts), _) => {
        let body = match stmts {
          [] => @types.Syntax::Unit
          [single] => single
          [.. init, last] =>
            init.rev_fold(init=last, fn(acc, stmt) {
              match stmt {
                @types.Syntax::Let(binding, value, _) =>
                  @types.Syntax::Let(binding, value, acc)
                @types.Syntax::LetTuple(bindings, value, _) =>
                  @types.Syntax::LetTuple(bindings, value, acc)
                @types.Syntax::LetRec(fn_def, _) =>
                  @types.Syntax::LetRec(fn_def, acc)
                _ =>
                  @types.Syntax::Let(
                    ("_", @types.Type::Var({ val: None })),
                    stmt,
                    acc,
                  )
              }
            })
        }
        @types.Syntax::While(expr, body)
      }
    }
  })
  .parse(tokens)
}

// return_stmt:
//  'return' expr? ';'

///|
fn returnStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("returnStmt: " + tokens.to_string())
  ptoken_return
  .zeroOrOnce(expr)
  .parser_and(semicolon)
  .map(fn(input) {
    match input {
      ((_, expr), _) => @types.Syntax::Return(expr)
    }
  })
  .parse(tokens)
}
// expr_stmt: expr ';';

///|

///|
fn exprStmt(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("exprStmt: " + tokens.to_string())
  Parser(expr)
  .parser_and(semicolon)
  .map(fn(input) {
    // @util.logger("expr stmt input: " + input.to_string())
    match input {
      (expr, _) => expr
    }
  })
  .parse(tokens)
}

// left_value:
//   IDENTIFIER
//   | left_value '.' IDENTIFIER
//   | left_value '[' expr ']';

///|
fn leftValue(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("leftValue :" + tokens.to_string())
  // 首先解析一个标识符，作为初始表达式（@types.Syntax::Var）
  identifier
  .map(fn(input) {
    match input {
      @lex.Token::IDENTIFIER(id) => @types.Syntax::Var(id)
      _ => @util.die("leftValue: expected identifier")
    }
  })
  // 然后解析任意个后缀：. IDENTIFIER  或  [ expr ]
  .zeroOrOnce(
    dot
    .parser_and(identifier)
    .parser_or(lbracket.parser_and(expr).parser_and(rbracket))
    .many(),
  )
  .map(fn(input) {
    match input {
      (id, None) => id
      (base_expr, Some(indices)) =>
        // Fold over the indices to build nested Get expressions
        indices.fold(init=base_expr, fn(acc, idx_expr) {
          match idx_expr {
            (Some((DOT, IDENTIFIER(id))), None) => FieldAccess(acc, id)
            (None, Some(((LBRACKET, expr), RBRACKET))) => Get(acc, expr)
            _ => @util.die("leftValue: invalid index expression")
          }
        })
    }
  })
  .parse(tokens)
}

///|
/// expr: // not associative
/// 	or_level_expr;
fn expr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("expr:" + tokens[:10].to_string())
  Parser(orLevelExpr).parse(tokens)
}

// or_level_expr: // left associative
// 	or_level_expr OR and_level_expr
// 	| and_level_expr;

///|
fn orLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("orLevelExpr token: " + tokens.to_string())
  Parser(andLevelExpr)
  .zeroOrOnce(ptoken_or.parser_and(andLevelExpr).many())
  .map(fn(input) {
    // @util.logger("orLevelExpr input: " + input.to_string())
    match input {
      (first_expr, Some(operations)) =>
        // Left-associative folding: (a || b) || c
        operations.fold(init=first_expr, fn(left_expr, operation) {
          match operation {
            (@lex.Token::OR, right_expr) =>
              @types.Syntax::Or(left_expr, right_expr)
            (token, _) => {
              println("Expected OR token, got: " + token.to_string())
              panic()
            }
          }
        })
      (first_expr, None) => first_expr
    }
  })
  .parse(tokens)
}

// and_level_expr: // left associative
// 	and_level_expr AND cmp_level_expr
// 	| cmp_level_expr;

///|
fn andLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("andLevelExpr token: " + tokens.to_string())
  Parser(cmpLevelExpr)
  .zeroOrOnce(ptoken_and.parser_and(cmpLevelExpr).many())
  .map(fn(input) {
    match input {
      (first_expr, Some(operations)) =>
        // Left-associative folding: ((a && b) && c) && d
        operations.fold(init=first_expr, fn(left_expr, operation) {
          match operation {
            (@lex.Token::AND, right_expr) =>
              @types.Syntax::And(left_expr, right_expr)
            (token, _) => {
              println("Expected AND token, got: " + token.to_string())
              panic()
            }
          }
        })
      (first_expr, None) => first_expr
    }
  })
  .parse(tokens)
}
// cmp_level_expr: // not associative
// 	add_sub_level_expr CMP_OPERATOR add_sub_level_expr
// 	| add_sub_level_expr;

///|
fn cmpLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  Parser(addSubLevelExpr)
  .zeroOrOnce(ptoken_cmp_operator.parser_and(addSubLevelExpr))
  .map(fn(input) {
    match input {
      (left_expr, Some((cmp_op, right_expr))) =>
        match cmp_op {
          @lex.Token::CMP_OPERATOR("==") =>
            @types.Syntax::Eq(left_expr, right_expr)
          @lex.Token::CMP_OPERATOR("<=") =>
            @types.Syntax::LE(left_expr, right_expr)
          @lex.Token::CMP_OPERATOR("<") =>
            @types.Syntax::LT(left_expr, right_expr)
          @lex.Token::CMP_OPERATOR(">=") =>
            @types.Syntax::GE(left_expr, right_expr)
          @lex.Token::CMP_OPERATOR(">") =>
            @types.Syntax::GT(left_expr, right_expr)
          @lex.Token::CMP_OPERATOR("!=") =>
            @types.Syntax::NE(left_expr, right_expr)
          _ => {
            println("Unsupported comparison operator: " + cmp_op.to_string())
            panic()
          }
        }
      (left, None) => left
    }
  })
  .or(addSubLevelExpr)
  .parse(tokens)
}

// add_sub_level_expr: // left associative
// 	add_sub_level_expr '+' mul_div_level_expr
// 	| add_sub_level_expr '-' mul_div_level_expr
// 	| mul_div_level_expr;

///|
fn addSubLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("addSubLevelExpr: " + tokens.to_string())
  Parser(mulDivLevelExpr)
  .zeroOrOnce(ptoken_plus.or(ptoken_minus).parser_and(mulDivLevelExpr).many())
  .map(fn(input) {
    // @util.logger("addSubLevelExpr input: " + input.to_string())
    match input {
      (first_expr, Some(operations)) =>
        // Left-associative folding: ((a + b) - c) + d
        operations.fold(init=first_expr, fn(left_expr, operation) {
          match operation {
            (@lex.Token::ADD, right_expr) =>
              @types.Syntax::Prim(left_expr, right_expr, @types.Add, kind=None)
            (@lex.Token::SUB, right_expr) =>
              @types.Syntax::Prim(left_expr, right_expr, @types.Sub, kind=None)
            (token, _) => {
              println("Expected ADD or SUB token, got: " + token.to_string())
              panic()
            }
          }
        })
      (first_expr, None) => first_expr
    }
  })
  .parse(tokens)
}

// mul_div_level_expr: // left associative
// 	mul_div_level_expr '*' if_level_expr
// 	| mul_div_level_expr '/' if_level_expr
// 	| mul_div_level_expr '%' if_level_expr
// 	| if_level_expr;

///|
fn mulDivLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("mulDivLevelExpr: token " + tokens.to_string())
  Parser(ifLevelExpr)
  .zeroOrOnce(
    ptoken_star.or(ptoken_slash).or(ptoken_mod).parser_and(ifLevelExpr).many(),
  )
  .map(fn(input) {
    match input {
      (e, Some(list)) => {
        if list.is_empty() {
          return e
        }
        let result = list.fold(init=e, fn(e, input) {
          match input {
            (MUL, expr) => Prim(e, expr, Mul, kind=None)
            (DIV, expr) => Prim(e, expr, Div, kind=None)
            (MOD, expr) => Prim(e, expr, Mod, kind=None)
            (t, _) => @util.die("MUL, DIV or MOD not " + t.to_string())
          }
        })
        result
      }
      (e, None) => e
    }
  })
  .parse(tokens)
}

// if_level_expr: get_or_apply_level_expr | if_expr;

///|
fn ifLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("ifLevelExpr: " + tokens.to_string())
  Parser(getOrApplyLevelExpr).or(ifExpr).or(matchExpr).parse(tokens)
}

// if_expr: 'if' expr block_expr ('else' (if_expr | block_expr))?;

///|
fn ifExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("ifExpr tokens: " + tokens.to_string())
  ptoken_if
  .parser_and(expr)
  .parser_and(blockExpr)
  .zeroOrOnce(ptoken_else.parser_and(Parser(ifExpr).or(blockExpr)))
  .map(fn(input) {
    // @util.logger("ifExpr input: " + tokens.to_string())
    match input {
      (((_, expr), block_expr), Some((_, block_expr2))) =>
        @types.Syntax::If(expr, block_expr, block_expr2)
      (((_, expr), block_expr), None) =>
        @types.Syntax::If(expr, block_expr, Unit)
    }
  })
  .parse(tokens)
}

// match_expr: 'match' expr '{' match_arm_list '}';

///|
fn matchExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("matchExpr: " + tokens[:10].to_string()) 
  ptoken_match
  .parser_and(expr)
  .parser_and(lcurlybracket.parser_and(matchArmList).parser_and(rcurlybracket))
  .map(fn(input) {
    // @util.logger("matchExpr input: " + input.to_string())
    match input {
      ((_, expr), ((_, match_arm_list), _)) =>
        @types.Syntax::Match(expr, match_arm_list)
    }
  })
  .parse(tokens)
}

// match_arm_list:
// 	match_arm (';' match_arm)* ';'?;

///|
fn matchArmList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(@types.Pattern, @types.Syntax)], ArrayView[@lex.Token])? {
  // @util.logger("matchArmList: " + tokens[:10].to_string())
  Parser(matchArm)
  .parser_and(semicolon.parser_and(matchArm).many())
  // .parser_and(semicolon)
  .zeroOrOnce(semicolon)
  .map(fn(input) {
    // @util.logger("matchArmList input: " + input.to_string())
    match input {
      ((match_arm, match_arms), _) => {
        let result = [match_arm]
        result.append(match_arms.map(fn(input) { input.1 }))
        result
      }
    }
  })
  .parse(tokens)
}
// match_arm:
//  	pattern '=>' expr;

///|
fn matchArm(
  tokens : ArrayView[@lex.Token],
) -> ((@types.Pattern, @types.Syntax), ArrayView[@lex.Token])? {
  // @util.logger("matchArm: " + tokens[:10].to_string())
  Parser(pattern)
  .parser_and(ptoken_assign)
  .parser_and(ptoken_gt)
  .parser_and(expr)
  .map(fn(input) {
    // @util.logger("matchArm input: " + input.to_string())
    match input {
      (((pattern, _), _), expr) => (pattern, expr)
    }
  })
  .parse(tokens)
}

// pattern:
//   NUMBER
//   | 'true'
//   | 'false'
//   | '(' pattern (',' pattern)* ')' // Tuple pattern
//   | WILDCARD // Wildcard pattern
//   | IDENTIFIER // Variable pattern
//   | (UPPER_IDENTIFIER '::')? UPPER_IDENTIFIER ('(' pattern ( ',' pattern )* ')')?; // Enum variant pattern

///|
fn pattern(
  tokens : ArrayView[@lex.Token],
) -> (@types.Pattern, ArrayView[@lex.Token])? {
  // @util.logger("pattern: " + tokens[:10].to_string())
  // IDENTIFIER("RGB"), LPAREN, IDENTIFIER("r"), COMMA, IDENTIFIER("g"), COMMA, IDENTIFIER("b"), RPAREN
  ptoken_number
  .parser_or(ptoken_true)
  .parser_or(ptoken_false)
  .parser_or(
    lparen
    .parser_and(
      Parser(pattern).parser_and(ptoken_comma.parser_and(pattern).many()),
    )
    .parser_and(rparen),
  )
  .parser_or(ptoken_wildcard)
  .parser_or(
    upperIdentifier
    .zeroOrOnce(
      ptoken_colon.parser_or(ptoken_colon).parser_and(upperIdentifier),
    )
    .zeroOrOnce(
      lparen
      .parser_and(pattern)
      .parser_and(ptoken_comma.parser_and(pattern).many())
      .parser_and(rparen),
    ),
  )
  .parser_or(identifier)
  .map(fn(input) {
    // @util.logger("pattern input: " + input.to_string())
    match input {
      (
        Some(
          (
            Some(
              (
                Some(
                  (
                    Some((Some((Some(@lex.Token::NUMBER(number)), None)), None)),
                    None,
                  )
                ),
                None,
              )
            ),
            None,
          )
        ),
        None,
      ) => @types.Pattern::PInt(number)
      (
        Some(
          (
            Some(
              (
                Some((Some((Some((None, Some(@lex.Token::TRUE))), None)), None)),
                None,
              )
            ),
            None,
          )
        ),
        None,
      ) => @types.Pattern::PBool(true)
      (
        Some(
          (
            Some((Some((Some((None, Some(@lex.Token::FALSE))), None)), None)),
            None,
          )
        ),
        None,
      ) => @types.Pattern::PBool(false)
      (
        Some(
          (
            Some((Some((None, Some(((_, (pattern1, patterns)), _)))), None)),
            None,
          )
        ),
        None,
      ) => {
        let result = [pattern1]
        result.append(patterns.map(fn(input) { input.1 }))
        // @types.Syntax::Tuple(result)
        @types.Pattern::PTuple(result)
      }
      (Some((Some((None, Some(WILDCARD))), None)), None) =>
        // @util.die("暂未实现: " + @lex.WILDCARD.to_string())
        @types.Pattern::PEnumVariant("_", [])
      (None, Some(IDENTIFIER(identifier))) => @types.Pattern::PVar(identifier)
      (Some((None, Some(((UPPER_IDENTIFIER(id), None), None)))), None) =>
        // @types.Syntax::EnumConstruct(id, [])
        @types.Pattern::PEnumVariant(id, [])
      (
        Some(
          (
            None,
            Some(
              (
                (UPPER_IDENTIFIER(identifier1), None),
                Some((((_, pattern1), patterns), _)),
              )
            ),
          )
        ),
        None,
      ) => {
        // @util.logger("pattern: input: " + input.to_string())
        let result = [pattern1]
        result.append(patterns.map(fn(input) { input.1 }))
        // @util.logger("pattern: result: " + result.to_string())
        // @types.Syntax::EnumConstruct(identifier1, result)
        @types.Pattern::PEnumVariant(identifier1, result)
      }
      _ => @util.die("pattern: " + input.to_string())
    }
  })
  .parse(tokens)
}

// get_or_apply_level_expr:
// 	value_expr # value_expr_
// 	// x[y]
// 	| get_or_apply_level_expr '[' expr ']' # get_expr_
// 	// f(x, y)
// 	| get_or_apply_level_expr '(' (expr (',' expr)*)? ')' # apply_expr;

// get_or_apply_level_expr:
// 	value_expr (
// 		'[' expr ']'
// 		| '(' (expr (',' expr)*)? ')'
// 		| '.' IDENTIFIER
// 	)*;

///|
fn getOrApplyLevelExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("getOrApplyLevelExpr: " + tokens.to_string())
  // Parser(getExpr).or(applyExpr).or(valueExpr).parse(tokens)
  Parser(valueExpr)
  .parser_and(
    lbracket
    .parser_and(Parser(expr))
    .parser_and(rbracket)
    .parser_or(
      lparen
      .zeroOrOnce(Parser(expr).parser_and(ptoken_comma.parser_and(expr).many()))
      .parser_and(rparen),
    )
    .parser_or(dot.parser_and(identifier))
    .many(),
  )
  .map(fn(input) {
    // @util.logger("getOrApplyLevelExpr input: " + input.to_string())
    match input {
      (expr, list) => {
        if list.is_empty() {
          return expr
        }
        let result = list.fold(init=expr, fn(acc, item) {
          match (acc, item) {
            (e, (Some((Some(((LBRACKET, expr), RBRACKET)), None)), None)) =>
              Get(e, expr)
            (e, (Some((None, Some(((LPAREN, exprs), RPAREN)))), None)) =>
              match exprs {
                None => App(e, [])
                Some((e1, e2s)) => {
                  let args = [e1]
                  let e2s = e2s.map(fn(input) { input.1 })
                  args.append(e2s)
                  App(e, args)
                }
              }
            (e, (None, Some((DOT, IDENTIFIER(id))))) => FieldAccess(e, id)
            _ => @util.die("getOrApplyLevelExpr input: " + input.to_string())
          }
        })
        result
      }
    }
  })
  .parse(tokens)
}

// ///|
// fn getOrApplyLevelExpr(
//   tokens : ArrayView[@lex.Token],
// ) -> (@types.Syntax, ArrayView[@lex.Token])? {
//   // println("getOrApplyLevelExpr: " + tokens.to_string())
//   // Parser(getExpr).or(applyExpr).or(valueExpr).parse(tokens)
//   Parser(valueExpr)
//   .parser_and(
//     lbracket
//     .or(lparen)
//     .or(dot)
//       .zeroOrOnce(Parser(expr).parser_and(ptoken_comma.parser_and(expr).many()))
//     .parser_and(rbracket.or(rparen).or(identifier))
//     .many(),
//   )
//   .map(fn(input) {
//     match input {
//       (expr, list) => {
//         if list.is_empty() {
//           return expr
//         }
//         let result = list.fold(init=expr, fn(acc, item) {
//           match (acc, item) {
//             (e, ((_, None), IDENTIFIER(id))) => {
//               FieldAccess(e, Var(id))
//             }
//             (e, ((l, None), _)) =>
//               match l {
//                 LBRACKET => {
//                   println(
//                     "getExpr LBRACKET not empty - token :" + tokens.to_string(),
//                   )
//                   panic()
//                 }
//                 LPAREN => App(e, [])
//                 _ => {
//                   println("Invalid getExpr need [ or (")
//                   panic()
//                 }
//               }
//             (e, ((l, Some((expr1, list))), _)) => {
//               let tails = list.map(e2 => e2.1)
//               // println("applyExpr tails: " + tails.to_string())
//               // println("applyExpr l: " + l.to_string())
//               match l {
//                 LBRACKET =>
//                   if list.is_empty() {
//                     Get(e, expr1)
//                   } else {
//                     @util.die(
//                       "getExpr LBRACKET is not empty - token :" +
//                       tokens.to_string(),
//                     )

//                   }
//                 LPAREN => App(e, [expr1, ..tails])
//                 _ => @util.die("getExpr")
//               }
//             }
//           }
//         })
//         result
//       }
//     }
//   })
//   .parse(tokens)
// }
// value_expr:
// 	unit_expr
// 	| group_expr
// 	| tuple_expr
// 	| array_expr
// 	| bool_expr
// 	| identifier_expr
// 	| block_expr
// 	| neg_expr
// 	| floating_point_expr
// 	| int_expr
// 	| not_expr
// 	| array_make_expr
//  | struct_construct_expr;
//  | enum_construct_expr

///|
fn valueExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("valueExpr: " + tokens.to_string())
  Parser(arrayMakeExpr)
  .or(structConstructExpr)
  .or(enumConstructExpr)
  .or(unitExpr)
  .or(groupExpr)
  .or(tupleExpr)
  .or(arrayExpr)
  .or(boolExpr)
  .or(identifierExpr)
  .or(blockExpr)
  .or(negExpr)
  .or(floatingPointExpr)
  .or(intExpr)
  .or(notExpr)
  .or(notExpr2)
  // .log()
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
  // @util.logger("tupleExpr: " + tokens[:10].to_string())
  lparen
  .parser_and(expr)
  .parser_and(ptoken_comma.parser_and(expr).many())
  .parser_and(rparen)
  .map(fn(input) {
    // @util.logger("tupleExpr input: " + input.to_string())
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
// array_expr: '[' expr (',' expr)* ']'; // [1, 2, 3]

///|
fn arrayExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  lbracket
  .parser_and(expr)
  .parser_and(ptoken_comma.parser_and(expr).many())
  .parser_and(rbracket)
  .map(fn(input) {
    // @util.logger("array_expr: " + input.to_string())
    match input {
      (((_, first), arr), _) => {
        // println("array_expr: " + arr.to_string())
        if arr.is_empty() {
          // For single element array, create Array::make(1, element)
          return @types.Syntax::ArrayExpr([first])
        }
        let expr = arr.map(fn(input) {
          match input {
            (_, expr) => expr
          }
        })
        @types.Syntax::ArrayExpr([first, ..expr])
      }
    }
  })
  .parse(tokens)
}

// block_expr: '{' stmt* expr? '}'; // { blah; blah; }

///|
fn blockExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  lcurlybracket
  .parser_and(Parser(stmt).many())
  .zeroOrOnce(expr)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    match input {
      (((_, stmts), Some(expr)), _) =>
        // 如果有表达式，将所有语句和最终表达式组合
        stmts.rev_fold(init=expr, fn(acc, stmt) {
          match stmt {
            @types.Syntax::Let(binding, value, _) =>
              @types.Syntax::Let(binding, value, acc)
            @types.Syntax::LetTuple(bindings, value, _) =>
              @types.Syntax::LetTuple(bindings, value, acc)
            @types.Syntax::LetRec(fn_def, _) =>
              @types.Syntax::LetRec(fn_def, acc)
            @types.Syntax::Put(binding, index, value) =>
              Let(("_", Unit), @types.Syntax::Put(binding, index, value), acc)
            _ =>
              @types.Syntax::Let(
                ("_", @types.Type::Var({ val: None })),
                stmt,
                acc,
              )
          }
        })
      (((_, stmts), None), _) =>
        // 如果没有表达式，最后一个语句作为返回值，其余作为前置语句
        match stmts {
          [] => @types.Syntax::Unit
          [single] => single
          [.. init, last] =>
            init.rev_fold(init=last, fn(acc, stmt) {
              match stmt {
                @types.Syntax::Let(binding, value, _) =>
                  @types.Syntax::Let(binding, value, acc)
                @types.Syntax::LetTuple(bindings, value, _) =>
                  @types.Syntax::LetTuple(bindings, value, acc)
                @types.Syntax::LetRec(fn_def, _) =>
                  @types.Syntax::LetRec(fn_def, acc)
                _ =>
                  @types.Syntax::Let(
                    ("_", @types.Type::Var({ val: None })),
                    stmt,
                    acc,
                  )
              }
            })
        }
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
  Parser(floatingPointExpr1).or(floatingPointExpr2).parse(tokens)
}

///|
fn floatingPointExpr1(
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
      ((big_or_int, _), big_or_int2) => {
        let big_or_int = match big_or_int {
          NUMBER(num) => num.to_int64()
          BIG_NUMBER(num) => num
          _ =>
            @util.die(
              "floatingPointExpr: not handled, big or int input: " +
              input.to_string(),
            )
        }
        let big_or_int2 = match big_or_int2 {
          Some(NUMBER(num)) => num.to_int64()
          Some(BIG_NUMBER(num)) => num
          None => 0
          _ =>
            @util.die(
              "floatingPointExpr: not handled, big or int input: " +
              input.to_string(),
            )
        }
        let d = try? @strconv.parse_double(
            big_or_int.to_string() + "." + big_or_int2.to_string(),
          )
        @types.Syntax::Double(d.unwrap())
      }
    }
  })
  .parse(tokens)
}

///|
fn floatingPointExpr2(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // println("floatingPointExpr: " + tokens.to_string())
  ptoken_float_number
  .map(fn(input) {
    match input {
      FLOAT_NUMBER(num) =>
        // println("intExpr: " + num.to_string())
        @types.Syntax::Double(num)
      _ =>
        @util.die(
          "floatingPointExpr: not handled, input: " + tokens.to_string(),
        )
    }
  })
  .parse(tokens)
}

// int_expr: NUMBER; // 1

///|
fn intExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("intExpr: " + tokens.to_string())
  ptoken_number
  .map(fn(input) {
    match input {
      NUMBER(num) =>
        // println("intExpr: " + num.to_string())
        @types.Syntax::Int(num)
      BIG_NUMBER(num) => @types.Syntax::Int64(num)
      _ =>
        // println("intExpr: not handled, input: " + tokens.to_string())
        @util.die("intExpr: not handled, input: " + tokens.to_string())
    }
  })
  .parse(tokens)
}

// not_expr: 'not' '(' expr ')'; // not(x) 
// not_expr: '!' expr ; // !x

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

///|
fn notExpr2(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  ptoken_not
  .parser_and(expr)
  .map(fn(input) {
    match input {
      (_, expr) => @types.Syntax::Not(expr)
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
  .parser_and(ptoken_comma)
  .parser_and(expr)
  .parser_and(rparen)
  .map(fn(input) {
    // @util.logger("array MakeExpr")
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
  identifier
  .map(fn(input) {
    match input {
      @lex.Token::IDENTIFIER(id) => @types.Syntax::Var(id)
      _ => @util.die("identifierExpr: not handled")
    }
  })
  .parse(tokens)
}

// struct_construct_expr:
// 	UPPER_IDENTIFIER '::' '{' struct_field_expr_list? '}'; // Point::{ x: 1, y: 2 }

///|
fn structConstructExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("structConstructExpr: " + tokens.to_string())
  upperIdentifier
  .parser_and(ptoken_colon)
  .parser_and(ptoken_colon)
  .parser_and(lcurlybracket)
  .zeroOrOnce(structFieldExprList)
  .parser_and(rcurlybracket)
  .map(fn(input) {
    // @util.logger("structConstructExpr input: " + input.to_string())
    match input {
      (((((UPPER_IDENTIFIER(name), _), _), _), Some(struct_field_exprs)), _) =>
        @types.Syntax::StructConstruct(name, struct_field_exprs)
      (((((UPPER_IDENTIFIER(name), _), _), _), None), _) =>
        @types.Syntax::StructConstruct(name, [])
      _ =>
        @util.die(
          "structConstructExpr: not handled, input: " + input.to_string(),
        )
    }
  })
  .parse(tokens)
}

// struct_field_expr_list:
// 	struct_field_expr (',' struct_field_expr)*;

///|
fn structFieldExprList(
  tokens : ArrayView[@lex.Token],
) -> (Array[(String, @types.Syntax)], ArrayView[@lex.Token])? {
  // @util.logger("struct_field_expr_list token: " + tokens.to_string())
  Parser(structFieldExpr)
  .parser_and(ptoken_comma.parser_and(structFieldExpr).many())
  .map(fn(input) {
    match input {
      (struct_field_expr, struct_field_exprs) => {
        let result = [struct_field_expr]
        let struct_field_exprs = struct_field_exprs.map(fn(input) {
          match input {
            (_, struct_field_expr) => struct_field_expr
          }
        })
        result.append(struct_field_exprs)
        result
      }
    }
  })
  .parse(tokens)
}

// struct_field_expr:
// 	IDENTIFIER ':' expr; // x: 1

///|
fn structFieldExpr(
  tokens : ArrayView[@lex.Token],
) -> ((String, @types.Syntax), ArrayView[@lex.Token])? {
  // @util.logger("structFieldExpr: " + tokens[0].to_string())
  identifier
  .parser_and(ptoken_colon)
  .parser_and(expr)
  .map(fn(input) {
    match input {
      ((@lex.Token::IDENTIFIER(id), _), expr) => (id, expr)
      _ => @util.die("structFieldExpr: not handled")
    }
  })
  .parse(tokens)
}

// enum_construct_expr:
//   (UPPER_IDENTIFIER '::')? UPPER_IDENTIFIER ('(' enum_construct_field_list? ')')?;

///|
fn enumConstructExpr(
  tokens : ArrayView[@lex.Token],
) -> (@types.Syntax, ArrayView[@lex.Token])? {
  // @util.logger("enumConstructExpr: " + tokens[:10].to_string())
  upperIdentifier
  .zeroOrOnce(ptoken_colon.parser_and(ptoken_colon).parser_and(upperIdentifier))
  .zeroOrOnce(lparen.parser_and(enumConstructFieldList).parser_and(rparen))
  .map(fn(input) {
    // @util.logger("enumConstructExpr input: " + input.to_string())
    match input {
      ((UPPER_IDENTIFIER(name), None), Some(((_, enum_construct_field_list), _))
      ) => @types.Syntax::EnumConstruct(name, enum_construct_field_list)
      ((UPPER_IDENTIFIER(name), None), None) =>
        @types.Syntax::EnumConstruct(name, [])
      ((UPPER_IDENTIFIER(name), Some(((COLON, COLON), UPPER_IDENTIFIER(field)))), None) => {
        @types.Syntax::EnumConstruct(name + "::" + field, [])
      }
      _ => @util.die("enumConstructExpr: not handled: " + input.to_string())
    }
  })
  .parse(tokens)
}

// enum_construct_field_list:
// 	expr (',' expr)*; // Point(1, 2)

///|
fn enumConstructFieldList(
  tokens : ArrayView[@lex.Token],
) -> (Array[@types.Syntax], ArrayView[@lex.Token])? {
  // @util.logger("enumConstructFieldList: " + tokens.to_string())
  Parser(expr)
  .parser_and(ptoken_comma.parser_and(expr).many())
  .map(fn(input) {
    match input {
      (expr, exprs) => {
        let result = [expr]
        let exprs = exprs.map(fn(input) {
          match input {
            (_, expr) => expr
          }
        })
        result.append(exprs)
        result
      }
    }
  })
  .parse(tokens)
}

// type:
// 	'Unit'
// 	| 'Bool'
// 	| 'Int'
// 	| 'Double'
// 	| array_type
// 	| tuple_type
// 	| function_type;

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
      @lex.Token::IDENTIFIER(_) => true
      @lex.Token::UPPER_IDENTIFIER(_) => true
      _ => false
    }
  })
  .map(fn(input) {
    match input {
      UNIT => @types.Type::Unit
      BOOL => @types.Type::Bool
      INT => @types.Type::Int
      DOUBLE => @types.Type::Double
      IDENTIFIER(name) => @types.Type::UserDefineType(name, { val: [] })
      UPPER_IDENTIFIER(name) => @types.Type::UserDefineType(name, { val: [] })
      _ => panic()
    }
  })
  .or(arrayType)
  .or(functionType)
  .or(tupleType)
  .or(genericType)
  .or(userDefineType)
  .parse(tokens)
}

// generic_type: UPPER_IDENTIFIER '[' type ']'; // [T]

///|
fn genericType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  upperIdentifier
  .map(fn(input) {
    match input {
      @lex.Token::UPPER_IDENTIFIER(name) =>
        @types.Type::UserDefineType(name, { val: [] })
      _ => @util.die("error user")
    }
  })
  .parse(tokens)
}
// user_defined_type: UPPER_IDENTIFIER;

///|
fn userDefineType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  upperIdentifier
  .map(fn(input) {
    // @util.logger("userDefineType: " + input.to_string())
    match input {
      @lex.Token::UPPER_IDENTIFIER(name) =>
        @types.Type::UserDefineType(name, { val: [] })
      _ => @util.die("error user")
    }
  })
  .parse(tokens)
}
// array_type: 'Array' '[' type ']';

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
// function_type:
// 	'(' type (',' type)* ')' '->' type; // (Int, Bool) -> Int

///|
fn functionType(
  tokens : ArrayView[@lex.Token],
) -> (@types.Type, ArrayView[@lex.Token])? {
  // println("functionType: " + tokens.to_string())
  lparen
  .parser_and(parseType)
  .parser_and(ptoken_comma.parser_and(parseType).many())
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
fn[I, O] Parser::map(self : Parser[I], f : (I) -> O) -> Parser[O] {
  fn(input) {
    match self.parse(input) {
      Some((token, rest)) => Some((f(token), rest))
      None => None
    }
  }
}

///|
fn[V1, V2] Parser::parser_and(
  self : Parser[V1],
  parser2 : Parser[V2],
) -> Parser[(V1, V2)] {
  fn(input) {
    self
    .parse(input)
    .bind(value_rest => parser2
      .parse(value_rest.1)
      .map(value2_rest2 => ((value_rest.0, value2_rest2.0), value2_rest2.1)))
  }
}

///|
fn[V] Parser::or(self : Parser[V], parser2 : Parser[V]) -> Parser[V] {
  fn(input) {
    match self.parse(input) {
      None => parser2.parse(input)
      Some(_) as result => result
    }
  }
}

///|
fn[V1, V2] Parser::parser_or(
  self : Parser[V1],
  parser2 : Parser[V2],
) -> Parser[(V1?, V2?)] {
  fn(input) {
    match self.parse(input) {
      Some((v1, rest1)) => Some(((Some(v1), None), rest1))
      None =>
        match parser2.parse(input) {
          None => None
          Some((v2, rest2)) => Some(((None, Some(v2)), rest2))
        }
    }
  }
}

///|
fn[Value] Parser::many(self : Parser[Value]) -> Parser[Array[Value]] {
  fn(input) {
    let cumul = []
    let mut rest = input
    loop self.parse(input) {
      None => Some((cumul, rest))
      Some((v, rest_)) => {
        // println(rest_.to_string())
        cumul.push(v)
        rest = rest_
        continue self.parse(rest_)
      }
    }
  }
}

// fn[V] log(self : Parser[V]) -> Parser[V] {
//   fn(input) {
//     match self.parse(input) {
//       None => @util.die("end")
//       Some(_) as result => {
//         @util.logger(":::" + input.to_string())
//         result
//       }
//     }
//   }
// }

///|
fn[V1, V2] Parser::zeroOrOnce(
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
  }
}

///|
pub struct Parser[V]((ArrayView[@lex.Token]) -> (V, ArrayView[@lex.Token])?)

///|
fn[V] Parser::parse(
  self : Parser[V],
  tokens : ArrayView[@lex.Token],
) -> (V, ArrayView[@lex.Token])? {
  // println("parsing: " + tokens.to_string())
  self(tokens)
}

///|
let parser : Parser[@types.Syntax] = Parser(program)

///|
pub(all) suberror ParserErr String derive(ToJson)

///|
pub fn parse_from_string(str : String) -> @types.Syntax {
  // println("parsing: \n" + str)
  let tokens = []
  @lex.julex({ str, offset: 0, array: tokens })
  // println(tokens)
  let (prog, _) = parser.parse(tokens[:]).unwrap()
  prog
}

///|
test {
  let tokens = []
  let test1 =
    #| fn main {
    #|    let x = 1;
    #| }
  @lex.julex({ str: test1, offset: 0, array: tokens })
  // println(tokens)
  let (prog, _) = parser.parse(tokens[:]).unwrap()
  println(prog)
}

///|
test {
  let tokens = []
  let _test2 = @fs.read_file_to_string(
    "contest-2025-data/test_cases/size/almabench.mbt",
  )
  println(_test2)
  @lex.julex({ str: _test2, offset: 0, array: tokens })
  println("tokens: " + tokens.to_string())
  let (prog, _) = parser.parse(tokens[:]).unwrap()
  println("prog: " + prog.to_json().stringify())
}

///|
test {
  let tokens = []
  // let _test2 = @fs.read_file_to_string("contest-2025-data/test_cases/mbt/conv_pool.mbt")
  // 遍历 contest-2025-data/test_cases/mbt 目录下的所有文件
  let files = @fs.read_dir("contest-2025-data/test_cases/mbt")
  println(files)
  for file in files {
    println("parsing: file " + file)
    let path = "contest-2025-data/test_cases/mbt/" + file
    let content = @fs.read_file_to_string(path)
    // println(content)
    @lex.julex({ str: content, offset: 0, array: tokens })
    // println(tokens)
    let (prog, _) = parser.parse(tokens[:]).unwrap()
    println(prog)
  }
  // println(_test2)
  // @lex.lex({ str: _test2, offset: 0, array: tokens })
  // println(tokens)
  // let (prog, _) = parser.parse(tokens[:]).unwrap()
  // println(prog)
}

///|
test {
  let x = ["1", "2", "3", "4"]
  let res = x.fold(init="0", (n, i) => "F(" + n + "," + i + ")")
  println(res)
}

///|
test {
  let tokens = []
  let _test2 = "Point::{ x: a.x + b.x, y: a.y + b.y }"
  // println(_test2)
  @lex.julex({ str: _test2, offset: 0, array: tokens })
  // println("tokens: " + tokens.to_string())
  // let (prog, _) = parser.parse(tokens[:]).unwrap()
  // println("prog: " + prog.to_string())

  let prog = expr(tokens)
  println("xxx:  " + prog.to_string())
}
