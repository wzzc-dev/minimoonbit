# 新测试脚本使用说明

## 功能特点
- 模块化设计：按照 config.yml 中定义的测试部分组织测试
- 智能测试逻辑：
  - tyck 部分为负向测试（期望类型检查失败）
  - size/speed 部分仅编译不运行
  - 其余部分完整编译并运行
- 10秒超时保护防止测试挂起
- 自动统计测试结果
- 彩色输出便于识别结果
- 自动清理临时文件
- 在最后列出所有成功和失败的测试用例

## 使用方法
### 运行默认测试部分
```bash
./script/new_test.sh
```

### 运行特定测试部分
```bash
./script/new_test.sh tyck
./script/new_test.sh codegen
./script/new_test.sh optional-enum-only
```

### 运行所有测试部分
```bash
./script/new_test.sh all
```

### 运行 size 和 speed 测试部分
```bash
./script/new_test.sh size-speed
```

## 测试部分说明
1. **tyck**: 类型检查测试（负向测试，期望类型检查失败）
2. **codegen**: 代码生成测试
3. **optional-asm**: 可选汇编相关测试
4. **optional-enum-only**: 仅枚举类型测试
5. **optional-generic-only**: 仅泛型测试
6. **optional-mixed**: 混合特性的测试
7. **optional-struct-only**: 仅结构体测试
8. **size**: 性能尺寸测试（仅编译）
9. **speed**: 性能速度测试（仅编译）

每个测试部分都根据其特性采用相应的测试策略，确保测试的有效性和准确性。