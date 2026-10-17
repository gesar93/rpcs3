[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$QtDirectory,
    [Parameter(Mandatory)][string]$VulkanDirectory,
    [string]$MSBuildPath,
    [string]$PlatformToolset = 'v145',
    [ValidateRange(1,16)][int]$ParallelProjects = 2
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$qt = (Resolve-Path -LiteralPath $QtDirectory).Path
$vulkan = (Resolve-Path -LiteralPath $VulkanDirectory).Path
foreach ($file in @((Join-Path $qt 'bin/moc.exe'), (Join-Path $vulkan 'Include/vulkan/vulkan.h'), (Join-Path $repo 'build/lib_ext/Release-x64/llvm_build/include/llvm/IR/Module.h'))) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing build dependency: $file" }
}
if (-not $MSBuildPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $MSBuildPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\**\Bin\amd64\MSBuild.exe' | Select-Object -First 1
}
if (-not $MSBuildPath -or -not (Test-Path -LiteralPath $MSBuildPath)) { throw 'MSBuild with C++ tools was not found' }
$saved = @{QTDIR=$env:QTDIR; VULKAN_SDK=$env:VULKAN_SDK; SKIP_RPCS3_TEST=$env:SKIP_RPCS3_TEST; CMAKE_BUILD_PARALLEL_LEVEL=$env:CMAKE_BUILD_PARALLEL_LEVEL}
try {
    $env:QTDIR = $qt
    $env:VULKAN_SDK = $vulkan
    # Matches the upstream Windows release job. Tooling tests are run separately.
    $env:SKIP_RPCS3_TEST = 'true'
    $env:CMAKE_BUILD_PARALLEL_LEVEL = '2'
    Push-Location $repo
    try {
        & $MSBuildPath 'rpcs3.sln' '/t:rpcs3' '/p:Configuration=Release' '/p:Platform=x64' "/p:PlatformToolset=$PlatformToolset" '/p:PreferredToolArchitecture=x64' '/p:CL_MPCount=2' "/m:$ParallelProjects" '/v:minimal' '/nologo'
        if ($LASTEXITCODE -ne 0) { throw "RPCS3 build failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
} finally {
    $env:QTDIR = $saved.QTDIR
    $env:VULKAN_SDK = $saved.VULKAN_SDK
    $env:SKIP_RPCS3_TEST = $saved.SKIP_RPCS3_TEST
    $env:CMAKE_BUILD_PARALLEL_LEVEL = $saved.CMAKE_BUILD_PARALLEL_LEVEL
}
