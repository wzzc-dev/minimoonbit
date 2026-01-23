import { readFileSync } from 'fs'
import process from 'process'

let memory = new WebAssembly.Memory({ initial: 10, maximum: 1000 })

async function read(stream) {
    const chunks = [];
    for await (const chunk of stream) chunks.push(chunk);
    return Buffer.concat(chunks).toString('utf8');
}
let input = await read(process.stdin)

let ptr = 0

let offset = 0

let whitespace_regex = /^\s+/
let int_regex = /^-?\d+/

// 引用计数管理（用于堆分配的对象）
// 内存布局: [ref_count: u32][用户数据...]
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

    // 引用计数内存分配
    minimbt_alloc: (size) => {
        // 分配: ref_count(4 bytes) + 用户数据
        let total_size = size + 4;
        if (memory.buffer.byteLength < offset + total_size) {
            memory.grow(Math.ceil((offset + total_size - memory.buffer.byteLength) / 65536) + 1);
        }
        let data_ptr = offset + 4; // 用户数据区域
        // 初始化 ref_count = 1
        let view = new Uint32Array(memory.buffer, offset, 1);
        view[0] = 1;
        offset += total_size;
        return data_ptr;
    },
    minimbt_malloc: (size) => {
        // 兼容旧接口
        return importObject.minimbt_alloc(size);
    },

    // 增加引用计数
    minimbt_incref: (data_ptr) => {
        if (data_ptr === 0) return;
        let ref_count_ptr = data_ptr - 4;
        let view = new Uint32Array(memory.buffer, ref_count_ptr, 1);
        view[0] += 1;
    },

    // 减少引用计数，如果为 0 则释放
    minimbt_decref: (data_ptr) => {
        if (data_ptr === 0) return;
        let ref_count_ptr = data_ptr - 4;
        let view = new Uint32Array(memory.buffer, ref_count_ptr, 1);
        let new_count = view[0] - 1;
        if (new_count === 0) {
            // 引用计数为 0，标记为已释放（在实际实现中可能需要更复杂的内存管理）
            view[0] = 0;
            // 注意：简单实现中我们不回收内存，只标记
            // 更完整的实现需要维护空闲列表
        } else {
            view[0] = new_count;
        }
    },

    minimbt_create_array: (size, initial) => {
        if (offset % 4 != 0) {
            offset = Math.ceil(offset / 4) * 4
        }
        while (memory.buffer.byteLength < offset + size * 4) {
            memory.grow(1)
        }
        let view = new Int32Array(memory.buffer, offset, size);
        view.fill(initial)
        let ptr = offset
        offset += size * 4
        return ptr;
    },
    minimbt_create_float_array: (size, initial) => {
        if (offset % 8 != 0) {
            offset = Math.ceil(offset / 8) * 8
        }
        while (memory.buffer.byteLength < offset + size * 8) {
            memory.grow(1)
        }
        let view = new Float64Array(memory.buffer, offset, size);
        view.fill(initial)
        let ptr = offset
        offset += size * 8
        return ptr;
    },
    minimbt_create_ptr_array: (size, initial) => {
        if (offset % 4 != 0) {
            offset = Math.ceil(offset / 4) * 4
        }
        while (memory.buffer.byteLength < offset + size * 4) {
            memory.grow(1)
        }
        let view = new Uint32Array(memory.buffer, offset, size);
        view.fill(initial >>> 0)
        let ptr = offset
        offset += size * 4
        return ptr;
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
    memory
}

let wasm_name = process.argv[2]
let wasm_code = readFileSync(wasm_name)
// User code in start section, so no need to run the main function
let _instance = await WebAssembly.instantiate(wasm_code, { moonbit: importObject })
