///|
test "comment_spec_tests" {
  @tests.load_spec_file("./spec/specs/comments.json").run_spec_tests()
}

test "delimiters_spec_tests" {
  @tests.load_spec_file("./spec/specs/delimiters.json").run_spec_tests()
}

test "interpolation_spec_tests" {
  @tests.load_spec_file("./spec/specs/interpolation.json").run_spec_tests()
}

test "inverted_spec_tests" {
  @tests.load_spec_file("./spec/specs/inverted.json").run_spec_tests()
}


test "partials_spec_tests" {
  @tests.load_spec_file("./spec/specs/partials.json").run_spec_tests()
}

test "sections_spec_tests" {
  @tests.load_spec_file("./spec/specs/sections.json").run_spec_tests()
}
