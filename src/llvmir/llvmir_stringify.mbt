///|
pub fn print_functions(llvmir : LLVMIR) -> String {
  let logger = @buffer.new()
  logger.write_string("\n")
  logger.write_string("Functions:\n" + llvmir.to_json().to_string() + "\n")
  logger.contents().to_unchecked_string()
}
