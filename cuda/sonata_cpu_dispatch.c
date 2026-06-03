#include "sonata_cpu_ast.h"
#include "sonata_cpu_ast_internal.h"
#include <math.h>

// =========================================================================
// Runtime SIMD level detection
// =========================================================================
#if defined(_MSC_VER)
#include <intrin.h>
#endif

static int g_forced_level = -1;  // -1 = auto
static int g_max_level = 0;      // detected at first call

static int cpu_has_feature(int leaf, int reg, int bit) {
    int info[4] = {0};
#if defined(_MSC_VER)
    __cpuidex(info, leaf, 0);
#else
    __cpuid_count(leaf, 0, info[0], info[1], info[2], info[3]);
#endif
    switch (reg) {
        case 0: return (info[0] >> bit) & 1; // EAX
        case 1: return (info[1] >> bit) & 1; // EBX
        case 2: return (info[2] >> bit) & 1; // ECX
        case 3: return (info[3] >> bit) & 1; // EDX
        default: return 0;
    }
}

static int cpu_has_osxsave(void) {
    return cpu_has_feature(1, 2, 27);
}

static int cpu_xsave_ymm_enabled(void) {
    if (!cpu_has_osxsave()) return 0;
    unsigned long long xcr0 = _xgetbv(0);
    return ((xcr0 >> 1) & 1) && ((xcr0 >> 2) & 1);
}

static void detect_max_level(void) {
    if (g_max_level > 0) return;

    // Level 3: AVX2 (leaf 7, EBX bit 5) + OS XSAVE YMM
    if (cpu_has_feature(7, 1, 5) && cpu_xsave_ymm_enabled()) {
        g_max_level = 3;
        return;
    }

    // Level 2: AVX (leaf 1, ECX bit 28) + OS XSAVE YMM
    if (cpu_has_feature(1, 2, 28) && cpu_xsave_ymm_enabled()) {
        g_max_level = 2;
        return;
    }

    // Level 1: SSE2 (always on x64)
    g_max_level = 1;
}

int select_level(void) {
    if (g_forced_level >= 0)
        return g_forced_level;
    if (g_max_level == 0)
        detect_max_level();
    return g_max_level;
}

// =========================================================================
// Scalar implementation (level 0, always available)
// =========================================================================
void sonata_eval_scalar(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error)
{
    double sse = 0.0;

    for (int row = 0; row < n_rows; row++) {
        float stack[64];
        int sp = 0;

        for (int i = 0; i < ast_len; i++) {
            int op = opcodes[i];
            switch (op) {
                case AST_OP_ADD: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = a + b; break; }
                case AST_OP_SUB: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = a - b; break; }
                case AST_OP_MUL: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = a * b; break; }
                case AST_OP_DIV: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = (b != 0.0f) ? a / b : 0.0f; break; }
                case AST_OP_SIN: { stack[sp - 1] = sinf(stack[sp - 1]); break; }
                case AST_OP_COS: { stack[sp - 1] = cosf(stack[sp - 1]); break; }
                case AST_OP_EXP: { stack[sp - 1] = expf(stack[sp - 1]); break; }
                case AST_OP_LOG: { float v = stack[sp - 1]; stack[sp - 1] = (v > 0.0f) ? logf(v) : 0.0f; break; }
                case AST_OP_SQRT: { float v = stack[sp - 1]; stack[sp - 1] = (v >= 0.0f) ? sqrtf(v) : 0.0f; break; }
                case AST_OP_NEG: { stack[sp - 1] = -stack[sp - 1]; break; }
                case AST_OP_VAR: { stack[sp++] = data[row * n_vars + (int)args[i]]; break; }
                case AST_OP_CONST: { stack[sp++] = args[i]; break; }
            }
        }

        float target = data[row * n_vars + (n_vars - 1)];
        float diff = stack[0] - target;
        sse += (double)diff * (double)diff;
    }

    *out_error = (float)sse;
}

// =========================================================================
// Public API
// =========================================================================
int sonata_cpu_eval_ast_sse(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error)
{
    if (!data || !opcodes || !args || !out_error || n_rows <= 0 || n_vars <= 1 || ast_len <= 0)
        return -1;

    int level = select_level();

    switch (level) {
        case 3: sonata_eval_avx2(data, n_rows, n_vars, opcodes, args, ast_len, out_error); break;
        case 2: sonata_eval_avx(data, n_rows, n_vars, opcodes, args, ast_len, out_error); break;
        case 1: sonata_eval_sse2(data, n_rows, n_vars, opcodes, args, ast_len, out_error); break;
        default: sonata_eval_scalar(data, n_rows, n_vars, opcodes, args, ast_len, out_error); break;
    }
    return 0;
}

int sonata_cpu_eval_ast_sse_batch(
    const float* data, int n_datasets, int n_rows_per_ds, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_errors)
{
    if (!data || !opcodes || !args || !out_errors ||
        n_datasets <= 0 || n_rows_per_ds <= 0 || n_vars <= 1 || ast_len <= 0)
        return -1;

    for (int ds = 0; ds < n_datasets; ds++) {
        int ret = sonata_cpu_eval_ast_sse(
            data + ds * n_rows_per_ds * n_vars,
            n_rows_per_ds, n_vars,
            opcodes, args, ast_len, &out_errors[ds]);
        if (ret != 0) return ret;
    }
    return 0;
}

int sonata_cpu_simd_level(void) {
    detect_max_level();
    return select_level();
}

int sonata_cpu_force_simd_level(int level) {
    if (level < -1 || level > 3)
        return -1;
    g_forced_level = level;
    return 0;
}
