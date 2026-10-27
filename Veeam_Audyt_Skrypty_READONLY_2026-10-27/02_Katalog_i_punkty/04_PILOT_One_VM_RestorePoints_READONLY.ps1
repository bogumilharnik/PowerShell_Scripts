#requires -Version 5.1
<#
.SYNOPSIS
  PILOT: metadane restore pointow JEDNEJ VM w JEDNYM zarejestrowanym backupie.
.DESCRIPTION
  Get-VBRBackup -Name (jedna nazwa) -> Get-VBRRestorePoint -Backup -Name.
  Nie wywoluje Get-VBRRestorePoint bez filtra. Nie czyta plikow VBK.
  Wynik 0 NIE jest dowodem braku backupu (np. kontenery per-VM / imported / nazwy).
  Moze zwrocic dluga historie, wiec test wykonywac poza szczytem aktywnosci.
.PARAMETER BackupName
  Dokladna nazwa pojedynczego zarejestrowanego backupu z katalogu.
.PARAMETER VMName
  Dokladna nazwa jednej VM we wskazanym backupie.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$BackupName,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$VMName,
    [string]$OutputRoot='C:\VeeamAudit\Exports'
)
$ErrorActionPreference='Stop'
foreach($n in @('Get-VBRBackup','Get-VBRRestorePoint')) {
    $cmd=Get-Command $n -ErrorAction Stop
    if($cmd.Source -ne 'Veeam.Backup.PowerShell'){throw "Nieoczekiwane zrodlo $n"}
}
$started=Get-Date
Write-Host "PILOT: $BackupName / $VMName"
$backup=@(Get-VBRBackup -Name $BackupName -ErrorAction Stop | Where-Object { $_.Name -eq $BackupName })
if($backup.Count -ne 1){throw "Wymagany 1 backup o podanej nazwie; odnaleziono: $($backup.Count). Nic nie pobrano."}
Write-Host ('BackupId={0}; Class={1}' -f $backup[0].Id,$backup[0].GetType().FullName)
# Ważne: powyzsze Get-VBRBackup nie jest odczytem z plikow repozytorium.
$points=@(Get-VBRRestorePoint -Backup $backup[0] -Name $VMName -ErrorAction Stop)
# Dopasowanie exact po zapytaniu, poniewaz parametr Name moze akceptowac wzorce.
$exact=@($points | Where-Object { [string]$_.Name -eq $VMName })
Write-Host ('Punkty ogolem otrzymane: {0}; dokladna nazwa: {1}' -f $points.Count,$exact.Count)
if($points.Count -ne $exact.Count) {
    Write-Warning 'Zapytanie zwrocilo inne nazwy VM; ich wiersze nie zostaly wyeksportowane.'
}
function S([object]$obj,[string]$prop) {
    $p=$obj.PSObject.Properties[$prop]
    if($null -eq $p -or $null -eq $p.Value){return ''}
    return [string]$p.Value
}
$rows=foreach($p in $exact) {
    [PSCustomObject]@{
        BackupName=$BackupName;BackupId=[string]$backup[0].Id
        VMName=(S $p 'Name');PointId=(S $p 'Id');ObjectId=(S $p 'ObjectId')
        CreationTime=(S $p 'CreationTime');CreationTimeUTC=(S $p 'CreationTimeUTC')
        Type=(S $p 'Type');IsConsistent=(S $p 'IsConsistent');IsAvailable=(S $p 'IsAvailable')
        PointClass=$p.GetType().FullName;ExportTime=$started.ToString('o')
    }
}
if($rows.Count -eq 0){
    Write-Warning 'Brak punktow: wynik NIEJEDNOZNACZNY, zadnego statusu brak ochrony.'
    return
}
if(-not (Test-Path -LiteralPath $OutputRoot -PathType Container)){New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null}
$dest=Join-Path $OutputRoot ('PILOT_RestorePoints_{0}_{1}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8)))
if(Test-Path -LiteralPath $dest){throw "Plik istnieje: $dest"}
$rows | Sort-Object CreationTime,PointId | Export-Csv -LiteralPath $dest -Delimiter ';' -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
$check=@(Import-Csv -LiteralPath $dest -Delimiter ';' -ErrorAction Stop)
if($check.Count -ne $rows.Count){throw "Niezgodna liczba wierszy: $($check.Count)/$($rows.Count)"}
Write-Host "Zapisano $($rows.Count) punktow: $dest"
Write-Host ('Czas: {0}; SHA256 CSV: {1}' -f ((Get-Date)-$started),(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash)
Write-Warning 'Metadane punktow nie sa dowodem odtwarzalnosci ani kompletnej zawartosci dyskow.'
