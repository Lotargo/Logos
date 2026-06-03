#include "sonata_cuda.h"

extern "C" {

EXPORT bool sonata_cuda_matmul(const float* A, const float* B, float* C, int M, int N, int P, void* stream = nullptr) {
    if (g_cublasHandle == nullptr) {
        cudaSetDevice(0);
        cudaFree(0);
        cublasStatus_t status = cublasCreate(&g_cublasHandle);
        if (status != CUBLAS_STATUS_SUCCESS) {
            std::cerr << "[cuBLAS Error] Lazy initialization failed: " << status << std::endl;
            return false;
        }
        cublasSetMathMode(g_cublasHandle, CUBLAS_TENSOR_OP_MATH);
    }

    cudaStream_t s = (cudaStream_t)stream;
    cublasSetStream(g_cublasHandle, s);

    const float alpha = 1.0f;
    const float beta = 0.0f;

    cublasStatus_t status = cublasSgemm(
        g_cublasHandle,
        CUBLAS_OP_N, CUBLAS_OP_N,
        P, M, N,
        &alpha,
        B, P,
        A, N,
        &beta,
        C, P
    );

    if (status != CUBLAS_STATUS_SUCCESS) {
        std::cerr << "[cuBLAS Error] cublasSgemm failed: " << status << std::endl;
        return false;
    }

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
    return true;
}

EXPORT bool sonata_cuda_matmul_fp16(const void* A, const void* B, void* C, int M, int N, int P, void* stream = nullptr) {
    if (g_cublasHandle == nullptr) {
        cudaSetDevice(0);
        cudaFree(0);
        cublasStatus_t status = cublasCreate(&g_cublasHandle);
        if (status != CUBLAS_STATUS_SUCCESS) {
            std::cerr << "[cuBLAS Error] Lazy initialization failed: " << status << std::endl;
            return false;
        }
        cublasSetMathMode(g_cublasHandle, CUBLAS_TENSOR_OP_MATH);
    }

    cudaStream_t s = (cudaStream_t)stream;
    cublasSetStream(g_cublasHandle, s);

    __half alpha = __float2half(1.0f);
    __half beta = __float2half(0.0f);

    cublasStatus_t status = cublasHgemm(
        g_cublasHandle,
        CUBLAS_OP_N, CUBLAS_OP_N,
        P, M, N,
        &alpha,
        (const __half*)B, P,
        (const __half*)A, N,
        &beta,
        (__half*)C, P
    );

    if (status != CUBLAS_STATUS_SUCCESS) {
        std::cerr << "[cuBLAS Error] cublasHgemm failed: " << status << std::endl;
        return false;
    }

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
    return true;
}

EXPORT bool sonata_cuda_matmul_backward_fp16(
    void* dA,          // FP16 dL/dA output (M x N)
    void* dB,          // FP16 dL/dB output (N x P)
    const void* dC,    // FP16 dL/dC upstream gradient (M x P)
    const void* A,     // FP16 activations (M x N)
    const void* B,     // FP16 weights (N x P)
    int M, int N, int P,
    void* stream = nullptr)
{
    if (g_cublasHandle == nullptr) {
        cudaSetDevice(0);
        cudaFree(0);
        cublasStatus_t status = cublasCreate(&g_cublasHandle);
        if (status != CUBLAS_STATUS_SUCCESS) return false;
        cublasSetMathMode(g_cublasHandle, CUBLAS_TENSOR_OP_MATH);
    }

    cudaStream_t stream_id = stream ? (cudaStream_t)stream : 0;
    cublasSetStream(g_cublasHandle, stream_id);

    const half alpha = __float2half(1.0f);
    const half beta = __float2half(1.0f); // Accumulate gradients directly into dA and dB

    cublasStatus_t status = CUBLAS_STATUS_SUCCESS;

    // dA = dC * B^T  (M x N) = (M x P) * (N x P)^T
    // Column-major: dA (N x M) = B^T (N x P) * dC (P x M)
    if (dA != nullptr) {
        status = cublasHgemm(
            g_cublasHandle,
            CUBLAS_OP_T, CUBLAS_OP_N,
            N, M, P,
            &alpha,
            (const __half*)B, P,
            (const __half*)dC, P,
            &beta,
            (__half*)dA, N);
        if (status != CUBLAS_STATUS_SUCCESS) return false;
    }

    // dB = A^T * dC  (N x P) = (M x N)^T * (M x P)
    // Column-major: dB (P x N) = dC (P x M) * A^T (M x N)
    if (dB != nullptr) {
        status = cublasHgemm(
            g_cublasHandle,
            CUBLAS_OP_N, CUBLAS_OP_T,
            P, N, M,
            &alpha,
            (const __half*)dC, P,
            (const __half*)A, N,
            &beta,
            (__half*)dB, P);
        if (status != CUBLAS_STATUS_SUCCESS) return false;
    }

    if (stream_id == nullptr) {
        cudaDeviceSynchronize();
    }

    return true;
}

}
