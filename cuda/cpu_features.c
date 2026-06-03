#include <stdio.h>
#include <windows.h>

void cpuid(int info[4], int level, int count) {
    __cpuidex(info, level, count);
}

int main() {
    int info[4] = {0};
    char vendor[13] = {0};
    char brand[49] = {0};

    cpuid(info, 0, 0);
    *(int*)&vendor[0] = info[1];
    *(int*)&vendor[4] = info[3];
    *(int*)&vendor[8] = info[2];

    int max_std = info[0];

    // Query brand string (leaf 0x80000002-0x80000004)
    for (int leaf = 0x80000002; leaf <= 0x80000004 && leaf <= max_std; leaf++) {
        cpuid(info, leaf, 0);
        memcpy(brand + (leaf - 0x80000002) * 16, info, 16);
    }

    printf("=== CPU Features ===\n");
    printf("Vendor: %s\n", vendor);
    printf("Brand:  %s\n", brand);

    // Leaf 1: feature bits ECX, EDX
    int leaf1[4] = {0};
    cpuid(leaf1, 1, 0);
    unsigned int ecx1 = leaf1[2];
    unsigned int edx1 = leaf1[3];

    printf("\nStandard features (leaf 1):\n");
    printf("  SSE3       %s\n", (ecx1 >> 0) & 1 ? "YES" : "no");
    printf("  PCLMULQDQ  %s\n", (ecx1 >> 1) & 1 ? "YES" : "no");
    printf("  SSSE3      %s\n", (ecx1 >> 9) & 1 ? "YES" : "no");
    printf("  FMA        %s\n", (ecx1 >> 12) & 1 ? "YES" : "no");
    printf("  SSE4.1     %s\n", (ecx1 >> 19) & 1 ? "YES" : "no");
    printf("  SSE4.2     %s\n", (ecx1 >> 20) & 1 ? "YES" : "no");
    printf("  MOVBE      %s\n", (ecx1 >> 22) & 1 ? "YES" : "no");
    printf("  POPCNT     %s\n", (ecx1 >> 23) & 1 ? "YES" : "no");
    printf("  AES        %s\n", (ecx1 >> 25) & 1 ? "YES" : "no");
    printf("  OSXSAVE    %s\n", (ecx1 >> 27) & 1 ? "YES" : "no");
    printf("  AVX        %s\n", (ecx1 >> 28) & 1 ? "YES" : "no");

    printf("  SSE2       %s\n", (edx1 >> 26) & 1 ? "YES" : "no");

    // Leaf 7 (sub-leaf 0): extended features EBX, ECX
    int leaf7[4] = {0};
    if (max_std >= 7) cpuid(leaf7, 7, 0);
    unsigned int ebx7 = leaf7[1];
    unsigned int ecx7 = leaf7[2];
    unsigned int edx7 = leaf7[3];

    printf("\nExtended features (leaf 7):\n");
    printf("  AVX2       %s\n", (ebx7 >> 5) & 1 ? "YES" : "no");
    printf("  AVX512F    %s\n", (ebx7 >> 16) & 1 ? "YES" : "no");
    printf("  AVX512DQ   %s\n", (ebx7 >> 17) & 1 ? "YES" : "no");
    printf("  RDSEED     %s\n", (ebx7 >> 18) & 1 ? "YES" : "no");
    printf("  ADX        %s\n", (ebx7 >> 19) & 1 ? "YES" : "no");
    printf("  AVX512IFMA %s\n", (ebx7 >> 21) & 1 ? "YES" : "no");
    printf("  SHA        %s\n", (ebx7 >> 29) & 1 ? "YES" : "no");
    printf("  AVX512BW   %s\n", (ebx7 >> 30) & 1 ? "YES" : "no");
    printf("  AVX512VL   %s\n", (ebx7 >> 31) & 1 ? "YES" : "no");

    printf("  AVX512VBMI  %s\n", (ecx7 >> 1) & 1 ? "YES" : "no");
    printf("  AVX512VNNI  %s\n", (ecx7 >> 11) & 1 ? "YES" : "no");
    printf("  AVX512BITALG %s\n", (ecx7 >> 12) & 1 ? "YES" : "no");
    printf("  AVX512VPOPCNTDQ %s\n", (ecx7 >> 14) & 1 ? "YES" : "no");
    printf("  GFNI       %s\n", (ecx7 >> 8) & 1 ? "YES" : "no");
    printf("  VAES       %s\n", (ecx7 >> 9) & 1 ? "YES" : "no");
    printf("  VPCLMULQDQ %s\n", (ecx7 >> 10) & 1 ? "YES" : "no");

    printf("  AVX512FP16 %s\n", (edx7 >> 23) & 1 ? "YES" : "no");
    printf("  AMX-BF16   %s\n", (edx7 >> 22) & 1 ? "YES" : "no");
    printf("  AMX-TILE   %s\n", (edx7 >> 24) & 1 ? "YES" : "no");
    printf("  AMX-INT8   %s\n", (edx7 >> 25) & 1 ? "YES" : "no");

    // OSXSAVE: check XMM/YMM/ZMM state
    int have_avx = (ecx1 >> 28) & 1;
    int have_avx2 = (ebx7 >> 5) & 1;
    int have_avx512f = (ebx7 >> 16) & 1;
    int have_osxsave = (ecx1 >> 27) & 1;

    if (have_osxsave) {
        unsigned long long xcr0 = _xgetbv(0);
        int xmm_enabled  = (xcr0 >> 1) & 1;  // XMM
        int ymm_enabled  = (xcr0 >> 2) & 1;  // YMM
        int zmm_enabled  = (xcr0 >> 5) & 1 & (xcr0 >> 6) & 1;  // ZMM0-15 + ZMM16-31
        int opmask_enabled = (xcr0 >> 5) & 1; // OPMASK

        printf("\nOS XSAVE state:\n");
        printf("  XMM state          %s\n", xmm_enabled ? "enabled" : "disabled");
        printf("  YMM state          %s\n", ymm_enabled ? "enabled" : "disabled");
        printf("  OPMASK state       %s\n", opmask_enabled ? "enabled" : "disabled");
        printf("  ZMM state          %s\n", zmm_enabled ? "enabled" : "disabled");

        // AVX is usable if OS enabled XMM+YMM
        int avx_usable = have_avx && xmm_enabled && ymm_enabled;
        int avx2_usable = have_avx2 && avx_usable;
        int avx512_usable = have_avx512f && avx_usable && opmask_enabled && zmm_enabled;

        printf("\nUsable instruction sets:\n");
        printf("  AVX       %s\n", avx_usable ? "YES" : "no");
        printf("  AVX2      %s\n", avx2_usable ? "YES" : "no");
        printf("  AVX-512F  %s\n", avx512_usable ? "YES" : "no");

        if (avx_usable) {
            printf("\nSIMD lanes per vector:\n");
            printf("  128-bit  (SSE):  4 floats\n");
            printf("  256-bit  (AVX):  8 floats\n");
            if (avx512_usable) printf("  512-bit (AVX-512): 16 floats\n");
        }
    } else {
        printf("\nOSXSAVE not supported\n");
    }

    // Summary
    printf("\n=== Summary ===\n");
    printf("Baseline (all x64):     SSE2\n");
    printf("Level 1:               SSE3, SSSE3, SSE4.1, SSE4.2\n");
    printf("Level 2 (AVX):         8-wide, FMA\n");
    printf("Level 3 (AVX2):        AVX2\n");
    int avx512 = (ebx7 >> 16) & 1;
    printf("Level 4 (AVX-512F):    %s\n", avx512 ? "AVAILABLE" : "not available");
    if (avx512) {
        printf("  AVX512BW  %s\n", (ebx7 >> 30) & 1 ? "YES" : "no");
        printf("  AVX512VL  %s\n", (ebx7 >> 31) & 1 ? "YES" : "no");
        printf("  AVX512DQ  %s\n", (ebx7 >> 17) & 1 ? "YES" : "no");
        printf("  AVX512VNNI %s\n", (ecx7 >> 11) & 1 ? "YES" : "no");
    }
    printf("SHA extensions:        %s\n", (ebx7 >> 29) & 1 ? "YES" : "no");
    printf("AES-NI:                %s\n", (ecx1 >> 25) & 1 ? "YES" : "no");

    return 0;
}
