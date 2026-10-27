# Read-only inspection of source/restored backup files; writes a NEW manifest on C:.
# PowerShell 5.1. Never writes inside repository.
param(
    [Parameter(Mandatory=$true)][string]$Folder,
    [Parameter(Mandatory=$true)][string]$OutputCsv
)
$ErrorActionPreference = 'Stop'
$expected = @('.vbk','.vib','.vbm')
if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "Missing folder: $Folder" }
if (Test-Path -LiteralPath $OutputCsv) { throw "Refusing to overwrite existing report: $OutputCsv" }
$dir = Split-Path -Parent $OutputCsv
if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Missing report directory: $dir" }
$allFiles = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction Stop | Sort-Object Name)
$subdirs = @(Get-ChildItem -LiteralPath $Folder -Directory -ErrorAction Stop)
if ($subdirs.Count -gt 0) { throw "Unexpected subdirectories ($($subdirs.Count)); inspect restore layout before hashing." }
if ($allFiles.Count -ne 10) { throw "Expected exactly 10 files; found $($allFiles.Count)." }
$other = @($allFiles | Where-Object { $_.Extension.ToLowerInvariant() -notin $expected })
if ($other.Count -gt 0) { throw "Unexpected file extensions; inspect folder." }
if (@($allFiles | Where-Object Extension -EQ '.vbk').Count -ne 2 -or @($allFiles | Where-Object Extension -EQ '.vib').Count -ne 7 -or @($allFiles | Where-Object Extension -EQ '.vbm').Count -ne 1) { throw 'Unexpected VBK/VIB/VBM file counts.' }
$done = 0
foreach ($file in $allFiles) {
    $done++
    Write-Progress -Activity 'SHA-256 Poczta' -Status ("File {0}/10: {1}" -f $done,$file.Name) -PercentComplete ([int](($done-1)/10*100))
    $start = Get-Date
    $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop
    [pscustomobject]@{
       Name=$file.Name; LengthBytes=[string]$file.Length; SHA256=$hash.Hash.ToUpperInvariant()
       MeasuredAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
       DurationMinutes=[math]::Round(((Get-Date)-$start).TotalMinutes,2)
    } | Export-Csv -LiteralPath $OutputCsv -Delimiter ';' -NoTypeInformation -Encoding UTF8 -Append
    Write-Host ("HASHED {0} ({1} bytes)" -f $file.Name,$file.Length)
}
Write-Progress -Activity 'SHA-256 Poczta' -Completed
Write-Host "Completed: $OutputCsv"
