///|
pub fn print_functions(llvmir : LLVMIR) -> String {
  let logger = @buffer.Buffer::new()
  logger.write_string("\n")
  logger.contents().to_unchecked_string()
}
