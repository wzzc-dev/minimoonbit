#!/bin/bash

# 新的测试脚本，参考 config.yml 的结构

# 定义颜色输出函数
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[34m$1\033[0m"; }

# 初始化统计变量
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 初始化成功和失败用例数组
PASSED_CASES=()
FAILED_CASES=()

# 定义测试目录基础路径
TEST_BASE_DIR="contest-2025-data/test_cases"

# 定义各个测试部分及其测试用例（参考 config.yml）
# 使用单独的变量代替关联数组，以兼容更多bash环境
test_tyck="arrary_type_mismatch array_put_type_mismatch assign_type_mismatch binary_type_mismatch block_type_mismatch closure_func_type_incorrect func_arg_type_mismacth func_ret_type_mismatch if_branch_type_mismatch if_cond_not_bool let_tuple_type_mismatch let_type_mismatch return_type_mismatch tuple_type_mismatch unary_type_mismatch"
test_codegen="ack adder adder2 caltz clamp cls-bug cls-bug2 cls-rec cls-reg-bug counter even-odd float funcomp gcd id inprod-loop inprod-rec inprod join-reg join-reg2 join-stack join-stack2 join-stack3 non-tail-if non-tail-if2 print shuffle spill spill2 spill3 sum-tail sum"
test_optional_asm="ack adder adder2 caltz clamp cls-bug cls-bug2 cls-rec cls-reg-bug counter even-odd float funcomp gcd id inprod-loop inprod-rec inprod join-reg join-reg2 join-stack join-stack2 join-stack3 non-tail-if non-tail-if2 print shuffle spill spill2 spill3 sum-tail sum"
test_optional_enum_only="enum1 enum2 enum3 enum4 enum5"
test_optional_generic_only="generic1 generic2 generic3 generic4 generic5"
test_optional_mixed="generic_enum1 generic_enum2 generic_struct_enum generic_struct1 generic_struct2 smith1 smith2 smith3 smith4 smith5 struct_enum1 struct_enum2"
test_optional_struct_only="struct1 struct2 struct3 struct4 struct5"
test_size="almabench cholesky conv_pool2 conv_pool3 eigen fpquicksort invmat lu nbody qr queen schur svd"
test_speed="almabench cholesky conv_pool2 conv_pool3 eigen fpquicksort invmat lu nbody qr queen schur svd"

# 定义所有测试部分
ALL_SECTIONS=("tyck" "codegen" "optional-asm" "optional-enum-only" "optional-generic-only" "optional-mixed" "optional-struct-only" "size" "speed")

# 获取指定部分的测试用例函数
get_test_cases() {
    local section="$1"
    case "$section" in
        "tyck") echo "$test_tyck" ;;
        "codegen") echo "$test_codegen" ;;
        "optional-asm") echo "$test_optional_asm" ;;
        "optional-enum-only") echo "$test_optional_enum_only" ;;
        "optional-generic-only") echo "$test_optional_generic_only" ;;
        "optional-mixed") echo "$test_optional_mixed" ;;
        "optional-struct-only") echo "$test_optional_struct_only" ;;
        "size") echo "$test_size" ;;
        "speed") echo "$test_speed" ;;
        *) echo "" ;;
    esac
}

# 默认测试部分
DEFAULT_SECTIONS=("tyck" "codegen" "optional-asm" "optional-enum-only" "optional-generic-only" "optional-mixed" "optional-struct-only")

# 获取要测试的部分
SECTIONS_TO_TEST=()
if [ $# -eq 0 ]; then
    SECTIONS_TO_TEST=("${ALL_SECTIONS[@]}")
else
    # 检查是否提供了特殊参数
    if [ "$1" == "base" ]; then
        # 获取所有部分
        SECTIONS_TO_TEST=("${DEFAULT_SECTIONS[@]}")
    elif [ "$1" == "size-speed" ]; then
        SECTIONS_TO_TEST=("size" "speed")
    else
        # 使用提供的部分
        SECTIONS_TO_TEST=("${ALL_SECTIONS[@]}")
    fi
fi

# 显示将要测试的部分
echo "Testing sections: ${SECTIONS_TO_TEST[*]}"
echo "========================================"

# 遍历指定的测试部分
for SECTION in "${SECTIONS_TO_TEST[@]}"; do
    # 获取该部分的测试用例
    TEST_CASES_STR=$(get_test_cases "$SECTION")
    
    # 检查部分是否存在
    if [[ -z "$TEST_CASES_STR" ]]; then
        yellow "Warning: Section '$SECTION' not found, skipping..."
        continue
    fi
    
    blue "Processing section: $SECTION"
    echo "----------------------------------------"
    
    read -ra TEST_CASES <<< "$TEST_CASES_STR"
    
    # 遍历测试用例
    for TEST_CASE in "${TEST_CASES[@]}"; do
        # 构建测试文件路径
        TEST_FILE="$TEST_BASE_DIR/$SECTION/$TEST_CASE.mbt"
        ANS_FILE="$TEST_BASE_DIR/$SECTION/$TEST_CASE.ans"
        
        # 检查测试文件是否存在
        if [[ ! -f "$TEST_FILE" ]]; then
            yellow "Warning: Test file '$TEST_FILE' not found, skipping..."
            ((SKIPPED_TESTS++))
            continue
        fi
        
        # 增加总测试数
        ((TOTAL_TESTS++))
        
        echo "Running test: $SECTION/$TEST_CASE"
        
        # 根据不同部分执行不同的测试逻辑
        case "$SECTION" in
            "tyck")
                # 类型检查测试（负向测试，期望类型检查失败）
                if moon run -g src/bin/main.mbt -- --end-stage typecheck "$TEST_FILE" >/dev/null 2>&1; then
                    red "Test $SECTION/$TEST_CASE failed: Type checking should have failed but passed"
                    ((FAILED_TESTS++))
                    FAILED_CASES+=("$SECTION/$TEST_CASE")
                else
                    green "Test $SECTION/$TEST_CASE passed: Type checking correctly failed"
                    ((PASSED_TESTS++))
                    PASSED_CASES+=("$SECTION/$TEST_CASE")
                fi
                ;;
            "size"|"speed")
                # 对于 size 和 speed 测试，我们只编译不运行
                if moon run -g src/bin/main.mbt -- "$TEST_FILE" -o "out.s" --ssa && \
                   zig build-exe -target riscv64-linux -femit-bin=test-exe-file "out.s" ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 >/dev/null 2>&1; then
                    green "Test $SECTION/$TEST_CASE passed: Compilation successful"
                    ((PASSED_TESTS++))
                    PASSED_CASES+=("$SECTION/$TEST_CASE")
                else
                    red "Test $SECTION/$TEST_CASE failed: Compilation failed"
                    ((FAILED_TESTS++))
                    FAILED_CASES+=("$SECTION/$TEST_CASE")
                fi
                # 清理生成的文件
                rm -f out.s test-exe-file
                ;;
            *)
                # 其他部分的常规测试（编译并运行）
                    if moon run -g src/bin/main.mbt -- "$TEST_FILE" -o "out.s" --ssa && \
                       zig build-exe -target riscv64-linux -femit-bin=test-exe-file "out.s" ./riscv_rt/zig-out/lib/libmincaml.a -O Debug -fno-strip -mcpu=baseline_rv64 >/dev/null 2>&1 && \
                       ./rvlinux -n test-exe-file | sed '/>>>/q' > output.txt; then
                    
                    # 检查是否有答案文件进行比较
                    if [[ -f "$ANS_FILE" ]]; then
                        # 比较输出和答案文件
                        if cmp -s \
                            <(tr -d '\r' < output.txt | sed '$ { /^$/ d; }' | perl -pe 'chomp if eof') \
                            <(tr -d '\r' < "$ANS_FILE" | sed '$ { /^$/ d; }' | perl -pe 'chomp if eof'); then
                            green "Test $SECTION/$TEST_CASE passed: Output matches"
                            ((PASSED_TESTS++))
                            PASSED_CASES+=("$SECTION/$TEST_CASE")
                        else
                            red "Test $SECTION/$TEST_CASE failed: Output differs from answer file"
                            ((FAILED_TESTS++))
                            FAILED_CASES+=("$SECTION/$TEST_CASE")
                        fi
                    else
                        green "Test $SECTION/$TEST_CASE passed: Execution successful (no answer file to compare)"
                        ((PASSED_TESTS++))
                        PASSED_CASES+=("$SECTION/$TEST_CASE")
                    fi
                else
                    red "Test $SECTION/$TEST_CASE failed: Execution failed or timed out"
                    ((FAILED_TESTS++))
                    FAILED_CASES+=("$SECTION/$TEST_CASE")
                fi
                # 清理生成的文件
                rm -f out.s test-exe-file output.txt
                ;;
        esac
    done
    echo ""
done

# 输出测试总结
echo "========================================"
echo "Test Summary:"
echo "  Total tests: $TOTAL_TESTS"
echo "  Passed: $PASSED_TESTS"
echo "  Failed: $FAILED_TESTS"
echo "  Skipped: $SKIPPED_TESTS"

# 列出成功的测试用例
echo ""
echo "Passed test cases:"
if [ ${#PASSED_CASES[@]} -eq 0 ]; then
    echo "  None"
else
    for case in "${PASSED_CASES[@]}"; do
        green "  ✓ $case"
    done
fi

# 列出失败的测试用例
echo ""
echo "Failed test cases:"
if [ ${#FAILED_CASES[@]} -eq 0 ]; then
    echo "  None"
else
    for case in "${FAILED_CASES[@]}"; do
        red "  ✗ $case"
    done
fi

echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    green "All tests passed!"
    exit 0
else
    red "Some tests failed!"
    exit 1
fi