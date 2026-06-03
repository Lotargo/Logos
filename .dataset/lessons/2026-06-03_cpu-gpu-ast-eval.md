# Dual-Backend AST Eval Engine (GPU CUDA + CPU SIMD)

## Problem
v7 symbolic regression evaluates candidate expressions row-by-row in Prolog, which is the bottleneck. We need hardware-accelerated batch evaluation.

## Solution
Two backends in a single DLL (`sonata_cuda.dll`), selected at Lisp runtime:

### GPU Backend (CUDA)
- File: `cuda/sonata_cuda_ast.cu`
- One CUDA thread per data row
- Stack-based postfix (RPN) AST interpreter with 12 opcodes
- Block-level SSE reduction via shared memory (256 threads/block)
- Single + batch variants exported

### CPU Backend (SIMD)
- 4 files, each compiled with its own `/arch` flag (critical: MSVC auto-vectorization with `/arch:AVX2` would crash non-AVX2 CPUs)
- **Level 0** — scalar (always available, dispatch.c)
- **Level 1** — SSE2 4-wide (x64 default, gather via `_mm_setr_ps`)
- **Level 2** — AVX 8-wide (`/arch:AVX`, scalar gather)
- **Level 3** — AVX2 8-wide (`/arch:AVX2`, `_mm256_i32gather_ps` + FMA)
- Runtime dispatch via CPUID (leaf 1 ECX[28]=AVX, leaf 7 EBX[5]=AVX2) + OSXSAVE YMM check
- Partial last batches fall back to scalar loads to avoid out-of-bounds on gather

### Lisp Interface
- Package: `sonata-engine` in `cuda/cffi.lisp`
- `(load-engine :backend :auto/:cpu/:cuda)` — auto tries CUDA → falls back to CPU
- `(eval-ast-sse opcodes args data n-rows n-vars)` — dispatches to active backend
- `(flatten-ast '(+ (* v0 2.0) v1))` — converts s-expr to postfix opcodes+args vectors
- `(cpu-simd-level)` / `(cpu-force-simd-level n)` — query/force SIMD level

### Build
- `cuda/build.ps1`: 5 steps — compile dispatch (no flag) + SSE2 (default) + AVX (`/arch:AVX`) + AVX2 (`/arch:AVX2`) + NVCC CUDA sources + link all into one DLL
- All files in `cuda/sonata/` are NN-specific (embedding, mamba, conv, optim, norm, loss) — NOT compiled, preserved for reference

### Tested
- i7-10750H (Comet Lake): auto detects AVX2 (level 3)
- All 4 levels produce identical SSE=0 for correct AST, SSE=35 for wrong AST
- 1000-row large test passes on all levels
- Sin/cos/exp/log/sqrt via scalar fallback

## First Task for Next Session
1. Load SBCL, `(load "cuda/cffi.lisp")`
2. `(sonata-engine:load-engine :backend :cpu)`
3. `(sonata-engine:cpu-simd-level)` → expect 3
4. Test with `(sonata-engine:demo-cpu)`
5. Then integrate into v7 engine to replace Prolog row-by-row eval
