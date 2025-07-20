///|
fn lookup(name : String, context : Context) -> Json? {
  if name != "." && name.contains(".") {
    let parts = name.split(".")
    return parts
      .head()
      .bind(head => lookup(head.to_string(), context).bind(value => {
        let tail = parts[1:].map(s => s.to_string()).join(".")
        lookup(tail, Context([value]))
      }))
  }
  for c in context.inner() {
    if name == "." {
      return Some(c)
    }
    let value = match c {
      Object(obj) => obj.get(name)
      _ => Some(c)
    }
    if !value.is_empty() {
      return value
    }
  }
  return None
}

///|
test {
  let ctx = Context([
    { "a": Json::number(2), "b": Json::object({ "c": Json::string("text") }) },
    { "e": Json::object({ "f": Json::object({ "g": Json::boolean(true) }) }) },
  ])
  let retrived = [
    (lookup("a", ctx), Json::number(2)),
    (lookup("b.c", ctx), Json::string("text")),
    (lookup("e.f.g", ctx), Json::boolean(true)),
  ]
  for value in retrived {
		assert_eq(value.0, Some(value.1))
  }
}
