#include "sonata_cuda.h"

__global__ void cuda_mamba_scan_kernel(
    const float* X, const float* Delta, const float* A_param, const float* B_param, const float* C_param, const float* InitH,
    float* out_Y, float* CachedH, float* CachedA_bar, float* CachedB_bar,
    int B, int L, int D, int N, bool has_init_h
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int num_pairs = B * D;
    if (idx >= num_pairs) return;

    int b_idx = idx / D;
    int d = idx % D;

    for (int t = 0; t < L; ++t) {
        int idx_bld = b_idx * L * D + t * D + d;
        float delta_val = Delta[idx_bld];
        float x_val = X[idx_bld];
        float y_val = 0.0f;

        for (int n = 0; n < N; ++n) {
            int idx_bln = b_idx * L * N + t * N + n;
            int idx_dn = d * N + n;
            int idx_bldn = b_idx * L * D * N + t * D * N + d * N + n;

            float a_bar = expf(delta_val * A_param[idx_dn]);
            float b_bar = delta_val * B_param[idx_bln];

            CachedA_bar[idx_bldn] = a_bar;
            CachedB_bar[idx_bldn] = b_bar;

            float h_prev = 0.0f;
            if (t > 0) {
                h_prev = CachedH[idx_bldn - D * N];
            } else if (has_init_h && InitH != nullptr) {
                int init_idx = b_idx * D * N + d * N + n;
                h_prev = InitH[init_idx];
            }

            float h_cur = a_bar * h_prev + b_bar * x_val;
            if (h_cur > 100.0f) h_cur = 100.0f;
            if (h_cur < -100.0f) h_cur = -100.0f;
            CachedH[idx_bldn] = h_cur;
            y_val += h_cur * C_param[idx_bln];
        }

        out_Y[idx_bld] = y_val;
    }
}

__global__ void cuda_mamba_scan_backward_kernel(
    const float* X, const float* Delta, const float* A_param, const float* B_param, const float* C_param, const float* InitH,
    const float* CachedH, const float* CachedA_bar, const float* CachedB_bar,
    const float* grad_out,
    float* grad_X, float* grad_Delta, float* grad_A, float* grad_B, float* grad_C,
    int B, int L, int D, int N, bool has_init_h,
    bool req_X, bool req_Delta, bool req_A, bool req_B, bool req_C
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int num_pairs = B * D;
    if (idx >= num_pairs) return;

    int b_idx = idx / D;
    int d = idx % D;

    float dH_next[256];
    for (int k = 0; k < N && k < 256; ++k) {
        dH_next[k] = 0.0f;
    }

    for (int r = L - 1; r >= 0; --r) {
        int idx_bld = b_idx * L * D + r * D + d;
        float dy_current = grad_out[idx_bld];
        float x_current = X[idx_bld];
        float delta_current = Delta[idx_bld];

        float d_delta_sum = 0.0f;

        for (int n = 0; n < N && n < 256; ++n) {
            int idx_bln = b_idx * L * N + r * N + n;
            int idx_dn = d * N + n;
            int idx_bldn = b_idx * L * D * N + r * D * N + d * N + n;

            float a_bar = CachedA_bar[idx_bldn];
            float b_bar = CachedB_bar[idx_bldn];
            float c_val = C_param[idx_bln];

            float h_prev = 0.0f;
            if (r > 0) {
                h_prev = CachedH[idx_bldn - D * N];
            } else if (has_init_h && InitH != nullptr) {
                int init_idx = b_idx * D * N + d * N + n;
                h_prev = InitH[init_idx];
            }

            float d_current = dy_current * c_val + dH_next[n];
            float d_abar = d_current * h_prev;
            float d_bbar = d_current * x_current;

            if (req_C && grad_C != nullptr) {
                atomicAdd(&grad_C[idx_bln], dy_current * CachedH[idx_bldn]);
            }

            if (req_X && grad_X != nullptr) {
                atomicAdd(&grad_X[idx_bld], d_current * b_bar);
            }

            if (req_B && grad_B != nullptr) {
                atomicAdd(&grad_B[idx_bln], d_bbar * delta_current);
            }

            if (req_Delta) {
                float d_delta_val = d_abar * A_param[idx_dn] * a_bar + d_bbar * B_param[idx_bln];
                d_delta_sum += d_delta_val;
            }

            if (req_A && grad_A != nullptr) {
                float d_a_val = d_abar * delta_current * a_bar;
                atomicAdd(&grad_A[idx_dn], d_a_val);
            }

            dH_next[n] = d_current * a_bar;
        }

        if (req_Delta && grad_Delta != nullptr) {
            grad_Delta[idx_bld] += d_delta_sum;
        }
    }
}

__global__ void cuda_mamba_scan_fp16_kernel(
    const __half* X, const __half* Delta, const float* A_param, const float* B_param, const float* C_param, const __half* InitH,
    __half* out_Y, __half* CachedH, __half* CachedA_bar, __half* CachedB_bar,
    int B, int L, int D, int N, bool has_init_h
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int num_pairs = B * D;
    if (idx >= num_pairs) return;

    int b_idx = idx / D;
    int d = idx % D;

    for (int t = 0; t < L; ++t) {
        int idx_bld = b_idx * L * D + t * D + d;
        float delta_val = __half2float(Delta[idx_bld]);
        float x_val = __half2float(X[idx_bld]);
        float y_val = 0.0f;

        for (int n = 0; n < N; ++n) {
            int idx_bln = b_idx * L * N + t * N + n;
            int idx_dn = d * N + n;
            int idx_bldn = b_idx * L * D * N + t * D * N + d * N + n;

            float a_bar = expf(delta_val * A_param[idx_dn]);
            float b_bar = delta_val * B_param[idx_bln];

            CachedA_bar[idx_bldn] = __float2half(a_bar);
            CachedB_bar[idx_bldn] = __float2half(b_bar);

            float h_prev = 0.0f;
            if (t > 0) {
                h_prev = __half2float(CachedH[idx_bldn - D * N]);
            } else if (has_init_h && InitH != nullptr) {
                int init_idx = b_idx * D * N + d * N + n;
                h_prev = __half2float(InitH[init_idx]);
            }

            float h_cur = a_bar * h_prev + b_bar * x_val;
            if (h_cur > 100.0f) h_cur = 100.0f;
            if (h_cur < -100.0f) h_cur = -100.0f;
            CachedH[idx_bldn] = __float2half(h_cur);
            y_val += h_cur * C_param[idx_bln];
        }

        out_Y[idx_bld] = __float2half(y_val);
    }
}

__global__ void cuda_mamba_scan_backward_fp16_kernel(
    const __half* X, const __half* Delta, const float* A_param, const float* B_param, const float* C_param, const __half* InitH,
    const __half* CachedH, const __half* CachedA_bar, const __half* CachedB_bar,
    const __half* grad_out,
    __half* grad_X, __half* grad_Delta, float* grad_A, float* grad_B, float* grad_C,
    int B, int L, int D, int N, bool has_init_h,
    bool req_X, bool req_Delta, bool req_A, bool req_B, bool req_C
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int num_pairs = B * D;
    if (idx >= num_pairs) return;

    int b_idx = idx / D;
    int d = idx % D;

    float dH_next[256];
    for (int k = 0; k < N && k < 256; ++k) {
        dH_next[k] = 0.0f;
    }

    for (int r = L - 1; r >= 0; --r) {
        int idx_bld = b_idx * L * D + r * D + d;
        float dy_current = __half2float(grad_out[idx_bld]);
        float x_current = __half2float(X[idx_bld]);
        float delta_current = __half2float(Delta[idx_bld]);

        float d_delta_sum = 0.0f;

        for (int n = 0; n < N && n < 256; ++n) {
            int idx_bln = b_idx * L * N + r * N + n;
            int idx_dn = d * N + n;
            int idx_bldn = b_idx * L * D * N + r * D * N + d * N + n;

            float a_bar = __half2float(CachedA_bar[idx_bldn]);
            float b_bar = __half2float(CachedB_bar[idx_bldn]);
            float c_val = C_param[idx_bln];

            float h_prev = 0.0f;
            if (r > 0) {
                h_prev = __half2float(CachedH[idx_bldn - D * N]);
            } else if (has_init_h && InitH != nullptr) {
                int init_idx = b_idx * D * N + d * N + n;
                h_prev = __half2float(InitH[init_idx]);
            }

            float d_current = dy_current * c_val + dH_next[n];
            float d_abar = d_current * h_prev;
            float d_bbar = d_current * x_current;

            if (req_C && grad_C != nullptr) {
                atomicAdd(&grad_C[idx_bln], dy_current * __half2float(CachedH[idx_bldn]));
            }

            if (req_X && grad_X != nullptr) {
                atomicAdd(&grad_X[idx_bld], __float2half(d_current * b_bar));
            }

            if (req_B && grad_B != nullptr) {
                atomicAdd(&grad_B[idx_bln], d_bbar * delta_current);
            }

            if (req_Delta) {
                float d_delta_val = d_abar * A_param[idx_dn] * a_bar + d_bbar * B_param[idx_bln];
                d_delta_sum += d_delta_val;
            }

            if (req_A && grad_A != nullptr) {
                float d_a_val = d_abar * delta_current * a_bar;
                atomicAdd(&grad_A[idx_dn], d_a_val);
            }

            dH_next[n] = d_current * a_bar;
        }

        if (req_Delta && grad_Delta != nullptr) {
            grad_Delta[idx_bld] = __hadd(grad_Delta[idx_bld], __float2half(d_delta_sum));
        }
    }
}

__global__ void cuda_mamba_recompute_cache_kernel(
    const float* Delta, const float* A_param, const float* B_param,
    float* CachedA_bar, float* CachedB_bar,
    int B, int L, int D, int N
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int size = B * L * D * N;
    if (idx < size) {
        int n = idx % N;
        int temp = idx / N;
        int d = temp % D;
        int temp2 = temp / D;
        int t = temp2 % L;
        int b = temp2 / L;

        int idx_bld = b * L * D + t * D + d;
        int idx_dn = d * N + n;
        int idx_bln = b * L * N + t * N + n;

        float delta_val = Delta[idx_bld];
        CachedA_bar[idx] = expf(delta_val * A_param[idx_dn]);
        CachedB_bar[idx] = delta_val * B_param[idx_bln];
    }
}

extern "C" {

EXPORT void sonata_cuda_mamba_scan(
    const float* X, const float* Delta, const float* A_param, const float* B_param, const float* C_param, const float* InitH,
    float* out_Y, float* CachedH, float* CachedA_bar, float* CachedB_bar,
    int B, int L, int D, int N, bool has_init_h, void* stream = nullptr
) {
    int num_pairs = B * D;
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_mamba_scan_kernel, 0, 0);
    }
    int blocksPerGrid = (num_pairs + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_mamba_scan_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        X, Delta, A_param, B_param, C_param, InitH,
        out_Y, CachedH, CachedA_bar, CachedB_bar,
        B, L, D, N, has_init_h
    );

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_mamba_scan_backward(
    const float* X, const float* Delta, const float* A_param, const float* B_param, const float* C_param, const float* InitH,
    const float* CachedH, const float* CachedA_bar, const float* CachedB_bar,
    const float* grad_out,
    float* grad_X, float* grad_Delta, float* grad_A, float* grad_B, float* grad_C,
    int B, int L, int D, int N, bool has_init_h,
    bool req_X, bool req_Delta, bool req_A, bool req_B, bool req_C,
    void* stream = nullptr
) {
    int num_pairs = B * D;
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_mamba_scan_backward_kernel, 0, 0);
    }
    int blocksPerGrid = (num_pairs + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_mamba_scan_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        X, Delta, A_param, B_param, C_param, InitH,
        CachedH, CachedA_bar, CachedB_bar,
        grad_out,
        grad_X, grad_Delta, grad_A, grad_B, grad_C,
        B, L, D, N, has_init_h,
        req_X, req_Delta, req_A, req_B, req_C
    );

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_mamba_scan_fp16(
    const __half* X, const __half* Delta, const float* A_param, const float* B_param, const float* C_param, const __half* InitH,
    __half* out_Y, __half* CachedH, __half* CachedA_bar, __half* CachedB_bar,
    int B, int L, int D, int N, bool has_init_h, void* stream = nullptr
) {
    int num_pairs = B * D;
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_mamba_scan_fp16_kernel, 0, 0);
    }
    int blocksPerGrid = (num_pairs + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_mamba_scan_fp16_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        X, Delta, A_param, B_param, C_param, InitH,
        out_Y, CachedH, CachedA_bar, CachedB_bar,
        B, L, D, N, has_init_h
    );

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_mamba_scan_backward_fp16(
    const __half* X, const __half* Delta, const float* A_param, const float* B_param, const float* C_param, const __half* InitH,
    const __half* CachedH, const __half* CachedA_bar, const __half* CachedB_bar,
    const __half* grad_out,
    __half* grad_X, __half* grad_Delta, float* grad_A, float* grad_B, float* grad_C,
    int B, int L, int D, int N, bool has_init_h,
    bool req_X, bool req_Delta, bool req_A, bool req_B, bool req_C,
    void* stream = nullptr
) {
    int num_pairs = B * D;
    static int optBlockSize = 0;
    static int minGridSize = 0;
    if (optBlockSize == 0) {
        cudaOccupancyMaxPotentialBlockSize(&minGridSize, &optBlockSize, cuda_mamba_scan_backward_fp16_kernel, 0, 0);
    }
    int blocksPerGrid = (num_pairs + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_mamba_scan_backward_fp16_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        X, Delta, A_param, B_param, C_param, InitH,
        CachedH, CachedA_bar, CachedB_bar,
        grad_out,
        grad_X, grad_Delta, grad_A, grad_B, grad_C,
        B, L, D, N, has_init_h,
        req_X, req_Delta, req_A, req_B, req_C
    );

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_mamba_recompute_cache(
    const float* Delta, const float* A_param, const float* B_param,
    float* CachedA_bar, float* CachedB_bar,
    int B, int L, int D, int N, void* stream = nullptr
) {
    int size = B * L * D * N;
    if (size <= 0) return;
    int optBlockSize = 256;
    int blocksPerGrid = (size + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;

    cuda_mamba_recompute_cache_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(
        Delta, A_param, B_param, CachedA_bar, CachedB_bar, B, L, D, N
    );

    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
