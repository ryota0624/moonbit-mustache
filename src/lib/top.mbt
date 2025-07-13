///|
/// parse mustache template with data
pub fn parse(template : String, data : Json) -> String raise {
   let output = try? Template::new("").parse_template(template).render([data])
  output.unwrap_or_error()
}
