#!/usr/bin/env pwsh
param(
    [string]$LogDir    = '/log',
    [string]$Threshold = '70',
    [string]$BackupDir = '/backup'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Fail([string]$m) { [Console]::Error.WriteLine($m); exit 1 }
if ($Threshold -notmatch '^\d{1,3}$' -or [int]$Threshold -gt 100) {
    Fail "Error: THRESHOLD should be a number in 0..100"
}
$thr = [int]$Threshold
Write-Host "LogDir = [$LogDir]"
if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) { Fail "Error: $LogDir not found" }
$logFull    = [IO.Path]::GetFullPath($LogDir).TrimEnd('\','/')
$backupFull = [IO.Path]::GetFullPath($BackupDir).TrimEnd('\','/')
if ($backupFull -eq $logFull -or
    $backupFull.StartsWith($logFull + [IO.Path]::DirectorySeparatorChar)) {
    Fail "Error: $BackupDir located in $LogDir"
}
$maxSize = Get-PSDrive -PSProvider FileSystem |
    Where-Object { $logFull -like "$($_.Root.TrimEnd('\','/'))*" } |
    Sort-Object { $_.Root.Length } -Descending |
    Select-Object -First 1 |
    ForEach-Object { [long]$_.Used + [long]$_.Free }
if (-not $maxSize) { Fail "Error: could not determine disk size for $LogDir" }
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$currentSize = 0L
Get-ChildItem -LiteralPath $LogDir -Recurse -Force -File |
    ForEach-Object { $currentSize += [long]$_.Length }
$percent = [long][math]::Floor([decimal]$currentSize * 100 / $maxSize)
Write-Host "Size of ${LogDir}: $currentSize bytes ($percent%)"
if ($percent -le $thr) { Write-Host "The fill level does not exceed $thr%."; exit 0 }

$target = [long][math]::Floor([decimal]$maxSize * $thr / 100)
$need   = $currentSize - $target
Write-Host "Need to free: $need bytes"
$filesArch = @()
$freed = 0L
foreach ($f in Get-ChildItem -LiteralPath $LogDir -Recurse -Force -File |
                Sort-Object LastWriteTime) {
    if ($need -le 0) { break }
    $filesArch += $f
    $need  -= $f.Length
    $freed += $f.Length
}
if ($filesArch.Count -eq 0) { Write-Host "No files found for archivation."; exit 0 }
if ($need -gt 0) {
    [Console]::Error.WriteLine("Warning: Failed to collect files for $need bytes; everything that was found will be archived and deleted.")
}
$ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
$ext  = if ($env:LAB1_MAX_COMPRESSION -eq '1') { 'lzma' } else { 'gz' }
$arch = Join-Path $BackupDir "archive_$ts.tar.$ext"
$rel = $filesArch | ForEach-Object {
    $_.FullName.Substring($logFull.Length).TrimStart('\','/').Replace('\','/')
}
if ($env:LAB1_MAX_COMPRESSION -eq '1') {  $tarTmp = Join-Path $BackupDir "archive_$ts.tar"
    & tar -cf $tarTmp -C $logFull -- $rel
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tarTmp)) {
        Fail "Error: tar failed: $tarTmp"
    }
    & xz --format=lzma $tarTmp
    if ($LASTEXITCODE -ne 0) {
        Fail "Error: xz failed: $tarTmp"
    }}
else { tar -czf $arch -C $logFull -- $rel }

if (-not (Test-Path -LiteralPath $arch) -or (Get-Item -LiteralPath $arch).Length -eq 0) {
    Fail "Error: archive is not created or empty: $arch"
}
Write-Host "Archive created: $arch"
Remove-Item -LiteralPath $filesArch.FullName -Force
Write-Host "Number of files deleted: $($filesArch.Count), freed: $freed bytes"