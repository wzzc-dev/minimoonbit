///|
pub fn to_llvmir(input: @closure.Program) -> LLVMIR {
    {name: "to_llvmir: " + input.fundefs.to_string() +  "\n" + input.body.to_string()}
}