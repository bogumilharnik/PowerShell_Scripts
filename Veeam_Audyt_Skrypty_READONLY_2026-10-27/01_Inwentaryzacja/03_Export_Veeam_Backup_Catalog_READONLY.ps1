#requires -Version 5.1
<#
.SYNOPSIS
  Katalog ZAREJESTROWANYCH backupow Veeam (bez odczytu punktow, storage, plikow VBK).
.DESCRIPTION
  Jeden Get-VBRBackup, nastepnie wylacznie proste wlasciwosci w pamieci.
  Dla per-VM rodzice/kontenery moga nie pokazac wszystkich dzieci. To NIE jest wykaz VM ani punktow.
  Plik wyjsciowy to lokalny CSV. Bez zmian w Veeam i repozytoriach.
#>
[CmdletBinding()]
param([string]$OutputRoot = 'C:\VeeamAudit\Exports')
$ErrorActionPreference='Stop'
$cmd=Get-Command Get-VBRBackup -ErrorAction Stop
if($cmd.Source -ne 'Veeam.Backup.PowerShell') {throw 'Nieoczekiwane zrodlo Get-VBRBackup'}
$started=Get-Date
Write-Host 'Odczyt katalogu backupow (metadane, bez punktow i VBK)...'
$backups=@(Get-VBRBackup -ErrorAction Stop)
if($backups.Count -eq 0) {throw 'Katalog pusty: przerwano zapis, sprawdz kontekst polaczenia.'}
function SafeProp([object]$obj,[string]$n) {
    $p=$obj.PSObject.Properties[$n]
    if($null -eq $p -or $null -eq $p.Value) {return ''}
    return [string]$p.Value
}
$rows=foreach($b in $backups) {
    [PSCustomObject]@{
        BackupName=(SafeProp $b 'Name');BackupId=(SafeProp $b 'Id');
        JobId=(SafeProp $b 'JobId');JobType=(SafeProp $b 'JobType');
        BackupType=(SafeProp $b 'Type');CreationTime=(SafeProp $b 'CreationTime');
        IsTruePerVmContainer=(SafeProp $b 'IsTruePerVmContainer');
        Class=$b.GetType().FullName;ExportTime=$started.ToString('o')
    }
}
if(-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null}
$dest=Join-Path $OutputRoot ('Veeam_Backup_Catalog_{0}_{1}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8)))
if(Test-Path -LiteralPath $dest) {throw "Plik istnieje: $dest"}
$rows | Sort-Object BackupName,BackupId | Export-Csv -LiteralPath $dest -Delimiter ';' -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
$check=@(Import-Csv -LiteralPath $dest -Delimiter ';')
if($check.Count -ne $rows.Count){throw "Niezgodnosc CSV: $($check.Count)/$($rows.Count)"}
Write-Host ('Katalog: {0} rekordow, czas: {1}' -f $rows.Count,((Get-Date)-$started))
Write-Host "Plik: $dest"
Write-Host ('SHA256: {0}' -f (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash)
Write-Warning 'Katalog backupow NIE dowodzi aktualnosci, kompletnosci ani odtwarzalnosci punktow.'
