#pragma once
#include <cuda_runtime.h>
#include <cublas_v2.h>
#include <cuda_fp16.h>
#include <iostream>
#include <mutex>
#include <map>
#include <unordered_map>
#include <cstring>

#ifndef __NVCC__
#ifndef __device__
#define __device__
#endif
static __device__ __half atomicAdd(__half* address, __half val) { return val; }
#endif

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

static inline cudaError_t sonata_cuda_real_synchronize_default_stream() {
    return cudaStreamSynchronize((cudaStream_t)0);
}

// Keep production launches asynchronous. Define CUDA_DEBUG_SYNC when debugging
// async CUDA errors and all guarded cudaDeviceSynchronize() calls become real.
#ifndef CUDA_DEBUG_SYNC
#define cudaDeviceSynchronize() ((void)0)
#endif

typedef struct {
    int multiProcessorCount;
    size_t totalGlobalMem;
    size_t sharedMemPerBlock;
    int warpSize;
    int maxThreadsPerBlock;
    int maxThreadsPerMultiProcessor;
    int major;
    int minor;
    int memoryClockRate;       // kHz
    int memoryBusWidth;        // bits
    int l2CacheSize;           // bytes
    char name[256];
} SonataGpuProperties;

class CachingAllocator {
private:
    std::mutex m_mutex;
    // Map from size to device pointers of free blocks
    std::multimap<size_t, void*> m_freeBlocks;
    // Map from device pointers of active blocks to their allocated size
    std::unordered_map<void*, size_t> m_activeBlocks;

public:
    void* allocate(size_t size) {
        std::lock_guard<std::mutex> lock(m_mutex);

        // Search for best-fit block: smallest block >= size
        auto it = m_freeBlocks.lower_bound(size);
        if (it != m_freeBlocks.end()) {
            void* ptr = it->second;
            size_t blockSize = it->first;
            m_freeBlocks.erase(it);
            m_activeBlocks[ptr] = blockSize;
            size_t current = getAllocatedBytes_Locked();
            if (current > m_peakBytes) m_peakBytes = current;
            return ptr;
        }

        // Allocate new VRAM if no cached block fits
        void* ptr = nullptr;
        cudaError_t err = cudaMalloc(&ptr, size);
        if (err != cudaSuccess) {
            m_failedAllocCount++;
            std::cerr << "[CUDA Pool Error] cudaMalloc failed for size " << size 
                      << " bytes: " << cudaGetErrorString(err) << std::endl;
            return nullptr;
        }

        m_activeBlocks[ptr] = size;
        size_t current = getAllocatedBytes_Locked();
        if (current > m_peakBytes) m_peakBytes = current;
        return ptr;
    }

    void free(void* ptr) {
        if (ptr == nullptr) return;

        std::lock_guard<std::mutex> lock(m_mutex);

        auto it = m_activeBlocks.find(ptr);
        if (it != m_activeBlocks.end()) {
            size_t size = it->second;
            m_activeBlocks.erase(it);
            m_freeBlocks.insert({size, ptr});
        } else {
            // Fallback for pointers not allocated by our pool
            cudaFree(ptr);
        }
    }

    void releaseAll() {
        std::lock_guard<std::mutex> lock(m_mutex);

        for (auto& pair : m_activeBlocks) {
            cudaFree(pair.first);
        }
        m_activeBlocks.clear();

        for (auto& pair : m_freeBlocks) {
            cudaFree(pair.second);
        }
        m_freeBlocks.clear();
    }

    // Stats methods for Phase 21 memory diagnostics
    size_t getAllocatedBytes() {
        std::lock_guard<std::mutex> lock(m_mutex);
        size_t total = 0;
        for (auto& pair : m_activeBlocks)
            total += pair.second;
        return total;
    }

    size_t getCachedBytes() {
        std::lock_guard<std::mutex> lock(m_mutex);
        size_t total = 0;
        for (auto& pair : m_freeBlocks)
            total += pair.first;
        return total;
    }

    size_t getPeakBytes() {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_peakBytes;
    }

    size_t getLiveBlockCount() {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_activeBlocks.size();
    }

    size_t getFailedAllocCount() {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_failedAllocCount;
    }

    void resetPeak() {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_peakBytes = getAllocatedBytes_Locked();
    }

    void releaseCached() {
        std::lock_guard<std::mutex> lock(m_mutex);
        for (auto& pair : m_freeBlocks) {
            cudaFree(pair.second);
        }
        m_freeBlocks.clear();
    }

private:
    size_t m_peakBytes = 0;
    size_t m_failedAllocCount = 0;

    size_t getAllocatedBytes_Locked() {
        size_t total = 0;
        for (auto& pair : m_activeBlocks)
            total += pair.second;
        return total;
    }
};

extern cublasHandle_t g_cublasHandle;
extern CachingAllocator g_allocator;

#ifdef __cplusplus
extern "C" {
#endif

// =========================================================================
// AST Evaluation (Symbolic Regression on GPU)
// Postfix (RPN) stack-based AST interpreter
// =========================================================================

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

// Single dataset: evaluate AST on all rows, output SSE (sum of squared errors)
// data[n_rows * n_vars] — row-major, last column = target value
// opcodes[ast_len]     — sequence of AST_OP_* values in postfix order
// args[ast_len]        — for OP_VAR: variable index; for OP_CONST: constant value
// out_error[1]         — scalar SSE output
EXPORT void sonata_cuda_eval_ast_sse(
    const float* data, int n_rows, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_error, void* stream);

// Batch: same AST against n_datasets independent datasets
// data[n_datasets * n_rows_per_ds * n_vars]
// out_errors[n_datasets] — one SSE per dataset
EXPORT void sonata_cuda_eval_ast_sse_batch(
    const float* data, int n_datasets, int n_rows_per_ds, int n_vars,
    const int* opcodes, const float* args, int ast_len,
    float* out_errors, void* stream);

#ifdef __cplusplus
}
#endif
