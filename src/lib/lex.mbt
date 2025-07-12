/// https://github.com/alexkappa/mustache/blob/master/lex.go

///|
priv struct Token {
  type_ : TokenType
  value : String
  line : Int
  col : Int
} derive(Show)

///|
priv enum TokenType {
  Error
  EOF
  Identifier
  LeftDelim
  RightDelim
  Text
  Comment
  SectionStart
  SectionInverse
  SectionEnd
  RawStart
  RawEnd
  RawAlt
  Partial
  SetDelim
} derive(Eq, Show)

///|
priv struct Lexer {
  name : String // the name of the input; used only for error reports.
  input : String // the string being scanned.
  mut leftDelim : String // start of action.
  mut rightDelim : String // end of action.
  mut state : StateFn // the next lexing function to enter.
  mut pos : Int // current position in the input.
  mut start : Int // start position of this token.
  tokens : Array[Token] // array of scanned tokens.
} derive(Show)

///|
fn Lexer::new(
  name : String,
  input : String,
  leftDelim~ : String = "{{",
  rightDelim~ : String = "}}"
) -> Lexer {
  {
    name,
    input,
    leftDelim,
    rightDelim,
    state: StateFn::Func(s => s.state_text()),
    pos: 0,
    start: 0,
    tokens: [],
  }
}

///|
priv enum StateFn {
  Func((Lexer) -> StateFn)
  None
}

///|
fn Lexer::state_text(self : Lexer) -> StateFn {
  for {
    if self.input.charcodes(start=self.pos).has_prefix(self.leftDelim) {
      if self.pos > self.start {
        self.emit(TokenType::Text)
      }
      return StateFn::Func(s => s.state_left_delim())
    }
    if self.next() == Rune::EOF {
      break
    }
  }
  if self.pos > self.start {
    self.emit(TokenType::Text)
  }
  self.emit(TokenType::EOF)
  return StateFn::None
}

///|
fn Lexer::state_left_delim(self : Lexer) -> StateFn {
  self.seek(self.leftDelim.length())
  if self.peek() == Rune::Char('=') {
    ignore(self.next())
    return StateFn::Func(s => s.state_set_delim())
  }
  self.emit(TokenType::LeftDelim)
  StateFn::Func(s => s.state_tag())
}

///|
fn Lexer::state_right_delim(self : Lexer) -> StateFn {
  self.seek(self.rightDelim.length())
  self.emit(TokenType::RightDelim)
  StateFn::Func(s => s.state_text())
}

///|
fn Lexer::ignore_(self : Lexer) -> Unit {
  self.start = self.pos
}

///|
fn state_set_delim(self : Lexer) -> StateFn {
  let end = "=" + self.rightDelim
  let endIndex = self.input.charcodes(start=self.pos).find(end)
  match endIndex {
    None => return self.error("Unterminated set delimiter")
    Some(index) => {
      let delimis = self.input
        .charcodes(start=self.pos, end=self.pos + index)
        .split(" ")
      if delimis.count() < 2 {
        self.error("set delimiters should be separated by a spac")
      } else {
        let mut delimFn : DelimFn = DelimFn::Func((l, s) => l.left_fn(s))
        for delim in delimis {
          if delim != "" {
            if not(delimFn.is_none_delim_fn()) {
              delimFn = match delimFn {
                DelimFn::Func(f) => f(self, delim.to_string())
                DelimFn::None => self.right_fn(delim.to_string())
              }
            }
          }
        }
        ignore(self.seek(index + end.length()))
        self.ignore_()
        self.emit(TokenType::SetDelim)
        StateFn::Func(s => s.state_text())
      }
    }
  }
}

///|
priv enum DelimFn {
  Func((Lexer, String) -> DelimFn)
  None
}

///|
fn DelimFn::is_none_delim_fn(self : DelimFn) -> Bool {
  match self {
    DelimFn::None => true
    _ => false
  }
}

///|
fn Lexer::left_fn(self : Lexer, s : String) -> DelimFn {
  self.leftDelim = s
  DelimFn::Func((l, s) => l.right_fn(s))
}

///|
fn Lexer::right_fn(self : Lexer, s : String) -> DelimFn {
  self.rightDelim = s
  DelimFn::None
}

///|
fn Lexer::state_tag(self : Lexer) -> StateFn {
  if self.input.charcodes(start=self.pos).has_prefix("}" + self.rightDelim) {
    ignore(self.seek(1))
    self.emit(TokenType::RawEnd)
    return StateFn::Func(s => s.state_right_delim())
  }
  if self.input.charcodes(start=self.pos).has_prefix(self.rightDelim) {
    return StateFn::Func(s => s.state_right_delim())
  }
  match self.next() {
    r if r.is_whitespaces() => {
      self.ignore_()
      StateFn::Func(s => s.state_tag())
    }
    Rune::Char(char) =>
      match char {
        '!' => {
          self.emit(TokenType::Comment)
          StateFn::Func(s => s.state_comment())
        }
        '#' => {
          self.emit(TokenType::SectionStart)
          StateFn::Func(s => s.state_tag())
        }
        '^' => {
          self.emit(TokenType::SectionInverse)
          StateFn::Func(s => s.state_tag())
        }
        '/' => {
          self.emit(TokenType::SectionEnd)
          return StateFn::Func(s => s.state_tag())
        }
        '>' => {
          self.emit(TokenType::Partial)
          StateFn::Func(s => s.state_tag())
        }
        '{' => {
          self.emit(TokenType::RawStart)
          StateFn::Func(s => s.state_tag())
        }
        '&' => {
          self.emit(TokenType::RawAlt)
          StateFn::Func(s => s.state_tag())
        }
        '\n' => self.error("unclosed actin")
        c =>
          if Rune::Char(c).is_alphanum() {
            self.backup()
            StateFn::Func(s => s.state_indent())
          } else {
            self.error("unexpected character in tag: " + char.to_string())
          }
      }
    EOF => return self.error("unclosed action")
  }
}

///|
fn Lexer::state_indent(self : Lexer) -> StateFn {
  for {
    let r = self.next()
    if not(r.is_alphanum()) {
      self.backup()
      self.emit(TokenType::Identifier)
      break
    }
  }
  return StateFn::Func(s => s.state_tag())
}

///|
fn Lexer::state_comment(self : Lexer) -> StateFn {
  let indexOfCommentEnd = self.input
    .charcodes(start=self.pos)
    .find(self.rightDelim)
  match indexOfCommentEnd {
    None => self.error("unclosed tag for comment")
    Some(index) => {
      ignore(self.seek(index))
      self.emit(TokenType::Text)
      return StateFn::Func(s => s.state_right_delim())
    }
  }
}

///|
fn Rune::is_whitespaces(self : Rune) -> Bool {
  match self {
    Rune::Char(' ' | '\t' | '\n' | '\r') => true
    _ => false
  }
}

///|
fn Rune::is_alphanum(self : Rune) -> Bool {
  match self {
    Rune::Char('_' | '.') => true
    Rune::Char(c) if c.is_ascii_digit() => true
    Rune::Char(c) if c.is_ascii_alphabetic() => true
    _ => false
  }
}

///|
impl Show for StateFn with output(_ : StateFn, logger : &Logger) {
  logger.write_string("StateFn")
}

///|
priv enum Rune {
  EOF
  Char(Char)
} derive(Eq)

///|
fn Lexer::next(self : Lexer) -> Rune {
  if self.pos >= self.input.length() {
    return Rune::EOF
  } else {
    let c = self.input.char_at(self.pos)
    self.pos += 1
    return Rune::Char(c)
  }
}

///|
fn Lexer::seek(self : Lexer, n : Int) -> Unit {
  self.pos += n
}

///|
fn Lexer::backup(self : Lexer) -> Unit {
  if self.pos > 0 {
    self.pos -= 1
  }
}

///|
fn Lexer::peek(self : Lexer) -> Rune {
  let r = self.next()
  self.backup()
  r
}

///|
fn Lexer::emit(self : Lexer, t : TokenType) -> Unit {
  let token = {
    type_: t,
    value: self.input.charcodes(start=self.start, end=self.pos).to_string(),
    line: self.line_num(),
    col: self.column_num(),
  }
  self.tokens.push(token)
  self.start = self.pos
}

///|
fn Lexer::error(self : Lexer, msg : String) -> StateFn {
  let token = {
    type_: TokenType::Error,
    value: msg,
    line: self.line_num(),
    col: self.column_num(),
  }
  self.tokens.push(token)
  StateFn::None
}

///|
fn Lexer::line_num(self : Lexer) -> Int {
  self.input.charcodes(end=self.pos).split("\n").count()
}

///|
test {
  let input = "hello\nworld"
  let lexer = {
    name: "test",
    input,
    leftDelim: "{{",
    rightDelim: "}}",
    state: StateFn::None,
    pos: 0,
    start: 0,
    tokens: [],
  }
  lexer.seek(5)
  println(lexer) // move to the end of "hello";
  assert_eq(lexer.line_num(), 1)
  lexer.seek(6) // move to the start of "world"
  assert_eq(lexer.line_num(), 2)
}

///|
fn Lexer::column_num(self : Lexer) -> Int {
  let last_lf = self.input.charcodes(end=self.pos).to_string().rev_find("\n")
  match last_lf {
    Some(lf) => {
      if lf == self.pos {
        return 0
      }
      self.input.charcodes(start=lf + 1, end=self.pos).length()
    }
    None => self.input.charcodes(end=self.pos).length()
  }
}

///|
test {
  let input = "hello\nworld"
  let lexer = {
    name: "test",
    input,
    leftDelim: "{{",
    rightDelim: "}}",
    state: None,
    pos: 0,
    start: 0,
    tokens: [],
  }
  lexer.seek(5) // move to the end of "hello"
  assert_eq(lexer.column_num(), 5)
  lexer.seek(1) // move to the start of "\n"
  assert_eq(lexer.column_num(), 0)
  lexer.seek(1) // move to the start of "world"
  assert_eq(lexer.column_num(), 1)
}

///|
test {
  let greeting = "hello, 世界"
  for k in greeting.iter() {
    println("\{k}")
  }
  println("---")
  println(greeting.char_at(7)) // prints 'h'
}

///|
test {
  let lexer = {
    name: "test",
    input: "hello, 世界",
    leftDelim: "{{",
    rightDelim: "}}",
    state: None,
    pos: 0,
    start: 0,
    tokens: [],
  }
  while true {
    let c = lexer.next()
    match c {
      Rune::EOF => break
      Rune::Char(ch) => println("Read character: \{ch}")
    }
  }
}

///|
fn token(self : Lexer) -> Token {
  for {
    let token = if self.tokens.is_empty() {
      Option::None
    } else {
      self.tokens.drain(0, 1).pop()
    }
    match token {
      Some(t) => return t
      None =>
        self.state = match self.state {
          StateFn::Func(f) => f(self)
          StateFn::None => None
        }
    }
  }
}

///|
fn Lexer::tokens(self : Lexer) -> Array[Token] raise Error {
  let tokens = Array::new()
  for {
    let token = self.token()
    match token.type_ {
      TokenType::EOF => break
      TokenType::Error => fail("Lexer error: " + token.value)
      _ => tokens.push(token)
    }
  }
  tokens
}

///|
test {
  let input = "hello {{world}}"
  let lexer = Lexer::new("test", input)
  let expected = [
    (TokenType::Text, "hello "),
    (TokenType::LeftDelim, "{{"),
    (TokenType::Identifier, "world"),
    (TokenType::RightDelim, "}}"),
  ]
  assert_eq(lexer.tokens().map(t => (t.type_, t.value)), expected)
}

///|
test {
  let input = "hello\n{{world}}"
  let lexer = Lexer::new("test", input)
  let expected = [
    (TokenType::Text, "hello\n"),
    (TokenType::LeftDelim, "{{"),
    (TokenType::Identifier, "world"),
    (TokenType::RightDelim, "}}"),
  ]
  assert_eq(lexer.tokens().map(t => (t.type_, t.value)), expected)
}

///|
test {
  let input = "foo {{{bar}}}\nbaz {{! this is ignored }}"
  let lexer = Lexer::new("test", input)
  let expected = [
    (TokenType::Text, "foo "),
    (TokenType::LeftDelim, "{{"),
    (TokenType::RawStart, "{"),
    (TokenType::Identifier, "bar"),
    (TokenType::RawEnd, "}"),
    (TokenType::RightDelim, "}}"),
    (TokenType::Text, "\nbaz "),
    (TokenType::LeftDelim, "{{"),
    (TokenType::Comment, "!"),
    (TokenType::Text, " this is ignored "),
    (TokenType::RightDelim, "}}"),
  ]
  assert_eq(lexer.tokens().map(t => (t.type_, t.value)), expected)
}

///|
test {
  let input = "\nfoo {{bar}} baz {{=| |=}}\r\n |foo| |={{ }}=| {{bar}}"
  let lexer = Lexer::new("test", input)
  let expected = [
    (TokenType::Text, "\nfoo "),
    (TokenType::LeftDelim, "{{"),
    (TokenType::Identifier, "bar"),
    (TokenType::RightDelim, "}}"),
    (TokenType::Text, " baz "),
    (TokenType::SetDelim, ""),
    (TokenType::Text, "\r\n "),
    (TokenType::LeftDelim, "|"),
    (TokenType::Identifier, "foo"),
    (TokenType::RightDelim, "|"),
    (TokenType::Text, " "),
    (TokenType::SetDelim, ""),
    (TokenType::Text, " "),
    (TokenType::LeftDelim, "{{"),
    (TokenType::Identifier, "bar"),
    (TokenType::RightDelim, "}}"),
  ]
  assert_eq(lexer.tokens().map(t => (t.type_, t.value)), expected)
}

///|
test {
  let input = "{{=| |=}}\r\n"
  let lexer = Lexer::new("test", input)
  let expected = [(TokenType::SetDelim, ""), (TokenType::Text, "\r\n")]
  assert_eq(lexer.tokens().map(t => (t.type_, t.value)), expected)
}
