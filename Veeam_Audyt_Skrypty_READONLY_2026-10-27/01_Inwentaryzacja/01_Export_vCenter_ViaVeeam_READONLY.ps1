#requires -Version 5.1
<#
.SYNOPSIS
  Inwentarz VM jednego vCenter zarejestrowanego w Veeam. Jeden odczyt; nie jest to niezalezny eksport vCenter.
.PARAMETER VCenterName
  Dokladna nazwa vCenter z Get-VBRServer -Type VC. Jedno vCenter na uruchomienie.
.PARAMETER OutputRoot
  Katalog WYŁĄCZNIE na lokalne raporty CSV; bez zapisu na repozytorium.
.NOTES
  Bazuje na przetestowanych poleceniach Veeam 12.3.2.3617.
  Odczyt duzego vCenter moze chwilowo obciazyc uslugi; nie uruchamiac rownolegle.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('horizon-vcenter.root.urk.edu.pl','10.43.1.10')][string]$VCenterName,
    [string]$OutputRoot = 'C:\VeeamAudit\Exports'
)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Wymagany proces PowerShell x64.' }
foreach ($n in @('Get-VBRServer','Find-VBRViEntity')) {
    $cmd = Get-Command $n -ErrorAction Stop
    if($cmd.Source -ne 'Veeam.Backup.PowerShell') { throw "Nieoczekiwane zrodlo $n : $($cmd.Source)" }
}
$vc = @(Get-VBRServer -Type VC -Name $VCenterName -ErrorAction Stop)
if($vc.Count -ne 1) { throw "Nie odnaleziono jednoznacznie $VCenterName. Liczba: $($vc.Count)" }
$began = Get-Date
Write-Host "Odczyt inwentarza $VCenterName (TYLKO ODCZYT)..."
$vms = @(Find-VBRViEntity -Server $vc[0] -VMsAndTemplates -ErrorAction Stop |
         Where-Object { [string]$_.Type -eq 'Vm' -and -not $_.IsTemplate })
if($vms.Count -eq 0) { throw 'Zero maszyn: brak eksportu, konieczna diagnostyka.' }
$rows = foreach ($vm in $vms) {
    [PSCustomObject]@{
        VCenter=$VCenterName;VMName=[string]$vm.Name;Id=[string]$vm.Id;Uuid=[string]$vm.Uuid
        Reference=[string]$vm.Reference;PowerState=[string]$vm.PowerState
        VmHostName=[string]$vm.VmHostName;VmFolderName=[string]$vm.VmFolderName
        Path=[string]$vm.Path;IsTemplate=[bool]$vm.IsTemplate
        ExportTime=$began.ToString('yyyy-MM-dd HH:mm:ss')
    }
}
$duplicateIds=@($rows | Group-Object Id | Where-Object { $_.Count -gt 1 })
if($duplicateIds.Count) { throw "Wynik zawiera zdublowane Id ($($duplicateIds.Count) grup). Raport wymaga analizy." }
if(-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -Path $OutputRoot -ItemType Directory -ErrorAction Stop | Out-Null
}
$safeName=$VCenterName -replace '[^a-zA-Z0-9._-]','_'
$filename='vCenter_VM_Inventory_{0}_{1}_{2}.csv' -f $safeName,(Get-Date -Format 'yyyyMMdd_HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
$dest=Join-Path $OutputRoot $filename
if(Test-Path -LiteralPath $dest) { throw "Plik juz istnieje: $dest" }
$rows | Sort-Object VMName,Id | Export-Csv -LiteralPath $dest -Delimiter ';' -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
$check=@(Import-Csv -LiteralPath $dest -Delimiter ';' -ErrorAction Stop)
if($check.Count -ne $rows.Count) {throw "Liczba zapisanych rekordow rozni sie: $($check.Count) / $($rows.Count)"}
Write-Host ('VM={0}; czas={1}; CSV={2}' -f $rows.Count,((Get-Date)-$began),$dest)
Write-Host ('SHA256 CSV: {0}' -f (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash)
