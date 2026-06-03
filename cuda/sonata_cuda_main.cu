#include "sonata_cuda.h"

cublasHandle_t g_cublasHandle = nullptr;
CachingAllocator g_allocator;

extern "C" {

EXPORT bool sonata_cuda_init() {
    cudaError_t err = cudaSetDevice(0);
    if (err != cudaSuccess) {
        std::cerr << "[CUDA Error] Failed to set device: " << cudaGetErrorString(err) << std::endl;
        return false;
    }

    cublasStatus_t status = cublasCreate(&g_cublasHandle);
    if (status != CUBLAS_STATUS_SUCCESS) {
        std::cerr << "[cuBLAS Error] Failed to create handle." << std::endl;
        return false;
    }

    // Configure cuBLAS to utilize Tensor Cores when possible
    cublasSetMathMode(g_cublasHandle, CUBLAS_TENSOR_OP_MATH);

    return true;
}

EXPORT void sonata_cuda_free_resources() {
    g_allocator.releaseAll();
    if (g_cublasHandle != nullptr) {
        cublasDestroy(g_cublasHandle);
        g_cublasHandle = nullptr;
    }
}

EXPORT void* sonata_cuda_stream_create() {
    cudaStream_t stream = nullptr;
    cudaError_t err = cudaStreamCreate(&stream);
    if (err != cudaSuccess) {
        std::cerr << "[CUDA Error] cudaStreamCreate failed: " << cudaGetErrorString(err) << std::endl;
        return nullptr;
    }
    return (void*)stream;
}

EXPORT void sonata_cuda_stream_destroy(void* stream) {
    if (stream != nullptr) {
        cudaError_t err = cudaStreamDestroy((cudaStream_t)stream);
        if (err != cudaSuccess) {
            std::cerr << "[CUDA Error] cudaStreamDestroy failed: " << cudaGetErrorString(err) << std::endl;
        }
    }
}

EXPORT void sonata_cuda_stream_synchronize(void* stream) {
    if (stream != nullptr) {
        cudaError_t err = cudaStreamSynchronize((cudaStream_t)stream);
        if (err != cudaSuccess) {
            std::cerr << "[CUDA Error] cudaStreamSynchronize failed: " << cudaGetErrorString(err) << std::endl;
        }
    } else {
        cudaError_t err = sonata_cuda_real_synchronize_default_stream();
        if (err != cudaSuccess) {
            std::cerr << "[CUDA Error] cudaStreamSynchronize(default) failed: " << cudaGetErrorString(err) << std::endl;
        }
    }
}

EXPORT int sonata_cuda_get_last_error_code(int clear_error) {
    cudaError_t err = clear_error ? cudaGetLastError() : cudaPeekAtLastError();
    return (int)err;
}

}
