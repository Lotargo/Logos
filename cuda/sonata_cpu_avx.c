#include "sonata_cpu_ast_internal.h"
#include <immintrin.h>
#include <math.h>

void sonata_eval_avx(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error)
{
    __m256 sse = _mm256_setzero_ps();
    int stride = n_vars;

    for (int row = 0; row < n_rows; row += 8) {
        int remaining = n_rows - row;
        int batch = remaining < 8 ? remaining : 8;

        __m256 stack[64];
        int sp = 0;

        for (int i = 0; i < ast_len; i++) {
            int op = opcodes[i];
            switch (op) {
                case AST_OP_ADD: {
                    __m256 b = stack[--sp]; __m256 a = stack[--sp];
                    stack[sp++] = _mm256_add_ps(a, b); break;
                }
                case AST_OP_SUB: {
                    __m256 b = stack[--sp]; __m256 a = stack[--sp];
                    stack[sp++] = _mm256_sub_ps(a, b); break;
                }
                case AST_OP_MUL: {
                    __m256 b = stack[--sp]; __m256 a = stack[--sp];
                    stack[sp++] = _mm256_mul_ps(a, b); break;
                }
                case AST_OP_DIV: {
                    __m256 b = stack[--sp]; __m256 a = stack[--sp];
                    __m256 mask = _mm256_cmp_ps(b, _mm256_setzero_ps(), _CMP_NEQ_OQ);
                    stack[sp++] = _mm256_and_ps(_mm256_div_ps(a, b), mask); break;
                }
                case AST_OP_SIN:
                case AST_OP_COS:
                case AST_OP_EXP:
                case AST_OP_LOG:
                case AST_OP_SQRT: {
                    float vals[8];
                    _mm256_storeu_ps(vals, stack[sp - 1]);
                    for (int j = 0; j < batch; j++) {
                        float v = vals[j];
                        switch (op) {
                            case AST_OP_SIN:  v = sinf(v); break;
                            case AST_OP_COS:  v = cosf(v); break;
                            case AST_OP_EXP:  v = expf(v); break;
                            case AST_OP_LOG:  v = (v > 0.0f) ? logf(v) : 0.0f; break;
                            case AST_OP_SQRT: v = (v >= 0.0f) ? sqrtf(v) : 0.0f; break;
                        }
                        vals[j] = v;
                    }
                    stack[sp - 1] = _mm256_loadu_ps(vals); break;
                }
                case AST_OP_NEG: {
                    stack[sp - 1] = _mm256_sub_ps(_mm256_setzero_ps(), stack[sp - 1]); break;
                }
                case AST_OP_VAR: {
                    int vi = (int)args[i];
                    float v[8] = {0};
                    for (int j = 0; j < batch; j++)
                        v[j] = data[(row + j) * stride + vi];
                    stack[sp++] = _mm256_loadu_ps(v); break;
                }
                case AST_OP_CONST: {
                    stack[sp++] = _mm256_set1_ps(args[i]); break;
                }
            }
        }

        float t[8] = {0};
        for (int j = 0; j < batch; j++)
            t[j] = data[(row + j) * stride + (n_vars - 1)];
        __m256 target_v = _mm256_loadu_ps(t);

        __m256 diff = _mm256_sub_ps(stack[0], target_v);
        sse = _mm256_add_ps(sse, _mm256_mul_ps(diff, diff));
    }

    float tmp[8];
    _mm256_storeu_ps(tmp, sse);
    *out_error = tmp[0] + tmp[1] + tmp[2] + tmp[3]
               + tmp[4] + tmp[5] + tmp[6] + tmp[7];
}
