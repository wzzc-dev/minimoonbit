# 多维数组功能实现说明

## 概述

本次修改为 miniju 项目的 KNF (A-Normal Form) 语法预处理器添加了多维数组支持。之前的实现只支持一维数组，现在可以处理任意维度的嵌套数组。

## 实现原理

### 1. 多维数组检测

通过检查 `ArrayExpr` 的第一个元素是否也是 `ArrayExpr` 来判断是否为多维数组：

```moonbit
let is_multidimensional = match elems[0] {
  ArrayExpr(_) => true
  _ => false
}
```

### 2. 递归处理

对于多维数组，系统会：

1. **创建外层数组**: 使用 `Array::make(len, default_inner_array)` 创建外层数组
2. **递归处理子数组**: 对每个子数组递归调用相应的处理函数
3. **分配子数组**: 将处理后的子数组分配到外层数组的相应位置

### 3. 代码结构

修改后的代码包含三个主要函数：

- `syntax_preprocess`: 主入口函数，判断数组类型并调用相应处理函数
- `process_1d_array`: 处理一维数组（原有逻辑）
- `process_multidimensional_array`: 处理多维数组（新增功能）

## 支持的功能

### 二维数组 (矩阵)
```moonbit
let matrix = [[1, 2, 3], [4, 5, 6]];
let element = matrix[0][1]; // 访问第一行第二列，值为 2
```

### 三维数组 (立方体)
```moonbit
let cube = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
let element = cube[1][0][1]; // 访问第二层第一行第二列，值为 6
```

### 任意维度
系统支持任意深度的嵌套数组，只要内存允许。

## 实现细节

### 临时变量命名
为了避免变量名冲突，系统为每个子数组生成唯一的临时变量名：
```moonbit
let temp_var_name = str + "_sub_" + i.to_string()
```

### 类型推导
系统会根据外层数组的类型推导内层数组的类型：
```moonbit
let sub_array_ty = match ty {
  Array(inner_ty) => inner_ty
  _ => @util.die("Expected Array type for multidimensional array")
}
```

### 递归终止条件
当子数组不再包含 `ArrayExpr` 时，递归终止，调用一维数组处理逻辑。

## 性能考虑

1. **内存效率**: 多维数组实际上是数组的数组，每个子数组都是独立分配的
2. **访问性能**: 多维数组访问需要多次间接寻址，性能略低于一维数组
3. **编译时处理**: 所有数组结构在编译时就被展开为相应的创建和赋值操作

## 测试

可以使用提供的 `test_multidimensional_array.mbt` 文件测试多维数组功能：

```bash
# 在项目根目录下运行
moon build
# 然后运行相应的测试
```

## 兼容性

- 完全向后兼容：现有的一维数组代码无需修改
- 类型安全：编译时会检查数组类型匹配
- 语法一致：使用与一维数组相同的语法规则