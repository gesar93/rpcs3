# Run against an already running, isolated RPCS3 instance. No application is stopped.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$Scenario,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z]{4}\d{5}$')][string]$TitleId,
    [Parameter(Mandatory)][string]$GameVersion,
    [Parameter(Mandatory)][string]$CacheState,
    [string]$EbootPath,
    [ValidateRange(1,7200)][int]$DurationSeconds = 900
)
$ErrorActionPreference = 'Stop'
$runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$process = Get-Process -Id $ProcessId
if ($process.ProcessName -ne 'rpcs3') { throw 'ProcessId must identify rpcs3.exe' }
$exe = Join-Path $runtime 'rpcs3.exe'
if ([IO.Path]::GetFullPath($process.Path) -ne [IO.Path]::GetFullPath($exe)) { throw 'Process does not belong to RuntimeDirectory' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a new output directory for every run' }
$out = New-Item -ItemType Directory -Path $OutputDirectory
$metadata = [ordered]@{
    startedUtc = [DateTime]::UtcNow.ToString('o'); scenario = $Scenario
    declaredTitleId = $TitleId; declaredGameVersion = $GameVersion; cacheState = $CacheState
    processId = $ProcessId; exeSha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    cpu = (Get-CimInstance Win32_Processor).Name
    gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
    durationSeconds = $DurationSeconds; stopReason = $null; endedUtc = $null
    ebootSha256 = $null
    warning = 'Declared game identity must be checked against RPCS3.log. Process memory alone cannot establish a leak or a graphics hang.'
}
if ($EbootPath) { $metadata.ebootSha256 = (Get-FileHash -LiteralPath $EbootPath -Algorithm SHA256).Hash }
$files = @('config.yml', "config/custom_configs/config_$TitleId.yml", 'GuiConfigs/config_database.dat')
foreach ($relative in $files) {
    $source = Join-Path $runtime $relative
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $out.FullName ($relative -replace '[/\\]', '_'))
    }
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out.FullName 'run.json') -Encoding UTF8
$timer = [Diagnostics.Stopwatch]::StartNew()
$csv = Join-Path $out.FullName 'memory.csv'
try {
    while ($timer.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $process.Refresh()
        if ($process.HasExited) { $metadata.stopReason = 'process_exited'; break }
        [pscustomobject]@{
            utc = [DateTime]::UtcNow.ToString('o'); elapsedSeconds = [math]::Round($timer.Elapsed.TotalSeconds,3)
            privateBytes = $process.PrivateMemorySize64; workingSetBytes = $process.WorkingSet64
            cpuSeconds = $process.TotalProcessorTime.TotalSeconds; handles = $process.HandleCount
        } | Export-Csv -LiteralPath $csv -NoTypeInformation -Append -Encoding UTF8
        Start-Sleep -Seconds 1
    }
    if (-not $metadata.stopReason) { $metadata.stopReason = 'duration_elapsed_process_left_running' }
} catch {
    $metadata.stopReason = 'collector_error'
    throw
} finally {
    if (-not $metadata.stopReason) { $metadata.stopReason = 'collection_interrupted' }
    $metadata.endedUtc = [DateTime]::UtcNow.ToString('o')
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out.FullName 'run.json') -Encoding UTF8
    foreach ($relative in @('log/RPCS3.log','log/RPCS3.log.gz','RPCS3.log','RPCS3.log.gz')) {
        $source = Join-Path $runtime $relative
        $name = $relative -replace '/', '_'
        if (Test-Path -LiteralPath $source) {
            try {
                $inputStream = [IO.File]::Open($source, 'Open', 'Read', 'ReadWrite')
                try {
                    $outputStream = [IO.File]::Create((Join-Path $out.FullName $name))
                    try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
                } finally { $inputStream.Dispose() }
            } catch { Write-Warning "Could not snapshot ${name}: $_" }
        }
    }
}
Write-Output $out.FullName
