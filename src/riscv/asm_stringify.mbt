///|
pub fn print_functions(rv_asm : Array[AssemblyFunction]) -> String {
  let logger = @buffer.new()
  let static_datas = []

  let text_asm = []
  for f in rv_asm {
    if f.static_data {
      static_datas.push(f)
    } else {
      text_asm.push(f)
    }
  }
  // Print data segment
  logger.write_string(".data\n")
  for f in static_datas {
    f.output(logger)
    logger.write_string("\n")
  }
  logger.write_string("\n")
  // Print text segment
  logger.write_string(".text\n")
  for f in text_asm {
    f.output(logger)
    logger.write_string("\n")
  }
  logger.contents().to_unchecked_string()
}