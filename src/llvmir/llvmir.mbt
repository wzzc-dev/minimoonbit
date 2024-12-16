struct LLVMIR {
    // 模块名称
    name: String
    // 全局变量列表
    globals: Array[Global]
    // 函数列表 
    functions: Array[Function]
    // 类型定义
    types: Array[Type]
    // 元数据
    metadata: Array[Metadata]
}

// 全局变量定义
struct Global {
    name: String
    ty: Type
    initializer: Option[Constant]
    is_constant: Bool
}

// 函数定义
struct Function {
    name: String
    return_type: Type
    parameters: Array[Parameter]
    basic_blocks: Array[BasicBlock]
}

// 基本块
struct BasicBlock {
    name: String
    instructions: Array[Instruction]
}

// 指令
enum Instruction {
    Add(Value, Value)
    Sub(Value, Value)
    Mul(Value, Value)
    Div(Value, Value)
    Load(Type, Value)
    Store(Value, Value)
    Call(Type, String, Array[Value])
    Return(Option[Value])
    // 其他指令...
    Unit
}

// 类型系统
enum Type {
    Void
    Integer(UInt)
    Float
    Double
    Pointer(Ref[Type])
    Array(Ref[Type], UInt)
    Function(Type, Array[Type])
    Struct(Array[Type])
}

// 元数据定义
enum Metadata {
    // 命名元数据
    Named(String, Array[MetadataNode])
    // 元数据节点
    Node(Array[MetadataValue])
}

// 元数据值类型
enum MetadataValue {
    // 字符串
    String(String)
    // 常量值
    Constant(Constant)
    // 引用其他元数据节点
    NodeRef(UInt)
    // null 值
    Null
    // 基本块引用
    BasicBlockRef(String)
    // 函数引用
    FunctionRef(String)
    // 全局变量引用
    GlobalRef(String)
}

// 常量值定义
enum Constant {
    Int(Int)
    Float(Double)
    Bool(Bool)
    Null
    Undef
    Array(Array[Constant])
    Struct(Array[Constant])
}

// 函数参数定义
struct Parameter {
    // 参数名称
    name: String
    // 参数类型
    ty: Type
    // 可选:参数属性(比如 byval, noalias 等)
    attributes: Array[String]
}

// 值类型定义
enum Value {
    // 常量值
    Constant(Constant)
    // 局部变量/临时值引用
    Local(String)
    // 全局变量引用
    Global(String)
    // 函数参数引用
    Parameter(String)
    // 基本块引用
    BasicBlock(String)
    // 函数引用
    Function(String)
    // null 值
    Null
}

// 元数据节点定义
struct MetadataNode {
    // 节点 ID
    id: UInt
    // 节点包含的元数据值
    values: Array[MetadataValue]
    // 可选: 节点的名称标识
    name: Option[String]
}