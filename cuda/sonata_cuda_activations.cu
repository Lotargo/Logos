#include "sonata_cuda.h"

__global__ void cuda_relu_kernel(const float* in, float* out, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        out[i] = (in[i] > 0.0f) ? in[i] : 0.0f;
    }
}

__global__ void cuda_sigmoid_kernel(const float* in, float* out, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float val = -in[i];
        if (val > 80.0f) val = 80.0f;
        if (val < -80.0f) val = -80.0f;
        out[i] = 1.0f / (1.0f + expf(val));
    }
}

__global__ void cuda_silu_kernel(const float* in, float* out, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float val = -in[i];
        if (val > 80.0f) val = 80.0f;
        if (val < -80.0f) val = -80.0f;
        out[i] = in[i] * (1.0f / (1.0f + expf(val)));
    }
}

__global__ void cuda_add_kernel(const float* a, const float* b, float* c, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        c[i] = a[i] + b[i];
    }
}

__global__ void cuda_sub_kernel(const float* a, const float* b, float* c, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        c[i] = a[i] - b[i];
    }
}

__global__ void cuda_mul_kernel(const float* a, const float* b, float* c, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        c[i] = a[i] * b[i];
    }
}

__global__ void cuda_div_kernel(const float* a, const float* b, float* c, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        c[i] = (b[i] != 0.0f) ? a[i] / b[i] : 0.0f;
    }
}

__global__ void cuda_relu_backward_kernel(const float* grad_out, const float* out_data, float* grad_in, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        grad_in[i] += (out_data[i] > 0.0f) ? grad_out[i] : 0.0f;
    }
}

__global__ void cuda_sigmoid_backward_kernel(const float* grad_out, const float* out_data, float* grad_in, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        grad_in[i] += grad_out[i] * out_data[i] * (1.0f - out_data[i]);
    }
}

__global__ void cuda_silu_backward_kernel(const float* grad_out, const float* in_data, const float* out_data, float* grad_in, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        float sig = 1.0f / (1.0f + expf(-in_data[i]));
        grad_in[i] += grad_out[i] * (sig + out_data[i] * (1.0f - sig));
    }
}

__global__ void cuda_sum_backward_kernel(const float* grad_out, float* grad_in, int size) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size) {
        grad_in[i] += grad_out[0];
    }
}

extern "C" {

EXPORT void sonata_cuda_relu(const float* in, float* out, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_relu_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_relu_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(in, out, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_sigmoid(const float* in, float* out, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_sigmoid_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_sigmoid_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(in, out, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_silu(const float* in, float* out, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_silu_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_silu_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(in, out, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_add(const float* a, const float* b, float* c, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_add_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_add_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(a, b, c, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_sub(const float* a, const float* b, float* c, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_sub_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_sub_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(a, b, c, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_mul(const float* a, const float* b, float* c, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_mul_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_mul_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(a, b, c, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_div(const float* a, const float* b, float* c, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_div_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_div_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(a, b, c, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_relu_backward(const float* grad_out, const float* out_data, float* grad_in, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_relu_backward_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_relu_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad_out, out_data, grad_in, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_sigmoid_backward(const float* grad_out, const float* out_data, float* grad_in, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_sigmoid_backward_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_sigmoid_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad_out, out_data, grad_in, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_silu_backward(const float* grad_out, const float* in_data, const float* out_data, float* grad_in, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_silu_backward_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_silu_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad_out, in_data, out_data, grad_in, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_sum_backward(const float* grad_out, float* grad_in, int size, void* stream = nullptr) {
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_sum_backward_kernel, 0, 0);
    }
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    cuda_sum_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad_out, grad_in, size);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
