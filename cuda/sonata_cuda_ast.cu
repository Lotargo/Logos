#include "sonata_cuda.h"

// =========================================================================
// AST Evaluation Kernel for Symbolic Regression
// Flattened postfix (RPN) AST interpreter on GPU
// One thread per data row, stack-based evaluation, block-level MSE reduction
// =========================================================================
//
// AST encoding (postfix/RPN):
//   opcodes[]  — sequence of OP_* values
//   args[]     — for OP_VAR: variable index as float; for OP_CONST: value
//
// Example: AST (mul (add v0 v1) 5.0)  →  postfix: v0 v1 add 5.0 mul
//   opcodes = {OP_VAR, OP_VAR, OP_ADD, OP_CONST, OP_MUL}
//   args    = {0.0f,   1.0f,   0.0f,   5.0f,     0.0f}
//
// Data layout:
//   data[n_rows * n_vars] — row-major, last column = target value
//   out_error[1]          — scalar: sum of squared errors (MSE * n_rows)

#define OP_ADD    1
#define OP_SUB    2
#define OP_MUL    3
#define OP_DIV    4
#define OP_SIN    5
#define OP_COS    6
#define OP_EXP    7
#define OP_LOG    8
#define OP_SQRT   9
#define OP_NEG    10
#define OP_VAR    11
#define OP_CONST  12

__global__ void eval_ast_sse_kernel(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error)
{
    __shared__ float block_errors[256];

    int row = blockIdx.x * blockDim.x + threadIdx.x;
    float row_error = 0.0f;

    if (row < n_rows) {
        float stack[32];
        int sp = 0;

        for (int i = 0; i < ast_len; i++) {
            int op = opcodes[i];
            switch (op) {
                case OP_ADD: {
                    float b = stack[--sp];
                    float a = stack[--sp];
                    stack[sp++] = a + b;
                    break;
                }
                case OP_SUB: {
                    float b = stack[--sp];
                    float a = stack[--sp];
                    stack[sp++] = a - b;
                    break;
                }
                case OP_MUL: {
                    float b = stack[--sp];
                    float a = stack[--sp];
                    stack[sp++] = a * b;
                    break;
                }
                case OP_DIV: {
                    float b = stack[--sp];
                    float a = stack[--sp];
                    stack[sp++] = (b != 0.0f) ? a / b : 0.0f;
                    break;
                }
                case OP_SIN: {
                    stack[sp - 1] = sinf(stack[sp - 1]);
                    break;
                }
                case OP_COS: {
                    stack[sp - 1] = cosf(stack[sp - 1]);
                    break;
                }
                case OP_EXP: {
                    stack[sp - 1] = expf(stack[sp - 1]);
                    break;
                }
                case OP_LOG: {
                    float v = stack[sp - 1];
                    stack[sp - 1] = (v > 0.0f) ? logf(v) : 0.0f;
                    break;
                }
                case OP_SQRT: {
                    float v = stack[sp - 1];
                    stack[sp - 1] = (v >= 0.0f) ? sqrtf(v) : 0.0f;
                    break;
                }
                case OP_NEG: {
                    stack[sp - 1] = -stack[sp - 1];
                    break;
                }
                case OP_VAR: {
                    int var_idx = (int)args[i];
                    stack[sp++] = data[row * n_vars + var_idx];
                    break;
                }
                case OP_CONST: {
                    stack[sp++] = args[i];
                    break;
                }
            }
        }

        float target = data[row * n_vars + (n_vars - 1)];
        float diff = stack[0] - target;
        row_error = diff * diff;
    }

    block_errors[threadIdx.x] = row_error;
    __syncthreads();

    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (threadIdx.x < s) {
            block_errors[threadIdx.x] += block_errors[threadIdx.x + s];
        }
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        atomicAdd(out_error, block_errors[0]);
    }
}

// =========================================================================
// Batch AST eval: evaluate same AST against multiple datasets
// Each dataset block gets its own MSE output
// =========================================================================

__global__ void eval_ast_sse_batch_kernel(
    const float* data, int n_datasets, int n_rows_per_ds, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_errors)
{
    extern __shared__ float block_errors[];
    int ds = blockIdx.y;
    int row = blockIdx.x * blockDim.x + threadIdx.x;
    float row_error = 0.0f;

    if (ds < n_datasets && row < n_rows_per_ds) {
        int base = ds * n_rows_per_ds * n_vars + row * n_vars;
        float stack[32];
        int sp = 0;

        for (int i = 0; i < ast_len; i++) {
            int op = opcodes[i];
            switch (op) {
                case OP_ADD: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = a + b; break; }
                case OP_SUB: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = a - b; break; }
                case OP_MUL: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = a * b; break; }
                case OP_DIV: { float b = stack[--sp]; float a = stack[--sp]; stack[sp++] = (b != 0.0f) ? a / b : 0.0f; break; }
                case OP_SIN: { stack[sp - 1] = sinf(stack[sp - 1]); break; }
                case OP_COS: { stack[sp - 1] = cosf(stack[sp - 1]); break; }
                case OP_EXP: { stack[sp - 1] = expf(stack[sp - 1]); break; }
                case OP_LOG: { float v = stack[sp - 1]; stack[sp - 1] = (v > 0.0f) ? logf(v) : 0.0f; break; }
                case OP_SQRT: { float v = stack[sp - 1]; stack[sp - 1] = (v >= 0.0f) ? sqrtf(v) : 0.0f; break; }
                case OP_NEG: { stack[sp - 1] = -stack[sp - 1]; break; }
                case OP_VAR: { int idx = (int)args[i]; stack[sp++] = data[base + idx]; break; }
                case OP_CONST: { stack[sp++] = args[i]; break; }
            }
        }

        float target = data[base + n_vars - 1];
        float diff = stack[0] - target;
        row_error = diff * diff;
    }

    block_errors[threadIdx.x] = row_error;
    __syncthreads();

    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (threadIdx.x < s) {
            block_errors[threadIdx.x] += block_errors[threadIdx.x + s];
        }
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        atomicAdd(&out_errors[ds], block_errors[0]);
    }
}

extern "C" {

// Evaluate AST on one dataset, return SSE (sum of squared errors)
EXPORT void sonata_cuda_eval_ast_sse(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error, void* stream)
{
    if (data == nullptr || opcodes == nullptr || args == nullptr ||
        out_error == nullptr || n_rows <= 0 || n_vars <= 1 || ast_len <= 0)
        return;

    cudaStream_t s = (cudaStream_t)stream;

    cudaMemsetAsync(out_error, 0, sizeof(float), s);

    int block_size = 256;
    int grid_size = (n_rows + block_size - 1) / block_size;

    eval_ast_sse_kernel<<<grid_size, block_size, 0, s>>>(
        data, n_rows, n_vars, opcodes, args, ast_len, out_error);

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

// Same AST evaluated against multiple independent datasets (batched)
EXPORT void sonata_cuda_eval_ast_sse_batch(
    const float* data, int n_datasets, int n_rows_per_ds, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_errors, void* stream)
{
    if (data == nullptr || opcodes == nullptr || args == nullptr ||
        out_errors == nullptr || n_datasets <= 0 || n_rows_per_ds <= 0 ||
        n_vars <= 1 || ast_len <= 0)
        return;

    cudaStream_t s = (cudaStream_t)stream;

    cudaMemsetAsync(out_errors, 0, n_datasets * sizeof(float), s);

    int block_size = 256;
    dim3 grid_size((n_rows_per_ds + block_size - 1) / block_size, n_datasets);
    size_t shared_mem = block_size * sizeof(float);

    eval_ast_sse_batch_kernel<<<grid_size, block_size, shared_mem, s>>>(
        data, n_datasets, n_rows_per_ds, n_vars, opcodes, args, ast_len, out_errors);

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
