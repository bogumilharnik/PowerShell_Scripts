#requires -Version 5.1
<#
.SYNOPSIS
  Lokalna kontrola CSV i manifest SHA256. Zero polaczen z Veeam/vCenter.
.PARAMETER CsvFolder
  Folder z raportami CSV. Odczytuje pliki w katalogu (bez rekurencji).
.PARAMETER OutputDir
  Katalog docelowy z manifestem; inny niz CsvFolder, nie nadpisuje plikow.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CsvFolder,
    [Parameter(Mandatory=$true)][string]$OutputDir
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $CsvFolder -PathType Container)){throw "Nie ma katalogu: $CsvFolder"}
if(-not(Test-Path -LiteralPath $OutputDir -PathType Container)){New-Item -ItemType Directory -Path $OutputDir -ErrorAction Stop | Out-Null}
$files=@(Get-ChildItem -LiteralPath $CsvFolder -File -Filter '*.csv' -ErrorAction Stop | Sort-Object Name)
if(-not $files.Count){throw 'Brak plikow CSV w wybranym katalogu.'}
$rows=foreach($file in $files){
  $csv=@(Import-Csv -LiteralPath $file.FullName -Delimiter ';' -ErrorAction Stop)
  [PSCustomObject]@{
    File=$file.Name;Bytes=$file.Length;CsvRows=$csv.Count
    Sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    CheckedAt=(Get-Date).ToString('o')
  }
}
$dest=Join-Path $OutputDir ('CSV_Integrity_{0}_{1}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8)))
$rows | Export-Csv -LiteralPath $dest -Delimiter ';' -Encoding UTF8 -NoTypeInformation -ErrorAction Stop
$rows | Format-Table -AutoSize
Write-Host "Manifest: $dest"
Write-Warning 'SHA256 zabezpiecza integralnosc eksportow, nie dowodzi integralnosci danych backupu.'
