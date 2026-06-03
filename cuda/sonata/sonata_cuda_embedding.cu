#include "sonata_cuda.h"

__global__ void cuda_embedding_forward_kernel(
    const float* weights, const int* token_ids, float* out,
    int num_tokens, int embed_dim
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int total_elements = num_tokens * embed_dim;
    if (idx < total_elements) {
        int token_idx = idx / embed_dim;
        int dim_idx = idx % embed_dim;
        int token_id = token_ids[token_idx];
        if (token_id < 0) token_id = 0;
        out[idx] = weights[token_id * embed_dim + dim_idx];
    }
}

__global__ void cuda_embedding_backward_kernel(
    const float* grad_out, const int* token_ids, float* grad_weights,
    int num_tokens, int embed_dim
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int total_elements = num_tokens * embed_dim;
    if (idx < total_elements) {
        int token_idx = idx / embed_dim;
        int dim_idx = idx % embed_dim;
        int token_id = token_ids[token_idx];
        if (token_id < 0) token_id = 0;
        atomicAdd(&grad_weights[token_id * embed_dim + dim_idx], grad_out[idx]);
    }
}

extern "C" {

EXPORT void sonata_cuda_embedding_forward(
    const float* weights, const int* token_ids, float* out,
    int num_tokens, int embed_dim, void* stream = nullptr
) {
    if (weights == nullptr || token_ids == nullptr || out == nullptr || num_tokens <= 0 || embed_dim <= 0) return;
    int total_elements = num_tokens * embed_dim;
    int optBlockSize = 256;
    int blocksPerGrid = (total_elements + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    
    cuda_embedding_forward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(weights, token_ids, out, num_tokens, embed_dim);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

EXPORT void sonata_cuda_embedding_backward(
    const float* grad_out, const int* token_ids, float* grad_weights,
    int num_tokens, int embed_dim, void* stream = nullptr
) {
    if (grad_out == nullptr || token_ids == nullptr || grad_weights == nullptr || num_tokens <= 0 || embed_dim <= 0) return;
    int total_elements = num_tokens * embed_dim;
    int optBlockSize = 256;
    int blocksPerGrid = (total_elements + optBlockSize - 1) / optBlockSize;
    cudaStream_t s = (cudaStream_t)stream;
    
    cuda_embedding_backward_kernel<<<blocksPerGrid, optBlockSize, 0, s>>>(grad_out, token_ids, grad_weights, num_tokens, embed_dim);
    if (s == nullptr) {
        cudaDeviceSynchronize();
    }
}

}
