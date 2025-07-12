// https://github.com/alexkappa/mustache/blob/master/mustache.go

///|
priv enum Node {
  DelimNode
  TextNode(String)
  VarNode(VarNode)
  CommentNode(String)
  SectionNode(SectionNode)
  PartialNode(String)
} derive(Show, Eq)

///|
fn Node::render(
  self : Node,
  t : RenderableTemplate,
  contexts : Array[Map[String, Json]]
) -> String raise {
  if !contexts.is_empty() {
    fail("")
  }
  "Iam Node \{self}"
}

// render(t *Template, w *writer, c ...interface{}) error

///|
priv struct VarNode {
  name : String
  escape : Bool
} derive(Show, Eq)

///|
priv struct SectionNode {
  name : String
  inverted : Bool
  elems : Array[Node]
} derive(Show, Eq)

///|
trait Context {}

// The Template type represents a template and its components.

///|
priv struct Template {
  name : String
  partials : Map[String, Template]
  startDelim : String
  endDelim : String
  silentMiss : Bool
}

///|
fn Template::parseString(
  self : Template,
  input : String
) -> RenderableTemplate raise ParseError {
  let l = Lexer::new(self.name, input)
  let p = Parser::new(l)
  { elms: p.parse(), silentMiss: self.silentMiss }
}

// TODO: fixme

///|
fn Template::new(name : String) -> Template {
  { name, partials: {}, startDelim: "", endDelim: "", silentMiss: false }
}

///|
priv struct RenderableTemplate {
  elms : Array[Node]
  silentMiss : Bool
}

///|
fn RenderableTemplate::render(
  self : RenderableTemplate,
  contexts : Array[Map[String, Json]]
) -> String raise {
  let mut result = ""
  for elem in self.elms {
    let renderedElem = try? elem.render(self, contexts)
    match renderedElem {
      Err(e) => if !self.silentMiss { raise e }
      Ok(rendered) => result = result + rendered
    }
  }
  result
}

///|
test {
  let t = Template::new("")
  let renderable = t.parseString("hello\n{{world}}")
  let rendered = renderable.render([])
  println(rendered)
}
