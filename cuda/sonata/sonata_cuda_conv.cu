#include "sonata_cuda.h"

__global__ void cuda_conv2d_kernel(
    const float* in, const float* weight, const float* bias, float* out,
    int B, int C_in, int H_in, int W_in,
    int C_out, int K,
    int H_out, int W_out,
    int Stride, int Padding
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int total_elements = B * C_out * H_out * W_out;
    if (idx >= total_elements) return;

    int w_idx = idx % W_out;
    int h_idx = (idx / W_out) % H_out;
    int c_out_idx = (idx / (W_out * H_out)) % C_out;
    int b_idx = idx / (W_out * H_out * C_out);

    float sum = 0.0f;
    if (bias != nullptr) {
        sum = bias[c_out_idx];
    }

    for (int ic = 0; ic < C_in; ++ic) {
        for (int kh = 0; kh < K; ++kh) {
            for (int kw = 0; kw < K; ++kw) {
                int ih = h_idx * Stride - Padding + kh;
                int iw = w_idx * Stride - Padding + kw;

                if (ih >= 0 && ih < H_in && iw >= 0 && iw < W_in) {
                    int in_idx = b_idx * (C_in * H_in * W_in) + ic * (H_in * W_in) + ih * W_in + iw;
                    int w_idx_flat = c_out_idx * (C_in * K * K) + ic * (K * K) + kh * K + kw;
                    sum += in[in_idx] * weight[w_idx_flat];
                }
            }
        }
    }

    out[idx] = sum;
}

extern "C" {

EXPORT void sonata_cuda_conv2d(
    const float* in, const float* weight, const float* bias, float* out,
    int B, int C_in, int H_in, int W_in,
    int C_out, int K,
    int H_out, int W_out,
    int Stride, int Padding,
    void* stream = nullptr
) {
    long long total_elements = (long long)B * C_out * H_out * W_out;
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_conv2d_kernel, 0, 0);
    }
    int blocksPerGrid = (int)((total_elements + optBlockSize - 1) / optBlockSize);
    cudaStream_t s = (cudaStream_t)stream;

    cuda_conv2d_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        in, weight, bias, out,
        B, C_in, H_in, W_in,
        C_out, K,
        H_out, W_out,
        Stride, Padding
    );
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
