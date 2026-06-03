#include "sonata_cuda.h"

__global__ void cuda_quantize_int8_row_kernel(const float* data, int8_t* data_q, float* scales, int rows, int cols) {
    int row = blockIdx.x * blockDim.x + threadIdx.x;
    if (row < rows) {
        float max_val = 1e-7f;
        for (int col = 0; col < cols; ++col) {
            float val = fabsf(data[row * cols + col]);
            if (val > max_val) {
                max_val = val;
            }
        }
        float scale = max_val / 127.0f;
        scales[row] = scale;

        float inv_scale = (scale > 0.0f) ? (1.0f / scale) : 0.0f;
        for (int col = 0; col < cols; ++col) {
            float val = data[row * cols + col];
            int qval = __float2int_rn(val * inv_scale);
            if (qval > 127) qval = 127;
            if (qval < -128) qval = -128;
            data_q[row * cols + col] = (int8_t)qval;
        }
    }
}

__global__ void cuda_quantize_int8_col_kernel(const float* weight, int8_t* weight_q, float* scales, int rows, int cols) {
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (col < cols) {
        float max_val = 1e-7f;
        for (int row = 0; row < rows; ++row) {
            float val = fabsf(weight[row * cols + col]);
            if (val > max_val) {
                max_val = val;
            }
        }
        float scale = max_val / 127.0f;
        scales[col] = scale;

        float inv_scale = (scale > 0.0f) ? (1.0f / scale) : 0.0f;
        for (int row = 0; row < rows; ++row) {
            float val = weight[row * cols + col];
            int qval = __float2int_rn(val * inv_scale);
            if (qval > 127) qval = 127;
            if (qval < -128) qval = -128;
            weight_q[row * cols + col] = (int8_t)qval;
        }
    }
}

__global__ void cuda_dequantize_output_kernel(float* C_float, const int32_t* C_int, const float* ScalesA, const float* ScalesB, int M, int P) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int size = M * P;
    if (idx < size) {
        int r = idx / P;
        int c = idx % P;
        C_float[idx] = (float)C_int[idx] * ScalesA[r] * ScalesB[c];
    }
}

extern "C" {

EXPORT void sonata_cuda_quantize_int8(const float* data, int8_t* data_q, float* scales, int rows, int cols) {
    if (data == nullptr || data_q == nullptr || scales == nullptr || rows <= 0 || cols <= 0) return;

    int threads = 256;
    int blocks = (rows + threads - 1) / threads;

    cuda_quantize_int8_row_kernel<<<blocks, threads>>>(data, data_q, scales, rows, cols);
    cudaDeviceSynchronize();
}

EXPORT void sonata_cuda_quantize_int8_col(const float* weight, int8_t* weight_q, float* scales, int rows, int cols) {
    if (weight == nullptr || weight_q == nullptr || scales == nullptr || rows <= 0 || cols <= 0) return;

    int threads = 256;
    int blocks = (cols + threads - 1) / threads;

    cuda_quantize_int8_col_kernel<<<blocks, threads>>>(weight, weight_q, scales, rows, cols);
    cudaDeviceSynchronize();
}

EXPORT bool sonata_cuda_matmul_int8(const int8_t* A, const int8_t* B, float* C, int M, int N, int P, const float* ScalesA, const float* ScalesB, void* stream = nullptr) {
    if (g_cublasHandle == nullptr) {
        return false;
    }

    // cuBLAS INT8 GEMM requires m, n, k and leading dimensions to be multiples of 4.
    if ((M % 4 != 0) || (N % 4 != 0) || (P % 4 != 0)) {
        return false;
    }

    cudaStream_t s = (cudaStream_t)stream;
    cublasSetStream(g_cublasHandle, s);

    int32_t alpha = 1;
    int32_t beta = 0;

    int32_t* temp_C = (int32_t*)g_allocator.allocate(M * P * sizeof(int32_t));
    if (temp_C == nullptr) {
        return false;
    }

    cublasStatus_t status = cublasGemmEx(
        g_cublasHandle,
        CUBLAS_OP_N, CUBLAS_OP_N,
        P, M, N,
        &alpha,
        B, CUDA_R_8I, P,
        A, CUDA_R_8I, N,
        &beta,
        temp_C, CUDA_R_32I, P,
        CUBLAS_COMPUTE_32I,
        CUBLAS_GEMM_DEFAULT_TENSOR_OP
    );

    if (status != CUBLAS_STATUS_SUCCESS) {
        g_allocator.free(temp_C);
        return false;
    }

    int size = M * P;
    int threads = 256;
    int blocks = (size + threads - 1) / threads;
    cuda_dequantize_output_kernel<<<blocks, threads, 0, s>>>(C, temp_C, ScalesA, ScalesB, M, P);

    if (s != nullptr) {
        cudaStreamSynchronize(s);
    } else {
        cudaDeviceSynchronize();
    }
    
    g_allocator.free(temp_C);
    return true;
}

}
