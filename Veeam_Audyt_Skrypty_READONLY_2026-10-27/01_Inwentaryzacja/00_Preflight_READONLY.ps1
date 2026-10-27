#requires -Version 5.1
<#
.SYNOPSIS
  Sprawdzenie dostepnosci cmdletow na lokalnym serwerze. Bez odpytania vCenter ani katalogu backupow.
.DESCRIPTION
  Bez instalacji, importu Veeam czy zmiany konfiguracji. Bez zapisu na dysk.
#>
$ErrorActionPreference = 'Stop'
Write-Host '=== PowerShell i architektura ==='
$PSVersionTable.PSVersion | Format-List
[PSCustomObject]@{ Is64BitProcess=[Environment]::Is64BitProcess; ComputerName=$env:COMPUTERNAME } | Format-List
Write-Host '=== Moduly lokalne ==='
Get-Module -ListAvailable | Where-Object { $_.Name -match '^(Veeam\.Backup\.PowerShell|VMware\.)' } |
    Select-Object Name,Version,Path | Format-Table -AutoSize
Write-Host '=== Dostepnosc polecen (bez wykonywania) ==='
@('Get-VBRServer','Find-VBRViEntity','Get-VBRJob','Get-VBRJobObject',
  'Get-VBRBackup','Get-VBRRestorePoint','Get-VBRBackupSession','Get-VBRTaskSession') | ForEach-Object {
    $cmd = Get-Command -Name $_ -ErrorAction SilentlyContinue
    [PSCustomObject]@{ Command=$_; Available=[bool]$cmd; Source=if($cmd){$cmd.Source}else{''}; Version=if($cmd){$cmd.Version}else{''} }
} | Format-Table -AutoSize
