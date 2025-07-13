///|
extern "js" fn read_file(
  path : String,
  ok : (String) -> Result[String, Failure],
  err : (String) -> Result[String, Failure]
) -> Result[String, Failure] =
  #|(d, ok, err) => {
  #| const fs = require('fs');
  #| try {
  #|  return ok(fs.readFileSync(d).toString());
  #| } catch (e) {
  #|  return err(e.toString());
  #| }
  #|}

///|
fn load_spec(path : String) -> Spec raise {
  let file = read_file(path, Ok(_), msg => Err(Failure(msg))).unwrap_or_error()
  parse_file_to_spec(file)
}

///|
fn load_spec_file(path : String) -> SpecFile raise {
  let spec = load_spec(path)
  let name = path
    .split("/")
    .last()
    .or_error(Failure("Failed to get file name from path: " + path))
    .to_string()
  { name, spec }
}

test "load_spec" {
  let spec = try? load_spec("./spec/specs/comments.json")
  assert_true(spec.is_ok())
}