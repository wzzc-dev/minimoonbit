///|
pub fn print_functions(rv_asm : Array[AssemblyFunction]) -> String {
  let logger = @buffer.new()
  for f in rv_asm {
    f.output(logger)
    logger.write_string("\n")
  }
  logger.contents().to_unchecked_string()
}

///|
/// Print assembly functions with data segment
pub fn print_array_data(datas : Array[AssemblyFunction]) -> String {
  let logger = @buffer.new()
  
  // Print data segment
  logger.write_string(".data\n")
  
  // Print text segment
  logger.write_string(".text\n")
  for data in datas {
    AssemblyFunction::output(data, logger)
  }
  
  logger.contents().to_unchecked_string()
}
