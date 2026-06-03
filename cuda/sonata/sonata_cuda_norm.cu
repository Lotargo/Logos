#include "sonata_cuda.h"

__global__ void cuda_rmsnorm_forward_fp16_kernel(
    const __half* X, const __half* W, __half* Y, float* InvRMS,
    int batch_size, int features, float eps
) {
    int b = blockIdx.x;
    if (b >= batch_size) return;

    extern __shared__ float s_mem[];
    int tid = threadIdx.x;
    int num_threads = blockDim.x;

    // Compute sum of squares in FP32 for numerical stability
    float thread_sum = 0.0f;
    for (int j = tid; j < features; j += num_threads) {
        float val = __half2float(X[b * features + j]);
        thread_sum += val * val;
    }
    s_mem[tid] = thread_sum;
    __syncthreads();

    // Parallel reduction in FP32
    for (int stride = num_threads / 2; stride > 0; stride /= 2) {
        if (tid < stride) {
            s_mem[tid] += s_mem[tid + stride];
        }
        __syncthreads();
    }

    __shared__ float inv_rms;
    if (tid == 0) {
        float mean_sq = (features > 0) ? s_mem[0] / features : 0.0f;
        inv_rms = rsqrtf(mean_sq + eps);
        InvRMS[b] = inv_rms;
    }
    __syncthreads();

    // Normalize and apply weight, output in FP16
    for (int j = tid; j < features; j += num_threads) {
        float x_val = __half2float(X[b * features + j]);
        float w_val = __half2float(W[j]);
        float result = (x_val * inv_rms) * w_val;
        Y[b * features + j] = __float2half(result);
    }
}

__global__ void cuda_rmsnorm_backward_fp16_kernel(
    const __half* X, const __half* W, const float* InvRMS, const __half* grad_out,
    __half* grad_X, __half* grad_W,
    int batch_size, int features,
    bool req_X, bool req_W
) {
    int b = blockIdx.x;
    if (b >= batch_size) return;

    extern __shared__ float s_mem[];
    int tid = threadIdx.x;
    int num_threads = blockDim.x;

    float inv_rms = InvRMS[b];

    // Compute sum for grad_X in FP32
    float thread_sum = 0.0f;
    for (int j = tid; j < features; j += num_threads) {
        float x_val = __half2float(X[b * features + j]);
        float x_norm = x_val * inv_rms;
        float dy = __half2float(grad_out[b * features + j]);
        
        float dX_norm = dy * __half2float(W[j]);
        thread_sum += dX_norm * x_norm;

        // Accumulate grad_W
        if (req_W && grad_W != nullptr) {
            atomicAdd(&grad_W[j], __float2half(dy * x_norm));
        }
    }

    s_mem[tid] = thread_sum;
    __syncthreads();

    // Parallel reduction in FP32
    for (int stride = num_threads / 2; stride > 0; stride /= 2) {
        if (tid < stride) {
            s_mem[tid] += s_mem[tid + stride];
        }
        __syncthreads();
    }

    float sum_dx_norm_x_norm = s_mem[0];
    __syncthreads();

    // Compute grad_X
    if (req_X && grad_X != nullptr) {
        for (int j = tid; j < features; j += num_threads) {
            float x_val = __half2float(X[b * features + j]);
            float x_norm = x_val * inv_rms;
            float dy = __half2float(grad_out[b * features + j]);
            float dX_norm = dy * __half2float(W[j]);

            float result = inv_rms * (dX_norm - x_norm * sum_dx_norm_x_norm / ((features > 0) ? features : 1));
            grad_X[b * features + j] = __hadd(grad_X[b * features + j], __float2half(result));
        }
    }
}

__global__ void cuda_rmsnorm_forward_kernel(
    const float* X, const float* W, float* Y, float* InvRMS,
    int batch_size, int features, float eps
) {
    int b = blockIdx.x;
    if (b >= batch_size) return;

    extern __shared__ float s_mem[];
    int tid = threadIdx.x;
    int num_threads = blockDim.x;

    float thread_sum = 0.0f;
    for (int j = tid; j < features; j += num_threads) {
        float val = X[b * features + j];
        thread_sum += val * val;
    }
    s_mem[tid] = thread_sum;
    __syncthreads();

    for (int stride = num_threads / 2; stride > 0; stride /= 2) {
        if (tid < stride) {
            s_mem[tid] += s_mem[tid + stride];
        }
        __syncthreads();
    }

    __shared__ float inv_rms;
    if (tid == 0) {
        float mean_sq = (features > 0) ? s_mem[0] / features : 0.0f;
        inv_rms = rsqrtf(mean_sq + eps);
        InvRMS[b] = inv_rms;
    }
    __syncthreads();

    for (int j = tid; j < features; j += num_threads) {
        Y[b * features + j] = (X[b * features + j] * inv_rms) * W[j];
    }
}

__global__ void cuda_rmsnorm_backward_kernel(
    const float* X, const float* W, const float* InvRMS, const float* grad_out,
    float* grad_X, float* grad_W,
    int batch_size, int features,
    bool req_X, bool req_W
) {
    int b = blockIdx.x;
    if (b >= batch_size) return;

    extern __shared__ float s_mem[];
    int tid = threadIdx.x;
    int num_threads = blockDim.x;

    float inv_rms = InvRMS[b];

    float thread_sum = 0.0f;
    for (int j = tid; j < features; j += num_threads) {
        float x_val = X[b * features + j];
        float x_norm = x_val * inv_rms;
        float dy = grad_out[b * features + j];
        
        float dX_norm = dy * W[j];
        thread_sum += dX_norm * x_norm;

        if (req_W && grad_W != nullptr) {
            atomicAdd(&grad_W[j], dy * x_norm);
        }
    }

    s_mem[tid] = thread_sum;
    __syncthreads();

    for (int stride = num_threads / 2; stride > 0; stride /= 2) {
        if (tid < stride) {
            s_mem[tid] += s_mem[tid + stride];
        }
        __syncthreads();
    }

    float sum_dx_norm_x_norm = s_mem[0];
    __syncthreads();

    if (req_X && grad_X != nullptr) {
        for (int j = tid; j < features; j += num_threads) {
            float x_val = X[b * features + j];
            float x_norm = x_val * inv_rms;
            float dy = grad_out[b * features + j];
            float dX_norm = dy * W[j];

            grad_X[b * features + j] += inv_rms * (dX_norm - x_norm * sum_dx_norm_x_norm / ((features > 0) ? features : 1));
        }
    }
}

extern "C" {

EXPORT void sonata_cuda_rmsnorm_forward_fp16(
    const __half* X, const __half* W, __half* Y, float* InvRMS,
    int batch_size, int features, float eps, void* stream = nullptr
) {
    if (X == nullptr || W == nullptr || Y == nullptr || InvRMS == nullptr || batch_size <= 0 || features <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    int threads = 256;
    cuda_rmsnorm_forward_fp16_kernel<<<batch_size, threads, threads * sizeof(float), s>>>(X, W, Y, InvRMS, batch_size, features, eps);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_rmsnorm_backward_fp16(
    const __half* X, const __half* W, const float* InvRMS, const __half* grad_out,
    __half* grad_X, __half* grad_W,
    int batch_size, int features,
    bool req_X, bool req_W,
    void* stream = nullptr
) {
    if (X == nullptr || W == nullptr || InvRMS == nullptr || grad_out == nullptr || batch_size <= 0 || features <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;

    int threads = 256;
    cuda_rmsnorm_backward_fp16_kernel<<<batch_size, threads, threads * sizeof(float), s>>>(
        X, W, InvRMS, grad_out, grad_X, grad_W, batch_size, features, req_X, req_W
    );
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_rmsnorm_forward(
    const float* X, const float* W, float* Y, float* InvRMS,
    int batch_size, int features, float eps, void* stream = nullptr
) {
    if (X == nullptr || W == nullptr || Y == nullptr || InvRMS == nullptr || batch_size <= 0 || features <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    int threads = 256;
    cuda_rmsnorm_forward_kernel<<<batch_size, threads, threads * sizeof(float), s>>>(X, W, Y, InvRMS, batch_size, features, eps);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_rmsnorm_backward(
    const float* X, const float* W, const float* InvRMS, const float* grad_out,
    float* grad_X, float* grad_W,
    int batch_size, int features,
    bool req_X, bool req_W,
    void* stream = nullptr
) {
    if (X == nullptr || W == nullptr || InvRMS == nullptr || grad_out == nullptr || batch_size <= 0 || features <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;

    int threads = 256;
    cuda_rmsnorm_backward_kernel<<<batch_size, threads, threads * sizeof(float), s>>>(
        X, W, InvRMS, grad_out, grad_X, grad_W, batch_size, features, req_X, req_W
    );
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
