import { readFileSync } from 'fs'
import process from 'process'
import { resolve } from 'path';

async function read(stream) {
    const chunks = [];
    for await (const chunk of stream) chunks.push(chunk);
    return Buffer.concat(chunks).toString('utf8');
}
let input = await read(process.stdin)

let ptr = 0

let whitespace_regex = /^\s+/
let int_regex = /^-?\d+/

// 引用计数内存管理
// JavaScript 有自己的 GC，incref/decref 为空操作（保持 API 兼容）
const refCountMap = new Map();

let importObject = {
    minimbt_read_int: () => {
        // skip whitespace
        let ws_result = whitespace_regex.exec(input.slice(ptr))
        if (ws_result !== null) {
            ptr += ws_result[0].length
        }
        // Parse int
        let result = int_regex.exec(input.slice(ptr))
        if (result === null) {
            throw new Error('Invalid input')
        }
        ptr += result[0].length
        return parseInt(result[0])
    },
    minimbt_read_char: () => {
        return input[ptr++].charCodeAt(0)
    },
    minimbt_print_int: (value) => process.stdout.write(`${value}`),
    minimbt_print_char: (value) => process.stdout.write(String.fromCharCode(value)),
    minimbt_print_endline: () => process.stdout.write('\n'),
    minimbt_print_newline: () => process.stdout.write('\n'),
    minimbt_create_array: (size, initial) => {
        return new Array(size).fill(initial)
    },
    minimbt_create_float_array: (size, initial) => {
        return new Array(size).fill(initial)
    },
    minimbt_create_ptr_array: (size, initial) => {
        return new Array(size).fill(initial)
    },
    minimbt_int_of_float: (f) => Math.trunc(f),
    minimbt_float_of_int: (i) => i,
    minimbt_truncate: (f) => Math.trunc(f),
    minimbt_floor: (f) => Math.floor(f),
    minimbt_abs_float: (f) => Math.abs(f),
    minimbt_sqrt: (f) => Math.sqrt(f),
    minimbt_sin: (f) => Math.sin(f),
    minimbt_cos: (f) => Math.cos(f),
    minimbt_atan: (f) => Math.atan(f),

    // 引用计数 API（JavaScript GC 处理内存，这些函数为空操作）
    minimbt_alloc: (size) => {
        // 返回用户数据区域指针（JS 中为对象引用）
        return new ArrayBuffer(size + 4); // +4 用于 ref_count 头
    },
    minimbt_malloc: (size) => {
        return importObject.minimbt_alloc(size);
    },
    minimbt_incref: (ptr) => {
        if (ptr === null || ptr === undefined) return;
        // JS GC 自动管理，不需要显式 incref
        // 如果需要跟踪，可以更新 refCountMap
        let count = refCountMap.get(ptr) || 1;
        refCountMap.set(ptr, count + 1);
    },
    minimbt_decref: (ptr) => {
        if (ptr === null || ptr === undefined) return;
        // JS GC 自动管理，不需要显式 decref
        let count = refCountMap.get(ptr) || 1;
        if (count <= 1) {
            refCountMap.delete(ptr);
            // 在实际使用中，这里可以触发 GC
        } else {
            refCountMap.set(ptr, count - 1);
        }
    },
}

for (let k in importObject) {
    globalThis[k] = importObject[k]
}

let script = process.argv[2]
let script_abs = `file://${resolve(script)}`;
let mod = await import(script_abs)
if (mod.default) {
    mod.default();
} else {
    throw new Error('No default export found in the module');
}
