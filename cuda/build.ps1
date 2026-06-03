$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $ScriptDir

$CudaSources = @(
    "sonata_cuda_main.cu"
    "sonata_cuda_utils.cu"
    "sonata_cuda_activations.cu"
    "sonata_cuda_memory.cu"
    "sonata_cuda_matmul.cu"
    "sonata_cuda_ast.cu"
)

$CpuObjs = @(
    "sonata_cpu_dispatch.obj"
    "sonata_cpu_sse2.obj"
    "sonata_cpu_avx.obj"
    "sonata_cpu_avx2.obj"
)

$Output    = "sonata_cuda.dll"
$Libs      = "cublas.lib"
$CudaPath  = if ($env:CUDA_PATH) { $env:CUDA_PATH } else { "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0" }
$VsPath    = "C:\Program Files\Microsoft Visual Studio\2022\Community"
$MsvcVer   = "14.43.34808"
$WinSdkVer = "10.0.26100.0"
$KitRoot   = "${env:ProgramFiles(x86)}\Windows Kits\10"

# --- Set VS/MSVC environment ---
$vcBin       = "$VsPath\VC\Tools\MSVC\$MsvcVer\bin\Hostx64\x64"
$vcInclude   = "$VsPath\VC\Tools\MSVC\$MsvcVer\include"
$atlmfcInc   = "$VsPath\VC\Tools\MSVC\$MsvcVer\atlmfc\include"
$sdkInclude  = "$KitRoot\Include\$WinSdkVer\ucrt;$KitRoot\Include\$WinSdkVer\um;$KitRoot\Include\$WinSdkVer\shared;$KitRoot\Include\$WinSdkVer\winrt"
$sdkLib      = "$KitRoot\Lib\$WinSdkVer\ucrt\x64;$KitRoot\Lib\$WinSdkVer\um\x64"

$env:Path = "$vcBin;$env:Path"
$env:INCLUDE = "$vcInclude;$atlmfcInc;$sdkInclude;$env:INCLUDE"
$env:LIB = "$sdkLib;$VsPath\VC\Tools\MSVC\$MsvcVer\lib\x64;$vsPath\VC\Tools\MSVC\$MsvcVer\atlmfc\lib\x64;$env:LIB"

$cl = "$vcBin\cl.exe"
$nvcc = "$CudaPath\bin\nvcc.exe"

Write-Host "=== Building sonata_cuda.dll ==="
Write-Host "CUDA src..: $($CudaSources -join ', ')"
Write-Host "CPU  src..: sonata_cpu_{dispatch,sse2,avx,avx2}.c"
Write-Host "NVCC......: $nvcc"
Write-Host "cl.exe....: $cl"
Write-Host ""

# --- Step 1: Compile CPU scalar + dispatch (no SIMD flags) ---
Write-Host "--- [1/4] CPU dispatch + scalar ---"
& $cl "/O2" "/MD" "/utf-8" "/c" "sonata_cpu_dispatch.c" "/Fo:sonata_cpu_dispatch.obj"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Step 2: Compile CPU SSE2 (default x64 flags) ---
Write-Host "--- [2/4] CPU SSE2 ---"
& $cl "/O2" "/MD" "/utf-8" "/c" "sonata_cpu_sse2.c" "/Fo:sonata_cpu_sse2.obj"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Step 3: Compile CPU AVX+FMA (/arch:AVX) ---
Write-Host "--- [3/4] CPU AVX ---"
& $cl "/O2" "/arch:AVX" "/MD" "/utf-8" "/c" "sonata_cpu_avx.c" "/Fo:sonata_cpu_avx.obj"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Step 4: Compile CPU AVX2+gather (/arch:AVX2) ---
Write-Host "--- [4/4] CPU AVX2 ---"
& $cl "/O2" "/arch:AVX2" "/MD" "/utf-8" "/c" "sonata_cpu_avx2.c" "/Fo:sonata_cpu_avx2.obj"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Step 5: Compile CUDA sources + link all objects into DLL ---
Write-Host "--- [5/5] CUDA compilation + linking DLL ---"
$CudaFlags = @(
    "--shared"
    "-O2"
    "--use_fast_math"
    "-arch=sm_86"
    "-I`"$CudaPath\include`""
    "-I."
    "-L`"$CudaPath\lib\x64`""
    "-Xcompiler=/MD,/O2,/utf-8"
    "--default-stream=per-thread"
)

& $nvcc @CudaFlags $CudaSources $Libs $CpuObjs "-o" $Output

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=== Build SUCCESS: $Output ==="
    # Clean up intermediate .obj files
    foreach ($obj in $CpuObjs) { Remove-Item -Force $obj -ErrorAction SilentlyContinue }
} else {
    Write-Host "`n=== Build FAILED (exit code: $LASTEXITCODE) ==="
    exit $LASTEXITCODE
}
