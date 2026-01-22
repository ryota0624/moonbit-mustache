test "mustache_boolean_context_shadowing_bug" {
  let template = "{{#section}}Value is: {{data}}{{/section}}"
  let data = Json::object({
    "section": Json::boolean(true),
    "data": Json::string("correct_value"),
  })
  let result = @mustache.parse!(template, data)
  inspect!(result, content="Value is: correct_value")
}
