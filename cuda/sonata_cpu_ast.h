#pragma once
#include <stdint.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

#define AST_OP_ADD    1
#define AST_OP_SUB    2
#define AST_OP_MUL    3
#define AST_OP_DIV    4
#define AST_OP_SIN    5
#define AST_OP_COS    6
#define AST_OP_EXP    7
#define AST_OP_LOG    8
#define AST_OP_SQRT   9
#define AST_OP_NEG    10
#define AST_OP_VAR    11
#define AST_OP_CONST  12

// CPU SIMD-accelerated AST eval. Selects best available SIMD (AVX2 > SSE2 > scalar).
// Returns 0 on success, -1 if SIMD feature unavailable at runtime.
EXPORT int sonata_cpu_eval_ast_sse(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error);

// Batch: same AST against multiple independent datasets.
EXPORT int sonata_cpu_eval_ast_sse_batch(
    const float* data, int n_datasets, int n_rows_per_ds, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_errors);

// SIMD level constants
#define SIMD_LEVEL_SCALAR  0
#define SIMD_LEVEL_SSE2    1
#define SIMD_LEVEL_AVX     2
#define SIMD_LEVEL_AVX2    3

// Query available SIMD level: 0=scalar, 1=SSE2, 2=AVX, 3=AVX2
EXPORT int sonata_cpu_simd_level(void);

// Force SIMD level (0=scalar, 1=SSE2, 2=AVX, 3=AVX2). -1 = auto. Returns 0 on success.
EXPORT int sonata_cpu_force_simd_level(int level);
