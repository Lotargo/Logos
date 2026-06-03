// CPU SIMD smoke test (standalone C, no CFFI needed)
#include <stdio.h>
#include <math.h>
#include <windows.h>

// Import from DLL
typedef int (*eval_fn)(const float*, int, int, const int*, const float*, int, float*);
typedef int (*batch_fn)(const float*, int, int, int, const int*, const float*, int, float*);
typedef int (*simd_level_fn)();
typedef int (*force_simd_fn)(int);

int main() {
    HMODULE dll = LoadLibraryA("cuda/sonata_cuda.dll");
    if (!dll) {
        printf("FAIL: cannot load sonata_cuda.dll (error %lu)\n", GetLastError());
        return 1;
    }

    eval_fn eval   = (eval_fn)GetProcAddress(dll, "sonata_cpu_eval_ast_sse");
    batch_fn batch = (batch_fn)GetProcAddress(dll, "sonata_cpu_eval_ast_sse_batch");
    simd_level_fn simd_level = (simd_level_fn)GetProcAddress(dll, "sonata_cpu_simd_level");
    force_simd_fn force_simd = (force_simd_fn)GetProcAddress(dll, "sonata_cpu_force_simd_level");

    if (!eval || !batch || !simd_level || !force_simd) {
        printf("FAIL: cannot find exports\n");
        FreeLibrary(dll);
        return 1;
    }

    printf("=== CPU SIMD Smoke Test ===\n");
    int auto_level = simd_level();
    printf("Auto SIMD level: %d (0=scalar,1=SSE2,2=AVX,3=AVX2)\n", auto_level);
    int pass = 1;

    // Reference data for all level tests
    int opcodes[] = {11, 12, 3, 11, 1};  // v0 2.0 * v1 +
    float args[]  = {0, 2.0f, 0, 1, 0};
    float data[]  = {1,2,4, 3,4,10, 5,6,16, 0,1,1};
    int n_rows = 4, n_vars = 3, ast_len = 5;

    // Sin test data
    int sopcodes[] = {11, 5, 12, 11, 3, 1};  // v0 sin 2.0 v1 * +
    float sargs[]  = {0, 0, 2.0f, 1, 0, 0};
    float sdata[]  = {0,0,0, 1.5707963f,0,1, 0,3,6};

    // Batch data
    int bopcodes[] = {11, 12, 3, 11, 1};  // v0 3.0 * v1 +
    float bargs[]  = {0, 3.0f, 0, 1, 0};
    float bdata[]  = {1,0,3, 2,1,7, 0,5,5, 4,0,12};
    float bresults[2];

    // Test with auto-detected level
    {
        float result = 0;
        int ret = eval(data, n_rows, n_vars, opcodes, args, ast_len, &result);
        printf("Auto:          SSE=%g %s\n", result,
               (ret==0 && fabs(result)<1e-5)?" PASS":" FAIL");
        if (ret!=0 || fabs(result)>=1e-5) pass = 0;
    }

    // Test each level explicitly
    const char* level_names[] = {"scalar", "SSE2", "AVX", "AVX2"};
    for (int level = 0; level <= 3; level++) {
        force_simd(level);
        float result = 0;
        int ret = eval(data, n_rows, n_vars, opcodes, args, ast_len, &result);
        printf("Level %d (%-6s): SSE=%g %s\n", level, level_names[level], result,
               (ret==0 && fabs(result)<1e-5)?" PASS":" FAIL");
        if (ret!=0 || fabs(result)>=1e-5) pass = 0;
    }

    // Test sin at each level (transcendental functions)
    for (int level = 0; level <= 3; level++) {
        force_simd(level);
        float result = 0;
        int ret = eval(sdata, 3, 3, sopcodes, sargs, 6, &result);
        printf("Sin L%d:         SSE=%g %s\n", level, result,
               (ret==0 && fabs(result)<1e-5)?" PASS":" FAIL");
        if (ret!=0 || fabs(result)>=1e-5) pass = 0;
    }

    // Batch test
    {
        force_simd(-1);
        memset(bresults, 0, sizeof(bresults));
        int ret = batch(bdata, 2, 2, 3, bopcodes, bargs, 5, bresults);
        printf("Batch:         SSEs=%g,%g %s\n", bresults[0], bresults[1],
               (ret==0 && fabs(bresults[0])<1e-5 && fabs(bresults[1])<1e-5)?" PASS":" FAIL");
        if (ret!=0 || fabs(bresults[0])>=1e-5 || fabs(bresults[1])>=1e-5) pass = 0;
    }

    // Wrong AST sanity check
    {
        int wopcodes[] = {11, 11, 1};
        float wargs[]  = {0, 1, 0};
        float result = 0;
        int ret = eval(data, 4, 3, wopcodes, wargs, 3, &result);
        printf("Wrong AST:     SSE=%g (expect >0) %s\n", result,
               (ret==0 && result>1e-5)?" PASS":" FAIL");
        if (ret!=0 || result<=1e-5) pass = 0;
    }

    // Large test: 1000 rows to verify no OOB issues with gather
    {
        int large_rows = 1000;
        int nv = 3;
        float* ldata = (float*)malloc(large_rows * nv * sizeof(float));
        for (int i = 0; i < large_rows; i++) {
            ldata[i * nv + 0] = (float)i;
            ldata[i * nv + 1] = (float)(i * 2);
            ldata[i * nv + 2] = (float)(i * 2 + i * 2);  // target = v0*2 + v1 = i*2 + i*2 = i*4
        }
        // AST: (+ (* v0 2.0) v1) -> pred = v0*2 + v1 = i*2 + i*2 = i*4
        // target = i*4 -> diff = 0
        {
            force_simd(-1);
            float result = 0;
            int ret = eval(ldata, large_rows, nv, opcodes, args, ast_len, &result);
            printf("Large %d:     SSE=%g %s\n", large_rows, result,
                   (ret==0 && fabs(result)<1e-3)?" PASS":" FAIL");
            if (ret!=0 || fabs(result)>=1e-3) pass = 0;
        }
        // Force each level
        for (int level = 0; level <= 3; level++) {
            force_simd(level);
            float result = 0;
            int ret = eval(ldata, large_rows, nv, opcodes, args, ast_len, &result);
            printf("Large L%d:     SSE=%g %s\n", level, result,
                   (ret==0 && fabs(result)<1e-3)?" PASS":" FAIL");
            if (ret!=0 || fabs(result)>=1e-3) pass = 0;
        }
        free(ldata);
    }

    force_simd(-1);
    FreeLibrary(dll);

    printf("\n=== %s ===\n", pass?"ALL TESTS PASSED":"SOME TESTS FAILED");
    return pass ? 0 : 1;
}
