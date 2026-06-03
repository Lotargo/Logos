#pragma once
#include "sonata_cpu_ast.h"
// Internal: each SIMD level implements this eval function.
// Compiled separately with the appropriate arch flag.
// All: data[n_rows * n_vars] row-major, last column = target.
void sonata_eval_scalar(const float* data, int n_rows, int n_vars,
                        const int* opcodes, const float* args, int ast_len,
                        float* out_error);

void sonata_eval_sse2(const float* data, int n_rows, int n_vars,
                      const int* opcodes, const float* args, int ast_len,
                      float* out_error);

void sonata_eval_avx(const float* data, int n_rows, int n_vars,
                     const int* opcodes, const float* args, int ast_len,
                     float* out_error);

void sonata_eval_avx2(const float* data, int n_rows, int n_vars,
                      const int* opcodes, const float* args, int ast_len,
                      float* out_error);
