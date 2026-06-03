#include "sonata_cuda.h"

__global__ void cuda_crossentropy_forward_kernel(
    const float* pred, const float* target, float* loss_val,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        float max_logit = pred[base];
        for (int j = 1; j < classes; ++j) {
            if (pred[base + j] > max_logit) {
                max_logit = pred[base + j];
            }
        }
        
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }
        
        float loss = 0.0f;
        for (int j = 0; j < classes; ++j) {
            if (target[base + j] > 0.5f) {
                loss -= ((pred[base + j] - max_logit) - logf(sum_exp));
            }
        }
        
        atomicAdd(loss_val, loss / batch_size);
    }
}

__global__ void cuda_crossentropy_backward_kernel(
    const float* pred, const float* target, const float* grad_out, float* grad_pred,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        float max_logit = pred[base];
        for (int j = 1; j < classes; ++j) {
            if (pred[base + j] > max_logit) {
                max_logit = pred[base + j];
            }
        }
        
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }
        
        float scale = grad_out[0] / batch_size;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            float softmax_val = expf(val) / sum_exp;
            if (softmax_val < 1e-15f) softmax_val = 1e-15f;
            
            grad_pred[base + j] += scale * (softmax_val - target[base + j]);
        }
    }
}

__global__ void cuda_crossentropy_sparse_forward_kernel(
    const float* pred, const float* target_indices, float* loss_val,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        int target_idx = (int)target_indices[i];
        
        float max_logit = pred[base];
        for (int j = 1; j < classes; ++j) {
            if (pred[base + j] > max_logit) {
                max_logit = pred[base + j];
            }
        }
        
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }
        
        float loss = 0.0f;
        if (target_idx >= 0 && target_idx < classes) {
            loss = -((pred[base + target_idx] - max_logit) - logf(sum_exp));
        }
        
        atomicAdd(loss_val, loss / batch_size);
    }
}

__global__ void cuda_crossentropy_sparse_backward_kernel(
    const float* pred, const float* target_indices, const float* grad_out, float* grad_pred,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        int target_idx = (int)target_indices[i];
        
        float max_logit = pred[base];
        for (int j = 1; j < classes; ++j) {
            if (pred[base + j] > max_logit) {
                max_logit = pred[base + j];
            }
        }
        
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }
        
        float scale = grad_out[0] / batch_size;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            float softmax_val = expf(val) / sum_exp;
            if (softmax_val < 1e-15f) softmax_val = 1e-15f;
            
            float target_val = (j == target_idx) ? 1.0f : 0.0f;
            grad_pred[base + j] += scale * (softmax_val - target_val);
        }
    }
}

__global__ void cuda_crossentropy_sparse_forward_i32_kernel(
    const float* pred, const int* target_indices, float* loss_val,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        int target_idx = target_indices[i];
        
        float max_logit = pred[base];
        for (int j = 1; j < classes; ++j) {
            if (pred[base + j] > max_logit) {
                max_logit = pred[base + j];
            }
        }
        
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }
        
        float loss = 0.0f;
        if (target_idx >= 0 && target_idx < classes) {
            loss = -((pred[base + target_idx] - max_logit) - logf(sum_exp));
        }
        
        atomicAdd(loss_val, loss / batch_size);
    }
}

__global__ void cuda_crossentropy_sparse_backward_i32_kernel(
    const float* pred, const int* target_indices, const float* grad_out, float* grad_pred,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        int target_idx = target_indices[i];
        
        float max_logit = pred[base];
        for (int j = 1; j < classes; ++j) {
            if (pred[base + j] > max_logit) {
                max_logit = pred[base + j];
            }
        }
        
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }
        
        float scale = grad_out[0] / batch_size;
        for (int j = 0; j < classes; ++j) {
            float val = pred[base + j] - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            float softmax_val = expf(val) / sum_exp;
            if (softmax_val < 1e-15f) softmax_val = 1e-15f;
            
            float target_val = (j == target_idx) ? 1.0f : 0.0f;
            grad_pred[base + j] += scale * (softmax_val - target_val);
        }
    }
}

__global__ void cuda_crossentropy_sparse_forward_i32_fp16_kernel(
    const __half* pred, const int* target_indices, float* loss_val,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        int target_idx = target_indices[i];

        // Find max logit in FP32 for numerical stability
        float max_logit = __half2float(pred[base]);
        for (int j = 1; j < classes; ++j) {
            float val = __half2float(pred[base + j]);
            if (val > max_logit) {
                max_logit = val;
            }
        }

        // Compute sum of exp in FP32
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = __half2float(pred[base + j]) - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }

        // Compute loss for target class
        float loss = 0.0f;
        if (target_idx >= 0 && target_idx < classes) {
            loss = -((__half2float(pred[base + target_idx]) - max_logit) - logf(sum_exp));
        }

        atomicAdd(loss_val, loss / batch_size);
    }
}

__global__ void cuda_crossentropy_sparse_backward_i32_fp16_kernel(
    const __half* pred, const int* target_indices, const float* grad_out, __half* grad_pred,
    int batch_size, int classes
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < batch_size) {
        long long base = (long long)i * classes;
        int target_idx = target_indices[i];

        // Find max logit in FP32 for numerical stability
        float max_logit = __half2float(pred[base]);
        for (int j = 1; j < classes; ++j) {
            float val = __half2float(pred[base + j]);
            if (val > max_logit) {
                max_logit = val;
            }
        }

        // Compute sum of exp in FP32
        float sum_exp = 0.0f;
        for (int j = 0; j < classes; ++j) {
            float val = __half2float(pred[base + j]) - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            sum_exp += expf(val);
        }

        // Compute gradient: scale * (softmax - target)
        float scale = grad_out[0] / batch_size;
        for (int j = 0; j < classes; ++j) {
            float val = __half2float(pred[base + j]) - max_logit;
            if (val > 80.0f) val = 80.0f;
            if (val < -80.0f) val = -80.0f;
            float softmax_val = expf(val) / sum_exp;
            if (softmax_val < 1e-15f) softmax_val = 1e-15f;

            float target_val = (j == target_idx) ? 1.0f : 0.0f;
            float g = scale * (softmax_val - target_val);
            // Accumulate gradient (FP32->FP16 conversion)
            grad_pred[base + j] = __hadd(grad_pred[base + j], __float2half(g));
        }
    }
}

extern "C" {

EXPORT void sonata_cuda_crossentropy_forward(
    const float* pred, const float* target, float* loss_val,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target == nullptr || loss_val == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    cudaMemsetAsync(loss_val, 0, sizeof(float), s);
    
    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_forward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target, loss_val, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_backward(
    const float* pred, const float* target, const float* grad_out, float* grad_pred,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target == nullptr || grad_out == nullptr || grad_pred == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target, grad_out, grad_pred, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_sparse_forward(
    const float* pred, const float* target_indices, float* loss_val,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target_indices == nullptr || loss_val == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    cudaMemsetAsync(loss_val, 0, sizeof(float), s);
    
    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_sparse_forward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target_indices, loss_val, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_sparse_backward(
    const float* pred, const float* target_indices, const float* grad_out, float* grad_pred,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target_indices == nullptr || grad_out == nullptr || grad_pred == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_sparse_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target_indices, grad_out, grad_pred, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_sparse_forward_i32(
    const float* pred, const int* target_indices, float* loss_val,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target_indices == nullptr || loss_val == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    cudaMemsetAsync(loss_val, 0, sizeof(float), s);
    
    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_sparse_forward_i32_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target_indices, loss_val, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_sparse_backward_i32(
    const float* pred, const int* target_indices, const float* grad_out, float* grad_pred,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target_indices == nullptr || grad_out == nullptr || grad_pred == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;
    
    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_sparse_backward_i32_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target_indices, grad_out, grad_pred, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_sparse_forward_i32_fp16(
    const __half* pred, const int* target_indices, float* loss_val,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target_indices == nullptr || loss_val == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;

    cudaMemsetAsync(loss_val, 0, sizeof(float), s);

    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_sparse_forward_i32_fp16_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target_indices, loss_val, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_crossentropy_sparse_backward_i32_fp16(
    const __half* pred, const int* target_indices, const float* grad_out, __half* grad_pred,
    int batch_size, int classes, void* stream = nullptr
) {
    if (pred == nullptr || target_indices == nullptr || grad_out == nullptr || grad_pred == nullptr || batch_size <= 0 || classes <= 0) return;
    cudaStream_t s = (cudaStream_t)stream;

    int optBlockSize = 256;
    int blocksPerGrid = (batch_size + optBlockSize - 1) / optBlockSize;
    cuda_crossentropy_sparse_backward_i32_fp16_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(pred, target_indices, grad_out, grad_pred, batch_size, classes);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
