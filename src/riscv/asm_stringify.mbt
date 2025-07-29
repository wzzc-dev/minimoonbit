///|
pub fn print_functions(rv_asm : Array[AssemblyFunction]) -> String {
  let logger = @buffer.new()
  for f in rv_asm {
    f.output(logger)
    logger.write_string("\n")
  }
  logger.contents().to_unchecked_string()
}
