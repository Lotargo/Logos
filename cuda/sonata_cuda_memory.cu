#include "sonata_cuda.h"

extern "C" {

EXPORT void* sonata_cuda_alloc(size_t size) {
    return g_allocator.allocate(size);
}

EXPORT void sonata_cuda_free_mem(void* ptr) {
    g_allocator.free(ptr);
}

EXPORT bool sonata_cuda_memcpy_h2d(void* dst, const void* src, size_t size) {
    cudaError_t err = cudaMemcpy(dst, src, size, cudaMemcpyHostToDevice);
    return err == cudaSuccess;
}

EXPORT bool sonata_cuda_memcpy_d2h(void* dst, const void* src, size_t size) {
    cudaError_t err = cudaMemcpy(dst, src, size, cudaMemcpyDeviceToHost);
    return err == cudaSuccess;
}

EXPORT bool sonata_cuda_memcpy_d2d(void* dst, const void* src, size_t size, void* stream = nullptr) {
    cudaError_t err;
    cudaStream_t s = (cudaStream_t)stream;
    if (s != nullptr) {
        err = cudaMemcpyAsync(dst, src, size, cudaMemcpyDeviceToDevice, s);
    } else {
        err = cudaMemcpy(dst, src, size, cudaMemcpyDeviceToDevice);
    }
    return err == cudaSuccess;
}

EXPORT bool sonata_cuda_memcpy_h2d_async(void* dst, const void* src, size_t size, void* stream = nullptr) {
    cudaError_t err;
    cudaStream_t s = (cudaStream_t)stream;
    if (s != nullptr) {
        err = cudaMemcpyAsync(dst, src, size, cudaMemcpyHostToDevice, s);
    } else {
        err = cudaMemcpy(dst, src, size, cudaMemcpyHostToDevice);
    }
    return err == cudaSuccess;
}

EXPORT bool sonata_cuda_memcpy_d2h_async(void* dst, const void* src, size_t size, void* stream = nullptr) {
    cudaError_t err;
    cudaStream_t s = (cudaStream_t)stream;
    if (s != nullptr) {
        err = cudaMemcpyAsync(dst, src, size, cudaMemcpyDeviceToHost, s);
    } else {
        err = cudaMemcpy(dst, src, size, cudaMemcpyDeviceToHost);
    }
    return err == cudaSuccess;
}

EXPORT bool sonata_cuda_malloc_host(void** ptr, size_t size) {
    cudaError_t err = cudaMallocHost(ptr, size);
    return err == cudaSuccess;
}

EXPORT void sonata_cuda_free_host(void* ptr) {
    cudaFreeHost(ptr);
}

EXPORT void sonata_cuda_memset(void* ptr, int value, size_t size, void* stream = nullptr) {
    if (ptr == nullptr || size <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    if (s != nullptr) {
        cudaMemsetAsync(ptr, value, size, s);
    } else {
        cudaMemset(ptr, value, size);
    }
}

}
