#include "sonata_cuda.h"

__global__ void cuda_transpose_kernel(const float* in, float* out, int rows, int cols) {
    int r = blockIdx.x * blockDim.x + threadIdx.x;
    int c = blockIdx.y * blockDim.y + threadIdx.y;
    if (r < rows && c < cols) {
        out[c * rows + r] = in[r * cols + c];
    }
}

__global__ void cuda_clamp_upper_kernel(float* data, float max_val, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float val = data[i];
        if (isnan(val)) {
            data[i] = max_val;
        } else if (val > max_val) {
            data[i] = max_val;
        }
    }
}

__global__ void cuda_clean_nans_kernel(float* data, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float val = data[i];
        if (isnan(val) || isinf(val)) {
            data[i] = 0.0f;
        }
    }
}

__global__ void cuda_cast_fp32_to_fp16_kernel(const float* src, __half* dst, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        dst[i] = __float2half(src[i]);
    }
}

__global__ void cuda_cast_fp16_to_fp32_kernel(const __half* src, float* dst, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        dst[i] = __half2float(src[i]);
    }
}

__global__ void cuda_check_nan_or_inf_kernel(const float* data, int* out_flag, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float val = data[i];
        if (isnan(val) || isinf(val)) {
            *out_flag = 1;
        }
    }
}

__global__ void cuda_quantize_grad_fp16_kernel(const float* grad_fp32, __half* grad_fp16, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        grad_fp16[i] = __float2half(grad_fp32[i]);
    }
}

extern "C" {

EXPORT void sonata_cuda_transpose(const float* in, float* out, int rows, int cols, void* stream = nullptr) {
    if (in == nullptr || out == nullptr || rows <= 0 || cols <= 0) return;
    dim3 threadsPerBlock(16, 16);
    dim3 numBlocks((rows + 15) / 16, (cols + 15) / 16);
    cudaStream_t s = (cudaStream_t)stream;
    cuda_transpose_kernel<<<numBlocks, threadsPerBlock, 0, s>>>(in, out, rows, cols);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_clamp_upper(float* data, float max_val, int size, void* stream = nullptr) {
    if (data == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_clamp_upper_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(data, max_val, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_clean_nans(float* data, int size, void* stream = nullptr) {
    if (data == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_clean_nans_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(data, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT float sonata_cuda_vector_norm2(const float* data, int size, void* stream = nullptr) {
    if (g_cublasHandle == nullptr || data == nullptr || size <= 0) {
        return 0.0f;
    }
    cudaStream_t s = (cudaStream_t)stream;
    cublasSetStream(g_cublasHandle, s);
    float result = 0.0f;
    cublasStatus_t status = cublasSnrm2(g_cublasHandle, size, data, 1, &result);
    if (status != CUBLAS_STATUS_SUCCESS) {
        std::cerr << "[cuBLAS Error] cublasSnrm2 failed: " << status << std::endl;
        return 0.0f;
    }
    return result;
}

EXPORT void sonata_cuda_vector_scale(float* data, float scale, int size, void* stream = nullptr) {
    if (g_cublasHandle == nullptr || data == nullptr || size <= 0) {
        return;
    }
    cudaStream_t s = (cudaStream_t)stream;
    cublasSetStream(g_cublasHandle, s);
    cublasStatus_t status = cublasSscal(g_cublasHandle, size, &scale, data, 1);
    if (status != CUBLAS_STATUS_SUCCESS) {
        std::cerr << "[cuBLAS Error] cublasSscal failed: " << status << std::endl;
    }
}

EXPORT void sonata_cuda_cast_fp32_to_fp16(const float* src, void* dst, int size, void* stream = nullptr) {
    if (src == nullptr || dst == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_cast_fp32_to_fp16_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(src, (__half*)dst, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_cast_fp16_to_fp32(const void* src, float* dst, int size, void* stream = nullptr) {
    if (src == nullptr || dst == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_cast_fp16_to_fp32_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>((const __half*)src, dst, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT bool sonata_cuda_check_nan_or_inf(const float* data, int size, void* stream = nullptr) {
    if (data == nullptr || size <= 0) return false;

    int* dev_flag = (int*)g_allocator.allocate(sizeof(int));
    if (dev_flag == nullptr) return false;

    int host_flag = 0;
    cudaError_t err = cudaMemcpy(dev_flag, &host_flag, sizeof(int), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) {
        g_allocator.free(dev_flag);
        return false;
    }

    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_check_nan_or_inf_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(data, dev_flag, size);
    if (s != nullptr) {
        cudaStreamSynchronize(s);
    } else {
        cudaDeviceSynchronize();
    }

    cudaMemcpy(&host_flag, dev_flag, sizeof(int), cudaMemcpyDeviceToHost);
    g_allocator.free(dev_flag);

    return host_flag != 0;
}

EXPORT void sonata_cuda_quantize_grad_fp16(const float* grad_fp32, void* grad_fp16, int size, void* stream = nullptr) {
    if (grad_fp32 == nullptr || grad_fp16 == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_quantize_grad_fp16_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad_fp32, (__half*)grad_fp16, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT bool sonata_cuda_get_device_properties(SonataGpuProperties* props) {
    if (props == nullptr) return false;

    cudaDeviceProp devProp;
    cudaError_t err = cudaGetDeviceProperties(&devProp, 0);
    if (err != cudaSuccess) {
        std::cerr << "[CUDA Error] cudaGetDeviceProperties failed: "
                  << cudaGetErrorString(err) << std::endl;
        return false;
    }

    props->totalGlobalMem            = devProp.totalGlobalMem;
    props->sharedMemPerBlock         = devProp.sharedMemPerBlock;
    
    strncpy(props->name, devProp.name, 255);
    props->name[255] = '\0';

    int temp = 0;
    
    if (cudaDeviceGetAttribute(&temp, cudaDevAttrMultiProcessorCount, 0) == cudaSuccess)
        props->multiProcessorCount = temp;
    else
        props->multiProcessorCount = devProp.multiProcessorCount;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrWarpSize, 0) == cudaSuccess)
        props->warpSize = temp;
    else
        props->warpSize = devProp.warpSize;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrMaxThreadsPerBlock, 0) == cudaSuccess)
        props->maxThreadsPerBlock = temp;
    else
        props->maxThreadsPerBlock = devProp.maxThreadsPerBlock;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrMaxThreadsPerMultiProcessor, 0) == cudaSuccess)
        props->maxThreadsPerMultiProcessor = temp;
    else
        props->maxThreadsPerMultiProcessor = 0;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrComputeCapabilityMajor, 0) == cudaSuccess)
        props->major = temp;
    else
        props->major = devProp.major;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrComputeCapabilityMinor, 0) == cudaSuccess)
        props->minor = temp;
    else
        props->minor = devProp.minor;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrMemoryClockRate, 0) == cudaSuccess)
        props->memoryClockRate = temp;
    else
        props->memoryClockRate = 0;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrGlobalMemoryBusWidth, 0) == cudaSuccess)
        props->memoryBusWidth = temp;
    else
        props->memoryBusWidth = 0;

    if (cudaDeviceGetAttribute(&temp, cudaDevAttrL2CacheSize, 0) == cudaSuccess)
        props->l2CacheSize = temp;
    else
        props->l2CacheSize = devProp.l2CacheSize;

    return true;
}

EXPORT bool sonata_cuda_get_free_mem(size_t* free_bytes, size_t* total_bytes) {
    if (free_bytes == nullptr || total_bytes == nullptr) return false;

    cudaError_t err = cudaMemGetInfo(free_bytes, total_bytes);
    if (err != cudaSuccess) {
        std::cerr << "[CUDA Error] cudaMemGetInfo failed: "
                  << cudaGetErrorString(err) << std::endl;
        *free_bytes = 0;
        *total_bytes = 0;
        return false;
    }
    return true;
}

EXPORT size_t sonata_cuda_pool_allocated() {
    return g_allocator.getAllocatedBytes();
}

EXPORT size_t sonata_cuda_pool_cached() {
    return g_allocator.getCachedBytes();
}

EXPORT size_t sonata_cuda_pool_peak() {
    return g_allocator.getPeakBytes();
}

EXPORT size_t sonata_cuda_pool_live_blocks() {
    return g_allocator.getLiveBlockCount();
}

EXPORT size_t sonata_cuda_pool_failed_allocs() {
    return g_allocator.getFailedAllocCount();
}

EXPORT void sonata_cuda_pool_reset_peak() {
    g_allocator.resetPeak();
}

EXPORT void sonata_cuda_pool_release_cached() {
    g_allocator.releaseCached();
}

}
