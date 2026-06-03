#include "sonata_cpu_ast_internal.h"
#include <emmintrin.h>
#include <math.h>

void sonata_eval_sse2(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error)
{
    __m128 sse = _mm_setzero_ps();
    int stride = n_vars;

    for (int row = 0; row < n_rows; row += 4) {
        int remaining = n_rows - row;
        int batch = remaining < 4 ? remaining : 4;

        __m128 stack[64];
        int sp = 0;

        for (int i = 0; i < ast_len; i++) {
            int op = opcodes[i];
            switch (op) {
                case AST_OP_ADD: {
                    __m128 b = stack[--sp]; __m128 a = stack[--sp];
                    stack[sp++] = _mm_add_ps(a, b); break;
                }
                case AST_OP_SUB: {
                    __m128 b = stack[--sp]; __m128 a = stack[--sp];
                    stack[sp++] = _mm_sub_ps(a, b); break;
                }
                case AST_OP_MUL: {
                    __m128 b = stack[--sp]; __m128 a = stack[--sp];
                    stack[sp++] = _mm_mul_ps(a, b); break;
                }
                case AST_OP_DIV: {
                    __m128 b = stack[--sp]; __m128 a = stack[--sp];
                    __m128 mask = _mm_cmpneq_ps(b, _mm_setzero_ps());
                    stack[sp++] = _mm_and_ps(_mm_div_ps(a, b), mask); break;
                }
                case AST_OP_SIN:
                case AST_OP_COS:
                case AST_OP_EXP:
                case AST_OP_LOG:
                case AST_OP_SQRT: {
                    float vals[4];
                    _mm_storeu_ps(vals, stack[sp - 1]);
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
                    stack[sp - 1] = _mm_loadu_ps(vals); break;
                }
                case AST_OP_NEG: {
                    stack[sp - 1] = _mm_sub_ps(_mm_setzero_ps(), stack[sp - 1]); break;
                }
                case AST_OP_VAR: {
                    int vi = (int)args[i];
                    float v[4] = {0};
                    for (int j = 0; j < batch; j++)
                        v[j] = data[(row + j) * stride + vi];
                    stack[sp++] = _mm_loadu_ps(v); break;
                }
                case AST_OP_CONST: {
                    stack[sp++] = _mm_set1_ps(args[i]); break;
                }
            }
        }

        float t[4] = {0};
        for (int j = 0; j < batch; j++)
            t[j] = data[(row + j) * stride + (n_vars - 1)];
        __m128 target_v = _mm_loadu_ps(t);
        __m128 diff = _mm_sub_ps(stack[0], target_v);
        sse = _mm_add_ps(sse, _mm_mul_ps(diff, diff));
    }

    float tmp[4];
    _mm_storeu_ps(tmp, sse);
    *out_error = tmp[0] + tmp[1] + tmp[2] + tmp[3];
}
