#include "sonata_cuda.h"

__global__ void cuda_clip_gradients_kernel(float* grad, float clip_val, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        if (isnan(grad[i])) grad[i] = 0.0f;
        if (grad[i] > clip_val) grad[i] = clip_val;
        else if (grad[i] < -clip_val) grad[i] = -clip_val;
    }
}

__global__ void cuda_adam_step_kernel(
    float* param, const float* grad, float* m, float* v,
    float lr, float beta1, float beta2, float eps,
    float beta1_power, float beta2_power, int size
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float grad_val = grad[i];
        if (isnan(grad_val)) grad_val = 0.0f;
        if (grad_val > 10000.0f) grad_val = 10000.0f;
        if (grad_val < -10000.0f) grad_val = -10000.0f;

        float m_val = beta1 * m[i] + (1.0f - beta1) * grad_val;
        if (isnan(m_val)) m_val = 0.0f;
        m[i] = m_val;

        float v_val = beta2 * v[i] + (1.0f - beta2) * (grad_val * grad_val);
        if (isnan(v_val) || (v_val > 1e12f)) v_val = 1e12f;
        v[i] = v_val;

        float m_hat = m_val / beta1_power;
        float v_hat = v_val / beta2_power;
        if (v_hat < 0.0f) v_hat = 0.0f;

        param[i] -= lr * m_hat / (sqrtf(v_hat) + eps);
    }
}

__global__ void cuda_adam_step_fp16_unified_kernel(
    float* param, const __half* grad_fp16, float* m, float* v,
    float lr, float beta1, float beta2, float eps,
    float beta1_power, float beta2_power,
    float loss_scale, float clip_norm, int size
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float grad_val = __half2float(grad_fp16[i]) / loss_scale;
        if (isnan(grad_val)) grad_val = 0.0f;
        if (grad_val > clip_norm) grad_val = clip_norm;
        else if (grad_val < -clip_norm) grad_val = -clip_norm;

        float m_val = beta1 * m[i] + (1.0f - beta1) * grad_val;
        if (isnan(m_val)) m_val = 0.0f;
        m[i] = m_val;

        float v_val = beta2 * v[i] + (1.0f - beta2) * (grad_val * grad_val);
        if (isnan(v_val) || (v_val > 1e12f)) v_val = 1e12f;
        v[i] = v_val;

        float m_hat = m_val / beta1_power;
        float v_hat = v_val / beta2_power;
        if (v_hat < 0.0f) v_hat = 0.0f;

        param[i] -= lr * m_hat / (sqrtf(v_hat) + eps);
    }
}

extern "C" {

EXPORT void sonata_cuda_clip_gradients(float* grad, float clip_val, int size, void* stream = nullptr) {
    if (grad == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_clip_gradients_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad, clip_val, size);

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_adam_step(
    float* param, const float* grad, float* m, float* v,
    float lr, float beta1, float beta2, float eps,
    float beta1_power, float beta2_power, int size,
    void* stream = nullptr
) {
    if (param == nullptr || grad == nullptr || m == nullptr || v == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_adam_step_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        param, grad, m, v,
        lr, beta1, beta2, eps,
        beta1_power, beta2_power, size
    );
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_adam_step_fp16(
    float* param, const void* grad_fp16, float* m, float* v,
    float lr, float beta1, float beta2, float eps,
    float beta1_power, float beta2_power,
    float loss_scale, float clip_norm, int size,
    void* stream = nullptr
) {
    if (param == nullptr || grad_fp16 == nullptr || m == nullptr || v == nullptr || size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_adam_step_fp16_unified_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        param, (const __half*)grad_fp16, m, v,
        lr, beta1, beta2, eps,
        beta1_power, beta2_power,
        loss_scale, clip_norm, size
    );
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
