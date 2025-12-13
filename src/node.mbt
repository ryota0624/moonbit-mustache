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
  context : Context,
) -> String raise RenderingError {
  match self {
    SectionNode(section) => section.render(context, t)
    VarNode(v) =>
      lookup(v.name, context)
      .map(value => Node::print_json(value))
      .map(printed => if v.escape { Node::escape(printed) } else { printed })
      .unwrap_or_error(RenderingError("failed to lookup"))
    TextNode(text) => text
    DelimNode => ""
    CommentNode(_) => ""
    PartialNode(part) => {
      let template = t.partials.get(part)
      match template {
        Some(template) => template.with_partials(t.partials).render(context)
        None => ""
      }
    }
  }
}

///|
fn Node::print_json(json : Json) -> String {
  match json {
    String(s) => s
    Number(n, ..) => n.to_string()
    False => "false"
    True => "true"
    Null => "null"
    _ => json.to_string()
  }
}

///|
fn Node::escape(str : String) -> String {
  if !(str.contains_char('\'') ||
    str.contains_char('"') ||
    str.contains_char('&') ||
    str.contains_char('<') ||
    str.contains_char('>')) {
    return str
  }
  str
  .replace_all(old="'", new="&quot;")
  .replace_all(old="\"", new="&apos;")
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

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
fn SectionNode::render(
  self : SectionNode,
  ctx : Context,
  t : RenderableTemplate,
) -> String raise RenderingError {
  fn renderElems(appendCtx : Context) -> String raise RenderingError {
    self.elems.fold(init="", (result, node) => result +
      node.render(t, Context([..appendCtx.0, ..ctx.0])))
  }

  let value = lookup(self.name, ctx)
  let is_falsy = is_falsy(value.unwrap_or(Json::null()))
  if !is_falsy != self.inverted {
    match value {
      Some(Array(array)) =>
        array
        .map(json => Context([json]))
        .fold(init="", (result, ctx) => result + renderElems(ctx))
      _ =>
        renderElems(
          if value is None {
            Context([])
          } else {
            Context([value.unwrap()])
          },
        )
    }
  } else {
    return ""
  }
}

///|
test {
  let t = Template::new("")
  let renderable = t.parse_template("hello {{^world}}world{{/world}}")
  let rendered = renderable.render([
    Json::object({ "world": Json::boolean(false) }),
  ])
  assert_eq(rendered, "hello world")
  let rendered = renderable.render([
    Json::object({ "world": Json::boolean(true) }),
  ])
  assert_eq(rendered, "hello ")
}

///|
test {
  let t = Template::new("")
  let renderable = t.parse_template("hello {{#world}}world{{/world}}")
  let rendered = renderable.render([
    Json::object({ "world": Json::boolean(true) }),
  ])
  assert_eq(rendered, "hello world")
  let rendered = renderable.render([
    Json::object({ "world": Json::boolean(false) }),
  ])
  assert_eq(rendered, "hello ")
}

///|
priv struct Context(Array[Json])

///|
priv suberror RenderingError String derive(Show)

// The Template type represents a template and its components.

///|
priv struct Template {
  name : String
  partials : Map[String, RenderableTemplate]
  _start_delim : String
  _end_delim : String
  silentMiss : Bool
}

///|
fn Template::parse_template(
  self : Template,
  input : String,
) -> RenderableTemplate raise ParseError {
  let l = Lexer::new(self.name, input)
  let p = Parser::new(l)
  { partials: self.partials, elms: p.parse(), silentMiss: self.silentMiss }
}

// TODO: fixme

///|
fn Template::new(name : String) -> Template {
  { name, partials: {}, _start_delim: "", _end_delim: "", silentMiss: false }
}

///|
priv struct RenderableTemplate {
  partials : Map[String, RenderableTemplate]
  elms : Array[Node]
  silentMiss : Bool
}

///|
fn RenderableTemplate::with_partials(
  self : RenderableTemplate,
  partials : Map[String, RenderableTemplate],
) -> RenderableTemplate {
  { partials, elms: self.elms, silentMiss: self.silentMiss }
}

///|
fn RenderableTemplate::render(
  self : RenderableTemplate,
  context : Context,
) -> String raise RenderingError {
  let mut result = ""
  for elem in self.elms {
    let renderedElem = try? elem.render(self, context)
    match renderedElem {
      Err(e) => if !self.silentMiss { raise e }
      Ok(rendered) => result = result + rendered
    }
  }
  result
}
