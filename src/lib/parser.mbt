// https://github.com/alexkappa/mustache/blob/master/parse.go

///|
priv struct Parser {
  readToken : () -> Token
  mut buf : Array[Token]
}

///|
fn Parser::new(lex : Lexer) -> Parser {
  { readToken: () => lex.token(), buf: [] }
}

///| read next token
fn Parser::read(self : Parser) -> Token {
  if self.buf.length() > 0 {
    let r = self.buf[0]
    self.buf = self.buf[1:].to_array()
    return r
  }
  return (self.readToken)()
}

///| read N next token
fn Parser::readn(self : Parser, n : Int) -> Array[Token] {
  let tokens = []
  for _ in 0..<n {
    let token = self.read()
    if token.type_ == TokenType::EOF {
      return tokens
    }
    tokens.push(token)
  }
  return tokens
}

///|
priv suberror ReachedEOF

///|
priv suberror ParseError {
  FormatError(String)
  ReadError(ReachedEOF)
}

///| read token reached TokenType
fn Parser::readt(self : Parser, t : TokenType) -> Array[Token] raise ReachedEOF {
  let tokens = []
  for {
    let token = self.read()
    tokens.push(token)
    match token.type_ {
      TokenType::EOF => raise ReachedEOF
      tokenType if tokenType == t => return tokens
      _ => ()
    }
  }
}

///|
fn Parser::readv(self : Parser, t : Token) -> Array[Token] raise ReachedEOF {
  let tokens = []
  for {
    let read = self.readt(t.type_)
    tokens.append(read)
    if read.length() > 0 &&
      read.last().map_or(false, last => last.type_ == t.type_) {
      break
    }
  }
  tokens
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.buf.length() > 0 {
    self.buf[0]
  } else {
    let t = (self.readToken)()
    self.buf.push(t)
    t
  }
}

///|
fn Parser::peekn(self : Parser, n : Int) -> Array[Token] raise ReachedEOF {
  if self.buf.length() > n {
    self.buf[:n].to_array()
  } else {
    for i in self.buf.length()..<n {
      let t = (self.readToken)()
      self.buf.push(t)
      if t.type_ == TokenType::EOF {
        raise ReachedEOF
      }
    }
    self.buf
  }
}

///|
fn Parser::peekt(self : Parser, t : TokenType) -> Array[Token] raise {
  for i in 0..<self.buf.length() {
    match self.buf[i].type_ {
      TokenType::EOF => raise ReachedEOF
      tType if tType == t => return self.buf[:i].to_array()
      _ => ()
    }
  }
  for {
    let token = (self.readToken)()
    self.buf.push(token)
    match token.type_ {
      TokenType::EOF => raise ReachedEOF
      tType if tType == t => return self.buf
      _ => ()
    }
  }
  fail("EOF not found")
}

///|
fn Parser::errorf(token : Token, message : String) -> ParseError {
  ParseError::FormatError(
    "\{token.line}:\{token.col} syntax error. (\{token.type_}: \{token.value}) \{message}",
  )
}

///|
fn Parser::parse(self : Parser) -> Array[Node] raise ParseError {
  let nodes : Array[Node] = []
  for {
    let token = self.read()
    match token.type_ {
      EOF => break
      Error => raise Parser::errorf(token, token.value)
      Text => nodes.push(TextNode(token.value))
      LeftDelim => nodes.push(self.parse_tag())
      RawStart => nodes.push(self.parse_raw_tag())
      SetDelim => nodes.push(DelimNode)
      _ => ()
    }
  }
  nodes
}

///|
test {
  let testCases = [
    "hello\n{{world}}", "foo {{{bar}}}\nbaz {{! this is ignored }}", "\nfoo {{bar}} baz {{=| |=}}\r\n |foo| |={{ }}=| {{bar}}",
  ]
  for testCase in testCases {
    let lexer = Lexer::new("test", testCase)
    let parser = Parser::new(lexer)
    let nodes = parser.parse()
    println(nodes)
  }
}

///|
fn Parser::parse_tag(self : Parser) -> Node raise ParseError {
  let token = self.read()
  match token.type_ {
    Identifier => self.parse_var(token, true)
    RawStart => self.parse_raw_tag()
    RawAlt => self.parse_raw_tag()
    Comment => self.parse_comment()
    SectionInverse => self.parse_section(true)
    SectionStart => self.parse_section(false)
    Partial => self.parse_partial()
    _ => raise ParseError::FormatError("unreachable code")
  }
}

///|
fn Parser::parse_raw_tag(self : Parser) -> Node raise ParseError {
  let token = self.read()
  if token.type_ != Identifier {
    raise Parser::errorf(token, "unexpected token")
  }
  let next = self.read()
  if next.type_ != RawEnd {
    raise Parser::errorf(next, "unexpected token")
  }
  let next = self.read()
  if next.type_ != RightDelim {
    raise Parser::errorf(next, "unexpected token")
  }
  VarNode({ name: token.value, escape: false })
}

///|
fn Parser::parse_var(
  self : Parser,
  ident : Token,
  escape : Bool
) -> Node raise ParseError {
  let next = self.read()
  if next.type_ != RightDelim {
    raise Parser::errorf(next, "unexpected token")
  }
  VarNode({ name: ident.value, escape })
}

///|
fn Parser::parse_comment(self : Parser) -> Node raise ParseError {
  let mut comment = ""
  for {
    let token = self.read()
    match token.type_ {
      EOF => raise Parser::errorf(token, "unexpected token")
      Error => raise Parser::errorf(token, token.value)
      RightDelim => return CommentNode(comment)
      _ => comment = comment + token.value
    }
  }
}

///|
fn Parser::parse_section(self : Parser, inverse : Bool) -> Node raise ParseError {
  let token = self.read()
  if token.type_ != Identifier {
    raise Parser::errorf(token, "unexpected token")
  }
  let next = self.read()
  if next.type_ != RightDelim {
    raise Parser::errorf(token, "unexpected token")
  }
  let tokens : Array[Token] = []
  let mut stack = 1
  for {
    let read = (try? self.readv(token))
      .map_err(ParseError::ReadError(_))
      .unwrap_or_error()
    tokens.append(read)
    if read.length() > 1 {
      // 			tt := read[len(read)-2]
      let tt = read[read.length() - 2]
      match tt.type_ {
        SectionStart | SectionInverse => stack = stack + 1
        SectionEnd => stack = stack - 1
        _ => ()
      }
    }
    if stack == 0 {
      break
    }
  }
  // StartSection, Ientifier,  RightDelim
  let nodes = self.sub_parser(tokens[:tokens.length() - 3].to_array()).parse()
  SectionNode({ name: token.value, inverted: inverse, elems: nodes })
}

///|
fn Parser::sub_parser(_ : Parser, tokens : Array[Token]) -> Parser {
  let eofToken = { type_: TokenType::EOF, value: "", line: 0, col: 0 }
  { readToken: () => eofToken, buf: tokens.copy() }
}

///|
fn Parser::parse_partial(self : Parser) -> Node raise ParseError {
  let token = self.read()
  if token.type_ != Identifier {
    raise Parser::errorf(token, "unexpected token")
  }
  let next = self.read()
  if next.type_ != RightDelim {
    raise Parser::errorf(next, "unexpected token")
  }
  PartialNode(token.value)
}
